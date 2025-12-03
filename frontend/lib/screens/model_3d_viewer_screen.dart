import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class Model3DViewerScreen extends StatelessWidget {
  final String? modelUrl;

  const Model3DViewerScreen({super.key, this.modelUrl});

  @override
  Widget build(BuildContext context) {
    // Get modelUrl from route arguments if not provided
    final String? url =
        modelUrl ?? (ModalRoute.of(context)?.settings.arguments as String?);

    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Building Model'),
        backgroundColor: Colors.deepPurple[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Help',
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: url == null || url.isEmpty
          ? _buildErrorView()
          : _build3DViewer(url),
    );
  }

  Widget _build3DViewer(String url) {
    return Column(
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.deepPurple[50],
          child: Row(
            children: [
              Icon(Icons.touch_app, color: Colors.deepPurple[700]),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Touch to rotate • Pinch to zoom • Two fingers to pan',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // 3D Model Viewer
        Expanded(
          child: ModelViewer(
            src: url,
            alt: '3D Building Model',
            ar: true, // Enable AR mode on supported devices
            autoRotate: true,
            cameraControls: true,
            backgroundColor: Colors.grey[100]!,
            loading: Loading.eager,

            // Camera settings
            cameraOrbit: '45deg 75deg 2.5m',
            minCameraOrbit: 'auto auto 1m',
            maxCameraOrbit: 'auto auto 10m',

            // AR settings
            arModes: const ['scene-viewer', 'webxr', 'quick-look'],

            // Environment
            environmentImage: null,
            exposure: 1.0,
            shadowIntensity: 1.0,
            shadowSoftness: 1.0,
          ),
        ),

        // Control panel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                Icons.view_in_ar,
                'AR View',
                Colors.deepPurple,
                () {
                  // AR view is automatically handled by ModelViewer
                },
              ),
              _buildControlButton(
                Icons.fullscreen,
                'Fullscreen',
                Colors.blue,
                () {
                  // Fullscreen functionality
                },
              ),
              _buildControlButton(
                Icons.camera_alt,
                'Screenshot',
                Colors.green,
                () {
                  // Screenshot functionality
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          const Text(
            'No 3D model available',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please generate a BOQ first',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 32),
          color: color,
          onPressed: onPressed,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('3D Viewer Controls'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHelpItem(Icons.touch_app, 'Rotate', 'Touch and drag'),
            _buildHelpItem(Icons.zoom_in, 'Zoom', 'Pinch in/out'),
            _buildHelpItem(Icons.pan_tool, 'Pan', 'Two-finger drag'),
            _buildHelpItem(Icons.view_in_ar, 'AR Mode', 'Tap AR View button'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
