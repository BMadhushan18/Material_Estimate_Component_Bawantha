import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:math' as math;

class VoiceToPlanScreen extends StatefulWidget {
  const VoiceToPlanScreen({super.key});

  @override
  State<VoiceToPlanScreen> createState() => _VoiceToPlanScreenState();
}

class _VoiceToPlanScreenState extends State<VoiceToPlanScreen>
    with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechEnabled = false;
  String _transcription = '';
  bool _isAnalyzing = false;
  bool _hasGenerated3D = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  // 4D Model properties
  int _currentPhase = 0;
  bool _isPlaying4D = false;
  Timer? _phaseTimer;

  // Building analysis results
  BuildingStructure? _analyzedBuilding;
  List<String> _detectedFeatures = [];
  List<ConstructionPhase> _constructionPhases = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initAnimations();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _phaseTimer?.cancel();
    super.dispose();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();

    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      bool available = await _speech.initialize(
        onStatus: (val) => setState(() {
          if (val == 'done' || val == 'notListening') {
            _isListening = false;
            _pulseController.stop();
          }
        }),
        onError: (val) => setState(() {
          _isListening = false;
          _pulseController.stop();
        }),
      );

      setState(() {
        _speechEnabled = available;
      });
    }
  }

  void _startListening() async {
    if (!_speechEnabled) return;

    setState(() {
      _isListening = true;
      _transcription = '';
      _analyzedBuilding = null;
      _hasGenerated3D = false;
      _detectedFeatures.clear();
    });

    _pulseController.repeat(reverse: true);

    await _speech.listen(
      onResult: (val) => setState(() {
        _transcription = val.recognizedWords;
      }),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
    _pulseController.stop();

    if (_transcription.isNotEmpty) {
      _analyzeBuilding();
    }
  }

  Future<void> _analyzeBuilding() async {
    setState(() {
      _isAnalyzing = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    // Analyze the transcription and extract building features
    final analysis = _performBuildingAnalysis(_transcription);

    setState(() {
      _analyzedBuilding = analysis;
      _isAnalyzing = false;
      _detectedFeatures = _extractFeatures(_transcription);
    });
  }

  BuildingStructure _performBuildingAnalysis(String text) {
    final lowerText = text.toLowerCase();

    // Extract rooms
    List<Room> rooms = [];

    // Common room patterns
    final roomPatterns = {
      'bedroom': RegExp(r'(\d+|\w+)\s*bedroom', caseSensitive: false),
      'bathroom': RegExp(r'(\d+|\w+)\s*bathroom', caseSensitive: false),
      'kitchen': RegExp(r'kitchen', caseSensitive: false),
      'living room': RegExp(r'living\s*room', caseSensitive: false),
      'dining room': RegExp(r'dining\s*room', caseSensitive: false),
      'garage': RegExp(r'garage', caseSensitive: false),
      'balcony': RegExp(r'balcony', caseSensitive: false),
    };

    roomPatterns.forEach((roomType, pattern) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        if (roomType == 'bedroom' || roomType == 'bathroom') {
          final countStr = match.group(1) ?? '1';
          int count = _parseNumber(countStr);
          for (int i = 0; i < count; i++) {
            rooms.add(
              Room(
                name: '$roomType ${i + 1}',
                type: roomType,
                dimensions: _estimateRoomSize(roomType),
              ),
            );
          }
        } else {
          rooms.add(
            Room(
              name: roomType,
              type: roomType,
              dimensions: _estimateRoomSize(roomType),
            ),
          );
        }
      }
    });

    // Extract floors
    int floors = 1;
    final floorPatterns = [
      RegExp(r'(\d+)\s*floor', caseSensitive: false),
      RegExp(r'(\d+)\s*story', caseSensitive: false),
      RegExp(r'(\d+)\s*level', caseSensitive: false),
    ];

    for (final pattern in floorPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        floors = int.tryParse(match.group(1) ?? '1') ?? 1;
        break;
      }
    }

    // Extract dimensions if mentioned
    final dimensionPattern = RegExp(
      r'(\d+)\s*(?:by|x|\×)\s*(\d+)',
      caseSensitive: false,
    );
    final dimensionMatch = dimensionPattern.firstMatch(text);

    double width = 10.0;
    double length = 12.0;

    if (dimensionMatch != null) {
      width = double.tryParse(dimensionMatch.group(1) ?? '10') ?? 10.0;
      length = double.tryParse(dimensionMatch.group(2) ?? '12') ?? 12.0;
    }

    return BuildingStructure(
      floors: floors,
      rooms: rooms.isEmpty
          ? [
              Room(
                name: 'Main Room',
                type: 'room',
                dimensions: Size(width, length),
              ),
            ]
          : rooms,
      totalWidth: width,
      totalLength: length,
      height: floors * 3.0, // 3 meters per floor
    );
  }

  int _parseNumber(String numberStr) {
    final numberWords = {
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
    };

    return numberWords[numberStr.toLowerCase()] ?? int.tryParse(numberStr) ?? 1;
  }

  Size _estimateRoomSize(String roomType) {
    switch (roomType) {
      case 'bedroom':
        return const Size(4.0, 3.5);
      case 'bathroom':
        return const Size(2.5, 2.0);
      case 'kitchen':
        return const Size(4.0, 3.0);
      case 'living room':
        return const Size(5.0, 4.0);
      case 'dining room':
        return const Size(4.0, 3.5);
      case 'garage':
        return const Size(6.0, 3.0);
      case 'balcony':
        return const Size(3.0, 1.5);
      default:
        return const Size(3.0, 3.0);
    }
  }

  List<String> _extractFeatures(String text) {
    final features = <String>[];
    final lowerText = text.toLowerCase();

    final featurePatterns = {
      'Windows': ['window', 'windows'],
      'Doors': ['door', 'doors', 'entrance'],
      'Stairs': ['stairs', 'staircase', 'steps'],
      'Garden': ['garden', 'yard', 'lawn'],
      'Parking': ['parking', 'garage', 'driveway'],
      'Balcony': ['balcony', 'terrace'],
      'Roof': ['roof', 'rooftop'],
      'Foundation': ['foundation', 'basement'],
    };

    featurePatterns.forEach((feature, keywords) {
      for (final keyword in keywords) {
        if (lowerText.contains(keyword)) {
          features.add(feature);
          break;
        }
      }
    });

    return features;
  }

  void _generate4D() {
    setState(() {
      _hasGenerated3D = true;
    });
    _rotationController.repeat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceToPlan'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _resetAll),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVoiceRecognitionCard(),
            const SizedBox(height: 20),
            if (_transcription.isNotEmpty) _buildTranscriptionCard(),
            const SizedBox(height: 20),
            if (_isAnalyzing) _buildAnalyzingCard(),
            if (_analyzedBuilding != null) _buildAnalysisResultsCard(),
            const SizedBox(height: 20),
            if (_analyzedBuilding != null && !_hasGenerated3D)
              _buildGenerate4DButton(),
            if (_hasGenerated3D) _build4DVisualization(),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRecognitionCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              _isListening ? 'Listening...' : 'Voice to Plan',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isListening
                  ? 'Describe your building structure'
                  : 'Tap to describe your building with voice',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _speechEnabled
                  ? (_isListening ? _stopListening : _startListening)
                  : null,
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
              label: Text(_isListening ? 'Stop Recording' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptionCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.transcribe, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Your Description',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(_transcription, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Analyzing Building Structure...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'AI is processing your description',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResultsCard() {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Building Analysis',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Building summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem('Floors', '${_analyzedBuilding!.floors}'),
                  _buildSummaryItem(
                    'Rooms',
                    '${_analyzedBuilding!.rooms.length}',
                  ),
                  _buildSummaryItem(
                    'Size',
                    '${_analyzedBuilding!.totalWidth.toInt()}×${_analyzedBuilding!.totalLength.toInt()}m',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Rooms list
            const Text(
              'Detected Rooms:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _analyzedBuilding!.rooms
                  .map(
                    (room) => Chip(
                      avatar: Icon(_getRoomIcon(room.type), size: 16),
                      label: Text(room.name),
                      backgroundColor: Colors.blue.shade100,
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 16),

            // Features
            if (_detectedFeatures.isNotEmpty) ...[
              const Text(
                'Features:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _detectedFeatures
                    .map(
                      (feature) => Chip(
                        label: Text(feature),
                        backgroundColor: Colors.orange.shade100,
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  IconData _getRoomIcon(String roomType) {
    switch (roomType) {
      case 'bedroom':
        return Icons.bed;
      case 'bathroom':
        return Icons.bathtub;
      case 'kitchen':
        return Icons.kitchen;
      case 'living room':
        return Icons.living;
      case 'dining room':
        return Icons.dining;
      case 'garage':
        return Icons.garage;
      case 'balcony':
        return Icons.balcony;
      default:
        return Icons.room;
    }
  }

  Widget _buildGenerate4DButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.indigo.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _generate4D,
        icon: const Icon(Icons.view_in_ar),
        label: const Text(
          'Generate 4D Model',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _build4DVisualization() {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.view_in_ar, color: Colors.purple, size: 28),
                    SizedBox(width: 8),
                    Text(
                      '4D Building Model',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '4D LIVE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(child: _build4DBuilding()),

            Container(
              height: 280,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200, width: 2),
              ),
              child: Stack(
                children: [
                  Center(
                    child: AnimatedBuilder(
                      animation: _rotationAnimation,
                      builder: (context, child) {
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(_rotationAnimation.value)
                            ..rotateX(0.3),
                          child: _build4DBuilding(),
                        );
                      },
                    ),
                  ),

                  // Construction phase overlay
                  if (_constructionPhases.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phase ${_currentPhase + 1}/${_constructionPhases.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _constructionPhases[_currentPhase].name,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Time indicator
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            color: Colors.white,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'TIMELINE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4D Controls
            _build4DControls(),

            const SizedBox(height: 12),
            const Center(
              child: Text(
                '4D Model: 3D Structure + Time Dimension (Construction Timeline)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build4DBuilding() {
    if (_analyzedBuilding == null) return const SizedBox();

    // Initialize construction phases if not done
    if (_constructionPhases.isEmpty) {
      _initializeConstructionPhases();
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Construction progress visualization
        if (_constructionPhases.isNotEmpty) ..._buildConstructionPhases(),

        // Building base (always visible)
        Container(
          width: 120,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.brown.shade300.withOpacity(
              _getPhaseOpacity('foundation'),
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),

        // Floors with construction timeline
        for (int i = 0; i < _analyzedBuilding!.floors; i++)
          Positioned(
            bottom: 20 + (i * 40),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: _getFloorOpacity(i),
              child: Container(
                width: 100 - (i * 5),
                height: 35,
                decoration: BoxDecoration(
                  color: _getFloorColor(i),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade600, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Floor ${i + 1}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_constructionPhases.isNotEmpty &&
                          _currentPhase >= i + 1)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 12,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Roof with completion indicator
        Positioned(
          top: 10,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: _getPhaseOpacity('roof'),
            child: Container(
              width: 90,
              height: 20,
              decoration: BoxDecoration(
                color: _getRoofColor(),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isConstructionComplete()
                  ? const Center(
                      child: Icon(Icons.home, color: Colors.white, size: 12),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  void _initializeConstructionPhases() {
    _constructionPhases = [
      ConstructionPhase(
        name: 'Site Preparation',
        duration: 2,
        color: Colors.brown,
      ),
      ConstructionPhase(name: 'Foundation', duration: 3, color: Colors.grey),
      for (int i = 0; i < _analyzedBuilding!.floors; i++)
        ConstructionPhase(
          name: 'Floor ${i + 1} Construction',
          duration: 4,
          color: Colors.blue,
        ),
      ConstructionPhase(name: 'Roofing', duration: 2, color: Colors.red),
      ConstructionPhase(
        name: 'Interior Work',
        duration: 5,
        color: Colors.green,
      ),
      ConstructionPhase(name: 'Finishing', duration: 3, color: Colors.purple),
      ConstructionPhase(
        name: 'Final Inspection',
        duration: 1,
        color: Colors.orange,
      ),
    ];
  }

  List<Widget> _buildConstructionPhases() {
    List<Widget> phases = [];

    // Construction equipment and workers (visible during active phases)
    if (_currentPhase < _constructionPhases.length) {
      // Crane (during construction)
      if (_currentPhase > 1 && _currentPhase < _constructionPhases.length - 2) {
        phases.add(
          Positioned(
            right: 10,
            top: 5,
            child: Container(
              width: 4,
              height: 100,
              color: Colors.yellow.shade700,
              child: const Align(
                alignment: Alignment.topCenter,
                child: Icon(Icons.construction, size: 16, color: Colors.orange),
              ),
            ),
          ),
        );
      }

      // Construction materials
      if (_currentPhase > 0 && _currentPhase < _constructionPhases.length - 1) {
        phases.add(
          Positioned(
            left: 10,
            bottom: 10,
            child: Row(
              children: [
                Container(width: 8, height: 8, color: Colors.brown),
                const SizedBox(width: 2),
                Container(width: 8, height: 8, color: Colors.grey),
                const SizedBox(width: 2),
                Container(width: 8, height: 8, color: Colors.red.shade300),
              ],
            ),
          ),
        );
      }
    }

    return phases;
  }

  double _getPhaseOpacity(String phase) {
    switch (phase) {
      case 'foundation':
        return _currentPhase >= 1 ? 1.0 : 0.3;
      case 'roof':
        return _currentPhase >= _constructionPhases.length - 3 ? 1.0 : 0.1;
      default:
        return 1.0;
    }
  }

  double _getFloorOpacity(int floorIndex) {
    if (_constructionPhases.isEmpty) return 1.0;
    return _currentPhase >= (floorIndex + 2) ? 1.0 : 0.2;
  }

  Color _getFloorColor(int floorIndex) {
    if (_constructionPhases.isEmpty) return Colors.blue.shade300;

    if (_currentPhase >= (floorIndex + 2)) {
      return Colors.blue.shade400; // Constructed
    } else if (_currentPhase == (floorIndex + 1)) {
      return Colors.orange.shade300; // Under construction
    } else {
      return Colors.grey.shade300; // Not started
    }
  }

  Color _getRoofColor() {
    if (_constructionPhases.isEmpty) return Colors.red.shade400;

    if (_isConstructionComplete()) {
      return Colors.green.shade400; // Completed
    } else if (_currentPhase >= _constructionPhases.length - 3) {
      return Colors.orange.shade400; // Under construction
    } else {
      return Colors.grey.shade300; // Not started
    }
  }

  bool _isConstructionComplete() {
    return _currentPhase >= _constructionPhases.length - 1;
  }

  Widget _build4DControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // Timeline slider
          if (_constructionPhases.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.timeline, size: 20, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _currentPhase.toDouble(),
                    max: (_constructionPhases.length - 1).toDouble(),
                    divisions: _constructionPhases.length - 1,
                    activeColor: Colors.purple,
                    onChanged: (value) {
                      setState(() {
                        _currentPhase = value.toInt();
                      });
                    },
                  ),
                ),
                Text(
                  '${_currentPhase + 1}/${_constructionPhases.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filled(
                  onPressed: _currentPhase > 0
                      ? () {
                          setState(() {
                            _currentPhase--;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.skip_previous),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.purple.shade100,
                  ),
                ),

                IconButton.filled(
                  onPressed: _toggle4DPlayback,
                  icon: Icon(_isPlaying4D ? Icons.pause : Icons.play_arrow),
                  style: IconButton.styleFrom(
                    backgroundColor: _isPlaying4D
                        ? Colors.red.shade100
                        : Colors.green.shade100,
                  ),
                ),

                IconButton.filled(
                  onPressed: _currentPhase < _constructionPhases.length - 1
                      ? () {
                          setState(() {
                            _currentPhase++;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.skip_next),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.purple.shade100,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          // Current phase info
          if (_constructionPhases.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _constructionPhases[_currentPhase].color.withOpacity(
                  0.1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Phase: ${_constructionPhases[_currentPhase].name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (_currentPhase + 1) / _constructionPhases.length,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      _constructionPhases[_currentPhase].color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Duration: ${_constructionPhases[_currentPhase].duration} weeks',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _toggle4DPlayback() {
    if (_isPlaying4D) {
      _phaseTimer?.cancel();
      setState(() {
        _isPlaying4D = false;
      });
    } else {
      setState(() {
        _isPlaying4D = true;
      });

      _phaseTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_currentPhase < _constructionPhases.length - 1) {
          setState(() {
            _currentPhase++;
          });
        } else {
          timer.cancel();
          setState(() {
            _isPlaying4D = false;
            _currentPhase = 0; // Reset to beginning
          });
        }
      });
    }
  }

  void _resetAll() {
    setState(() {
      _transcription = '';
      _analyzedBuilding = null;
      _hasGenerated3D = false;
      _detectedFeatures.clear();
      _isListening = false;
      _isAnalyzing = false;
      _currentPhase = 0;
      _isPlaying4D = false;
      _constructionPhases.clear();
    });
    _pulseController.stop();
    _rotationController.stop();
    _phaseTimer?.cancel();
  }
}

class BuildingStructure {
  final int floors;
  final List<Room> rooms;
  final double totalWidth;
  final double totalLength;
  final double height;

  BuildingStructure({
    required this.floors,
    required this.rooms,
    required this.totalWidth,
    required this.totalLength,
    required this.height,
  });
}

class Room {
  final String name;
  final String type;
  final Size dimensions;

  Room({required this.name, required this.type, required this.dimensions});
}

class ConstructionPhase {
  final String name;
  final int duration; // in weeks
  final Color color;

  ConstructionPhase({
    required this.name,
    required this.duration,
    required this.color,
  });
}
