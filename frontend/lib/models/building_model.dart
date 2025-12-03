// Building Model
import 'room_model.dart';

class BuildingModel {
  final String id;
  final String name;
  final String? ownerName;
  final List<RoomModel> rooms;
  final double totalFloorAreaSqm;
  final int numberOfFloors;

  // Multi-modal data sources
  Map<String, dynamic>? floorPlanData;
  Map<String, dynamic>? arData;
  Map<String, dynamic>? voiceData;
  Map<String, dynamic>? photoData;

  bool fusionComplete;
  double overallConfidence;

  BuildingModel({
    required this.id,
    required this.name,
    this.ownerName,
    this.rooms = const [],
    this.totalFloorAreaSqm = 0.0,
    this.numberOfFloors = 1,
    this.floorPlanData,
    this.arData,
    this.voiceData,
    this.photoData,
    this.fusionComplete = false,
    this.overallConfidence = 0.0,
  });

  factory BuildingModel.fromJson(Map<String, dynamic> json) {
    return BuildingModel(
      id: json['id'] ?? 'building_1',
      name: json['name'] ?? 'My Building',
      ownerName: json['owner_name'],
      rooms:
          (json['rooms'] as List?)
              ?.map((r) => RoomModel.fromJson(r))
              .toList() ??
          [],
      totalFloorAreaSqm: (json['total_floor_area_sqm'] ?? 0).toDouble(),
      numberOfFloors: json['number_of_floors'] ?? 1,
      fusionComplete: json['fusion_complete'] ?? false,
      overallConfidence: (json['overall_confidence'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (ownerName != null) 'owner_name': ownerName,
      'rooms': rooms.map((r) => r.toJson()).toList(),
      'total_floor_area_sqm': totalFloorAreaSqm,
      'number_of_floors': numberOfFloors,
      'fusion_complete': fusionComplete,
      'overall_confidence': overallConfidence,
    };
  }

  // Add floor plan data
  void addFloorPlanData(Map<String, dynamic> data) {
    floorPlanData = data;
  }

  // Add AR data
  void addARData(Map<String, dynamic> data) {
    arData = data;
  }

  // Add voice data
  void addVoiceData(String text) {
    voiceData = {'text': text};
  }

  // Add photo data
  void addPhotoData(Map<String, dynamic> data) {
    photoData = data;
  }

  // Check if has data from source
  bool hasFloorPlanData() =>
      floorPlanData != null && (floorPlanData!['success'] ?? false);
  bool hasARData() => arData != null && (arData!['success'] ?? false);
  bool hasVoiceData() =>
      voiceData != null && voiceData!['text']?.isNotEmpty == true;
  bool hasPhotoData() => photoData != null && (photoData!['success'] ?? false);

  // Get all data for fusion
  Map<String, dynamic> getAllDataForFusion() {
    return {
      'building_id': id,
      'building_name': name,
      if (ownerName != null) 'owner_name': ownerName,
      if (floorPlanData != null) 'floor_plan_data': floorPlanData,
      if (arData != null) 'ar_data': arData,
      if (voiceData != null) 'voice_data': voiceData,
      if (photoData != null) 'photo_data': photoData,
    };
  }
}
