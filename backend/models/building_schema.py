"""
Pydantic models for building structure data
"""
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from enum import Enum


class RoomType(str, Enum):
    MASTER_BEDROOM = "master_bedroom"
    BEDROOM = "bedroom"
    LIVING_ROOM = "living_room"
    DINING_ROOM = "dining_room"
    KITCHEN = "kitchen"
    BATHROOM = "bathroom"
    TOILET = "toilet"
    BALCONY = "balcony"
    CORRIDOR = "corridor"
    STORAGE = "storage"
    UNKNOWN = "unknown"


class OpeningType(str, Enum):
    DOOR = "door"
    WINDOW = "window"
    SLIDING_DOOR = "sliding_door"
    FRENCH_DOOR = "french_door"


class DataSource(str, Enum):
    FLOOR_PLAN = "floor_plan"
    PHOTOS = "photos"
    AR_MEASUREMENT = "ar_measurement"
    VOICE_INPUT = "voice_input"
    MANUAL = "manual"


class Point2D(BaseModel):
    x: float
    y: float


class Point3D(BaseModel):
    x: float
    y: float
    z: float


class Opening(BaseModel):
    """Door or window in a room"""
    type: OpeningType
    position: Point2D
    width_mm: float
    height_mm: float
    wall_index: Optional[int] = None


class Measurement(BaseModel):
    """Single measurement with source and confidence"""
    value: float
    unit: str = "mm"
    source: DataSource
    confidence: float = Field(ge=0.0, le=1.0)
    timestamp: Optional[str] = None


class RoomDimensions(BaseModel):
    """Room dimensions with multiple source tracking"""
    length_mm: Optional[Measurement] = None
    width_mm: Optional[Measurement] = None
    height_mm: Optional[Measurement] = None
    area_sqm: Optional[float] = None


class Room(BaseModel):
    """Complete room data structure"""
    id: str
    name: str
    type: RoomType = RoomType.UNKNOWN
    polygon: List[Point2D] = []
    dimensions: RoomDimensions
    doors: List[Opening] = []
    windows: List[Opening] = []
    floor_level: int = 0
    
    # Multi-source data tracking
    sources: List[DataSource] = []
    confidence_score: float = 0.0
    
    # Finishing specifications
    wall_finish: str = "paint"
    floor_finish: str = "tiles"
    ceiling_finish: str = "paint"


class Building(BaseModel):
    """Complete building structure"""
    id: str
    name: str
    owner_name: Optional[str] = None
    rooms: List[Room] = []
    total_floor_area_sqm: float = 0.0
    number_of_floors: int = 1
    
    # Data fusion metadata
    floor_plan_data: Optional[Dict[str, Any]] = None
    photo_data: Optional[Dict[str, Any]] = None
    ar_data: Optional[Dict[str, Any]] = None
    voice_data: Optional[Dict[str, Any]] = None
    
    fusion_complete: bool = False
    overall_confidence: float = 0.0


class MaterialItem(BaseModel):
    """Single material item in BOQ"""
    material_type: str
    description: str
    quantity: float
    unit: str
    room_id: Optional[str] = None
    room_name: Optional[str] = None
    coverage_area_sqm: Optional[float] = None
    wastage_factor: float = 1.0
    estimated_cost_lkr: Optional[float] = None


class BOQ(BaseModel):
    """Bill of Quantities"""
    building_id: str
    building_name: str
    generated_date: str
    
    # Material categories
    paint_items: List[MaterialItem] = []
    putty_items: List[MaterialItem] = []
    tile_items: List[MaterialItem] = []
    adhesive_items: List[MaterialItem] = []
    
    # Summary
    total_paint_liters: float = 0.0
    total_putty_kg: float = 0.0
    total_tiles_count: int = 0
    total_estimated_cost_lkr: float = 0.0
    
    # Metadata
    data_sources_used: List[DataSource] = []
    calculation_confidence: float = 0.0
