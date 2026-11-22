# SafeNetic Project Progress

Last updated: 2026-09-20

## Current status

SafeNetic is a working Android-first Flutter prototype with Firebase authentication and data storage, guardian management, location sharing, SMS and FCM emergency channels, background sensing, on-device ML assets, BLE support, local caching, a FastAPI fallback service, a Firestore Cloud Function, a marketing website, and a basic release workflow.

The automated test suite currently passes (18 tests). The SOS push de-duplication contract is implemented locally across the client, Cloud Function, FastAPI fallback, Firestore receipts, alert history, and alert screen. It is not production-verified until the server components are deployed in the required order and exercised with emulator/real-device concurrency tests. The branch is still **not release-ready** because release builds use the debug signing key, production security issues remain open, and the repository does not contain Firestore security rules.

## Audit baseline

| Item | Result |
|---|---|
| Latest commit reviewed | `03e4f070` — emergency alert notification system and countdown UI |
| Tracked files | 4,323 |
| Tracked `node_modules` files | 3,691 |
| Dart source files | 56 |
| Project test files | 7 files / 18 tests |
| Flutter tests | 18 passed |
| Flutter analysis | No compile errors; 1 warning and 3 deprecation notices |
| Cloud Function syntax | Passed `node --check functions/index.js` |
| Python backend syntax | Passed `python -m compileall -q backend` |
| Ruflo state | Ruflo is not initialized in this repository |
| Ruflo deep security scan | Reported 0 findings; manual and dependency checks found material issues |
| Working tree at audit start | Modified `lib/services/sos_event_service.dart`; generated `.claude/security-scans/scan-all-deep.json` |

## Implemented areas

### Application foundation

- Flutter application structure, routing, shared theme, reusable widgets, and light/dark theme providers are present.
- Android is the primary configured mobile target. Firebase options exist for Android and web; Windows and Linux are explicitly unsupported.
- App startup initializes configuration, Firebase, messaging, local notifications, background services, onboarding state, and device token registration.
- A 15-minute background inactivity sign-out policy is implemented.

### Accounts, profile, and settings

- Firebase email/password sign-up and sign-in are implemented.
- User profiles, SOS delay settings, guardian management, device management, notification preferences, and onboarding/terms screens are present.
- Profile, settings, and quick-SOS entry points are implemented.
- Credentials are currently persisted with secure storage for automatic login; this is flagged for redesign in [SECURITY_CHECKS.md](SECURITY_CHECKS.md).

### Data and offline storage

- Firestore services cover users, guardians, devices, alert history, guardian tokens, and SOS events.
- SQLite mirrors users, guardians, and alert history for local caching.
- Alert history is read as a descending, 50-item Firestore stream.
- Firestore rule/configuration files are absent from the repository, so server-side authorization cannot be verified.

### Guardian linking and notifications

- Guardians can link a device to a protected user ID.
- Guardian FCM tokens are registered in `users/{protectedUserId}/guardian_tokens/{guardianUid}`.
- Foreground, background-open, and terminated-state FCM handling are implemented.
- High-priority Android notification channels and an incoming emergency screen are implemented.
- SMS sends through the vendored Android `background_sms` plugin, with a system SMS intent fallback when silent sending is unavailable.

### SOS and emergency flow

- Manual SOS and quick SOS entry points are implemented.
- The alert screen includes a configurable countdown and cancellation path.
- Current location is acquired and included in SMS/FCM payloads when available.
- Firestore alert-history logging and SOS-event logging are implemented.
- A Firestore-triggered Cloud Function sends FCM notifications.
- A FastAPI service at `alerts.safenetic.online` also sends FCM notifications.
- The pre-audit implementation invoked both paths for one event, which could notify the same guardian twice.

### Detection, background work, and devices

- Motion and distress-noise TFLite assets are included.
- Accelerometer and gyroscope collection, buffered motion inference, confidence thresholds, and callbacks are implemented.
- Audio capture, PCM conversion, FFT/mel preprocessing, spectrogram generation, and noise-model inference are implemented.
- A heuristic motion fallback remains in the ML service and should not be treated as production-grade detection.
- A foreground background-service scaffold runs monitoring and adjusts the inference interval for low battery.
- BLE scanning, connection state, heart-rate notifications, and accelerometer characteristic parsing are implemented.
- Battery-state tracking and low-power mode are implemented.

### Backend, deployment, and website

- The Python FastAPI backend initializes Firebase Admin, accepts SOS trigger requests, sends multicast FCM, and removes invalid tokens.
- Deployment scripts define an Oracle VM setup, a systemd service, and a Cloudflare Tunnel for `alerts.safenetic.online`.
- The Firebase Cloud Function sends multicast FCM and removes stale tokens.
- A static marketing website is present.
- A tag-triggered GitHub Actions workflow builds an APK and publishes a GitHub release.

### Tests currently present

- Model mapping/copy tests for users, guardians, devices, and alerts.
- Emergency SMS message construction tests.
- Dashboard SOS button and status-card widget tests.
- Missing: Firebase emulator tests, SOS integration tests, backend tests, Cloud Function tests, auth tests, guardian-link authorization tests, ML accuracy/regression tests, BLE tests, and release smoke tests.

## SOS push de-duplication

The requested delivery policy is:

1. Firestore Cloud Function is the primary push provider.
2. `alerts.safenetic.online` is a fallback only after the primary records an explicit failure.
3. A timeout remains pending and does not invoke the fallback, because the primary may still be delivering.
4. The SOS Firestore document is the durable delivery receipt.

### Implemented in the current uncommitted change

- Added `SosDeliveryResult` with provider, status, success/failure/total counts, and error data.
- Added a `delivery` object to newly created SOS documents.
- Removed the unconditional HTTPS call after every Firestore write.
- Added a 15-second wait for a terminal primary delivery receipt.
- Added fallback invocation only when Firestore explicitly reports `failed` and `fallbackEligible: true`.
- Preserved SOS event creation in Firestore.
- A timeout returns `pending` rather than risking a duplicate alert.
- The Cloud Function atomically claims only new events routed to `firestore_cloud_function`, writes durable processing/final receipts, and makes fallback eligible only after a confirmed zero-success result.
- A partial primary success never invokes the full-recipient fallback because that would duplicate the successful subset.
- An exception after an FCM call begins is recorded as `unknown`; fallback is suppressed because FCM may already have accepted the message.
- The FastAPI service atomically claims only explicit eligible failures. Repeated and concurrent calls receive HTTP 409 and cannot send again.
- Legacy app events without delivery metadata are handled only by the backend; the new Cloud Function deliberately skips them.
- Both providers deduplicate repeated FCM token values before multicast sending and clean stale token documents afterward.
- `NotificationService` now returns separate SMS and push results and writes both to the existing Firestore alert-history entry.
- The alert screen reports primary/backup acceptance, partial results, pending/unknown outcomes, no-guardian cases, and SMS status without claiming unconfirmed delivery.
- Added result-state unit tests for primary success, backup success, ambiguous outcomes, and confirmed all-channel failure.

### Validation completed

- `flutter test`: 18 passed.
- `flutter analyze`: no new issues from this change; four pre-existing findings remain.
- `node --check functions/index.js`: passed.
- Direct local module loading is currently blocked by the repository's incomplete checked-in `functions/node_modules` (`@google-cloud/firestore/build/src/path` is missing). Run a clean dependency install in deployment/emulator CI rather than trusting the vendored tree.
- `python -m compileall -q backend`: passed.
- `git diff --check`: passed; line-ending warnings only.

### Still required before production release

- Add Firebase emulator/integration tests for transactional claims, simultaneous/repeated fallback calls, function retries, partial multicast results, and process interruption.
- Recreate Cloud Function dependencies from `package-lock.json` with a clean Node 18 install before emulator or deployment validation.
- Deploy in this exact order: **Cloud Function first, FastAPI backend second, client last**. Deploying the new backend before the new function can duplicate alerts from legacy clients because the old function still sends legacy events.
- Run a real-device matrix with at least two guardian tokens and verify exactly one push per event for primary success, zero-success fallback, timeout, ambiguous failure, partial success, and repeated HTTP calls.
- Add monitoring for SOS documents stuck in `processing` or `unknown`; do not automatically retry ambiguous sends.

## Remaining work by priority

### P0 — release blockers

- Deploy and integration-test the implemented SOS primary/fallback contract described above.
- Rotate and purge the tracked SSH private key.
- Remove the shared backend secret from the app bundle and authenticate backend requests with Firebase identity/App Check plus server-side authorization.
- Add and test Firestore security rules, including protected guardian-link and token-write rules.
- Replace debug signing with a protected release keystore and CI secrets.
- Upgrade vulnerable Cloud Function dependencies; `npm audit --omit=dev` reports 1 high and 13 moderate vulnerabilities.

### P1 — reliability and security

- Add rate limiting, replay/idempotency protection, audit logging, request-size limits, and structured error handling to the FastAPI endpoint.
- Stop logging FCM token values and avoid returning raw internal exception details.
- Remove unnecessary cleartext network permission and review all high-risk Android permissions.
- Replace raw-UID guardian linking with an expiring, owner-approved invite/pairing flow.
- Stop storing the Firebase password; rely on Firebase session persistence and use biometrics only to unlock local app access.
- Add Firebase emulator coverage and end-to-end emergency-delivery tests.
- Add CI gates for formatting, analysis, tests, dependency audits, and secret scanning.

### P2 — maintainability and performance

- Remove tracked `functions/node_modules`; keep only manifests/lockfile and install in CI/deployment.
- Initialize Ruflo only if the team wants Ruflo MCP/hooks/memory in this repository.
- Upgrade dependencies in staged groups; 89 locked packages are upgradable and 42 direct/transitive constraints block resolvable versions.
- Split very large screens (Home 1,466 lines, ML Test 1,315, Settings 1,170, Profile 987) into focused widgets/controllers.
- Move FFT/spectrogram preprocessing and heavy inference preparation off the UI isolate or into reusable typed buffers.
- Fix uncancelled timers and stream subscriptions documented in [SECURITY_CHECKS.md](SECURITY_CHECKS.md).
- Add performance baselines for startup, background battery use, inference latency, memory, and APK size.
- Replace the heuristic motion placeholder with a validated fallback or clearly disable it in production.
- Add README, architecture, deployment, incident-response, and data-retention documentation.

## Suggested delivery sequence

1. Contain exposed credentials and establish Firestore authorization.
2. Deploy the implemented SOS components in the documented order.
3. Add emulator, concurrency, and real-device integration tests for the entire alert flow.
4. Fix dependency advisories and release signing.
5. Address resource leaks and background battery/inference performance.
6. Refactor oversized screens and expand feature coverage.
7. Run a staged internal release, real-device alert test, and rollback drill.

## Definition of done for the SOS alert change

- [x] One SOS event produces at most one push attempt owner at a time in the implementation.
- [x] The backend cannot notify a routed event unless the Cloud Function recorded an eligible failure.
- [x] Partial primary success never triggers a full-recipient fallback.
- [x] Firestore contains the event and delivery receipt, including failed or ambiguous outcomes.
- [x] The UI never claims push acceptance without a server-confirmed success count.
- [x] SMS status and push status are shown separately.
- [ ] Firebase emulator tests cover duplicate function delivery, repeated/concurrent HTTP calls, timeout, zero-token, stale-token, partial failure, and interruption cases.
- [ ] Real-device verification confirms one push per event across primary and fallback scenarios.
- [x] Production deployment order is documented; operational rollback steps still need deployment-runbook detail.
