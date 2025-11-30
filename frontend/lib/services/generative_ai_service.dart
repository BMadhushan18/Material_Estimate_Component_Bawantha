import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/config.dart';

class GenerativeAiService {
  final String apiKey;
  final String model;
  final String endpoint;

  GenerativeAiService({String? apiKey, String? model, String? endpoint})
    : apiKey = apiKey ?? AppConfig.geminiApiKey,
      model = model ?? AppConfig.geminiModel,
      endpoint = endpoint ?? AppConfig.geminiEndpoint;

  bool get isConfigured => apiKey.isNotEmpty;

  Future<String> generateContent(
    String prompt, {
    double temperature = 0.7,
    int maxOutputTokens = 1024,
    double topP = 0.95,
    int topK = 40,
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Gemini API key is not configured. Use --dart-define=GEMINI_API_KEY=KEY',
      );
    }

    final url = '$endpoint/$model:generateContent?key=$apiKey';

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': temperature,
        'topK': topK,
        'topP': topP,
        'maxOutputTokens': maxOutputTokens,
      },
    };

    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        final content = data['candidates'][0]['content'];
        if (content != null &&
            content['parts'] != null &&
            content['parts'].isNotEmpty) {
          return content['parts'][0]['text'] as String;
        }
      }
      throw Exception('Unexpected Gemini response structure');
    } else if (res.statusCode == 429) {
      throw Exception('Rate limit exceeded (429)');
    } else if (res.statusCode == 403 || res.statusCode == 401) {
      throw Exception(
        'API key invalid or unauthorized (status: ${res.statusCode})',
      );
    } else {
      throw Exception('Gemini API Error: ${res.statusCode} ${res.body}');
    }
  }
}
