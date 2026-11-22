# SafeNetic Security Checks, Potential Breaches, and Performance Enhancements

Last updated: 2026-11-19

## Executive assessment

Repository fixes are in the working tree, but they are **not deployed**. Production posture still depends on credential rotation, deployment, and project-console restrictions.

### Current remediation status

- Removed the SSH private key and service-account JSON from the current source tree. Start the new repository from this sanitized working tree. Revoke the old SSH key on every trusted host and revoke the service-account key in Google Cloud IAM.
- Removed the shared backend key. The SOS endpoint now verifies Firebase ID tokens, derives the user ID from the verified identity, and applies a per-user rate limit.
- Added default-deny Firestore rules and server-issued, expiring, single-use guardian invites. Deploy the rules and functions together before releasing the updated app.
- Removed `.env` from Flutter assets, removed the Maps key from the manifest, and made the Android build read it from a local property or environment variable. Removed stale key entries from the ignored local `.env`. Rotate and restrict the previously exposed Maps key in Google Cloud before release.
- Removed debug-key release signing, disabled cleartext traffic, stopped storing passwords, and removed token/phone data from debug logs.
- Switched the backend to application-default credentials and removed the local service-account JSON key from the workspace.
- Upgraded the Cloud Functions dependencies. The current production `npm audit` reports zero vulnerabilities; `functions/node_modules` is no longer tracked.
- Node and Python syntax checks passed. Flutter tooling is unavailable in this environment, so Dart analysis/build was not run.

Firebase API-key restrictions, SSH/service-account key revocation, App Check registration/enforcement, and deployment cannot be completed from source code alone. App Check is not yet integrated in the Flutter client. The remaining non-secret local `.env` values are not loaded or bundled by current app code.

## Historical checks performed (2026-09-20 snapshot)

The table and detailed findings below describe the pre-remediation snapshot. Their evidence and status statements are historical and are superseded by the current remediation status above.

| Check | Result |
|---|---|
| Ruflo status | Not initialized in this repository |
| Ruflo/`@claude-flow/cli` deep security scan | 0 automated findings; artifact saved at `.claude/security-scans/scan-all-deep.json` |
| Secret and sensitive-file review | Tracked SSH private key and client-bundled backend credential design found |
| Firebase authorization review | No `firestore.rules`, `storage.rules`, `firebase.json`, or `.firebaserc` found |
| Guardian-link review | Cross-user token write is initiated from the client using only a protected-user UID |
| Android manifest review | Cleartext traffic enabled; broad background/location/audio/SMS permissions present |
| Backend auth/logging review | Static API key, caller-selected user/event path, no rate limiting; full token-value logging removed in the current change |
| Release configuration review | Release APK is signed with the debug key |
| npm production audit | 14 vulnerabilities: 1 high, 13 moderate |
| Flutter dependency review | 89 locked packages upgradable; 42 constraints behind resolvable versions; 2 transitive packages discontinued |
| Flutter static analysis | 1 warning and 3 deprecation notices; no compile errors |
| Flutter tests | 18 passed |
| Node syntax | Passed |
| Python syntax | Passed |

## Security findings

### SEC-001 — Tracked SSH private key

- Severity: **Critical**
- Evidence: `Cloud keys/ssh-key-2026-07-05.key` is tracked by Git.
- Risk: Anyone with repository/history access may be able to authenticate to infrastructure that trusts this key. Adding the path to `.gitignore` does not remove it from history.
- Immediate action:
  1. Revoke/remove the corresponding public key from every server and cloud account.
  2. Generate a replacement key outside the repository.
  3. Remove the private key from the current tree and rewrite Git history with an approved history-cleaning procedure.
  4. Invalidate old clones/artifacts where practical and review SSH/auth logs.
  5. Add `Cloud keys/` and private-key patterns to `.gitignore` plus CI secret scanning.

### SEC-002 — Shared backend secret is extractable from the mobile app

- Severity: **Critical**
- Evidence:
  - `pubspec.yaml` packages `.env` as a Flutter asset.
  - `ConfigService.safeneticApiKey` reads `SAFENETIC_API_KEY` in client code and has a hard-coded fallback.
  - `backend/main.py` uses the same style of hard-coded fallback for its API key.
- Risk: Mobile assets and application code are recoverable from an APK. An attacker can extract the shared key and call the SOS endpoint.
- Remediation:
  - Remove the backend secret from Flutter and from bundled assets.
  - Remove all hard-coded secret defaults; fail closed when server secrets are absent.
  - Authenticate callers with a short-lived Firebase ID token and verify it server-side.
  - Authorize the token subject against the requested user/event.
  - Add Firebase App Check/device attestation as an additional abuse signal, not as the sole authorization control.
  - Store server secrets in the deployment platform secret manager/environment only.

### SEC-003 — Backend trusts caller-supplied identity and event data

- Severity: **Critical**
- Evidence: `backend/main.py` accepts `userId`, `sosId`, name, coordinates, and alert type from a client protected only by the shared API key.
- Risk: With the extractable key, an attacker who learns or guesses a user ID can trigger guardian notifications, spoof emergency details, cause alarm fatigue, or conduct denial-of-service/harassment.
- Remediation:
  - Verify Firebase identity and derive the user ID from the verified token.
  - Read authoritative event data from Firestore by event ID; do not trust the client copy.
  - Require a server-side fallback-eligible state before sending.
  - Add per-user/device/IP rate limits, request body limits, replay protection, and abuse monitoring.

### SEC-004 — Firestore authorization is absent from source control

- Severity: **Critical until proven otherwise**
- Evidence: no versioned Firestore rules or Firebase project configuration were found.
- Risk: The deployed rules cannot be reviewed or reproduced. Overly broad rules could expose profiles, guardian phone numbers, medical/location data, alert history, SOS events, or FCM tokens.
- Remediation:
  - Export/version `firestore.rules` and `firebase.json`.
  - Default-deny all collections.
  - Permit users to read/write only their own profile and approved subcollections.
  - Prevent clients from writing server-owned delivery fields.
  - Restrict guardian token writes to a verified invite relationship and the authenticated guardian UID.
  - Add Firebase Emulator Suite allow/deny tests for every collection and role.

### SEC-005 — Guardian linking lacks an owner-approved proof in client code

- Severity: **High**
- Evidence: `registerAsGuardian(protectedUserId)` writes the caller’s FCM token below another user's document using only the protected user's UID.
- Risk: If Firestore rules permit this write, an unauthorized authenticated user could subscribe to a victim's emergency notifications and location.
- Remediation:
  - Use random, expiring, single-use invite codes or signed links.
  - Require protected-user approval and record both parties' UIDs.
  - Enforce the relationship in Firestore rules/server code.
  - Support revocation, device inventory, and a visible guardian audit trail.

### SEC-006 — Debug client logging still exposes an FCM token prefix

- Severity: **High**
- Implementation status: **Backend token-value logging removed; client debug logging remains.**
- Evidence:
  - The Flutter app logs a token prefix in debug mode.
  - The FastAPI backend and Cloud Function now log counts and event IDs without token values.
- Risk: Central logs, support exports, or shared consoles may disclose tokens. A token is sensitive routing data and should be treated as a credential-like identifier.
- Remediation:
  - Remove token values from logs in every environment.
  - Log only counts, event IDs, provider status, and a non-reversible short hash when correlation is essential.
  - Apply production log access controls and retention limits.

### SEC-007 — SOS idempotency implemented locally; rate limiting and production verification remain

- Severity: **High**
- Implementation status: **Mitigation implemented but not deployed/integration-tested.**
- Evidence: the Cloud Function now transactionally claims routed `pending` events; the backend transactionally accepts only explicit zero-success failures with `fallbackEligible: true`; both write provider/count/status receipts. Repeated or concurrent backend calls are rejected with HTTP 409. Ambiguous post-send exceptions are recorded as `unknown` and are not retried.
- Remaining risk: the guarantee has not yet been exercised against Firebase emulators or production concurrency, and the endpoint still lacks per-user/IP rate limits. Intentional creation of many distinct event IDs can still cause spam and cost.
- Remaining remediation:
  - Add emulator tests for concurrent claims, retries, partial success, timeouts, and process interruption.
  - Apply authenticated per-user/event and edge/IP rate limits.
  - Deploy Cloud Function first, backend second, and client last; then verify exactly one guardian push per event on real devices.

### SEC-008 — Release builds use the debug signing key

- Severity: **High**
- Evidence: `android/app/build.gradle.kts` assigns the debug signing configuration to the release build.
- Risk: The build lacks an appropriate production trust and key-management process; future secure updates may become difficult.
- Remediation:
  - Generate a dedicated release/upload key.
  - Store it outside Git and inject credentials through protected CI secrets.
  - Enable Play App Signing if distributing through Google Play.
  - Document key backup, rotation, and incident response.

### SEC-009 — Production dependency vulnerabilities

- Severity: **High**
- Evidence: `npm audit --omit=dev` reports 14 vulnerabilities, including a high-severity `fast-xml-parser` issue and moderate issues in `body-parser`, `qs`, `protobufjs`, `uuid`, and Firebase dependency chains.
- Risk: Denial of service and parser/resource-consumption weaknesses in deployed function dependencies.
- Remediation:
  - Run a reviewed non-breaking `npm audit fix`, test, and redeploy.
  - Plan the Firebase Admin major upgrade needed to clear the remaining `uuid` chain.
  - Upgrade the declared Node runtime from 18 after confirming Firebase support.
  - Add automated npm audit/OSV/Dependabot checks.

### SEC-010 — Cleartext traffic is globally enabled

- Severity: **Medium**
- Evidence: Android application manifest sets `android:usesCleartextTraffic="true"`.
- Risk: Any accidental HTTP endpoint can transmit sensitive data without TLS; this broad setting weakens the platform default.
- Remediation:
  - Remove the flag or set it to false.
  - If local development requires HTTP, use a debug-only network security configuration scoped to exact hosts.

### SEC-011 — Password is retained for automatic login

- Severity: **Medium**
- Evidence: the login screen stores and restores the Firebase email and password with `flutter_secure_storage`.
- Risk: Secure storage reduces exposure but retaining the reusable password is unnecessary and increases impact if device secrets are extracted.
- Remediation:
  - Rely on Firebase Auth's persisted refresh/session tokens.
  - Never repopulate the password field.
  - Use local authentication to unlock the app/session rather than storing the password.
  - Clear legacy stored values during migration and on sign-out.

### SEC-012 — API keys require explicit restrictions

- Severity: **Medium**
- Evidence: Google/Firebase API keys are present in Android/Firebase configuration, as expected for client Firebase apps, but repository evidence of API/application restrictions is unavailable.
- Risk: Unrestricted keys can be abused against enabled Google APIs and quotas.
- Remediation:
  - Restrict the Maps key to the Android package and production signing certificate.
  - Restrict APIs to the minimum required.
  - Review quotas/billing alerts and rotate any key that was used outside intended restrictions.

### SEC-013 — Sensitive error and initialization details can reach users/logs

- Severity: **Medium**
- Evidence: Firebase initialization exceptions are rendered directly in the UI; the backend returns raw exception strings in HTTP 500 details.
- Risk: Internal service/configuration details may aid reconnaissance.
- Remediation:
  - Show stable user-safe error codes/messages.
  - Keep detailed exceptions only in access-controlled structured logs with sensitive fields redacted.

### SEC-014 — Broad Android permissions and privacy surface

- Severity: **Medium**
- Evidence: the app requests SMS, fine/coarse/background location, microphone, Bluetooth scan/connect, wake lock, boot completed, battery optimization exemption, notifications, foreground service types, and full-screen intent.
- Risk: These permissions are justified by features but create a large abuse/privacy surface and store-review burden.
- Remediation:
  - Request permissions just in time and only when the feature is enabled.
  - Provide clear disclosures and revocation behavior.
  - Confirm foreground-service declarations match actual use.
  - Document data retention, deletion, consent, and guardian visibility.
  - Remove permissions that are not required in the production flavor.

### SEC-015 — Repository and CI supply-chain hygiene

- Severity: **Medium**
- Evidence:
  - 3,691 `functions/node_modules` files are tracked.
  - GitHub Actions use mutable version tags rather than pinned commit SHAs.
  - No Dependabot configuration or CI secret scan is present.
- Risk: Bloated diffs hide malicious/accidental changes, vendored dependency files become stale, and mutable action tags expand supply-chain risk.
- Remediation:
  - Remove tracked `node_modules`, add appropriate ignore rules, and use `npm ci` from the lockfile.
  - Pin actions to reviewed commit SHAs.
  - Add dependency updates, secret scanning, code scanning, and artifact provenance/SBOM generation.

### SEC-016 — Service account operational controls need verification

- Severity: **Medium**
- Evidence: the backend loads a long-lived `serviceAccountKey.json` file; it is ignored by Git, but deployment scripts instruct operators to copy it to the application directory.
- Risk: Long-lived JSON keys are high-impact if copied, backed up, or permissioned incorrectly.
- Remediation:
  - Prefer workload identity/instance credentials over downloadable keys.
  - If a file key is temporarily unavoidable, use least privilege, strict ownership/mode, rotation, and monitoring.
  - Keep the key outside the writable application directory.

## Potential breach scenarios

| Scenario | Likely path | Impact | Priority response |
|---|---|---|---|
| Infrastructure login using leaked SSH key | Clone/history exposes tracked private key | Server takeover, data/token theft | Revoke key, investigate logs, rotate related secrets |
| Fake emergency alert campaign | Extract shared API key from APK and submit arbitrary user IDs/events | Guardian spam, panic, reputational harm | Disable/rotate shared key; require verified Firebase identity and event claims |
| Unauthorized guardian subscription | Submit a victim UID to client linking flow under permissive rules | Receive victim alerts and location | Lock Firestore rules; deploy invite approval flow |
| User/location data exposure | Overly broad or missing deployed Firestore rules | Privacy breach involving profiles, phone numbers, locations, medical context | Default-deny rules and emulator tests |
| Notification token exposure | Backend/debug logs contain FCM tokens | Targeting metadata disclosure and possible abuse | Purge/redact logs and remove token logging |
| Duplicate/replayed SOS | Repeated endpoint calls or both providers dispatch | Alarm fatigue, cost, loss of trust | Transactional event ownership and idempotency |
| Dependency DoS | Crafted parser/input path reaches vulnerable package | Function unavailability or resource exhaustion | Upgrade dependencies and enforce size/rate limits |

## Performance findings and enhancements

### PERF-001 — No-op one-second background timer

- Evidence: `background_service.dart` starts a one-second periodic timer whose body only checks foreground status.
- Impact: needless wakeups and battery use in a safety app expected to run for long periods.
- Enhancement: remove the timer; use event-driven service lifecycle callbacks. If a health heartbeat is required, use a much lower frequency and persist/cancel the timer.

### PERF-002 — Battery polling timer is not retained or cancelled

- Evidence: `BatteryOptimizationService` creates a five-minute periodic timer but only cancels the battery stream in `dispose`.
- Impact: duplicate polling after lifecycle recreation and a resource leak.
- Enhancement: store the timer in a field, cancel it in `dispose`, and avoid starting a second timer.

### PERF-003 — BLE characteristic subscriptions are not managed

- Evidence: heart-rate and accelerometer `onValueReceived.listen` subscriptions are not stored; `dispose` cancels only scan and connection subscriptions.
- Impact: duplicate callbacks after reconnect, retained objects, unnecessary CPU, and closed-controller errors.
- Enhancement: retain all characteristic subscriptions, cancel on disconnect/reconnect/dispose, and disable notifications before teardown.

### PERF-004 — Home background-event subscription is not cancelled

- Evidence: `HomeScreen` listens to `FlutterBackgroundService().on('onEmergencyEvent')` without retaining the subscription.
- Impact: reopening the screen can multiply event handlers and duplicate emergency UI actions.
- Enhancement: store the subscription and cancel it in `dispose`.

### PERF-005 — FFT/spectrogram preparation allocates heavily

- Evidence: audio processing repeatedly creates FFT windows, nested mel arrays, transposed spectrograms, and 256×256×3 nested lists; TFLite inference is invoked synchronously.
- Impact: garbage-collection pressure, UI/background isolate latency, and increased battery use.
- Enhancement:
  - Reuse typed buffers and preallocated tensors.
  - Move preprocessing/inference to a dedicated isolate where supported.
  - Benchmark end-to-end frame latency and dropped audio.
  - Reduce copies such as `sublist`, repeated `List.generate`, and transpose allocation.

### PERF-006 — Motion input tensors are rebuilt each inference

- Evidence: nested `List.generate` calls allocate a full motion tensor every inference interval.
- Impact: steady allocation and GC churn at 500 ms intervals.
- Enhancement: maintain a ring buffer and reusable typed input/output tensors; benchmark TFLite delegates and thread settings on target phones.

### PERF-007 — Very large stateful screens

- Evidence: Home is 1,466 lines, ML Test 1,315, Settings 1,170, Profile 987, and Alert Sent 699.
- Impact: broad rebuild scopes, hard-to-profile state changes, merge risk, and slow review/testing.
- Enhancement: extract feature controllers/view models and small const widgets; use selectors/listenable builders so sensor/location updates rebuild only affected regions.

### PERF-008 — Backend token cleanup performs serial queries

- Evidence: each invalid token triggers a separate Firestore query before a batch delete.
- Impact: extra latency and reads during failure-heavy multicast results.
- Enhancement: retain token document references when initially loading tokens, map response index directly to the document reference, and batch-delete without re-querying.

### PERF-009 — Repository dependency footprint

- Evidence: tracked `node_modules` accounts for 3,691 of 4,323 tracked files.
- Impact: slow clones, indexing, scans, diffs, and CI cache invalidation.
- Enhancement: untrack dependencies and restore them deterministically with `npm ci`.

### PERF-010 — Dependency maintenance debt

- Evidence: Flutter reports 89 upgradable locked dependencies and 42 constraints behind resolvable versions; two transitive packages are discontinued.
- Impact: missed fixes/performance improvements and harder future migrations.
- Enhancement: upgrade in tested batches (Firebase, device/platform plugins, UI/network), review breaking changes, and capture startup/inference/APK baselines before and after.

### PERF-011 — Duplicate libraries and service responsibilities

- Evidence: both `location` and `geolocator` are dependencies, while notification responsibilities are split across SMS service, SOS event service, guardian FCM service, Cloud Function, and FastAPI.
- Impact: larger binary/permission surface and unclear ownership that contributed to duplicate alerts.
- Enhancement: consolidate location use if feasible and define one orchestration boundary with explicit channel results and server-owned delivery state.

## Remediation plan

### First 24 hours

- Revoke the tracked SSH key and rotate affected access.
- Disable/rotate the shared SOS backend key and temporarily restrict the endpoint at the edge.
- Confirm deployed Firestore rules are not open; apply an emergency default-deny policy if uncertain.
- Confirm deployed backend/function versions no longer emit token values and purge or restrict historical logs.

### Before the next internal build

- Deploy and integration-test transactional SOS provider ownership and accurate UI receipts.
- Add Firebase identity/App Check verification, authorization, and rate limits around the idempotent event claim.
- Commit tested Firestore rules and emulator tests.
- Configure release signing.
- Upgrade vulnerable npm dependencies and rerun audits.
- Remove cleartext traffic and stored passwords.

### Before production

- Complete end-to-end and abuse-case alert tests on real devices.
- Perform a focused penetration test of auth, guardian linking, Firestore rules, backend replay, and location exposure.
- Add CI security gates, pinned actions, dependency automation, SBOM/provenance, and secret scanning.
- Establish log retention, incident response, data deletion, key rotation, and rollback procedures.
- Measure background battery drain, inference latency, memory, network use, and alert-delivery latency against acceptance thresholds.

## Retest checklist

- [ ] Old SSH key is rejected everywhere; initialize the new repository from the sanitized working tree.
- [ ] No client bundle contains a reusable backend secret.
- [ ] Backend derives identity from a verified token and rejects mismatched user/event data.
- [ ] Firestore emulator tests prove unauthorized profile, guardian, token, location, and delivery writes fail.
- [ ] Repeated SOS requests and duplicate triggers produce no duplicate guardian notification.
- [ ] Logs contain no FCM tokens, passwords, service-account data, or precise location beyond approved retention.
- [ ] Release APK is signed with the production process and Maps key restrictions match its certificate.
- [ ] `npm audit --omit=dev` has no unaccepted high/critical findings.
- [ ] Flutter analysis/tests, backend tests, function tests, and end-to-end alert tests pass in CI.
- [ ] Background timers/subscriptions are lifecycle-safe and battery/inference benchmarks meet targets.
