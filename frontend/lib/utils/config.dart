import 'dart:io' show Platform;

class AppConfig {
  // Base URL for API calls
  static String get apiBaseUrl {
    if (Platform.isAndroid) {
      return 'https://unpleasant-theadora-rdtech-b5350ed8.koyeb.app';
    } else if (Platform.isIOS) {
      return 'http://127.0.0.1:5134';
    } else {
      return 'http://10.43.52.207:5134';
    }
  }

  static const String appName = 'Clean Water & Sanitation App';
  static const String appVersion = '1.0.0';
  static const bool enableAnalytics = true;

  static const String _geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
  static String get geminiApiKey => _geminiApiKey;

  static const String geminiModel = 'gemini-2.5-flash';
  static const String geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
}
