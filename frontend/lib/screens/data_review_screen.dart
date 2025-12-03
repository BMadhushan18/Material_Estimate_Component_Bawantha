import 'package:flutter/material.dart';
import '../models/building_model.dart';
import '../models/room_model.dart';

class DataReviewScreen extends StatelessWidget {
  final BuildingModel building;

  const DataReviewScreen({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    final allData = building.getAllDataForFusion();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Collected Data'),
        backgroundColor: Colors.indigo[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Data sources summary
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Sources',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 20),
                    _buildDataSourceChip(
                      'Floor Plan',
                      allData['floor_plan_data'] != null,
                      Icons.image,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildDataSourceChip(
                      'AR Measurements',
                      allData['ar_data'] != null,
                      Icons.view_in_ar,
                      Colors.purple,
                    ),
                    const SizedBox(height: 8),
                    _buildDataSourceChip(
                      'Voice Input',
                      allData['voice_transcription'] != null,
                      Icons.mic,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Floor plan data
            if (allData['floor_plan_data'] != null)
              _buildFloorPlanSection(allData['floor_plan_data']),

            // AR data
            if (allData['ar_data'] != null)
              _buildARDataSection(allData['ar_data']),

            // Voice data
            if (allData['voice_transcription'] != null)
              _buildVoiceSection(allData['voice_transcription']),

            const SizedBox(height: 24),

            // Confidence summary
            if (building.rooms.isNotEmpty) _buildConfidenceSummary(),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Data'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSourceChip(
    String label,
    bool available,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: available ? color.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: available ? color : Colors.grey, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: available ? color : Colors.grey, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: available ? Colors.black87 : Colors.grey,
              ),
            ),
          ),
          Icon(
            available ? Icons.check_circle : Icons.cancel,
            color: available ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildFloorPlanSection(Map<String, dynamic> data) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: const Icon(Icons.image, color: Colors.blue),
        title: const Text('Floor Plan Data'),
        subtitle: Text('${data['total_rooms'] ?? 0} rooms detected'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Scale Ratio', '${data['scale_ratio']}'),
                _buildInfoRow('Total Rooms', '${data['total_rooms']}'),
                if (data['rooms'] != null)
                  ...List<Map<String, dynamic>>.from(
                    data['rooms'],
                  ).map((room) => _buildRoomInfo(room, 'Floor Plan')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildARDataSection(List<dynamic> arData) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: const Icon(Icons.view_in_ar, color: Colors.purple),
        title: const Text('AR Measurement Data'),
        subtitle: Text('${arData.length} planes detected'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: arData
                  .map((plane) => _buildARPlaneInfo(plane))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceSection(String transcription) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: const Icon(Icons.mic, color: Colors.orange),
        title: const Text('Voice Input Transcription'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              transcription,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceSummary() {
    return Card(
      elevation: 3,
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  'Fusion Confidence',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            ...building.rooms.map((room) => _buildRoomConfidence(room)),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomConfidence(RoomModel room) {
    final confidence = room.fusionMetadata?.confidence ?? 0.0;
    final sources = room.fusionMetadata?.sourcesUsed ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                room.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${(confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getConfidenceColor(confidence),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: confidence,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation(_getConfidenceColor(confidence)),
          ),
          const SizedBox(height: 4),
          Text(
            'Sources: ${sources.join(", ")}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildRoomInfo(Map<String, dynamic> room, String source) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            room['name'] ?? 'Unknown Room',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Type: ${room['type'] ?? 'unknown'}'),
          Text(
            'Dimensions: ${room['dimensions']?['length_mm']}mm × ${room['dimensions']?['width_mm']}mm',
          ),
        ],
      ),
    );
  }

  Widget _buildARPlaneInfo(Map<String, dynamic> plane) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plane['room']} - ${plane['type']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Size: ${plane['width']?.toStringAsFixed(2) ?? 0}m × ${plane['length']?.toStringAsFixed(2) ?? 0}m',
          ),
          Text(
            'Confidence: ${((plane['confidence'] ?? 0) * 100).toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }
}
