import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io' show File, Platform;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'services/generative_ai_service.dart';
import 'widgets/ai_chat_card.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/forgot_password_page.dart';
import 'auth/auth_service.dart';
import 'utils/config.dart';
import 'screens/input_wizard_screen.dart';
import 'screens/boq_display_screen.dart';
import 'screens/model_3d_viewer_screen.dart';
import 'screens/ar_camera_screen.dart';
import 'screens/voice_to_plan_screen.dart';
import 'screens/stereo_vision_calibration_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // If Firebase isn't configured, continue — we'll show errors when saving.
    debugPrint('Firebase initialize error: $e');
  }
  runApp(const MyApp());
}

class Plan2Dto3DPage extends StatefulWidget {
  const Plan2Dto3DPage({super.key});

  @override
  State<Plan2Dto3DPage> createState() => _Plan2Dto3DPageState();
}

class _Plan2Dto3DPageState extends State<Plan2Dto3DPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String? _selectedFilePath;
  bool _isUploading = false;
  String? _modelLocalPath;
  final TextEditingController _heightController = TextEditingController(
    text: '3000',
  );
  final TextEditingController _scaleController = TextEditingController(
    text: '0.01',
  );

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null) return;
      setState(() {
        _imageFile = picked;
        _modelLocalPath = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image pick failed: $e')));
    }
  }

  Future<void> _uploadPlan() async {
    if (_imageFile == null && _selectedFilePath == null) return;
    setState(() => _isUploading = true);
    try {
      final backendFromEnv = const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: '',
      );
      final backendUrl = backendFromEnv.isNotEmpty
          ? backendFromEnv
          : AppConfig.apiBaseUrl;
      final base = backendUrl.endsWith('/')
          ? backendUrl.substring(0, backendUrl.length - 1)
          : backendUrl;
      final uri = Uri.parse('$base/plan2dto3d');

      final req = http.MultipartRequest('POST', uri);
      // Attach parameters: height_mm and scale_m_per_px
      req.fields['height_mm'] = _heightController.text.trim();
      req.fields['scale_m_per_px'] = _scaleController.text.trim();
      if (_selectedFilePath != null) {
        req.files.add(
          await http.MultipartFile.fromPath('file', _selectedFilePath!),
        );
      } else if (_imageFile != null) {
        req.files.add(
          await http.MultipartFile.fromPath('plan', _imageFile!.path),
        );
      }
      final streamed = await req.send();
      final bytes = await streamed.stream.toBytes();
      if (streamed.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final out = File(
          p.join(
            tempDir.path,
            'plan_model_${DateTime.now().millisecondsSinceEpoch}.glb',
          ),
        );
        await out.writeAsBytes(bytes);
        setState(() => _modelLocalPath = out.path);
      } else {
        final body = utf8.decode(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Server error: $body')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAnyFile() async {
    try {
      final XTypeGroup typeGroup = XTypeGroup(
        label: 'files',
        // allow common CAD and image types
        extensions: ['png', 'jpg', 'jpeg', 'dxf', 'svg'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      setState(() {
        _selectedFilePath = file.path;
        _imageFile = null;
        _modelLocalPath = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File pick failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan2Dto3D')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a 2D plan (photo or image) to convert to 3D.'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickAnyFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select File'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadPlan,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: const Text('Upload & Convert'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Height (mm)'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _scaleController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Scale m/px (or m/unit for DXF)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_imageFile != null) ...[
              SizedBox(height: 200, child: Image.file(File(_imageFile!.path))),
            ],
            if (_selectedFilePath != null) ...[
              Text('Selected file: ${p.basename(_selectedFilePath!)}'),
            ],
            const SizedBox(height: 12),
            if (_modelLocalPath != null) ...[
              const Text('Converted model preview:'),
              const SizedBox(height: 8),
              Expanded(
                child: ModelViewer(
                  src: 'file://$_modelLocalPath',
                  alt: 'Converted plan model',
                  autoRotate: true,
                  cameraControls: true,
                  ar: false,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      // allow user to share or save the GLB
                      try {
                        await Share.shareXFiles([
                          XFile(_modelLocalPath!),
                        ], text: 'Converted model');
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Share failed: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Share/Save'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _scaleController.dispose();
    super.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // Temporarily start at home for quicker testing on device.
      initialRoute: '/home',
      routes: {
        '/login': (ctx) => const LoginPage(),
        '/signup': (ctx) => const SignupPage(),
        '/forgot': (ctx) => const ForgotPasswordPage(),
        '/home': (ctx) => const MyHomePage(title: 'Material Estimate'),
        '/input-wizard': (ctx) => const InputWizardScreen(),
        '/model-viewer': (ctx) => const Model3DViewerScreen(),
      },
    );
  }
}

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  // These can be provided at build/run time using --dart-define.
  // Do NOT hardcode API keys in source. Pass them securely.
  final String _backendUrl = const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );
  final String _openaiKeyFromEnv = const String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  final String _hfKeyFromEnv = const String.fromEnvironment(
    'HF_API_KEY',
    defaultValue: '',
  );
  final String _hfModelFromEnv = const String.fromEnvironment(
    'HF_MODEL',
    defaultValue: 'gpt2',
  );

  // Runtime API key (optional) entered by the user at runtime if env var is empty.
  String? _runtimeOpenAiKey;

  String get _openaiKey => _openaiKeyFromEnv.isNotEmpty
      ? _openaiKeyFromEnv
      : (_runtimeOpenAiKey ?? '');

  String? _runtimeHfKey;
  String get _hfKey =>
      _hfKeyFromEnv.isNotEmpty ? _hfKeyFromEnv : (_runtimeHfKey ?? '');
  String get _hfModel => _hfModelFromEnv;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askForApiKey() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter OpenAI API key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'sk-...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _runtimeOpenAiKey = result);
    }
  }

  Future<void> _askForHfKey() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Hugging Face API key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'hf_...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _runtimeHfKey = result);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _controller.clear();
      _isSending = true;
    });

    try {
      // Prefer Gemini (GenerativeAiService) when configured via --dart-define=GEMINI_API_KEY
      try {
        final generative = GenerativeAiService();
        if (generative.isConfigured) {
          final reply = await generative.generateContent(text);
          setState(() => _messages.add({'role': 'assistant', 'text': reply}));
          return;
        }
      } catch (e) {
        // If Gemini call fails, show an assistant message then fall back to other providers
        setState(
          () => _messages.add({
            'role': 'assistant',
            'text': 'AI (Gemini) error: $e',
          }),
        );
      }

      // 1) Try backend proxy if configured
      if (_backendUrl.isNotEmpty) {
        final base = _backendUrl.endsWith('/')
            ? _backendUrl.substring(0, _backendUrl.length - 1)
            : _backendUrl;
        final uri = Uri.parse('$base/chat');
        try {
          final res = await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'message': text}),
              )
              .timeout(const Duration(seconds: 60));
          if (res.statusCode == 200) {
            try {
              final data = jsonDecode(res.body);
              final reply = (data is Map && data['reply'] != null)
                  ? data['reply'].toString()
                  : res.body;
              setState(
                () => _messages.add({'role': 'assistant', 'text': reply}),
              );
            } catch (_) {
              setState(
                () => _messages.add({'role': 'assistant', 'text': res.body}),
              );
            }
          } else {
            setState(
              () => _messages.add({
                'role': 'assistant',
                'text': 'Server error: ${res.statusCode}\n${res.body}',
              }),
            );
          }
        } catch (e) {
          setState(
            () => _messages.add({
              'role': 'assistant',
              'text': 'Backend request failed: $e',
            }),
          );
        }
        return;
      }

      // 2) Try Hugging Face Inference API (free tier for some models)
      final hfUri = Uri.parse(
        'https://api-inference.huggingface.co/models/$_hfModel',
      );
      final hfHeaders = <String, String>{'Content-Type': 'application/json'};
      if (_hfKey.isNotEmpty) hfHeaders['Authorization'] = 'Bearer $_hfKey';

      try {
        final hfRes = await http
            .post(
              hfUri,
              headers: hfHeaders,
              body: jsonEncode({
                'inputs': text,
                'options': {'wait_for_model': true},
              }),
            )
            .timeout(const Duration(seconds: 60));
        if (hfRes.statusCode == 200) {
          String reply = '';
          try {
            final parsed = jsonDecode(hfRes.body);
            if (parsed is List && parsed.isNotEmpty) {
              final first = parsed[0];
              if (first is Map && first['generated_text'] != null) {
                reply = first['generated_text'].toString();
              } else {
                reply = parsed[0].toString();
              }
            } else if (parsed is Map && parsed['generated_text'] != null) {
              reply = parsed['generated_text'].toString();
            } else {
              reply = hfRes.body;
            }
          } catch (_) {
            reply = hfRes.body;
          }
          setState(() => _messages.add({'role': 'assistant', 'text': reply}));
          return;
        }
        // If HF requires auth (401) or is rate-limited (429/503) we'll try OpenAI as fallback
        if (hfRes.statusCode == 401) {
          // prompt for HF key and retry once
          await _askForHfKey();
          if (_hfKey.isNotEmpty) {
            final hfRes2 = await http
                .post(
                  hfUri,
                  headers: hfHeaders..['Authorization'] = 'Bearer $_hfKey',
                  body: jsonEncode({
                    'inputs': text,
                    'options': {'wait_for_model': true},
                  }),
                )
                .timeout(const Duration(seconds: 60));
            if (hfRes2.statusCode == 200) {
              try {
                final parsed = jsonDecode(hfRes2.body);
                final reply =
                    (parsed is List &&
                        parsed.isNotEmpty &&
                        parsed[0] is Map &&
                        parsed[0]['generated_text'] != null)
                    ? parsed[0]['generated_text'].toString()
                    : hfRes2.body;
                setState(
                  () => _messages.add({'role': 'assistant', 'text': reply}),
                );
                return;
              } catch (_) {
                setState(
                  () =>
                      _messages.add({'role': 'assistant', 'text': hfRes2.body}),
                );
                return;
              }
            }
          }
        }
      } catch (e) {
        // HF request failed — we'll attempt OpenAI if key provided
      }

      // 3) Fallback to OpenAI
      if (_openaiKey.isEmpty) {
        await _askForApiKey();
        if (_openaiKey.isEmpty) {
          setState(
            () => _messages.add({
              'role': 'assistant',
              'text': 'No API key provided.',
            }),
          );
          return;
        }
      }

      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      final payload = {
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': text},
        ],
        'max_tokens': 512,
      };

      // retry on 429
      http.Response? res;
      const int maxAttempts = 3;
      int attempt = 0;
      while (attempt < maxAttempts) {
        attempt += 1;
        try {
          res = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $_openaiKey',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 60));
        } catch (e) {
          setState(
            () => _messages.add({
              'role': 'assistant',
              'text': 'Request error: $e',
            }),
          );
          res = null;
          break;
        }

        if (res.statusCode == 200) break;
        if (res.statusCode == 429 && attempt < maxAttempts) {
          final backoffSeconds = (1 << attempt) + (attempt % 2);
          await Future.delayed(Duration(seconds: backoffSeconds));
          continue;
        }
        break;
      }

      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final content = (data['choices'] as List).isNotEmpty
            ? (data['choices'][0]['message']['content'] ?? '').toString()
            : 'No response';
        setState(() => _messages.add({'role': 'assistant', 'text': content}));
      } else if (res != null) {
        final r = res;
        String bodyMsg = r.body;
        try {
          final parsed = jsonDecode(r.body);
          if (parsed is Map && parsed['error'] != null) {
            bodyMsg = parsed['error'].toString();
          }
        } catch (_) {}
        setState(
          () => _messages.add({
            'role': 'assistant',
            'text': 'OpenAI error: ${r.statusCode}\n$bodyMsg',
          }),
        );
      } else {
        setState(
          () => _messages.add({
            'role': 'assistant',
            'text': 'Request failed (no response).',
          }),
        );
      }
    } catch (e) {
      setState(
        () =>
            _messages.add({'role': 'assistant', 'text': 'Request failed: $e'}),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        actions: [
          if (_backendUrl.isEmpty)
            IconButton(
              tooltip: 'Set API key',
              icon: const Icon(Icons.vpn_key),
              onPressed: _askForApiKey,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final isUser = m['role'] == 'user';
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
                    child: Text(m['text'] ?? ''),
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
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _isSending ? null : _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
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
                      : IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _sendMessage,
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

class _DashboardCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = 0.96);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  void _onTap() {
    setState(() => _scale = 1.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: 1.0,
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTapDown: _onTapDown,
            onTapCancel: _onTapCancel,
            onTap: _onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: widget.color.withAlpha(
                      (0.15 * 255).round(),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.title, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MaterialEstimatePage extends StatefulWidget {
  const MaterialEstimatePage({super.key});

  @override
  State<MaterialEstimatePage> createState() => _MaterialEstimatePageState();
}

class _MaterialEstimatePageState extends State<MaterialEstimatePage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';
  String _status = 'inactive';

  // Tile options in millimeters
  final Map<String, List<int>> _tileOptions = {
    '300 x 300 mm': [300, 300],
    '400 x 400 mm': [400, 400],
    '600 x 600 mm': [600, 600],
    '200 x 200 mm': [200, 200],
    'Custom (mm)': [0, 0],
  };

  String _selectedTile = '300 x 300 mm';
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();
  final TextEditingController _manualAreaController = TextEditingController();

  double? _lastComputedTiles;
  double _wastagePercent = 10.0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<bool> _initSpeech() async {
    if (kIsWeb) {
      setState(() => _status = 'web not supported');
      return false;
    }
    try {
      final available = await _speech.initialize(
        onStatus: (s) => setState(() => _status = s),
        onError: (e) => setState(() => _status = 'error'),
      );
      if (!available) setState(() => _status = 'not available');
      return available;
    } catch (_) {
      setState(() => _status = 'init error');
      return false;
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) return;

    setState(() => _isListening = true);
    _speech.listen(
      onResult: (r) => setState(() => _lastWords = r.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  void _computeFromInput() {
    final raw = _manualAreaController.text.trim();
    final area = double.tryParse(raw.replaceAll(',', '.'));
    if (area == null || area <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid area in m²')),
      );
      return;
    }

    double tileWidthMm, tileHeightMm;
    if (_selectedTile == 'Custom (mm)') {
      tileWidthMm = double.tryParse(_customWidthController.text) ?? 0;
      tileHeightMm = double.tryParse(_customHeightController.text) ?? 0;
      if (tileWidthMm <= 0 || tileHeightMm <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter custom tile width and height in mm'),
          ),
        );
        return;
      }
    } else {
      final dims = _tileOptions[_selectedTile] ?? _tileOptions['300 x 300 mm']!;
      tileWidthMm = dims[0].toDouble();
      tileHeightMm = dims[1].toDouble();
    }

    final tileAreaM2 = (tileWidthMm / 1000.0) * (tileHeightMm / 1000.0);
    final effectiveArea = area * (1 + _wastagePercent / 100.0);
    final tilesNeeded = (effectiveArea / tileAreaM2).ceilToDouble();

    setState(() => _lastComputedTiles = tilesNeeded);
  }

  @override
  void dispose() {
    _customWidthController.dispose();
    _customHeightController.dispose();
    _manualAreaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Material Estimate')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Input Options',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Camera input not implemented yet',
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Gallery input not implemented yet',
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'PDF input not implemented yet',
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Import PDF'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _toggleListening,
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                            ),
                            label: Text(_isListening ? 'Stop' : 'Voice'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Transcript:'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        _lastWords.isEmpty ? 'No speech yet' : _lastWords,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Speech status: $_status'),
                    const SizedBox(height: 12),
                    const Text(
                      'Tile selection',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTile,
                      items: _tileOptions.keys
                          .map(
                            (k) => DropdownMenuItem(value: k, child: Text(k)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedTile = v ?? _selectedTile),
                    ),
                    if (_selectedTile == 'Custom (mm)') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customWidthController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Width (mm)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _customHeightController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Height (mm)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Area (m²)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualAreaController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Enter area in square meters (e.g. 25.5)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Wastage:'),
                        Expanded(
                          child: Slider(
                            value: _wastagePercent,
                            min: 0,
                            max: 30,
                            divisions: 30,
                            label: '${_wastagePercent.round()}%',
                            onChanged: (v) =>
                                setState(() => _wastagePercent = v),
                          ),
                        ),
                        Text('${_wastagePercent.toStringAsFixed(0)}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _computeFromInput,
                      icon: const Icon(Icons.calculate),
                      label: const Text('Compute Tiles'),
                    ),
                    if (_lastComputedTiles != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Tiles needed: ${_lastComputedTiles!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This includes ${_wastagePercent.toStringAsFixed(0)}% wastage as a construction allowance.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressTrackingPage extends StatelessWidget {
  const ProgressTrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress Tracking')),
      body: const Center(child: Text('Progress Tracking page (TODO)')),
    );
  }
}

class WoodIdentificationPage extends StatelessWidget {
  const WoodIdentificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wood Identification')),
      body: const Center(child: Text('Wood Identification page (TODO)')),
    );
  }
}

class MachineManagementPage extends StatelessWidget {
  const MachineManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Machine Management')),
      body: const Center(child: Text('Machine Management page (TODO)')),
    );
  }
}

class AreaAnalyzePage extends StatelessWidget {
  const AreaAnalyzePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Area Analyze')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Area Analyze',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('This is a placeholder for the Area Analyze feature.'),
          ],
        ),
      ),
    );
  }
}

class BuildingPlanPage extends StatefulWidget {
  const BuildingPlanPage({super.key});

  @override
  State<BuildingPlanPage> createState() => _BuildingPlanPageState();
}

class OCRPage extends StatefulWidget {
  const OCRPage({super.key});

  @override
  State<OCRPage> createState() => _OCRPageState();
}

class _OCRPageState extends State<OCRPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String _ocrResult = '';
  final TextEditingController _ocrController = TextEditingController();
  bool _isEditing = false;
  bool _isProcessing = false;
  bool _isSaving = false;

  void _onOcrControllerChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _ocrController.addListener(_onOcrControllerChanged);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked == null) return;
      setState(() {
        _imageFile = picked;
        _ocrResult = '';
      });
    } catch (e) {
      debugPrint('Image pick error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isDenied) {
      final r = await Permission.camera.request();
      return r.isGranted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Camera permission required'),
          content: const Text(
            'Please enable Camera permission in app settings to take a photo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (open == true) await openAppSettings();
      return false;
    }
    return false;
  }

  @override
  void dispose() {
    _ocrController.removeListener(_onOcrControllerChanged);
    _ocrController.dispose();
    super.dispose();
  }

  Future<bool> _ensureGalleryPermission() async {
    if (kIsWeb) return true;
    // For Android, request storage and photos (cover Android versions). For iOS request photos
    if (Platform.isAndroid) {
      final s = await Permission.storage.status;
      if (s.isGranted) return true;
      if (s.isDenied) {
        final r = await Permission.storage.request();
        if (r.isGranted) return true;
      }
      // Try photos permission (Android 13+) too
      final pstat = await Permission.photos.status;
      if (pstat.isGranted) return true;
      if (pstat.isDenied) {
        final pr = await Permission.photos.request();
        if (pr.isGranted) return true;
      }
      if (s.isPermanentlyDenied || pstat.isPermanentlyDenied) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Storage permission required'),
            content: const Text(
              'Please enable Storage/Photos permission in app settings to select an image.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (open == true) await openAppSettings();
        return false;
      }
      return false;
    } else {
      final status = await Permission.photos.status;
      if (status.isGranted) return true;
      if (status.isDenied) {
        final r = await Permission.photos.request();
        return r.isGranted;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Photos permission required'),
            content: const Text(
              'Please enable Photos permission in app settings to select an image.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (open == true) await openAppSettings();
        return false;
      }
      return false;
    }
  }

  Future<void> _performOcr() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick or capture an image first')),
      );
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final inputImage = InputImage.fromFilePath(_imageFile!.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      setState(() {
        _ocrResult = recognizedText.text.trim();
        _ocrController.text = _ocrResult;
      });
    } catch (e) {
      debugPrint('OCR error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCR failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _clear() {
    setState(() {
      _imageFile = null;
      _ocrResult = '';
      _ocrController.clear();
      _isEditing = false;
    });
  }

  Future<void> _copyToClipboard() async {
    final text = _ocrController.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _shareText() async {
    final text = _ocrController.text;
    if (text.isEmpty) return;
    await Share.share(text);
  }

  Future<String?> _uploadImageToFirebase(XFile file) async {
    try {
      final storage = FirebaseStorage.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final filename = file.name;
      final ref = storage.ref().child('ocr/$now/$filename');
      final bytes = await file.readAsBytes();
      final uploadTask = ref.putData(bytes);
      final snapshot = await uploadTask.whenComplete(() {});
      final url = await snapshot.ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Image upload failed: $e');
      return null;
    }
  }

  Future<void> _saveOcrToFirestore() async {
    final text = _ocrController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No text to save')));
      return;
    }
    setState(() => _isSaving = true);
    String? imageUrl;
    try {
      if (_imageFile != null) {
        imageUrl = await _uploadImageToFirebase(_imageFile!);
      }
      final col = FirebaseFirestore.instance.collection('ocr_results');
      final doc = await col.add({
        'text': text,
        'image_url': imageUrl,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved OCR to Firestore: ${doc.id}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await _ensureCameraPermission();
                      if (!ok) return;
                      await _pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await _ensureGalleryPermission();
                      if (!ok) return;
                      await _pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Select Image'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_imageFile != null) ...[
              SizedBox(
                height: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_imageFile!.path),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _performOcr,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.text_snippet),
                    label: const Text('Submit (OCR)'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _imageFile == null && _ocrResult.isEmpty
                      ? null
                      : _clear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Recognized Text:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: TextField(
                          controller: _ocrController,
                          maxLines: null,
                          readOnly: false,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'No text recognized yet',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Copy',
                        onPressed: _ocrController.text.isEmpty
                            ? null
                            : _copyToClipboard,
                        icon: const Icon(Icons.copy),
                      ),
                      IconButton(
                        tooltip: 'Share',
                        onPressed: _ocrController.text.isEmpty
                            ? null
                            : _shareText,
                        icon: const Icon(Icons.share),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveOcrToFirestore,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildingPlanPageState extends State<BuildingPlanPage> {
  int _currentStep = 0;
  List<XFile> _pickedFiles = [];

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if (kIsWeb) return;
    try {
      await _speech.initialize(
        onStatus: (_) => setState(() {}),
        onError: (_) => setState(() {}),
      );
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    try {
      final typeGroup = XTypeGroup(
        label: 'plans',
        extensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
      if (!mounted) return;

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No files selected')));
        return;
      }

      // Basic validation — on desktop/mobile we can check path existence
      final validated = <XFile>[];
      for (final f in files) {
        try {
          final exists = await File(f.path).exists();
          if (!exists) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Picked file not found on disk: ${p.basename(f.path)}',
                ),
              ),
            );
          }
        } catch (_) {
          // ignore platforms where File(path) isn't supported
        }
        validated.add(f);
      }

      if (!mounted) return;
      setState(() {
        _pickedFiles = validated;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected ${_pickedFiles.length} file(s)')),
      );
    } catch (e, st) {
      // Provide visible feedback for debugging
      debugPrint('File pick error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking files: $e')));
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) return;

    setState(() {
      _isListening = true;
      _transcript = '';
    });

    _speech.listen(
      onResult: (r) => setState(() => _transcript = r.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  void _stopListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }
  }

  Future<void> _confirmAndSubmit() async {
    // Package inputs into a payload to send to AI backend.
    final filesInfo = <Map<String, dynamic>>[];
    for (final f in _pickedFiles) {
      int size = 0;
      try {
        size = await f.length();
      } catch (_) {}
      filesInfo.add({'name': f.name, 'size': size, 'path': f.path});
    }

    final payload = {
      'files': filesInfo,
      'transcript': _transcript,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm submission'),
        content: SingleChildScrollView(
          child: Text(
            'Send the collected files and notes to AI for analysis?\n\nPayload preview:\n${payload.toString()}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    // Send to backend
    final backendUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    final uri = Uri.parse('$backendUrl/analyze-plan');

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final req = http.MultipartRequest('POST', uri);
      req.fields['transcript'] = _transcript;
      // BuildingPlanPage does not have tile/wastage state; send placeholder
      // metadata. The MaterialEstimate page manages tile selection separately.
      final userData = {'tile': 'unknown', 'wastage_percent': 0};
      req.fields['userData'] = jsonEncode(userData);

      for (final f in _pickedFiles) {
        try {
          final bytes = await f.readAsBytes();
          req.files.add(
            http.MultipartFile.fromBytes('files', bytes, filename: f.name),
          );
        } catch (e) {
          debugPrint('Failed adding file ${f.name}: $e');
        }
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (mounted) {
        Navigator.of(context).pop(); // close progress (only if still mounted)
      }

      if (res.statusCode != 200) {
        final body = res.body;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error: ${res.statusCode}\n$body')),
        );
        return;
      }

      final Map<String, dynamic> report =
          jsonDecode(res.body) as Map<String, dynamic>;

      // After receiving the AI report, upload files to Firebase Storage
      // and save the report to Firestore (if Firebase is initialized).
      if (!mounted) return;

      // show saving progress
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      String? docId;
      try {
        List<String> fileUrls = [];
        try {
          fileUrls = await _uploadFilesToFirebase(_pickedFiles);
        } catch (e) {
          debugPrint('File upload to Firebase failed: $e');
        }

        try {
          docId = await _saveReportToFirestore(report, _transcript, fileUrls);
        } catch (e) {
          debugPrint('Saving report to Firestore failed: $e');
        }
      } finally {
        // close saving progress
        if (mounted) Navigator.of(context).pop();
      }

      // Show final dialog including Firestore doc id (if saved) and the report
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('AI Analysis Result'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(jsonEncode(report)),
                const SizedBox(height: 12),
                if (docId != null)
                  Text('Saved to Firestore: $docId')
                else
                  const Text('Not saved to Firestore'),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Submit error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<List<String>> _uploadFilesToFirebase(List<XFile> files) async {
    final urls = <String>[];
    if (files.isEmpty) return urls;
    try {
      final storage = FirebaseStorage.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final basePath = 'plans/$now';
      for (final f in files) {
        try {
          final bytes = await f.readAsBytes();
          final filename = f.name;
          final ref = storage.ref().child('$basePath/$filename');
          final uploadTask = ref.putData(bytes);
          final snapshot = await uploadTask.whenComplete(() {});
          final url = await snapshot.ref.getDownloadURL();
          urls.add(url);
        } catch (e) {
          debugPrint('Upload error for ${f.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('Firebase storage error: $e');
    }
    return urls;
  }

  Future<String> _saveReportToFirestore(
    Map<String, dynamic> report,
    String transcript,
    List<String> fileUrls,
  ) async {
    try {
      final col = FirebaseFirestore.instance.collection('building_plans');
      final doc = await col.add({
        'report': report,
        'transcript': transcript,
        'files': fileUrls,
        'created_at': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('Firestore save error: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Building Plan')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 0 && _pickedFiles.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please upload at least one plan or image'),
              ),
            );
            return;
          }
          if (_currentStep < 2) setState(() => _currentStep += 1);
        },
        onStepCancel: () {
          if (_currentStep == 0) return;
          setState(() => _currentStep -= 1);
        },
        steps: [
          Step(
            title: const Text('Upload plans & images'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload one or more 2D building plans, images or PDFs that identify the building structure.',
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Pick files'),
                ),
                const SizedBox(height: 8),
                if (_pickedFiles.isEmpty)
                  const Text('No files selected')
                else
                  Column(
                    children: _pickedFiles
                        .map(
                          (f) => ListTile(
                            leading: const Icon(Icons.insert_drive_file),
                            title: Text(f.name),
                            subtitle: FutureBuilder<int>(
                              future: f.length(),
                              builder: (context, snap) {
                                if (snap.hasData) {
                                  return Text('${snap.data} bytes');
                                }
                                return const Text('size: -');
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
            isActive: _currentStep == 0,
            state: _pickedFiles.isNotEmpty
                ? StepState.complete
                : StepState.indexed,
          ),
          Step(
            title: const Text('Voice notes'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Speak details about the plan; speech will be converted to text in realtime.',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _toggleListening,
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      label: Text(_isListening ? 'Stop' : 'Start'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _stopListening,
                      icon: const Icon(Icons.save),
                      label: const Text('Stop & Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    _transcript.isEmpty ? 'No speech yet' : _transcript,
                  ),
                ),
              ],
            ),
            isActive: _currentStep == 1,
            state: _transcript.isNotEmpty
                ? StepState.complete
                : StepState.indexed,
          ),
          Step(
            title: const Text('Review & submit'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review collected files and notes. When ready, confirm to send everything to the AI chatbot for analysis.',
                ),
                const SizedBox(height: 8),
                const Text('Files:'),
                if (_pickedFiles.isEmpty)
                  const Text('No files')
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _pickedFiles
                        .map((f) => Text('- ${f.name}'))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                const Text('Notes (transcript):'),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(_transcript.isEmpty ? 'No notes' : _transcript),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _confirmAndSubmit,
                  icon: const Icon(Icons.send),
                  label: const Text('Confirm & Submit'),
                ),
              ],
            ),
            isActive: _currentStep == 2,
            state: StepState.indexed,
          ),
        ],
      ),
    );
  }
}

class SpeechPage extends StatefulWidget {
  const SpeechPage({super.key});

  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';
  String _status = 'inactive';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<bool> _initSpeech() async {
    if (kIsWeb) {
      setState(() => _status = 'web not supported');
      return false;
    }
    try {
      final available = await _speech.initialize(
        onStatus: (status) => setState(() => _status = status),
        onError: (error) =>
            setState(() => _status = 'error: ${error.errorMsg}'),
      );
      if (!available) setState(() => _status = 'not available');
      return available;
    } catch (e) {
      setState(() => _status = 'init error');
      return false;
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stopped listening')));
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Starting listening...')));
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!mounted) return;

    if (!_speech.isAvailable) {
      final available = await _initSpeech();
      if (!available) return;
    }

    if (!_speech.isAvailable || !hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Speech recognition not available or permission denied',
          ),
        ),
      );
      return;
    }

    setState(() => _isListening = true);
    _speech.listen(
      onResult: (result) {
        setState(() => _lastWords = result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('Voice')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 200,
              width: 300,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _lastWords.isEmpty ? 'Say something...' : _lastWords,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Status: $_status'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _toggleListening,
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
              label: Text(_isListening ? 'Stop' : 'Voice'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isListening ? Colors.red : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            // Toggle the drawer; if it's already open, close it.
            if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            } else {
              _scaffoldKey.currentState?.openDrawer();
            }
          },
        ),
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Text(
                    'Menu',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.calculate),
              title: const Text('Material Estimate'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MaterialEstimatePage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text('Multi-Modal BOQ'),
              subtitle: const Text('AI-Powered Analysis'),
              onTap: () {
                Navigator.of(context).pop(); // Close drawer
                Navigator.pushNamed(context, '/input-wizard');
              },
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Building Plan'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BuildingPlanPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Progress tracking'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProgressTrackingPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.nature),
              title: const Text('Wood Identification'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WoodIdentificationPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_enhance),
              title: const Text('AR Camera'),
              subtitle: const Text('AR Detection & Measurement'),
              onTap: () {
                Navigator.of(context).pop(); // Close drawer
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ARCameraScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('VoiceToPlan'),
              subtitle: const Text('Voice to 3D Building Model'),
              onTap: () {
                Navigator.of(context).pop(); // Close drawer
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceToPlanScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.precision_manufacturing),
              title: const Text('Machine Management'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MachineManagementPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mic),
              title: const Text('Voice'),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SpeechPage())),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner),
              title: const Text('OCR'),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const OCRPage())),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await AuthService.logout();
                if (!mounted) return;
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _DashboardCard(
              icon: Icons.calculate,
              title: 'Material Estimate',
              color: Colors.blue,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MaterialEstimatePage()),
              ),
            ),
            _DashboardCard(
              icon: Icons.timeline,
              title: 'Progress tracking',
              color: Colors.green,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProgressTrackingPage()),
              ),
            ),
            _DashboardCard(
              icon: Icons.nature,
              title: 'Wood Identification',
              color: Colors.orange,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WoodIdentificationPage(),
                ),
              ),
            ),
            _DashboardCard(
              icon: Icons.precision_manufacturing,
              title: 'Machine Management',
              color: Colors.purple,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MachineManagementPage(),
                ),
              ),
            ),
            _DashboardCard(
              icon: Icons.map,
              title: 'Building Plan',
              color: Colors.teal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BuildingPlanPage()),
              ),
            ),
            _DashboardCard(
              icon: Icons.threed_rotation,
              title: 'Plan2Dto3D',
              color: Colors.cyan,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const Plan2Dto3DPage())),
            ),
            _DashboardCard(
              icon: Icons.analytics,
              title: 'Area Analyze',
              color: Colors.red,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AreaAnalyzePage()),
              ),
            ),
            _DashboardCard(
              icon: Icons.document_scanner,
              title: 'OCR',
              color: Colors.brown,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const OCRPage())),
            ),
            _DashboardCard(
              icon: Icons.chat,
              title: 'AI chat',
              color: Colors.indigo,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AiChatScreen())),
            ),
            _DashboardCard(
              icon: Icons.camera_enhance,
              title: 'AR',
              color: Colors.deepPurple,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ARCameraScreen())),
            ),
            _DashboardCard(
              icon: Icons.record_voice_over,
              title: 'VoiceToPlan',
              color: Colors.orange,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceToPlanScreen()),
              ),
            ),
            _DashboardCard(
              icon: Icons.visibility,
              title: 'Stereo Vision',
              color: Colors.blueGrey,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StereoVisionCalibrationScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
      // FloatingActionButton removed as it's related to default template counter
    );
  }
}
