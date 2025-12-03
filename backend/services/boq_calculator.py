"""
BOQ (Bill of Quantities) Calculator
Calculates material requirements for paint, putty, and tiles
Based on Sri Lankan construction standards
"""
import sqlite3
import logging
from typing import Dict, List, Any, Tuple
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BOQCalculator:
    def __init__(self, standards_db_path='backend/database/sl_construction_standards.db'):
        self.db_path = standards_db_path
        self.load_standards()
    
    def load_standards(self):
        """Load construction standards from database"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            c = conn.cursor()
            
            # Load paint standards
            c.execute("SELECT * FROM paint_standards WHERE paint_type='emulsion' AND surface_type='smooth'")
            row = c.fetchone()
            self.paint_standard = dict(row) if row else None
            
            # Load putty standards
            c.execute("SELECT * FROM putty_standards WHERE putty_type='wall_putty'")
            row = c.fetchone()
            self.putty_standard = dict(row) if row else None
            
            # Load tile standards
            c.execute("SELECT * FROM tile_standards WHERE tile_type='ceramic' AND size_mm='600x600'")
            row = c.fetchone()
            self.tile_standard = dict(row) if row else None
            
            # Load material costs
            c.execute("SELECT * FROM material_costs")
            rows = c.fetchall()
            self.material_costs = {f"{row['material_category']}_{row['material_name']}": dict(row) for row in rows}
            
            conn.close()
            logger.info("Standards loaded successfully")
            
        except Exception as e:
            logger.error(f"Failed to load standards: {e}")
            self._use_default_standards()
    
    def _use_default_standards(self):
        """Fallback to hardcoded standards if database fails"""
        self.paint_standard = {
            'coverage_sqm_per_liter': 12.0,
            'coats_required': 2,
            'primer_required': 1,
            'primer_coverage_sqm_per_liter': 14.0
        }
        self.putty_standard = {
            'coverage_sqm_per_kg': 15.0,
            'coats_required': 2
        }
        self.tile_standard = {
            'adhesive_kg_per_sqm': 5.0,
            'grout_kg_per_sqm': 1.5,
            'wastage_factor': 0.10
        }
        self.material_costs = {}
    
    def generate_complete_boq(self, building_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate complete Bill of Quantities for the building
        
        Args:
            building_data: Fused building data with rooms
            
        Returns:
            Complete BOQ with itemized materials
        """
        try:
            rooms = building_data.get('rooms', [])
            building_info = building_data.get('building', {})
            
            boq = {
                'building_id': building_info.get('id', 'building_1'),
                'building_name': building_info.get('name', 'My Building'),
                'owner_name': building_info.get('owner_name', ''),
                'generated_date': datetime.now().isoformat(),
                'rooms_breakdown': [],
                'paint_items': [],
                'putty_items': [],
                'tile_items': [],
                'adhesive_items': [],
                'summary': {}
            }
            
            # Process each room
            total_paint = 0
            total_primer = 0
            total_putty = 0
            total_floor_tiles = 0
            total_wall_tiles = 0
            total_adhesive = 0
            total_grout = 0
            total_cost = 0
            
            for room in rooms:
                room_boq = self.calculate_room_boq(room)
                boq['rooms_breakdown'].append(room_boq)
                
                # Accumulate totals
                total_paint += room_boq['paint']['paint_liters']
                total_primer += room_boq['paint']['primer_liters']
                total_putty += room_boq['putty']['kg']
                
                if room_boq['flooring']['material'] == 'tiles':
                    total_floor_tiles += room_boq['flooring']['tiles_count']
                    total_adhesive += room_boq['flooring']['adhesive_kg']
                    total_grout += room_boq['flooring']['grout_kg']
                
                if 'wall_tiles' in room_boq:
                    total_wall_tiles += room_boq['wall_tiles'].get('tiles_count', 0)
                
                total_cost += room_boq.get('total_cost_lkr', 0)
            
            # Create itemized lists
            boq['paint_items'] = self.create_paint_items(rooms, boq['rooms_breakdown'])
            boq['putty_items'] = self.create_putty_items(rooms, boq['rooms_breakdown'])
            boq['tile_items'] = self.create_tile_items(rooms, boq['rooms_breakdown'])
            boq['adhesive_items'] = self.create_adhesive_items(rooms, boq['rooms_breakdown'])
            
            # Summary
            boq['summary'] = {
                'total_paint_liters': round(total_paint, 1),
                'total_primer_liters': round(total_primer, 1),
                'total_putty_kg': round(total_putty, 1),
                'total_floor_tiles_count': int(total_floor_tiles),
                'total_wall_tiles_count': int(total_wall_tiles),
                'total_adhesive_kg': round(total_adhesive, 1),
                'total_grout_kg': round(total_grout, 1),
                'total_estimated_cost_lkr': round(total_cost, 2),
                'total_rooms': len(rooms),
                'total_floor_area_sqm': building_info.get('total_floor_area_sqm', 0)
            }
            
            logger.info(f"BOQ generated for {len(rooms)} rooms")
            return boq
            
        except Exception as e:
            logger.error(f"BOQ generation error: {str(e)}")
            return {'error': str(e)}
    
    def calculate_room_boq(self, room: Dict[str, Any]) -> Dict[str, Any]:
        """Calculate BOQ for a single room"""
        dims = room['dimensions']
        room_type = room.get('type', 'unknown')
        
        # Calculate paintable areas
        wall_area, ceiling_area = self.calculate_paintable_areas(room)
        
        # Paint calculation
        paint_req = self.calculate_paint_requirement(wall_area + ceiling_area, room_type)
        
        # Putty calculation
        putty_req = self.calculate_putty_requirement(wall_area + ceiling_area)
        
        # Floor tiles calculation
        floor_req = self.calculate_floor_tiles(dims['area_sqm'], room_type)
        
        # Wall tiles (for bathrooms/kitchens)
        wall_tiles_req = {}
        if room_type in ['bathroom', 'toilet']:
            wall_tiles_req = self.calculate_bathroom_wall_tiles(room)
        elif room_type == 'kitchen':
            wall_tiles_req = self.calculate_kitchen_wall_tiles(room)
        
        # Cost estimation
        room_cost = self.estimate_room_cost(paint_req, putty_req, floor_req, wall_tiles_req)
        
        room_boq = {
            'room_id': room['id'],
            'room_name': room['name'],
            'room_type': room_type,
            'dimensions': dims,
            'areas': {
                'wall_area_sqm': round(wall_area, 2),
                'ceiling_area_sqm': round(ceiling_area, 2),
                'floor_area_sqm': dims['area_sqm'],
                'total_paintable_sqm': round(wall_area + ceiling_area, 2)
            },
            'paint': paint_req,
            'putty': putty_req,
            'flooring': floor_req,
            'total_cost_lkr': room_cost
        }
        
        if wall_tiles_req:
            room_boq['wall_tiles'] = wall_tiles_req
        
        return room_boq
    
    def calculate_paintable_areas(self, room: Dict) -> Tuple[float, float]:
        """Calculate wall and ceiling areas for painting"""
        dims = room['dimensions']
        
        # Perimeter
        perimeter = 2 * (dims['length_m'] + dims['width_m'])
        
        # Gross wall area
        gross_wall_area = perimeter * dims['height_m']
        
        # Subtract doors and windows
        door_area = 0
        for door in room.get('doors', []):
            door_area += (door.get('width_mm', 900) * door.get('height_mm', 2100)) / 1_000_000
        
        window_area = 0
        for window in room.get('windows', []):
            window_area += (window.get('width_mm', 1200) * window.get('height_mm', 1200)) / 1_000_000
        
        # If no openings specified, estimate based on room type
        if door_area == 0:
            door_area = 1.89  # Standard door 900mm x 2100mm
        
        net_wall_area = max(0, gross_wall_area - door_area - window_area)
        
        # Ceiling area
        ceiling_area = dims['area_sqm']
        
        return net_wall_area, ceiling_area
    
    def calculate_paint_requirement(self, area_sqm: float, room_type: str) -> Dict[str, float]:
        """Calculate paint requirement in liters"""
        coverage = self.paint_standard.get('coverage_sqm_per_liter', 12.0)
        coats = self.paint_standard.get('coats_required', 2)
        primer_coverage = self.paint_standard.get('primer_coverage_sqm_per_liter', 14.0)
        
        # Paint
        paint_liters = (area_sqm * coats) / coverage
        
        # Add 5% wastage
        paint_with_wastage = paint_liters * 1.05
        
        # Primer
        primer_liters = area_sqm / primer_coverage
        primer_with_wastage = primer_liters * 1.05
        
        return {
            'paint_liters': round(paint_with_wastage, 2),
            'primer_liters': round(primer_with_wastage, 2),
            'coverage_sqm': round(area_sqm, 2),
            'coats': coats,
            'paint_type': 'emulsion'
        }
    
    def calculate_putty_requirement(self, area_sqm: float) -> Dict[str, float]:
        """Calculate putty requirement in kg"""
        coverage = self.putty_standard.get('coverage_sqm_per_kg', 15.0)
        coats = self.putty_standard.get('coats_required', 2)
        
        kg_needed = (area_sqm * coats) / coverage
        kg_with_wastage = kg_needed * 1.08  # 8% wastage
        
        return {
            'kg': round(kg_with_wastage, 2),
            'coverage_sqm': round(area_sqm, 2),
            'coats': coats
        }
    
    def calculate_floor_tiles(self, area_sqm: float, room_type: str, 
                             tile_size: str = '600x600') -> Dict[str, Any]:
        """Calculate floor tile requirement"""
        # Parse tile size
        tile_w, tile_h = [int(d) / 1000 for d in tile_size.split('x')]
        tile_area = tile_w * tile_h
        
        # Number of tiles
        tiles_needed = area_sqm / tile_area
        
        # Wastage factor
        wastage = self.tile_standard.get('wastage_factor', 0.10)
        tiles_with_wastage = tiles_needed * (1 + wastage)
        tiles_final = int(np.ceil(tiles_with_wastage))
        
        # Adhesive and grout
        adhesive_kg = area_sqm * self.tile_standard.get('adhesive_kg_per_sqm', 5.0)
        grout_kg = area_sqm * self.tile_standard.get('grout_kg_per_sqm', 1.5)
        
        return {
            'material': 'tiles',
            'tiles_count': tiles_final,
            'tile_size': tile_size,
            'tile_type': 'ceramic',
            'area_sqm': round(area_sqm, 2),
            'adhesive_kg': round(adhesive_kg, 1),
            'grout_kg': round(grout_kg, 1),
            'wastage_percent': int(wastage * 100)
        }
    
    def calculate_bathroom_wall_tiles(self, room: Dict) -> Dict[str, Any]:
        """Calculate wall tiles for bathroom (typically up to ceiling)"""
        dims = room['dimensions']
        perimeter = 2 * (dims['length_m'] + dims['width_m'])
        
        # Full height tiling
        wall_area = perimeter * dims['height_m']
        
        # Subtract door
        wall_area -= 1.89  # Standard door
        
        return self.calculate_floor_tiles(wall_area, room['type'], tile_size='300x600')
    
    def calculate_kitchen_wall_tiles(self, room: Dict) -> Dict[str, Any]:
        """Calculate wall tiles for kitchen (backsplash area)"""
        dims = room['dimensions']
        
        # Assume backsplash: 2.4m width x 0.6m height behind counter
        backsplash_area = 2.4 * 0.6
        
        return self.calculate_floor_tiles(backsplash_area, room['type'], tile_size='300x600')
    
    def estimate_room_cost(self, paint_req: Dict, putty_req: Dict, 
                          floor_req: Dict, wall_tiles_req: Dict) -> float:
        """Estimate total cost for room in LKR"""
        total_cost = 0
        
        # Paint cost
        paint_cost_per_liter = self.material_costs.get('paint_Emulsion Paint', {}).get('price_lkr', 1600)
        primer_cost_per_liter = self.material_costs.get('paint_Primer', {}).get('price_lkr', 1400)
        
        total_cost += paint_req['paint_liters'] * paint_cost_per_liter
        total_cost += paint_req['primer_liters'] * primer_cost_per_liter
        
        # Putty cost
        putty_cost_per_kg = self.material_costs.get('putty_Wall Putty', {}).get('price_lkr', 180)
        total_cost += putty_req['kg'] * putty_cost_per_kg
        
        # Floor tiles cost (approximate 1200 LKR per sqm)
        if floor_req.get('material') == 'tiles':
            total_cost += floor_req['area_sqm'] * 1200
            
            # Adhesive and grout
            adhesive_cost = self.material_costs.get('adhesive_Tile Adhesive', {}).get('price_lkr', 85)
            grout_cost = self.material_costs.get('grout_Tile Grout', {}).get('price_lkr', 120)
            
            total_cost += floor_req['adhesive_kg'] * adhesive_cost
            total_cost += floor_req['grout_kg'] * grout_cost
        
        # Wall tiles cost
        if wall_tiles_req:
            total_cost += wall_tiles_req.get('area_sqm', 0) * 900  # Wall tiles cheaper
        
        return round(total_cost, 2)
    
    def create_paint_items(self, rooms: List, room_boqs: List) -> List[Dict]:
        """Create itemized paint list"""
        items = []
        for room, boq in zip(rooms, room_boqs):
            items.append({
                'material_type': 'paint',
                'description': f'Emulsion Paint for {room["name"]}',
                'quantity': boq['paint']['paint_liters'],
                'unit': 'liters',
                'room_id': room['id'],
                'room_name': room['name'],
                'coverage_area_sqm': boq['paint']['coverage_sqm']
            })
            items.append({
                'material_type': 'primer',
                'description': f'Primer for {room["name"]}',
                'quantity': boq['paint']['primer_liters'],
                'unit': 'liters',
                'room_id': room['id'],
                'room_name': room['name']
            })
        return items
    
    def create_putty_items(self, rooms: List, room_boqs: List) -> List[Dict]:
        """Create itemized putty list"""
        items = []
        for room, boq in zip(rooms, room_boqs):
            items.append({
                'material_type': 'putty',
                'description': f'Wall Putty for {room["name"]}',
                'quantity': boq['putty']['kg'],
                'unit': 'kg',
                'room_id': room['id'],
                'room_name': room['name'],
                'coverage_area_sqm': boq['putty']['coverage_sqm']
            })
        return items
    
    def create_tile_items(self, rooms: List, room_boqs: List) -> List[Dict]:
        """Create itemized tile list"""
        items = []
        for room, boq in zip(rooms, room_boqs):
            items.append({
                'material_type': 'floor_tiles',
                'description': f'Floor Tiles ({boq["flooring"]["tile_size"]}) for {room["name"]}',
                'quantity': boq['flooring']['tiles_count'],
                'unit': 'pieces',
                'room_id': room['id'],
                'room_name': room['name'],
                'coverage_area_sqm': boq['flooring']['area_sqm']
            })
        return items
    
    def create_adhesive_items(self, rooms: List, room_boqs: List) -> List[Dict]:
        """Create itemized adhesive/grout list"""
        items = []
        for room, boq in zip(rooms, room_boqs):
            items.append({
                'material_type': 'adhesive',
                'description': f'Tile Adhesive for {room["name"]}',
                'quantity': boq['flooring']['adhesive_kg'],
                'unit': 'kg',
                'room_id': room['id'],
                'room_name': room['name']
            })
            items.append({
                'material_type': 'grout',
                'description': f'Tile Grout for {room["name"]}',
                'quantity': boq['flooring']['grout_kg'],
                'unit': 'kg',
                'room_id': room['id'],
                'room_name': room['name']
            })
        return items


# Fix numpy import
import numpy as np
