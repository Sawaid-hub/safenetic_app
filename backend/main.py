from datetime import datetime, timedelta, timezone
from typing import Optional

import firebase_admin
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth, firestore, messaging
from google.cloud import firestore as google_firestore
from pydantic import BaseModel, Field

BACKEND_PROVIDER = 'alerts_backend'

try:
    try:
        firebase_app = firebase_admin.get_app()
    except ValueError:
        # Uses workload identity or GOOGLE_APPLICATION_CREDENTIALS outside the
        # application directory; private JSON keys are never loaded from source.
        firebase_app = firebase_admin.initialize_app()
    db = firestore.client(app=firebase_app)
except Exception as setup_error:
    # Keep the health endpoint available, but all SOS requests fail closed.
    print(f'Firebase backend setup failed: {type(setup_error).__name__}')
    db = None

app = FastAPI(title='SafeNetic Custom Backend')
bearer_scheme = HTTPBearer(auto_error=False)


@app.get('/')
async def root():
    return {'message': 'SafeNetic Backend is Online! 🚀'}


def authenticated_uid(
    credentials_header: Optional[HTTPAuthorizationCredentials] = Depends(
        bearer_scheme
    ),
) -> str:
    if credentials_header is None:
        raise HTTPException(status_code=401, detail='Authentication required')
    try:
        claims = auth.verify_id_token(
            credentials_header.credentials,
            check_revoked=True,
        )
    except Exception:
        raise HTTPException(status_code=401, detail='Invalid authentication token')
    uid = claims.get('uid')
    if not isinstance(uid, str) or not uid:
        raise HTTPException(status_code=401, detail='Invalid authentication token')
    return uid


class SosTriggerRequest(BaseModel):
    sosId: str = Field(min_length=1, max_length=128, pattern=r'^[^/]+$')


FALLBACK_RATE_LIMIT = 10
FALLBACK_RATE_WINDOW = timedelta(minutes=1)


def _consume_fallback_rate_limit(uid: str) -> bool:
    now = datetime.now(timezone.utc)
    ref = db.collection('backend_rate_limits').document(uid)
    transaction = db.transaction()

    @google_firestore.transactional
    def consume(transaction, rate_ref):
        snapshot = rate_ref.get(transaction=transaction)
        current = snapshot.to_dict() or {}
        window_start = current.get('windowStartedAt')
        count = current.get('count', 0)
        if (
            window_start is not None
            and now - window_start < FALLBACK_RATE_WINDOW
        ):
            if count >= FALLBACK_RATE_LIMIT:
                return False
            transaction.update(rate_ref, {'count': count + 1})
            return True
        transaction.set(rate_ref, {'windowStartedAt': now, 'count': 1})
        return True

    return consume(transaction, ref)


def _claim_event_for_backend(event_ref):
    transaction = db.transaction()

    @google_firestore.transactional
    def claim(transaction, ref):
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            return None

        event_data = snapshot.to_dict() or {}
        delivery = event_data.get('delivery')

        if delivery:
            is_eligible_fallback = (
                delivery.get('fallback') == BACKEND_PROVIDER
                and delivery.get('status') == 'failed'
                and delivery.get('fallbackEligible') is True
            )
            if not is_eligible_fallback:
                return None
            route = 'fallback'
        else:
            # Compatibility for older app versions: the new Cloud Function
            # skips events without routing metadata, so the backend is their
            # one primary provider. This transaction still prevents replay.
            route = 'legacy_primary'

        transaction.update(ref, {
            'delivery.status': 'processing',
            'delivery.primary': (
                'firestore_cloud_function'
                if route == 'fallback'
                else BACKEND_PROVIDER
            ),
            'delivery.fallback': BACKEND_PROVIDER,
            'delivery.provider': BACKEND_PROVIDER,
            'delivery.route': route,
            'delivery.fallbackEligible': False,
            'delivery.startedAt': google_firestore.SERVER_TIMESTAMP,
        })
        return route

    return claim(transaction, event_ref)


def _write_delivery(
    event_ref,
    *,
    status,
    success_count,
    failure_count,
    total_count,
    error=None,
):
    event_ref.update({
        'delivery.status': status,
        'delivery.provider': BACKEND_PROVIDER,
        'delivery.fallbackEligible': False,
        'delivery.successCount': success_count,
        'delivery.failureCount': failure_count,
        'delivery.totalCount': total_count,
        'delivery.completedAt': google_firestore.SERVER_TIMESTAMP,
        'delivery.error': error,
    })


@app.post('/api/sos/trigger')
async def trigger_sos(
    request: SosTriggerRequest,
    uid: str = Depends(authenticated_uid),
):
    """
    HTTPS fallback for new events and sole provider for legacy events.

    A new event is accepted only after the Firestore Cloud Function records an
    explicit zero-success failure. The transaction claim makes repeated or
    concurrent calls idempotent and prevents both providers from sending.
    """
    if not db:
        raise HTTPException(
            status_code=500,
            detail='SOS delivery is temporarily unavailable',
        )

    if not _consume_fallback_rate_limit(uid):
        raise HTTPException(status_code=429, detail='SOS fallback rate limit reached')

    event_ref = (
        db.collection('users')
        .document(uid)
        .collection('sos_events')
        .document(request.sosId)
    )

    claimed = False
    send_started = False
    try:
        route = _claim_event_for_backend(event_ref)
        if route is None:
            raise HTTPException(
                status_code=409,
                detail='SOS event is not eligible for backend delivery',
            )
        claimed = True

        # The event document is authoritative. Request fields are retained in
        # the schema for compatibility but are not trusted for notification
        # content after the claim.
        event_snapshot = event_ref.get()
        event_data = event_snapshot.to_dict() or {}
        user_name = event_data.get('userName') or 'Unknown User'
        alert_type = event_data.get('alertType') or 'manual'
        is_automatic = event_data.get('generatedAutomatically') is True
        latitude = event_data.get('latitude')
        longitude = event_data.get('longitude')
        timestamp_value = event_data.get('timestamp')
        if hasattr(timestamp_value, 'isoformat'):
            timestamp = timestamp_value.isoformat()
        else:
            timestamp = ''

        guardian_tokens_ref = (
            db.collection('users')
            .document(uid)
            .collection('guardian_tokens')
        )
        token_entries = {}
        for token_doc in guardian_tokens_ref.stream():
            token = token_doc.to_dict().get('token')
            if not token:
                continue
            token_entries.setdefault(token, []).append(token_doc.reference)
        tokens = list(token_entries.keys())

        if not tokens:
            _write_delivery(
                event_ref,
                status='no_guardians',
                success_count=0,
                failure_count=0,
                total_count=0,
            )
            return {
                'message': 'No valid guardian tokens found',
                'delivery_status': 'no_guardians',
                'provider': BACKEND_PROVIDER,
                'route': route,
                'success_count': 0,
                'failure_count': 0,
                'total_count': 0,
            }

        if alert_type == 'fall':
            trigger_text = '⚠️ FALL DETECTED'
        elif alert_type == 'noise':
            trigger_text = '🔊 DISTRESS NOISE DETECTED'
        elif alert_type == 'motion':
            trigger_text = '📳 MOTION ANOMALY DETECTED'
        else:
            trigger_text = '🆘 SOS ACTIVATED'

        title = f'{trigger_text} — {user_name}'
        if is_automatic:
            body = (
                f'Automatic emergency alert triggered for {user_name}. '
                'Open SafeNetic to view their location.'
            )
        else:
            body = (
                f'{user_name} pressed the SOS button. '
                'Open SafeNetic to view their location.'
            )

        if latitude is not None and longitude is not None:
            body += f'\n📍 https://maps.google.com/?q={latitude},{longitude}'

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={
                'sosId': request.sosId,
                'userId': uid,
                'alertType': alert_type,
                'userName': user_name,
                'generatedAutomatically': str(is_automatic).lower(),
                'latitude': str(latitude) if latitude is not None else '',
                'longitude': str(longitude) if longitude is not None else '',
                'timestamp': timestamp,
            },
            android=messaging.AndroidConfig(
                priority='high',
                ttl=0,
                notification=messaging.AndroidNotification(
                    channel_id='sos_alert_channel',
                    priority='max',
                    default_vibrate_timings=True,
                    default_sound=True,
                    click_action='FLUTTER_NOTIFICATION_CLICK',
                    visibility='public',
                ),
            ),
            tokens=tokens,
        )

        send_started = True
        response = messaging.send_each_for_multicast(message)
        if response.success_count == len(tokens):
            delivery_status = 'delivered'
        elif response.success_count > 0:
            delivery_status = 'partial'
        else:
            delivery_status = 'failed'

        _write_delivery(
            event_ref,
            status=delivery_status,
            success_count=response.success_count,
            failure_count=response.failure_count,
            total_count=len(tokens),
            error=(
                'Fallback FCM delivery failed'
                if response.success_count == 0
                else None
            ),
        )

        invalid_tokens = []
        for index, result in enumerate(response.responses):
            if result.success:
                continue
            error_code = getattr(result.exception, 'code', None)
            if error_code in (
                'messaging/invalid-registration-token',
                'messaging/registration-token-not-registered',
            ):
                invalid_tokens.append(tokens[index])

        if invalid_tokens:
            try:
                batch = db.batch()
                for token in invalid_tokens:
                    for token_ref in token_entries.get(token, []):
                        batch.delete(token_ref)
                batch.commit()
            except Exception as cleanup_error:
                print('Stale-token cleanup failed')

        print(
            f'SOS {request.sosId} via {route}: '
            f'{response.success_count} delivered, '
            f'{response.failure_count} failed'
        )
        return {
            'message': 'SOS alert processed',
            'delivery_status': delivery_status,
            'provider': BACKEND_PROVIDER,
            'route': route,
            'success_count': response.success_count,
            'failure_count': response.failure_count,
            'total_count': len(tokens),
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f'Backend delivery failed for SOS {request.sosId}: {type(error).__name__}')
        if claimed:
            try:
                _write_delivery(
                    event_ref,
                    status='unknown' if send_started else 'failed',
                    success_count=0,
                    failure_count=0,
                    total_count=0,
                    error=(
                        'Fallback FCM outcome could not be confirmed'
                        if send_started
                        else 'Fallback delivery failed before sending'
                    ),
                )
            except Exception as receipt_error:
                print(f'Could not write failure receipt: {receipt_error}')
        raise HTTPException(status_code=500, detail='SOS delivery failed')
