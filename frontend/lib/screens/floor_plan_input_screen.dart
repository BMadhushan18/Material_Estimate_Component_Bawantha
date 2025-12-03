import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';

class FloorPlanInputWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onPlanProcessed;

  const FloorPlanInputWidget({super.key, required this.onPlanProcessed});

  @override
  State<FloorPlanInputWidget> createState() => _FloorPlanInputWidgetState();
}

class _FloorPlanInputWidgetState extends State<FloorPlanInputWidget> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isProcessing = false;
  final TextEditingController _scaleController = TextEditingController(
    text: '0.01',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '3000',
  );
  final APIService _apiService = APIService();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload a 2D floor plan image (PNG, JPG) for automatic room detection.',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),

        // Image preview
        if (_imageFile != null) ...[
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.file(_imageFile!, fit: BoxFit.contain),
          ),
          const SizedBox(height: 16),
        ],

        // Upload button
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _pickImage,
          icon: const Icon(Icons.upload_file),
          label: Text(
            _imageFile == null ? 'Upload Floor Plan' : 'Change Image',
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),

        if (_imageFile != null) ...[
          const SizedBox(height: 16),

          // Scale ratio input
          TextField(
            controller: _scaleController,
            decoration: const InputDecoration(
              labelText: 'Scale Ratio (pixels to mm)',
              helperText: 'e.g., 0.01 means 1 pixel = 10mm',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 12),

          // Default height input
          TextField(
            controller: _heightController,
            decoration: const InputDecoration(
              labelText: 'Default Ceiling Height (mm)',
              helperText: 'Typical: 3000mm (3m)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 16),

          // Process button
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _processFloorPlan,
            icon: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.analytics),
            label: Text(_isProcessing ? 'Processing...' : 'Process Floor Plan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (picked != null) {
        setState(() {
          _imageFile = File(picked.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _processFloorPlan() async {
    if (_imageFile == null) return;

    setState(() => _isProcessing = true);

    try {
      final scaleRatio = double.tryParse(_scaleController.text) ?? 0.01;
      final heightMm = double.tryParse(_heightController.text) ?? 3000.0;

      final result = await _apiService.processFloorPlan(
        imageFile: _imageFile!,
        scaleRatio: scaleRatio,
        heightMm: heightMm,
      );

      if (result['success'] == true) {
        widget.onPlanProcessed(result);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Floor plan processed! Found ${result['total_rooms']} rooms',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result['error'] ?? 'Processing failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _heightController.dispose();
    super.dispose();
  }
}
