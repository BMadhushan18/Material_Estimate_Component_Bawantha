import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/boq_model.dart';

class BOQDisplayScreen extends StatelessWidget {
  final BOQModel boq;
  final String? modelUrl;

  const BOQDisplayScreen({super.key, required this.boq, this.modelUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill of Quantities'),
        backgroundColor: Colors.teal[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () => _exportPDF(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () => _shareBOQ(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Project Summary',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      'Total Rooms',
                      '${boq.roomsBreakdown.length}',
                      Icons.meeting_room,
                    ),
                    _buildSummaryRow(
                      'Total Paint',
                      '${boq.summary.totalPaintLiters.toStringAsFixed(1)} L',
                      Icons.format_paint,
                    ),
                    _buildSummaryRow(
                      'Total Putty',
                      '${boq.summary.totalPuttyKg.toStringAsFixed(1)} kg',
                      Icons.construction,
                    ),
                    _buildSummaryRow(
                      'Floor Tiles',
                      '${boq.summary.totalFloorTilesCount} pcs',
                      Icons.grid_on,
                    ),
                    _buildSummaryRow(
                      'Wall Tiles',
                      '${boq.summary.totalWallTilesCount} pcs',
                      Icons.view_module,
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      'Total Cost',
                      'LKR ${boq.summary.totalEstimatedCostLkr.toStringAsFixed(2)}',
                      Icons.attach_money,
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Cost breakdown chart
            const Text(
              'Cost Distribution',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _buildCostPieChart()),

            const SizedBox(height: 24),

            // Room-by-room breakdown
            const Text(
              'Room-by-Room Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ...boq.roomsBreakdown.map((room) => _buildRoomCard(room)),

            const SizedBox(height: 24),

            // 3D Model button
            if (modelUrl != null && modelUrl!.isNotEmpty)
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to 3D model viewer
                    Navigator.pushNamed(
                      context,
                      '/model-viewer',
                      arguments: modelUrl,
                    );
                  },
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('View 3D Model'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    backgroundColor: Colors.blue[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon, {
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.teal, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.teal[700] : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostPieChart() {
    final totalPaintCost = boq.roomsBreakdown.fold<double>(
      0,
      (sum, room) => sum + room.paint.estimatedCostLkr,
    );
    final totalPuttyCost = boq.roomsBreakdown.fold<double>(
      0,
      (sum, room) => sum + room.putty.estimatedCostLkr,
    );
    final totalFloorTilesCost = boq.roomsBreakdown.fold<double>(
      0,
      (sum, room) => sum + room.flooring.estimatedCostLkr,
    );
    final totalWallTilesCost = boq.roomsBreakdown.fold<double>(
      0,
      (sum, room) => sum + (room.wallTiling?.estimatedCostLkr ?? 0),
    );

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: totalPaintCost,
            title:
                'Paint\n${((totalPaintCost / boq.summary.totalEstimatedCostLkr) * 100).toStringAsFixed(0)}%',
            color: Colors.blue,
            radius: 80,
          ),
          PieChartSectionData(
            value: totalPuttyCost,
            title:
                'Putty\n${((totalPuttyCost / boq.summary.totalEstimatedCostLkr) * 100).toStringAsFixed(0)}%',
            color: Colors.orange,
            radius: 80,
          ),
          PieChartSectionData(
            value: totalFloorTilesCost,
            title:
                'Floor Tiles\n${((totalFloorTilesCost / boq.summary.totalEstimatedCostLkr) * 100).toStringAsFixed(0)}%',
            color: Colors.green,
            radius: 80,
          ),
          if (totalWallTilesCost > 0)
            PieChartSectionData(
              value: totalWallTilesCost,
              title:
                  'Wall Tiles\n${((totalWallTilesCost / boq.summary.totalEstimatedCostLkr) * 100).toStringAsFixed(0)}%',
              color: Colors.purple,
              radius: 80,
            ),
        ],
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildRoomCard(RoomBOQ room) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(_getRoomIcon(room.roomName), color: Colors.teal),
        title: Text(
          room.roomName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Total: LKR ${room.totalCostLkr.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.teal),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMaterialRow(
                  'Paint',
                  '${room.paint.paintLiters.toStringAsFixed(1)} L',
                  'LKR ${room.paint.estimatedCostLkr.toStringAsFixed(2)}',
                ),
                _buildMaterialRow(
                  'Putty',
                  '${room.putty.kg.toStringAsFixed(1)} kg',
                  'LKR ${room.putty.estimatedCostLkr.toStringAsFixed(2)}',
                ),
                _buildMaterialRow(
                  'Floor Tiles',
                  '${room.flooring.tilesCount} pcs',
                  'LKR ${room.flooring.estimatedCostLkr.toStringAsFixed(2)}',
                ),
                if (room.wallTiling != null)
                  _buildMaterialRow(
                    'Wall Tiles',
                    '${room.wallTiling!.tilesCount} pcs',
                    'LKR ${room.wallTiling!.estimatedCostLkr.toStringAsFixed(2)}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialRow(String material, String quantity, String cost) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(material)),
          Text(quantity, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              cost,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRoomIcon(String roomName) {
    final name = roomName.toLowerCase();
    if (name.contains('bedroom')) return Icons.bed;
    if (name.contains('kitchen')) return Icons.kitchen;
    if (name.contains('bathroom') || name.contains('toilet')) {
      return Icons.bathroom;
    }
    if (name.contains('living')) return Icons.chair;
    return Icons.meeting_room;
  }

  Future<void> _exportPDF(BuildContext context) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Bill of Quantities',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Total Cost: LKR ${boq.summary.totalEstimatedCostLkr.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 10),
            ...boq.roomsBreakdown.map(
              (room) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      room.roomName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Paint: ${room.paint.paintLiters.toStringAsFixed(1)} L - LKR ${room.paint.estimatedCostLkr.toStringAsFixed(2)}',
                    ),
                    pw.Text(
                      'Putty: ${room.putty.kg.toStringAsFixed(1)} kg - LKR ${room.putty.estimatedCostLkr.toStringAsFixed(2)}',
                    ),
                    pw.Text(
                      'Floor Tiles: ${room.flooring.tilesCount} pcs - LKR ${room.flooring.estimatedCostLkr.toStringAsFixed(2)}',
                    ),
                    if (room.wallTiling != null)
                      pw.Text(
                        'Wall Tiles: ${room.wallTiling!.tilesCount} pcs - LKR ${room.wallTiling!.estimatedCostLkr.toStringAsFixed(2)}',
                      ),
                    pw.Divider(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _shareBOQ(BuildContext context) async {
    // Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share functionality to be implemented')),
    );
  }
}
