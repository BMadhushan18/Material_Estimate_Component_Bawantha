import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io' show File;
import 'package:http/http.dart' as http;
import '../utils/config.dart';
import '../services/generative_ai_service.dart';
import '../services/mock_generative_ai_service.dart';

class AiChatScreen extends StatelessWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Chat')),
      body: const Padding(padding: EdgeInsets.all(8.0), child: AiChatCard()),
    );
  }
}

class AiChatCard extends StatefulWidget {
  const AiChatCard({super.key});

  @override
  State<AiChatCard> createState() => _AiChatCardState();
}

class _AiChatCardState extends State<AiChatCard> {
  final TextEditingController _ctrl = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;

  // Use real service when configured, otherwise fallback to mock for dev.
  late final dynamic _aiService;
  late final stt.SpeechToText _speech;
  bool _isListeningSpeech = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    final gen = GenerativeAiService();
    if (gen.isConfigured) {
      _aiService = gen;
    } else {
      _aiService = MockGenerativeAiService();
    }
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if (kIsWeb) return; // web speech is not supported here
    try {
      await _speech.initialize(onStatus: (s) {}, onError: (e) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isSending = true;
      _ctrl.clear();
    });

    try {
      final reply = await _aiService.generateContent(text);
      setState(() => _messages.add({'role': 'assistant', 'text': reply}));
    } catch (e) {
      setState(() => _messages.add({'role': 'assistant', 'text': 'Error: $e'}));
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked == null) return;
      final path = picked.path;
      setState(() {
        _messages.add({
          'role': 'user',
          'text': '[Image attached: ${picked.name}]',
          'imagePath': path,
          'fileName': picked.name,
        });
        _messages.add({
          'role': 'assistant',
          'text': 'Uploading and analyzing ${picked.name}...',
        });
      });
      await _uploadAndAnalyze(File(path), picked.name);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image pick failed: $e')));
    }
  }

  Future<void> _pickPdf() async {
    try {
      final typeGroup = XTypeGroup(label: 'pdf', extensions: ['pdf']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      setState(() {
        _messages.add({
          'role': 'user',
          'text': '[File attached: ${file.name}]',
          'filePath': file.path,
          'fileName': file.name,
        });
        _messages.add({
          'role': 'assistant',
          'text': 'Uploading and analyzing ${file.name}...',
        });
      });
      await _uploadAndAnalyze(File(file.path), file.name);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File pick failed: $e')));
    }
  }

  Future<void> _uploadAndAnalyze(File file, String filename) async {
    // Determine backend URL: prefer compile-time BACKEND_URL, otherwise AppConfig.apiBaseUrl
    final backendFromEnv = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: '',
    );
    final backendUrl = backendFromEnv.isNotEmpty
        ? backendFromEnv
        : AppConfig.apiBaseUrl;

    final uri = Uri.parse(
      backendUrl.endsWith('/')
          ? '${backendUrl}analyze-plan'
          : '$backendUrl/analyze-plan',
    );
    try {
      final req = http.MultipartRequest('POST', uri);
      req.fields['transcript'] = _lastWords;
      req.fields['userData'] = '{}';
      req.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: filename,
        ),
      );

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        final body = res.body;
        setState(() {
          // remove the 'Uploading and analyzing...' placeholder
          for (int i = _messages.length - 1; i >= 0; i--) {
            final m = _messages[i];
            if (m['role'] == 'assistant' &&
                (m['text'] as String).contains('Uploading and analyzing')) {
              _messages.removeAt(i);
              break;
            }
          }
          // backend returns JSON with analysis; show raw body (could be JSON)
          _messages.add({'role': 'assistant', 'text': body});
        });
      } else {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'text': 'Analyze API error: ${res.statusCode} ${res.body}',
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Failed to upload/analyze: $e',
        });
      });
    }
  }

  Future<void> _toggleListening() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input not supported on web')),
      );
      return;
    }

    if (_isListeningSpeech) {
      // stop and auto-send
      await _speech.stop();
      setState(() => _isListeningSpeech = false);
      if (_lastWords.trim().isNotEmpty) {
        _ctrl.text = _lastWords;
        await _send();
      }
      return;
    }

    // request permission
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
        return;
      }
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Microphone not available')));
      return;
    }

    setState(() {
      _isListeningSpeech = true;
      _lastWords = '';
    });

    _speech.listen(
      onResult: (r) {
        setState(() {
          _lastWords = r.recognizedWords;
          _ctrl.text = _lastWords;
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: null,
      onSoundLevelChange: null,
      cancelOnError: true,
      listenMode: stt.ListenMode.dictation,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final isUser = m['role'] == 'user';
                Widget content;
                if (m.containsKey('imagePath')) {
                  final imgPath = m['imagePath'] as String;
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m['text'] != null) Text(m['text']),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(imgPath),
                          width: MediaQuery.of(context).size.width * 0.6,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  );
                } else if (m.containsKey('filePath')) {
                  content = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.picture_as_pdf,
                        size: 28,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(m['fileName'] ?? m['text'] ?? 'File'),
                      ),
                    ],
                  );
                } else {
                  content = Text(m['text'] ?? '');
                }

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.blue.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _isSending ? null : _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask the AI...',
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.image),
                              onPressed: _pickImage,
                              tooltip: 'Attach image',
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file),
                              onPressed: _pickPdf,
                              tooltip: 'Attach file (pdf)',
                            ),
                            IconButton(
                              icon: _isListeningSpeech
                                  ? const Icon(Icons.mic, color: Colors.red)
                                  : const Icon(Icons.mic_none),
                              onPressed: _toggleListening,
                              tooltip: 'Voice input',
                            ),
                            IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: _send,
                              tooltip: 'Send message',
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
