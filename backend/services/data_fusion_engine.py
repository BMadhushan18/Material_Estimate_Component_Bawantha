"""
Data Fusion Engine
Combines measurements from multiple sources (floor plan, photos, AR, voice)
Uses weighted averaging and conflict resolution
"""
import logging
import numpy as np
from typing import Dict, List, Any, Optional, Tuple
from scipy import stats
from collections import defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DataFusionEngine:
    def __init__(self):
        # Confidence weights for each source
        self.source_weights = {
            'ar_measurement': 0.9,  # Highest accuracy (LiDAR/depth sensors)
            'floor_plan': 0.7,      # High accuracy if professional plan
            'photos': 0.6,          # Medium accuracy (depth estimation)
            'voice_input': 0.5      # Lowest (human memory errors)
        }
        
    def fuse_all_sources(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Main fusion pipeline - combines all data sources
        
        Args:
            data: Dictionary containing all input data sources
            {
                'floor_plan_data': {...},
                'ar_data': {...},
                'voice_data': {...},
                'photo_data': {...}
            }
            
        Returns:
            Fused building data with confidence scores
        """
        try:
            logger.info("Starting multi-modal data fusion...")
            
            # Extract rooms from each source
            all_rooms = self.extract_all_rooms(data)
            
            # Match rooms across sources
            matched_rooms = self.match_rooms_across_sources(all_rooms)
            
            # Fuse measurements for each room
            fused_rooms = []
            for room_group in matched_rooms:
                fused_room = self.fuse_room_measurements(room_group)
                if fused_room:
                    fused_rooms.append(fused_room)
            
            # Calculate overall building metrics
            building_data = self.calculate_building_metrics(fused_rooms, data)
            
            return {
                'success': True,
                'building': building_data,
                'rooms': fused_rooms,
                'fusion_metadata': {
                    'sources_used': self.get_sources_used(data),
                    'total_rooms_detected': len(fused_rooms),
                    'overall_confidence': self.calculate_overall_confidence(fused_rooms)
                }
            }
            
        except Exception as e:
            logger.error(f"Data fusion error: {str(e)}")
            return {'error': str(e), 'success': False}
    
    def extract_all_rooms(self, data: Dict[str, Any]) -> Dict[str, List[Dict]]:
        """Extract room data from all sources"""
        all_rooms = {
            'floor_plan': [],
            'ar_measurement': [],
            'voice_input': [],
            'photos': []
        }
        
        # Floor plan rooms
        if data.get('floor_plan_data', {}).get('success'):
            all_rooms['floor_plan'] = data['floor_plan_data'].get('rooms', [])
        
        # AR rooms
        if data.get('ar_data', {}).get('success'):
            all_rooms['ar_measurement'] = data['ar_data'].get('rooms', [])
        
        # Voice rooms
        if data.get('voice_data', {}).get('success'):
            all_rooms['voice_input'] = data['voice_data'].get('rooms', [])
        
        # Photo rooms
        if data.get('photo_data', {}).get('success'):
            all_rooms['photos'] = data['photo_data'].get('rooms', [])
        
        logger.info(f"Extracted rooms - FP: {len(all_rooms['floor_plan'])}, "
                   f"AR: {len(all_rooms['ar_measurement'])}, "
                   f"Voice: {len(all_rooms['voice_input'])}, "
                   f"Photos: {len(all_rooms['photos'])}")
        
        return all_rooms
    
    def match_rooms_across_sources(self, all_rooms: Dict[str, List[Dict]]) -> List[List[Dict]]:
        """
        Match rooms from different sources
        Groups rooms that likely represent the same physical room
        """
        matched_groups = []
        
        # Start with floor plan as base (if available)
        if all_rooms['floor_plan']:
            for fp_room in all_rooms['floor_plan']:
                group = [{'source': 'floor_plan', 'data': fp_room}]
                
                # Try to match with AR data
                ar_match = self.find_best_match(fp_room, all_rooms['ar_measurement'])
                if ar_match:
                    group.append({'source': 'ar_measurement', 'data': ar_match})
                
                # Try to match with voice data
                voice_match = self.find_best_match(fp_room, all_rooms['voice_input'])
                if voice_match:
                    group.append({'source': 'voice_input', 'data': voice_match})
                
                matched_groups.append(group)
        
        # If no floor plan, use AR as base
        elif all_rooms['ar_measurement']:
            for ar_room in all_rooms['ar_measurement']:
                group = [{'source': 'ar_measurement', 'data': ar_room}]
                
                voice_match = self.find_best_match(ar_room, all_rooms['voice_input'])
                if voice_match:
                    group.append({'source': 'voice_input', 'data': voice_match})
                
                matched_groups.append(group)
        
        # Unmatched voice rooms
        else:
            for voice_room in all_rooms['voice_input']:
                matched_groups.append([{'source': 'voice_input', 'data': voice_room}])
        
        return matched_groups
    
    def find_best_match(self, reference_room: Dict, candidate_rooms: List[Dict]) -> Optional[Dict]:
        """Find best matching room from candidates based on type and dimensions"""
        if not candidate_rooms:
            return None
        
        ref_type = reference_room.get('type', 'unknown')
        ref_dims = reference_room.get('dimensions', {})
        ref_area = ref_dims.get('area_sqm', 0)
        
        best_match = None
        best_score = 0
        
        for candidate in candidate_rooms:
            score = 0
            
            # Type matching (high weight)
            if candidate.get('type') == ref_type and ref_type != 'unknown':
                score += 0.6
            
            # Dimension matching
            cand_area = candidate.get('dimensions', {}).get('area_sqm', 0)
            if ref_area > 0 and cand_area > 0:
                area_diff = abs(ref_area - cand_area) / max(ref_area, cand_area)
                if area_diff < 0.3:  # Within 30%
                    score += 0.4 * (1 - area_diff)
            
            if score > best_score:
                best_score = score
                best_match = candidate
        
        # Only return if confidence is reasonable
        if best_score > 0.4:
            return best_match
        
        return None
    
    def fuse_room_measurements(self, room_group: List[Dict]) -> Optional[Dict]:
        """
        Fuse measurements from multiple sources for a single room
        Uses weighted averaging with outlier detection
        """
        if not room_group:
            return None
        
        # Collect measurements from all sources
        length_measurements = []
        width_measurements = []
        height_measurements = []
        weights = []
        
        room_types = []
        room_names = []
        
        for item in room_group:
            source = item['source']
            room_data = item['data']
            dims = room_data.get('dimensions', {})
            
            weight = self.source_weights.get(source, 0.5)
            
            if dims.get('length_mm'):
                length_measurements.append(dims['length_mm'])
                width_measurements.append(dims.get('width_mm', 0))
                height_measurements.append(dims.get('height_mm', 3000))
                weights.append(weight)
            
            if room_data.get('type'):
                room_types.append(room_data['type'])
            if room_data.get('name'):
                room_names.append(room_data['name'])
        
        if not length_measurements:
            return None
        
        # Remove outliers
        length_clean, width_clean, height_clean, weights_clean = self.remove_outliers(
            length_measurements, width_measurements, height_measurements, weights
        )
        
        # Weighted average fusion
        fused_length = self.weighted_average(length_clean, weights_clean)
        fused_width = self.weighted_average(width_clean, weights_clean)
        fused_height = self.weighted_average(height_clean, weights_clean)
        
        # Determine room type (most common)
        room_type = max(set(room_types), key=room_types.count) if room_types else 'unknown'
        room_name = room_names[0] if room_names else f'{room_type.replace("_", " ").title()}'
        
        # Calculate confidence
        confidence = self.calculate_measurement_confidence(
            length_clean, weights_clean, len(room_group)
        )
        
        # Validate dimensions
        is_valid, validation_msg = self.validate_dimensions(
            fused_length / 1000, fused_width / 1000, fused_height / 1000, room_type
        )
        
        fused_room = {
            'id': f'fused_{room_group[0]["data"].get("id", "room")}',
            'name': room_name,
            'type': room_type,
            'dimensions': {
                'length_mm': round(fused_length, 2),
                'width_mm': round(fused_width, 2),
                'height_mm': round(fused_height, 2),
                'length_m': round(fused_length / 1000, 2),
                'width_m': round(fused_width / 1000, 2),
                'height_m': round(fused_height / 1000, 2),
                'area_sqm': round((fused_length * fused_width) / 1_000_000, 2)
            },
            'fusion_metadata': {
                'sources_used': [item['source'] for item in room_group],
                'confidence': round(confidence, 2),
                'measurements_fused': len(length_clean),
                'is_valid': is_valid,
                'validation_message': validation_msg
            },
            'doors': room_group[0]['data'].get('doors', []),
            'windows': room_group[0]['data'].get('windows', [])
        }
        
        return fused_room
    
    def weighted_average(self, values: List[float], weights: List[float]) -> float:
        """Calculate weighted average"""
        if not values or not weights:
            return 0.0
        
        weighted_sum = sum(v * w for v, w in zip(values, weights))
        weight_sum = sum(weights)
        
        return weighted_sum / weight_sum if weight_sum > 0 else 0.0
    
    def remove_outliers(self, lengths: List[float], widths: List[float], 
                       heights: List[float], weights: List[float]) -> Tuple:
        """Remove outliers using z-score method"""
        if len(lengths) < 3:
            return lengths, widths, heights, weights
        
        # Calculate z-scores for lengths
        lengths_arr = np.array(lengths)
        z_scores = np.abs(stats.zscore(lengths_arr))
        
        # Keep values with z-score < 2 (within 2 standard deviations)
        mask = z_scores < 2
        
        return (
            [l for l, m in zip(lengths, mask) if m],
            [w for w, m in zip(widths, mask) if m],
            [h for h, m in zip(heights, mask) if m],
            [wt for wt, m in zip(weights, mask) if m]
        )
    
    def calculate_measurement_confidence(self, measurements: List[float], 
                                        weights: List[float], num_sources: int) -> float:
        """Calculate confidence based on variance and number of sources"""
        if not measurements:
            return 0.0
        
        # Base confidence from average weight
        avg_weight = sum(weights) / len(weights) if weights else 0.5
        
        # Bonus for multiple sources
        source_bonus = min(num_sources * 0.1, 0.3)
        
        # Penalty for high variance
        if len(measurements) > 1:
            variance = np.var(measurements)
            mean = np.mean(measurements)
            cv = (np.sqrt(variance) / mean) if mean > 0 else 1.0  # Coefficient of variation
            variance_penalty = min(cv * 0.2, 0.3)
        else:
            variance_penalty = 0.1
        
        confidence = avg_weight + source_bonus - variance_penalty
        return max(0.0, min(1.0, confidence))
    
    def validate_dimensions(self, length_m: float, width_m: float, 
                          height_m: float, room_type: str) -> Tuple[bool, str]:
        """Validate dimensions against Sri Lankan building standards"""
        # Minimum standards (based on UDA guidelines)
        standards = {
            'master_bedroom': {'min_area': 9.0, 'min_length': 2.7, 'min_height': 2.75},
            'bedroom': {'min_area': 7.5, 'min_length': 2.4, 'min_height': 2.75},
            'living_room': {'min_area': 12.0, 'min_length': 3.0, 'min_height': 2.75},
            'kitchen': {'min_area': 5.5, 'min_length': 2.1, 'min_height': 2.75},
            'bathroom': {'min_area': 3.0, 'min_length': 1.5, 'min_height': 2.4},
            'toilet': {'min_area': 1.5, 'min_length': 1.2, 'min_height': 2.4}
        }
        
        area = length_m * width_m
        
        # Get standard for room type
        std = standards.get(room_type, {'min_area': 2.0, 'min_length': 1.5, 'min_height': 2.4})
        
        # Check area
        if area < std['min_area']:
            return False, f"Area {area:.1f}m² below minimum {std['min_area']}m² for {room_type}"
        
        # Check minimum dimension
        if min(length_m, width_m) < std['min_length']:
            return False, f"Dimension below minimum {std['min_length']}m for {room_type}"
        
        # Check height
        if height_m < std['min_height']:
            return False, f"Height {height_m:.1f}m below minimum {std['min_height']}m"
        
        # Check realistic maximums
        if area > 100:
            return False, f"Area {area:.1f}m² unusually large"
        
        if height_m > 5.0:
            return False, f"Height {height_m:.1f}m unusually high"
        
        return True, "Valid"
    
    def calculate_building_metrics(self, rooms: List[Dict], data: Dict) -> Dict[str, Any]:
        """Calculate overall building metrics"""
        total_area = sum(r['dimensions']['area_sqm'] for r in rooms)
        
        # Extract building info from voice data if available
        building_info = data.get('voice_data', {}).get('building_info', {})
        
        return {
            'id': 'building_1',
            'name': data.get('building_name', 'My Building'),
            'owner_name': data.get('owner_name'),
            'total_floor_area_sqm': round(total_area, 2),
            'number_of_floors': building_info.get('floors', 1),
            'total_rooms': len(rooms)
        }
    
    def get_sources_used(self, data: Dict) -> List[str]:
        """Get list of data sources that were successfully used"""
        sources = []
        if data.get('floor_plan_data', {}).get('success'):
            sources.append('floor_plan')
        if data.get('ar_data', {}).get('success'):
            sources.append('ar_measurement')
        if data.get('voice_data', {}).get('success'):
            sources.append('voice_input')
        if data.get('photo_data', {}).get('success'):
            sources.append('photos')
        return sources
    
    def calculate_overall_confidence(self, rooms: List[Dict]) -> float:
        """Calculate overall confidence for the entire building"""
        if not rooms:
            return 0.0
        
        confidences = [r['fusion_metadata']['confidence'] for r in rooms]
        return round(sum(confidences) / len(confidences), 2)
