/// Compile-time configuration.
///
/// Provide values with:
///   flutter run --dart-define-from-file=env.json
///
/// `env.json` is gitignored; `env.example.json` is committed.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void validate() {
    if (!isConfigured) {
      throw const ConfigurationException(
        'Missing SUPABASE_URL / SUPABASE_ANON_KEY. '
        'Run with --dart-define-from-file=env.json (see env.example.json).',
      );
    }
  }
}

class ConfigurationException implements Exception {
  const ConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}
