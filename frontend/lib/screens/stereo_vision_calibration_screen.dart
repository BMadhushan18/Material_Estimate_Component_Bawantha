import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StereoVisionCalibrationScreen extends StatefulWidget {
  const StereoVisionCalibrationScreen({super.key});

  @override
  State<StereoVisionCalibrationScreen> createState() =>
      _StereoVisionCalibrationScreenState();
}

class _StereoVisionCalibrationScreenState
    extends State<StereoVisionCalibrationScreen> {
  int _step = 0; // 0: balance, 1: start, 2: left, 3: right, 4: finish
  bool _isProcessing = false;
  bool _isBalanced = false;

  Future<void> _balanceCameras() async {
    setState(() => _isProcessing = true);
    try {
      final apiService = APIService();
      await apiService.balanceCameras();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera balancing completed!')),
      );
      setState(() => _isBalanced = true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Camera balancing failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _startCalibration() async {
    setState(() => _step = 2);
  }

  void _preview() {
    setState(() => _isProcessing = true);
    _startDistanceDetectionPreview();
  }

  Future<void> _startDistanceDetectionPreview() async {
    try {
      final apiService = APIService();
      await apiService.distanceDetectionPreview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Distance detection preview completed!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _calibrateLeft() async {
    setState(() => _isProcessing = true);
    try {
      final apiService = APIService();
      await apiService.calibrateLeft(manual: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Left camera calibrated successfully!')),
      );
      setState(() => _step = 3);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Left calibration failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _calibrateRight() async {
    setState(() => _isProcessing = true);
    try {
      final apiService = APIService();
      await apiService.calibrateRight(manual: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Right camera calibrated successfully!')),
      );
      setState(() => _step = 4);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Right calibration failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _finish() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stereo Vision Calibration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_step == 0 && !_isBalanced)
              const Text(
                'First, balance the cameras by aligning them physically. Ensure both cameras are streaming.',
                textAlign: TextAlign.center,
              )
            else if (_step == 0 && _isBalanced)
              const Text(
                'Ensure both phone cameras are streaming chessboard patterns.',
                textAlign: TextAlign.center,
              )
            else if (_step >= 2)
              const Text(
                'Calibration in progress...',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 40),
            if (_step == 0)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _isBalanced || _isProcessing
                        ? null
                        : _balanceCameras,
                    child: _isProcessing && !_isBalanced
                        ? const CircularProgressIndicator()
                        : const Text('Start Camera Balancing'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _startCalibration,
                    child: const Text('Start Calibration'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _preview,
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Preview'),
                  ),
                ],
              )
            else if (_step == 2)
              ElevatedButton(
                onPressed: _isProcessing ? null : _calibrateLeft,
                child: _isProcessing
                    ? const CircularProgressIndicator()
                    : const Text('Calibrate Left Camera'),
              )
            else if (_step == 3)
              ElevatedButton(
                onPressed: _isProcessing ? null : _calibrateRight,
                child: _isProcessing
                    ? const CircularProgressIndicator()
                    : const Text('Calibrate Right Camera'),
              )
            else if (_step == 4)
              ElevatedButton(onPressed: _finish, child: const Text('Finish')),
          ],
        ),
      ),
    );
  }
}
