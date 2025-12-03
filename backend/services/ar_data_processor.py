"""
AR Data Processor
Processes ARCore/ARKit plane detection data
"""
import logging
import numpy as np
from typing import Dict, List, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ARDataProcessor:
    def __init__(self):
        self.confidence_score = 0.9  # AR measurements are highly accurate
        
    def process(self, ar_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process AR measurement data from mobile device
        
        Expected input format:
        {
            'rooms': [
                {
                    'name': 'Living Room',
                    'planes': [...],
                    'measurements': {'length_m': 4.2, 'width_m': 3.5, 'height_m': 2.8}
                }
            ]
        }
        """
        try:
            processed_rooms = []
            
            for idx, room_data in enumerate(ar_data.get('rooms', [])):
                room = self.process_room(room_data, idx)
                if room:
                    processed_rooms.append(room)
            
            return {
                'success': True,
                'rooms': processed_rooms,
                'source': 'ar_measurement',
                'confidence': self.confidence_score,
                'total_rooms': len(processed_rooms)
            }
            
        except Exception as e:
            logger.error(f"AR data processing error: {str(e)}")
            return {'error': str(e), 'success': False}
    
    def process_room(self, room_data: Dict, index: int) -> Optional[Dict]:
        """Process individual room AR data"""
        try:
            measurements = room_data.get('measurements', {})
            
            # Convert to millimeters
            length_m = measurements.get('length_m', 0)
            width_m = measurements.get('width_m', 0)
            height_m = measurements.get('height_m', 0)
            
            if length_m <= 0 or width_m <= 0:
                logger.warning(f"Invalid AR measurements for room {index}")
                return None
            
            # Ensure length is longer dimension
            if width_m > length_m:
                length_m, width_m = width_m, length_m
            
            room = {
                'id': room_data.get('id', f'ar_room_{index + 1}'),
                'name': room_data.get('name', f'Room {index + 1}'),
                'type': room_data.get('type', 'unknown'),
                'dimensions': {
                    'length_mm': round(length_m * 1000, 2),
                    'width_mm': round(width_m * 1000, 2),
                    'height_mm': round(height_m * 1000, 2),
                    'length_m': round(length_m, 2),
                    'width_m': round(width_m, 2),
                    'height_m': round(height_m, 2),
                    'area_sqm': round(length_m * width_m, 2)
                },
                'measurement': {
                    'source': 'ar_measurement',
                    'confidence': self.confidence_score,
                    'device': room_data.get('device', 'unknown')
                }
            }
            
            # Add plane data if available
            if 'planes' in room_data:
                room['planes'] = self.process_planes(room_data['planes'])
            
            # Detect doors and windows from plane gaps
            if 'openings' in room_data:
                room['doors'] = []
                room['windows'] = []
                for opening in room_data['openings']:
                    if opening.get('type') == 'door':
                        room['doors'].append(opening)
                    elif opening.get('type') == 'window':
                        room['windows'].append(opening)
            
            return room
            
        except Exception as e:
            logger.error(f"Room processing error: {str(e)}")
            return None
    
    def process_planes(self, planes: List[Dict]) -> List[Dict]:
        """Process detected planes (walls, floor, ceiling)"""
        processed_planes = []
        
        for plane in planes:
            plane_type = self.classify_plane(plane.get('normal', [0, 1, 0]))
            
            processed_planes.append({
                'type': plane_type,
                'area_sqm': plane.get('area_sqm', 0),
                'boundary_points': plane.get('boundary_points', []),
                'normal': plane.get('normal', [0, 0, 0])
            })
        
        return processed_planes
    
    def classify_plane(self, normal: List[float]) -> str:
        """Classify plane based on normal vector"""
        # Normalize
        norm = np.linalg.norm(normal)
        if norm == 0:
            return 'unknown'
        
        n = np.array(normal) / norm
        
        # Check orientation
        if n[1] > 0.8:  # Normal points up
            return 'floor'
        elif n[1] < -0.8:  # Normal points down
            return 'ceiling'
        elif abs(n[1]) < 0.3:  # Horizontal normal
            return 'wall'
        
        return 'unknown'
    
    def validate_dimensions(self, length_m: float, width_m: float, height_m: float) -> bool:
        """Validate AR measurements against realistic ranges"""
        # Sri Lankan typical room dimensions
        if not (1.0 <= length_m <= 15.0):
            return False
        if not (1.0 <= width_m <= 15.0):
            return False
        if not (2.0 <= height_m <= 5.0):
            return False
        
        return True
