// Room Model
class RoomModel {
  final String id;
  final String name;
  final String type;
  final RoomDimensions dimensions;
  final List<Opening> doors;
  final List<Opening> windows;
  final FusionMetadata? fusionMetadata;

  RoomModel({
    required this.id,
    required this.name,
    required this.type,
    required this.dimensions,
    this.doors = const [],
    this.windows = const [],
    this.fusionMetadata,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'unknown',
      dimensions: RoomDimensions.fromJson(json['dimensions'] ?? {}),
      doors:
          (json['doors'] as List?)?.map((e) => Opening.fromJson(e)).toList() ??
          [],
      windows:
          (json['windows'] as List?)
              ?.map((e) => Opening.fromJson(e))
              .toList() ??
          [],
      fusionMetadata: json['fusion_metadata'] != null
          ? FusionMetadata.fromJson(json['fusion_metadata'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'dimensions': dimensions.toJson(),
      'doors': doors.map((e) => e.toJson()).toList(),
      'windows': windows.map((e) => e.toJson()).toList(),
      if (fusionMetadata != null) 'fusion_metadata': fusionMetadata!.toJson(),
    };
  }
}

class RoomDimensions {
  final double lengthMm;
  final double widthMm;
  final double heightMm;
  final double lengthM;
  final double widthM;
  final double heightM;
  final double areaSqm;

  RoomDimensions({
    required this.lengthMm,
    required this.widthMm,
    required this.heightMm,
    required this.lengthM,
    required this.widthM,
    required this.heightM,
    required this.areaSqm,
  });

  factory RoomDimensions.fromJson(Map<String, dynamic> json) {
    return RoomDimensions(
      lengthMm: (json['length_mm'] ?? 0).toDouble(),
      widthMm: (json['width_mm'] ?? 0).toDouble(),
      heightMm: (json['height_mm'] ?? 0).toDouble(),
      lengthM: (json['length_m'] ?? 0).toDouble(),
      widthM: (json['width_m'] ?? 0).toDouble(),
      heightM: (json['height_m'] ?? 0).toDouble(),
      areaSqm: (json['area_sqm'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'length_mm': lengthMm,
      'width_mm': widthMm,
      'height_mm': heightMm,
      'length_m': lengthM,
      'width_m': widthM,
      'height_m': heightM,
      'area_sqm': areaSqm,
    };
  }
}

class Opening {
  final String type; // 'door' or 'window'
  final double widthMm;
  final double heightMm;

  Opening({required this.type, required this.widthMm, required this.heightMm});

  factory Opening.fromJson(Map<String, dynamic> json) {
    return Opening(
      type: json['type'] ?? 'door',
      widthMm: (json['width_mm'] ?? 0).toDouble(),
      heightMm: (json['height_mm'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'width_mm': widthMm, 'height_mm': heightMm};
  }
}

class FusionMetadata {
  final List<String> sourcesUsed;
  final double confidence;
  final int measurementsFused;
  final bool isValid;
  final String validationMessage;

  FusionMetadata({
    required this.sourcesUsed,
    required this.confidence,
    required this.measurementsFused,
    required this.isValid,
    required this.validationMessage,
  });

  factory FusionMetadata.fromJson(Map<String, dynamic> json) {
    return FusionMetadata(
      sourcesUsed: List<String>.from(json['sources_used'] ?? []),
      confidence: (json['confidence'] ?? 0).toDouble(),
      measurementsFused: json['measurements_fused'] ?? 0,
      isValid: json['is_valid'] ?? false,
      validationMessage: json['validation_message'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sources_used': sourcesUsed,
      'confidence': confidence,
      'measurements_fused': measurementsFused,
      'is_valid': isValid,
      'validation_message': validationMessage,
    };
  }
}
