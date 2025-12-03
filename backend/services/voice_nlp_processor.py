"""
Voice NLP Processor
Processes speech transcriptions to extract building information
Uses pattern matching and NLP for entity extraction
"""
import re
import logging
from typing import Dict, List, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VoiceNLPProcessor:
    def __init__(self):
        self.confidence_score = 0.5  # Voice input has lower confidence
        
        # Room type keywords
        self.room_keywords = {
            'master_bedroom': ['master bedroom', 'master bed', 'mbr', 'm.b.r', 'main bedroom'],
            'bedroom': ['bedroom', 'bed room', 'br ', ' br', 'sleeping room'],
            'living_room': ['living room', 'hall', 'drawing room', 'lounge', 'sitting room'],
            'kitchen': ['kitchen', 'pantry', 'cooking area'],
            'bathroom': ['bathroom', 'bath', 'washroom'],
            'toilet': ['toilet', 'wc', 'restroom', 'powder room'],
            'dining_room': ['dining room', 'dining area', 'dining'],
            'balcony': ['balcony', 'terrace', 'verandah']
        }
        
        # Number word to digit mapping
        self.number_words = {
            'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
            'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10
        }
    
    def process(self, text: str) -> Dict[str, Any]:
        """
        Process voice transcription text to extract building information
        
        Args:
            text: Transcribed speech text
            
        Returns:
            Dictionary with extracted rooms and measurements
        """
        try:
            text_lower = text.lower()
            
            # Extract room count
            room_counts = self.extract_room_counts(text_lower)
            
            # Extract room descriptions with dimensions
            rooms = self.extract_room_descriptions(text_lower)
            
            # Extract general building info
            building_info = self.extract_building_info(text_lower)
            
            return {
                'success': True,
                'rooms': rooms,
                'room_counts': room_counts,
                'building_info': building_info,
                'source': 'voice_input',
                'confidence': self.confidence_score,
                'original_text': text
            }
            
        except Exception as e:
            logger.error(f"Voice NLP processing error: {str(e)}")
            return {'error': str(e), 'success': False}
    
    def extract_room_counts(self, text: str) -> Dict[str, int]:
        """
        Extract room counts from text
        Example: "there are 3 bedrooms" -> {'bedroom': 3}
        """
        counts = {}
        
        # Pattern: "X bedrooms", "there are X bedrooms", "has X bedrooms"
        for room_type, keywords in self.room_keywords.items():
            for keyword in keywords:
                # Try digit pattern
                pattern = rf'(\d+)\s+{keyword}s?'
                matches = re.findall(pattern, text)
                if matches:
                    counts[room_type] = int(matches[0])
                    break
                
                # Try word pattern
                for word, num in self.number_words.items():
                    pattern = rf'{word}\s+{keyword}s?'
                    if re.search(pattern, text):
                        counts[room_type] = num
                        break
        
        return counts
    
    def extract_room_descriptions(self, text: str) -> List[Dict]:
        """
        Extract individual room descriptions with measurements
        Example: "the master bedroom is 12 feet by 10 feet"
        """
        rooms = []
        
        # Pattern for room with dimensions
        # "master bedroom is 12 feet by 10 feet"
        # "bedroom which is 3 meters by 4 meters"
        dimension_pattern = r'([\w\s]+(?:bedroom|room|kitchen|bathroom|toilet|hall|balcony))\s+(?:is|which is|measuring|measures|sized)?\s*(\d+(?:\.\d+)?)\s*(feet|foot|ft|meters?|m)\s+(?:by|x|\*)\s+(\d+(?:\.\d+)?)\s*(feet|foot|ft|meters?|m)'
        
        matches = re.finditer(dimension_pattern, text, re.IGNORECASE)
        
        for idx, match in enumerate(matches):
            room_name = match.group(1).strip()
            dim1 = float(match.group(2))
            unit1 = match.group(3)
            dim2 = float(match.group(4))
            unit2 = match.group(5)
            
            # Convert to millimeters
            length_mm = self.convert_to_mm(dim1, unit1)
            width_mm = self.convert_to_mm(dim2, unit2)
            
            # Ensure length is longer
            if width_mm > length_mm:
                length_mm, width_mm = width_mm, length_mm
            
            # Identify room type
            room_type = self.identify_room_type(room_name)
            
            rooms.append({
                'id': f'voice_room_{idx + 1}',
                'name': room_name.title(),
                'type': room_type,
                'dimensions': {
                    'length_mm': length_mm,
                    'width_mm': width_mm,
                    'height_mm': 3000,  # Default height
                    'length_m': round(length_mm / 1000, 2),
                    'width_m': round(width_mm / 1000, 2),
                    'height_m': 3.0,
                    'area_sqm': round((length_mm * width_mm) / 1_000_000, 2)
                },
                'measurement': {
                    'source': 'voice_input',
                    'confidence': self.confidence_score,
                    'original_text': match.group(0)
                }
            })
        
        return rooms
    
    def extract_building_info(self, text: str) -> Dict[str, Any]:
        """Extract general building information"""
        info = {}
        
        # Extract number of floors
        floor_pattern = r'(\d+|one|two|three)\s+(?:floor|storey|story|stories|storeys)'
        match = re.search(floor_pattern, text)
        if match:
            floor_num = match.group(1)
            info['floors'] = self.number_words.get(floor_num, int(floor_num) if floor_num.isdigit() else 1)
        
        # Extract ceiling height if mentioned
        height_pattern = r'(?:ceiling height|height)\s+(?:is|of)?\s*(\d+(?:\.\d+)?)\s*(feet|foot|ft|meters?|m)'
        match = re.search(height_pattern, text)
        if match:
            height_val = float(match.group(1))
            unit = match.group(2)
            info['ceiling_height_mm'] = self.convert_to_mm(height_val, unit)
        
        return info
    
    def identify_room_type(self, room_name: str) -> str:
        """Identify room type from room name"""
        room_name_lower = room_name.lower()
        
        for room_type, keywords in self.room_keywords.items():
            for keyword in keywords:
                if keyword in room_name_lower:
                    return room_type
        
        return 'unknown'
    
    def convert_to_mm(self, value: float, unit: str) -> float:
        """Convert measurement to millimeters"""
        unit_lower = unit.lower()
        
        if unit_lower in ['feet', 'foot', 'ft']:
            return value * 304.8  # 1 foot = 304.8mm
        elif unit_lower in ['meter', 'meters', 'm']:
            return value * 1000
        elif unit_lower in ['cm', 'centimeter', 'centimeters']:
            return value * 10
        
        # Default assume meters
        return value * 1000
