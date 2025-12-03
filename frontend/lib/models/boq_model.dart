// BOQ (Bill of Quantities) Model
class BOQModel {
  final String buildingId;
  final String buildingName;
  final String? ownerName;
  final String generatedDate;
  final List<RoomBOQ> roomsBreakdown;
  final BOQSummary summary;

  BOQModel({
    required this.buildingId,
    required this.buildingName,
    this.ownerName,
    required this.generatedDate,
    required this.roomsBreakdown,
    required this.summary,
  });

  factory BOQModel.fromJson(Map<String, dynamic> json) {
    return BOQModel(
      buildingId: json['building_id'] ?? '',
      buildingName: json['building_name'] ?? '',
      ownerName: json['owner_name'],
      generatedDate: json['generated_date'] ?? '',
      roomsBreakdown:
          (json['rooms_breakdown'] as List?)
              ?.map((r) => RoomBOQ.fromJson(r))
              .toList() ??
          [],
      summary: BOQSummary.fromJson(json['summary'] ?? {}),
    );
  }
}

class RoomBOQ {
  final String roomId;
  final String roomName;
  final String roomType;
  final Map<String, double> areas;
  final PaintRequirement paint;
  final PuttyRequirement putty;
  final FlooringRequirement flooring;
  final WallTilingRequirement? wallTiling;
  final double totalCostLkr;

  RoomBOQ({
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.areas,
    required this.paint,
    required this.putty,
    required this.flooring,
    this.wallTiling,
    required this.totalCostLkr,
  });

  factory RoomBOQ.fromJson(Map<String, dynamic> json) {
    return RoomBOQ(
      roomId: json['room_id'] ?? '',
      roomName: json['room_name'] ?? '',
      roomType: json['room_type'] ?? '',
      areas: Map<String, double>.from(
        (json['areas'] ?? {}).map((k, v) => MapEntry(k, v.toDouble())),
      ),
      paint: PaintRequirement.fromJson(json['paint'] ?? {}),
      putty: PuttyRequirement.fromJson(json['putty'] ?? {}),
      flooring: FlooringRequirement.fromJson(json['flooring'] ?? {}),
      wallTiling: json['wall_tiling'] != null
          ? WallTilingRequirement.fromJson(json['wall_tiling'])
          : null,
      totalCostLkr: (json['total_cost_lkr'] ?? 0).toDouble(),
    );
  }
}

class PaintRequirement {
  final double paintLiters;
  final double primerLiters;
  final double coverageSqm;
  final int coats;
  final String paintType;
  final double estimatedCostLkr;

  PaintRequirement({
    required this.paintLiters,
    required this.primerLiters,
    required this.coverageSqm,
    required this.coats,
    required this.paintType,
    required this.estimatedCostLkr,
  });

  factory PaintRequirement.fromJson(Map<String, dynamic> json) {
    return PaintRequirement(
      paintLiters: (json['paint_liters'] ?? 0).toDouble(),
      primerLiters: (json['primer_liters'] ?? 0).toDouble(),
      coverageSqm: (json['coverage_sqm'] ?? 0).toDouble(),
      coats: json['coats'] ?? 2,
      paintType: json['paint_type'] ?? 'emulsion',
      estimatedCostLkr: (json['estimated_cost_lkr'] ?? 0).toDouble(),
    );
  }
}

class PuttyRequirement {
  final double kg;
  final double coverageSqm;
  final int coats;
  final double estimatedCostLkr;

  PuttyRequirement({
    required this.kg,
    required this.coverageSqm,
    required this.coats,
    required this.estimatedCostLkr,
  });

  factory PuttyRequirement.fromJson(Map<String, dynamic> json) {
    return PuttyRequirement(
      kg: (json['kg'] ?? 0).toDouble(),
      coverageSqm: (json['coverage_sqm'] ?? 0).toDouble(),
      coats: json['coats'] ?? 2,
      estimatedCostLkr: (json['estimated_cost_lkr'] ?? 0).toDouble(),
    );
  }
}

class FlooringRequirement {
  final String material;
  final int tilesCount;
  final String tileSize;
  final String tileType;
  final double areaSqm;
  final double adhesiveKg;
  final double groutKg;
  final int wastagePercent;
  final double estimatedCostLkr;

  FlooringRequirement({
    required this.material,
    required this.tilesCount,
    required this.tileSize,
    required this.tileType,
    required this.areaSqm,
    required this.adhesiveKg,
    required this.groutKg,
    required this.wastagePercent,
    required this.estimatedCostLkr,
  });

  factory FlooringRequirement.fromJson(Map<String, dynamic> json) {
    return FlooringRequirement(
      material: json['material'] ?? 'tiles',
      tilesCount: json['tiles_count'] ?? 0,
      tileSize: json['tile_size'] ?? '600x600',
      tileType: json['tile_type'] ?? 'ceramic',
      areaSqm: (json['area_sqm'] ?? 0).toDouble(),
      adhesiveKg: (json['adhesive_kg'] ?? 0).toDouble(),
      groutKg: (json['grout_kg'] ?? 0).toDouble(),
      wastagePercent: json['wastage_percent'] ?? 10,
      estimatedCostLkr: (json['estimated_cost_lkr'] ?? 0).toDouble(),
    );
  }
}

class WallTilingRequirement {
  final int tilesCount;
  final String tileSize;
  final double areaSqm;
  final double estimatedCostLkr;

  WallTilingRequirement({
    required this.tilesCount,
    required this.tileSize,
    required this.areaSqm,
    required this.estimatedCostLkr,
  });

  factory WallTilingRequirement.fromJson(Map<String, dynamic> json) {
    return WallTilingRequirement(
      tilesCount: json['tiles_count'] ?? 0,
      tileSize: json['tile_size'] ?? '300x600',
      areaSqm: (json['area_sqm'] ?? 0).toDouble(),
      estimatedCostLkr: (json['estimated_cost_lkr'] ?? 0).toDouble(),
    );
  }
}

class BOQSummary {
  final double totalPaintLiters;
  final double totalPrimerLiters;
  final double totalPuttyKg;
  final int totalFloorTilesCount;
  final int totalWallTilesCount;
  final double totalAdhesiveKg;
  final double totalGroutKg;
  final double totalEstimatedCostLkr;
  final int totalRooms;
  final double totalFloorAreaSqm;

  BOQSummary({
    required this.totalPaintLiters,
    required this.totalPrimerLiters,
    required this.totalPuttyKg,
    required this.totalFloorTilesCount,
    required this.totalWallTilesCount,
    required this.totalAdhesiveKg,
    required this.totalGroutKg,
    required this.totalEstimatedCostLkr,
    required this.totalRooms,
    required this.totalFloorAreaSqm,
  });

  factory BOQSummary.fromJson(Map<String, dynamic> json) {
    return BOQSummary(
      totalPaintLiters: (json['total_paint_liters'] ?? 0).toDouble(),
      totalPrimerLiters: (json['total_primer_liters'] ?? 0).toDouble(),
      totalPuttyKg: (json['total_putty_kg'] ?? 0).toDouble(),
      totalFloorTilesCount: json['total_floor_tiles_count'] ?? 0,
      totalWallTilesCount: json['total_wall_tiles_count'] ?? 0,
      totalAdhesiveKg: (json['total_adhesive_kg'] ?? 0).toDouble(),
      totalGroutKg: (json['total_grout_kg'] ?? 0).toDouble(),
      totalEstimatedCostLkr: (json['total_estimated_cost_lkr'] ?? 0).toDouble(),
      totalRooms: json['total_rooms'] ?? 0,
      totalFloorAreaSqm: (json['total_floor_area_sqm'] ?? 0).toDouble(),
    );
  }
}
