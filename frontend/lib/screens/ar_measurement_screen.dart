import 'package:flutter/material.dart';
import 'dart:async';

class ARMeasurementScreen extends StatefulWidget {
  const ARMeasurementScreen({super.key});

  @override
  State<ARMeasurementScreen> createState() => _ARMeasurementScreenState();
}

class _ARMeasurementScreenState extends State<ARMeasurementScreen> {
  final List<Map<String, dynamic>> _detectedPlanes = [];
  bool _isScanning = false;
  String _currentRoomName = '';
  final TextEditingController _roomNameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Room Measurement'),
        backgroundColor: Colors.purple[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _detectedPlanes.isEmpty
                ? null
                : () => Navigator.pop(context, _detectedPlanes),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AR Measurement Instructions:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _buildInstruction('1. Enter room name below'),
                _buildInstruction('2. Point camera at floor/walls/ceiling'),
                _buildInstruction('3. Move device slowly to scan surfaces'),
                _buildInstruction('4. Tap detected planes to measure'),
                _buildInstruction('5. Repeat for each room'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Room name input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: 'Current Room Name',
                hintText: 'e.g., Master Bedroom',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.meeting_room),
              ),
              onSubmitted: (value) {
                setState(() => _currentRoomName = value);
              },
            ),
          ),

          const SizedBox(height: 16),

          // AR View placeholder (actual AR would use arcore_flutter_plugin)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.purple, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: Colors.black,
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 64,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Scanning for surfaces...\nMove device slowly'
                              : 'AR Camera View\n(ARCore integration required)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scanning indicator
                  if (_isScanning)
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Scanning',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Detected planes list
          Container(
            height: 150,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detected Planes (${_detectedPlanes.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _detectedPlanes.isEmpty
                      ? const Center(
                          child: Text(
                            'No planes detected yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _detectedPlanes.length,
                          itemBuilder: (context, index) {
                            final plane = _detectedPlanes[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  _getPlaneIcon(plane['type']),
                                  color: Colors.purple,
                                ),
                                title: Text(
                                  '${plane['room']} - ${plane['type']}',
                                ),
                                subtitle: Text(
                                  'Size: ${plane['width'].toStringAsFixed(2)}m × ${plane['length'].toStringAsFixed(2)}m',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () {
                                    setState(() {
                                      _detectedPlanes.removeAt(index);
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentRoomName.isEmpty
                        ? null
                        : () {
                            setState(() => _isScanning = !_isScanning);
                            if (_isScanning) {
                              _simulateARScan();
                            }
                          },
                    icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                    label: Text(_isScanning ? 'Stop Scan' : 'Start AR Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? Colors.red : Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _currentRoomName.isEmpty ? null : _addManualPlane,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Manually'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  IconData _getPlaneIcon(String type) {
    switch (type.toLowerCase()) {
      case 'floor':
        return Icons.square_foot;
      case 'ceiling':
        return Icons.align_vertical_top;
      case 'wall':
        return Icons.crop_portrait;
      default:
        return Icons.crop_square;
    }
  }

  Future<void> _simulateARScan() async {
    // Simulate AR plane detection (in real implementation, use arcore_flutter_plugin)
    await Future.delayed(const Duration(seconds: 3));

    if (_isScanning && mounted) {
      setState(() {
        _detectedPlanes.add({
          'room': _currentRoomName,
          'type': 'floor',
          'width': 3.5,
          'length': 4.2,
          'height': 0.0,
          'confidence': 0.9,
          'normal': [0.0, 1.0, 0.0],
          'center': [0.0, 0.0, 0.0],
        });
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Floor plane detected!')));
    }
  }

  Future<void> _addManualPlane() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ManualPlaneDialog(roomName: _currentRoomName),
    );

    if (result != null) {
      setState(() {
        _detectedPlanes.add(result);
      });
    }
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }
}

class _ManualPlaneDialog extends StatefulWidget {
  final String roomName;

  const _ManualPlaneDialog({required this.roomName});

  @override
  State<_ManualPlaneDialog> createState() => _ManualPlaneDialogState();
}

class _ManualPlaneDialogState extends State<_ManualPlaneDialog> {
  final _widthController = TextEditingController();
  final _lengthController = TextEditingController();
  final _heightController = TextEditingController();
  String _selectedType = 'floor';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Manual Measurement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Plane Type'),
            items: const [
              DropdownMenuItem(value: 'floor', child: Text('Floor')),
              DropdownMenuItem(value: 'ceiling', child: Text('Ceiling')),
              DropdownMenuItem(value: 'wall', child: Text('Wall')),
            ],
            onChanged: (value) => setState(() => _selectedType = value!),
          ),
          TextField(
            controller: _widthController,
            decoration: const InputDecoration(labelText: 'Width (m)'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _lengthController,
            decoration: const InputDecoration(labelText: 'Length (m)'),
            keyboardType: TextInputType.number,
          ),
          if (_selectedType == 'wall')
            TextField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Height (m)'),
              keyboardType: TextInputType.number,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final width = double.tryParse(_widthController.text) ?? 0;
            final length = double.tryParse(_lengthController.text) ?? 0;
            final height = double.tryParse(_heightController.text) ?? 0;

            if (width > 0 && length > 0) {
              Navigator.pop(context, {
                'room': widget.roomName,
                'type': _selectedType,
                'width': width,
                'length': length,
                'height': height,
                'confidence': 0.9,
                'normal': _selectedType == 'floor'
                    ? [0.0, 1.0, 0.0]
                    : _selectedType == 'ceiling'
                    ? [0.0, -1.0, 0.0]
                    : [0.0, 0.0, 1.0],
                'center': [0.0, 0.0, 0.0],
              });
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
