import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'dart:io' show File;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // If Firebase isn't configured, continue — we'll show errors when saving.
    debugPrint('Firebase initialize error: $e');
  }
  runApp(const MyApp());
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
      home: const MyHomePage(title: 'Material Estimate'),
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

    final ctx = context;
    // ignore: use_build_context_synchronously
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Confirm submission'),
        content: SingleChildScrollView(
          child: Text(
            'Send the collected files and notes to AI for analysis?\n\nPayload preview:\n${payload.toString()}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
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
        child: Column(
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
            const Spacer(),
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
              icon: Icons.analytics,
              title: 'Area Analyze',
              color: Colors.red,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AreaAnalyzePage()),
              ),
            ),
          ],
        ),
      ),
      // FloatingActionButton removed as it's related to default template counter
    );
  }
}
