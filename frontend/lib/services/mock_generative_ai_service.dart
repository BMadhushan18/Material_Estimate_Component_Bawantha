import 'dart:async';

class MockGenerativeAiService {
  final bool isConfigured = true;

  Future<String> generateContent(
    String prompt, {
    double temperature = 0.7,
    int maxOutputTokens = 1024,
    double topP = 0.95,
    int topK = 40,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final preview = prompt.length > 120
        ? '${prompt.substring(0, 120)}...'
        : prompt;
    return 'Mock reply for: $preview';
  }
}
