import 'package:flutter/material.dart';
import '../models/building_model.dart';
import '../services/api_service.dart';
import 'floor_plan_input_screen.dart';
import 'voice_input_screen.dart';
import 'ar_measurement_screen.dart';
import 'boq_display_screen.dart';

class InputWizardScreen extends StatefulWidget {
  const InputWizardScreen({super.key});

  @override
  State<InputWizardScreen> createState() => _InputWizardScreenState();
}

class _InputWizardScreenState extends State<InputWizardScreen> {
  int _currentStep = 0;
  final BuildingModel _building = BuildingModel(
    id: 'building_${DateTime.now().millisecondsSinceEpoch}',
    name: 'My Building',
  );

  bool _isProcessing = false;
  final APIService _apiService = APIService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Building Analysis Wizard'),
        backgroundColor: Colors.blue[700],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: details.onStepContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    _currentStep == _getSteps().length - 1
                        ? 'Generate BOQ'
                        : 'Next',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
              ],
            ),
          );
        },
        steps: _getSteps(),
      ),
    );
  }

  List<Step> _getSteps() {
    return [
      Step(
        title: const Text('1. Floor Plan'),
        subtitle: const Text('Upload 2D plan (optional)'),
        content: FloorPlanInputWidget(
          onPlanProcessed: (data) {
            setState(() {
              _building.addFloorPlanData(data);
            });
          },
        ),
        isActive: _currentStep >= 0,
        state: _building.hasFloorPlanData()
            ? StepState.complete
            : StepState.indexed,
      ),
      Step(
        title: const Text('2. AR Scan'),
        subtitle: const Text('Real-time measurements'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use your camera to scan rooms and measure dimensions in real-time.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final data = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const ARMeasurementScreen(),
                  ),
                );
                if (data != null) {
                  setState(() {
                    _building.addARData(data);
                  });
                }
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start AR Scanning'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            if (_building.hasARData()) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('AR data captured successfully'),
                ],
              ),
            ],
          ],
        ),
        isActive: _currentStep >= 1,
        state: _building.hasARData() ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: const Text('3. Voice Details'),
        subtitle: const Text('Describe verbally'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Speak to describe room names, dimensions, and other details.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final text = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (ctx) => const VoiceInputScreen()),
                );
                if (text != null && text.isNotEmpty) {
                  setState(() {
                    _building.addVoiceData(text);
                  });
                }
              },
              icon: const Icon(Icons.mic),
              label: const Text('Record Voice Input'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            if (_building.hasVoiceData()) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Voice data captured successfully'),
                ],
              ),
            ],
          ],
        ),
        isActive: _currentStep >= 2,
        state: _building.hasVoiceData()
            ? StepState.complete
            : StepState.indexed,
      ),
      Step(
        title: const Text('4. Review'),
        subtitle: const Text('Verify and generate'),
        content: _buildReviewContent(),
        isActive: _currentStep >= 3,
      ),
    ];
  }

  Widget _buildReviewContent() {
    final sources = <String>[];
    if (_building.hasFloorPlanData()) sources.add('Floor Plan');
    if (_building.hasARData()) sources.add('AR Measurements');
    if (_building.hasVoiceData()) sources.add('Voice Input');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data Sources:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (sources.isEmpty)
          const Text(
            'No data sources added yet. Please go back and add at least one source.',
            style: TextStyle(color: Colors.orange),
          )
        else
          ...sources.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(s),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'The system will:',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        _buildInfoPoint('Combine all data sources'),
        _buildInfoPoint('Generate 3D model'),
        _buildInfoPoint('Calculate material quantities'),
        _buildInfoPoint('Estimate costs'),
        if (_isProcessing) ...[
          const SizedBox(height: 20),
          const Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Processing... Please wait'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.arrow_right, size: 20),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  void _onStepContinue() {
    if (_currentStep < _getSteps().length - 1) {
      setState(() => _currentStep++);
    } else {
      _generateBOQ();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _generateBOQ() async {
    // Check if we have at least one data source
    if (!_building.hasFloorPlanData() &&
        !_building.hasARData() &&
        !_building.hasVoiceData()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide at least one data source'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Call API to fuse data and generate BOQ
      final result = await _apiService.fuseAndGenerateBOQ(building: _building);

      if (!mounted) return;

      if (result.success) {
        // Navigate to BOQ display
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (ctx) =>
                BOQDisplayScreen(boq: result.boq, modelUrl: result.modelUrl),
          ),
        );
      } else {
        throw Exception('BOQ generation failed');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
