const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();

const PRIMARY_PROVIDER = 'firestore_cloud_function';
const SOS_RATE_LIMIT = 10;
const SOS_RATE_WINDOW_MS = 60 * 1000;
const INVITE_RATE_LIMIT = 5;
const INVITE_RATE_WINDOW_MS = 5 * 60 * 1000;

function requireAuthenticatedUser(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Sign in to manage guardian links.'
    );
  }
  return context.auth.uid;
}

async function consumeInviteRateLimit(userId) {
  const db = admin.firestore();
  const rateRef = db.collection('guardian_invite_limits').doc(userId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateRef);
    const current = snapshot.data() || {};
    const nowMs = Date.now();
    const startMs = current.windowStartedAt?.toMillis?.() || 0;
    if (startMs > 0 && nowMs - startMs < INVITE_RATE_WINDOW_MS) {
      if ((current.count || 0) >= INVITE_RATE_LIMIT) return false;
      transaction.update(rateRef, { count: (current.count || 0) + 1 });
      return true;
    }
    transaction.set(rateRef, {
      windowStartedAt: admin.firestore.Timestamp.fromMillis(nowMs),
      count: 1,
    });
    return true;
  });
}

exports.createGuardianInvite = functions.https.onCall(async (_data, context) => {
  const protectedUid = requireAuthenticatedUser(context);
  if (!(await consumeInviteRateLimit(protectedUid))) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'Too many invite codes were created. Try again later.'
    );
  }
  const inviteCode = crypto.randomBytes(16).toString('hex').toUpperCase();
  const inviteId = crypto.createHash('sha256').update(inviteCode).digest('hex');
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    now.toMillis() + 24 * 60 * 60 * 1000
  );

  await admin.firestore().collection('guardianInvites').doc(inviteId).create({
    protectedUid,
    status: 'pending',
    createdAt: now,
    expiresAt,
  });

  return { inviteCode, expiresAt: expiresAt.toDate().toISOString() };
});

exports.acceptGuardianInvite = functions.https.onCall(async (data, context) => {
  const guardianUid = requireAuthenticatedUser(context);
  const inviteCode = String(data?.inviteCode || '').trim().toUpperCase();
  const token = String(data?.fcmToken || '').trim();
  if (!/^[A-F0-9]{32}$/.test(inviteCode) || token.length < 20 || token.length > 4096) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid invite.');
  }

  const inviteId = crypto.createHash('sha256').update(inviteCode).digest('hex');
  const db = admin.firestore();
  const inviteRef = db.collection('guardianInvites').doc(inviteId);
  const inviteSnapshot = await inviteRef.get();
  if (!inviteSnapshot.exists) {
    throw new functions.https.HttpsError('not-found', 'Invite not found or expired.');
  }
  const protectedUid = inviteSnapshot.get('protectedUid');
  if (!protectedUid || protectedUid === guardianUid) {
    throw new functions.https.HttpsError('failed-precondition', 'This invite cannot be used.');
  }
  const guardianTokenRef = db
    .collection('users')
    .doc(protectedUid)
    .collection('guardian_tokens')
    .doc(guardianUid);
  const guardianLinkRef = db
    .collection('users')
    .doc(guardianUid)
    .collection('protected_links')
    .doc(protectedUid);

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(inviteRef);
    if (!current.exists) {
      throw new functions.https.HttpsError('not-found', 'Invite not found or expired.');
    }
    const invite = current.data();
    const now = admin.firestore.Timestamp.now();
    const isRetryBySameGuardian =
      invite.status === 'accepted' && invite.acceptedBy === guardianUid;
    if (
      !invite.expiresAt ||
      invite.expiresAt.toMillis() <= now.toMillis() ||
      (invite.status !== 'pending' && !isRetryBySameGuardian)
    ) {
      throw new functions.https.HttpsError('failed-precondition', 'Invite is expired or already used.');
    }

    if (!isRetryBySameGuardian) {
      transaction.update(inviteRef, {
        status: 'accepted',
        acceptedBy: guardianUid,
        acceptedAt: now,
      });
    }
    transaction.set(guardianTokenRef, {
      token,
      guardianUid,
      registeredAt: now,
      inviteId,
    });
    transaction.set(guardianLinkRef, {
      protectedUid,
      inviteId,
      linkedAt: now,
    });
  });

  return { linked: true };
});

exports.refreshGuardianTokens = functions.https.onCall(async (data, context) => {
  const guardianUid = requireAuthenticatedUser(context);
  const token = String(data?.fcmToken || '').trim();
  if (token.length < 20 || token.length > 4096) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid device token.');
  }

  const db = admin.firestore();
  const links = await db
    .collection('users')
    .doc(guardianUid)
    .collection('protected_links')
    .get();
  const now = admin.firestore.Timestamp.now();
  await Promise.all(links.docs.map((link) =>
    db
      .collection('users')
      .doc(link.id)
      .collection('guardian_tokens')
      .doc(guardianUid)
      .set({ token, guardianUid, registeredAt: now }, { merge: true })
  ));
  return { updatedCount: links.size };
});

async function consumeSosRateLimit(userId) {
  const db = admin.firestore();
  const rateRef = db
    .collection('users')
    .doc(userId)
    .collection('server_metadata')
    .doc('sos_rate_limit');

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateRef);
    const current = snapshot.data() || {};
    const nowMs = Date.now();
    const startMs = current.windowStartedAt?.toMillis?.() || 0;
    if (startMs > 0 && nowMs - startMs < SOS_RATE_WINDOW_MS) {
      if ((current.count || 0) >= SOS_RATE_LIMIT) return false;
      transaction.update(rateRef, { count: (current.count || 0) + 1 });
      return true;
    }
    transaction.set(rateRef, {
      windowStartedAt: admin.firestore.Timestamp.fromMillis(nowMs),
      count: 1,
    });
    return true;
  });
}

/**
 * Firestore is both the trigger and the durable delivery receipt.
 *
 * New clients mark this function as the primary provider. Legacy events have
 * no delivery object and are deliberately skipped here; the legacy client
 * calls the HTTPS backend, which claims those events atomically.
 */
exports.sendSosAlert = functions.firestore
  .document('users/{userId}/sos_events/{sosId}')
  .onCreate(async (snap, context) => {
    const { userId, sosId } = context.params;
    const eventRef = snap.ref;
    let claimed = false;
    let sendStarted = false;

    try {
      claimed = await admin.firestore().runTransaction(async (transaction) => {
        const current = await transaction.get(eventRef);
        if (!current.exists) return false;

        const delivery = current.data().delivery;
        if (
          !delivery ||
          delivery.primary !== PRIMARY_PROVIDER ||
          delivery.status !== 'pending'
        ) {
          return false;
        }

        transaction.update(eventRef, {
          'delivery.status': 'processing',
          'delivery.provider': PRIMARY_PROVIDER,
          'delivery.fallbackEligible': false,
          'delivery.startedAt': admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });

      if (!claimed) {
        console.log(
          `Skipping SOS ${sosId}: not a pending ${PRIMARY_PROVIDER} event`
        );
        return null;
      }

      console.log(`Primary delivery claimed for SOS ${sosId}, user ${userId}`);

      if (!(await consumeSosRateLimit(userId))) {
        await eventRef.update({
          'delivery.status': 'failed',
          'delivery.provider': PRIMARY_PROVIDER,
          'delivery.fallbackEligible': false,
          'delivery.successCount': 0,
          'delivery.failureCount': 0,
          'delivery.totalCount': 0,
          'delivery.completedAt': admin.firestore.FieldValue.serverTimestamp(),
          'delivery.error': 'SOS delivery rate limit reached',
        });
        console.warn(`SOS rate limit reached for user ${userId}`);
        return null;
      }

      const tokensSnapshot = await admin
        .firestore()
        .collection('users')
        .doc(userId)
        .collection('guardian_tokens')
        .get();

      const tokenEntries = new Map();
      tokensSnapshot.docs.forEach((doc) => {
        const token = doc.data().token;
        if (typeof token !== 'string' || token.length === 0) return;
        const refs = tokenEntries.get(token) || [];
        refs.push(doc.ref);
        tokenEntries.set(token, refs);
      });
      const tokens = Array.from(tokenEntries.keys());

      if (tokens.length === 0) {
        await eventRef.update({
          'delivery.status': 'no_guardians',
          'delivery.provider': PRIMARY_PROVIDER,
          'delivery.fallbackEligible': false,
          'delivery.successCount': 0,
          'delivery.failureCount': 0,
          'delivery.totalCount': 0,
          'delivery.completedAt': admin.firestore.FieldValue.serverTimestamp(),
          'delivery.error': null,
        });
        console.log(`No valid guardian tokens for SOS ${sosId}`);
        return null;
      }

      const sosData = snap.data();
      const userName = sosData.userName || 'Unknown User';
      const isAutomatic = sosData.generatedAutomatically === true;
      const alertType = sosData.alertType || 'manual';

      let triggerText;
      switch (alertType) {
        case 'fall':
          triggerText = '⚠️ FALL DETECTED';
          break;
        case 'noise':
          triggerText = '🔊 DISTRESS NOISE DETECTED';
          break;
        case 'motion':
          triggerText = '📳 MOTION ANOMALY DETECTED';
          break;
        default:
          triggerText = '🆘 SOS ACTIVATED';
      }

      const title = `${triggerText} — ${userName}`;
      let body = isAutomatic
        ? `Automatic emergency alert triggered for ${userName}. Open SafeNetic to view their location.`
        : `${userName} pressed the SOS button. Open SafeNetic to view their location.`;

      if (sosData.latitude != null && sosData.longitude != null) {
        body += `\n📍 https://maps.google.com/?q=${sosData.latitude},${sosData.longitude}`;
      }

      const timestamp =
        typeof sosData.timestamp?.toDate === 'function'
          ? sosData.timestamp.toDate().toISOString()
          : '';

      const message = {
        tokens,
        notification: { title, body },
        data: {
          sosId,
          userId,
          alertType,
          userName,
          generatedAutomatically: String(isAutomatic),
          latitude: String(sosData.latitude ?? ''),
          longitude: String(sosData.longitude ?? ''),
          timestamp,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'sos_alert_channel',
            priority: 'max',
            defaultVibrateTimings: true,
            defaultSound: true,
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
            visibility: 'public',
          },
          ttl: 0,
        },
      };

      sendStarted = true;
      const response = await admin.messaging().sendEachForMulticast(message);
      const status =
        response.successCount === tokens.length
          ? 'delivered'
          : response.successCount > 0
            ? 'partial'
            : 'failed';

      // A full-recipient fallback is allowed only when the primary delivered
      // to zero devices. Partial success must not duplicate successful sends.
      const fallbackEligible = response.successCount === 0;
      await eventRef.update({
        'delivery.status': status,
        'delivery.provider': PRIMARY_PROVIDER,
        'delivery.fallbackEligible': fallbackEligible,
        'delivery.successCount': response.successCount,
        'delivery.failureCount': response.failureCount,
        'delivery.totalCount': tokens.length,
        'delivery.completedAt': admin.firestore.FieldValue.serverTimestamp(),
        'delivery.error':
          response.successCount === 0 ? 'Primary FCM delivery failed' : null,
      });

      console.log(
        `SOS ${sosId}: ${response.successCount} delivered, ${response.failureCount} failed`
      );

      // Delivery is already recorded. Token cleanup failure must not change
      // the receipt or cause a retry of the notification send.
      const invalidTokens = [];
      response.responses.forEach((result, index) => {
        if (result.success) return;
        const errorCode = result.error?.code;
        if (
          errorCode === 'messaging/invalid-registration-token' ||
          errorCode === 'messaging/registration-token-not-registered'
        ) {
          invalidTokens.push(tokens[index]);
        }
      });

      if (invalidTokens.length > 0) {
        try {
          const batch = admin.firestore().batch();
          invalidTokens.forEach((token) => {
            (tokenEntries.get(token) || []).forEach((ref) => batch.delete(ref));
          });
          await batch.commit();
          console.log(`Removed ${invalidTokens.length} stale token(s)`);
        } catch (cleanupError) {
          console.error('Stale-token cleanup failed');
        }
      }

      return response;
    } catch (error) {
      console.error(
        `Primary FCM delivery failed for SOS ${sosId}: ${error?.code || error?.name || 'unknown error'}`
      );

      if (claimed) {
        // Once the FCM call starts, an exception can have an ambiguous outcome.
        // Never run the fallback in that case because FCM may have accepted
        // the message. Only pre-send failures are safe fallback candidates.
        await eventRef.update({
          'delivery.status': sendStarted ? 'unknown' : 'failed',
          'delivery.provider': PRIMARY_PROVIDER,
          'delivery.fallbackEligible': !sendStarted,
          'delivery.successCount': 0,
          'delivery.failureCount': 0,
          'delivery.completedAt': admin.firestore.FieldValue.serverTimestamp(),
          'delivery.error': sendStarted
            ? 'Primary FCM outcome could not be confirmed'
            : String(error?.message || error),
        });
        return null;
      }

      // No provider claimed the event, so a retry cannot duplicate a send.
      throw error;
    }
  });
