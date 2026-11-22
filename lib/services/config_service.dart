/// Non-secret client configuration supplied with `--dart-define` when needed.
///
/// Credentials must never be placed here: values compiled into a mobile app can
/// be recovered from the application package.
class ConfigService {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://alerts.safenetic.online',
  );

  static const int apiTimeout = int.fromEnvironment(
    'API_TIMEOUT_MS',
    defaultValue: 30000,
  );
}
