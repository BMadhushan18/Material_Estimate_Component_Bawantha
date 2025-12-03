import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/building_model.dart';
import '../models/boq_model.dart';

class APIService {
  // Get backend URL from environment or use default
  static const String defaultBackendUrl = 'http://localhost:8000';

  String get backendUrl {
    const envUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;

    // For Android emulator, use 10.0.2.2 instead of localhost
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }

    return defaultBackendUrl;
  }

  /// Process floor plan image
  Future<Map<String, dynamic>> processFloorPlan({
    required File imageFile,
    double? scaleRatio,
    double heightMm = 3000.0,
  }) async {
    try {
      final uri = Uri.parse('$backendUrl/api/process-floor-plan');

      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('plan', imageFile.path),
      );

      if (scaleRatio != null) {
        request.fields['scale_ratio'] = scaleRatio.toString();
      }
      request.fields['height_mm'] = heightMm.toString();

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Floor plan processing failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error processing floor plan: $e');
      rethrow;
    }
  }

  /// Process AR measurement data
  Future<Map<String, dynamic>> processARData({
    required Map<String, dynamic> arData,
  }) async {
    try {
      final uri = Uri.parse('$backendUrl/api/process-ar-data');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(arData),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('AR data processing failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error processing AR data: $e');
      rethrow;
    }
  }

  /// Process voice transcription
  Future<Map<String, dynamic>> processVoiceInput({
    required String transcriptionText,
  }) async {
    try {
      final uri = Uri.parse('$backendUrl/api/process-voice');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': transcriptionText}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Voice processing failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error processing voice: $e');
      rethrow;
    }
  }

  /// Fuse all data sources and generate BOQ
  Future<FusionResult> fuseAndGenerateBOQ({
    required BuildingModel building,
  }) async {
    try {
      final uri = Uri.parse('$backendUrl/api/fuse-and-generate-boq');

      final requestData = building.getAllDataForFusion();

      debugPrint('Sending fusion request with data: ${requestData.keys}');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        return FusionResult(
          success: result['success'] ?? false,
          building: BuildingModel.fromJson(result['building'] ?? {}),
          boq: BOQModel.fromJson(result['boq'] ?? {}),
          modelUrl: result['model_url'],
          fusionMetadata: result['fusion_metadata'],
        );
      } else {
        throw Exception('BOQ generation failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error generating BOQ: $e');
      rethrow;
    }
  }

  /// Download 3D model file
  Future<File> download3DModel({
    required String modelUrl,
    required String savePath,
  }) async {
    try {
      final uri = Uri.parse('$backendUrl$modelUrl');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        throw Exception('Model download failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading 3D model: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> calibrateStereo() async {
    final uri = Uri.parse('$backendUrl/api/calibrate-stereo');
    var response = await http.post(uri);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Calibration failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> calibrateLeft({bool manual = false}) async {
    final uri = Uri.parse('$backendUrl/api/calibrate-left');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'mode': manual ? 'manual' : 'auto'}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Left calibration failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> calibrateRight({bool manual = false}) async {
    final uri = Uri.parse('$backendUrl/api/calibrate-right');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'mode': manual ? 'manual' : 'auto'}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Right calibration failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> balanceCameras() async {
    final uri = Uri.parse('$backendUrl/api/balance-cameras');
    final response = await http.post(uri);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Camera balancing failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> distanceDetectionPreview() async {
    final uri = Uri.parse('$backendUrl/api/distance-detection-preview');
    final response = await http.post(uri);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Distance detection preview failed: ${response.body}');
    }
  }
}

/// Result from fusion and BOQ generation
class FusionResult {
  final bool success;
  final BuildingModel building;
  final BOQModel boq;
  final String? modelUrl;
  final Map<String, dynamic>? fusionMetadata;

  FusionResult({
    required this.success,
    required this.building,
    required this.boq,
    this.modelUrl,
    this.fusionMetadata,
  });
}
