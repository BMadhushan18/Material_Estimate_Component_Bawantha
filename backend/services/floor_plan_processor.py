"""
Floor Plan Processing Service
Analyzes 2D floor plans using OpenCV and extracts room structure
"""
import cv2
import numpy as np
from PIL import Image
import io
import logging
from typing import List, Dict, Any, Tuple, Optional
from shapely.geometry import Polygon, Point as ShapelyPoint
from shapely.ops import unary_union
import pytesseract
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FloorPlanProcessor:
    def __init__(self):
        self.scale_ratio = 0.01  # Default: 1 pixel = 10mm
        self.min_room_area_pixels = 5000  # Minimum area for valid room
        
    def process(self, image_file, scale_ratio: float = None, default_height_mm: float = 3000) -> Dict[str, Any]:
        """
        Main processing pipeline for floor plans
        
        Args:
            image_file: Uploaded image file
            scale_ratio: Pixels to mm conversion (e.g., 0.01 = 1px = 10mm)
            default_height_mm: Default ceiling height if not specified
            
        Returns:
            Dictionary with rooms, dimensions, and metadata
        """
        try:
            # Load image
            image_bytes = image_file.read()
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return {'error': 'Failed to decode image'}
            
            logger.info(f"Processing floor plan image: {img.shape}")
            
            # Preprocess image
            preprocessed = self.preprocess_image(img)
            
            # Try to extract scale from image
            extracted_scale = self.extract_scale(img)
            if extracted_scale and scale_ratio is None:
                scale_ratio = extracted_scale
            elif scale_ratio is None:
                scale_ratio = self.scale_ratio
            
            # Detect walls
            wall_mask, lines = self.detect_walls(preprocessed)
            
            # Segment rooms
            rooms_data = self.segment_rooms(wall_mask, scale_ratio)
            
            # Extract room labels using OCR
            rooms_with_labels = self.extract_room_labels(img, rooms_data)
            
            # Calculate dimensions
            rooms_with_dimensions = self.calculate_dimensions(
                rooms_with_labels, 
                scale_ratio, 
                default_height_mm
            )
            
            return {
                'success': True,
                'rooms': rooms_with_dimensions,
                'scale_ratio': scale_ratio,
                'total_rooms': len(rooms_with_dimensions),
                'source': 'floor_plan',
                'confidence': 0.7,
                'image_dimensions': {'width': img.shape[1], 'height': img.shape[0]}
            }
            
        except Exception as e:
            logger.error(f"Floor plan processing error: {str(e)}")
            return {'error': str(e), 'success': False}
    
    def preprocess_image(self, img: np.ndarray) -> np.ndarray:
        """Preprocess image for better wall detection"""
        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            gray, 255, 
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY_INV, 
            11, 2
        )
        
        # Denoise
        denoised = cv2.fastNlMeansDenoising(thresh, None, 10, 7, 21)
        
        return denoised
    
    def extract_scale(self, img: np.ndarray) -> Optional[float]:
        """
        Extract scale information from floor plan using OCR
        Looks for patterns like "1:100", "1cm=1m", etc.
        """
        try:
            # Extract text from bottom portion of image (where scale usually is)
            height = img.shape[0]
            scale_region = img[int(height * 0.8):, :]
            
            # OCR
            text = pytesseract.image_to_string(scale_region)
            
            # Pattern matching
            # Pattern 1: "1:100" format
            ratio_pattern = r'1\s*:\s*(\d+)'
            match = re.search(ratio_pattern, text)
            if match:
                ratio = int(match.group(1))
                # Assuming drawing is in mm, 1:100 means 1mm drawing = 100mm real
                pixels_per_mm = ratio / 100  # Approximate
                logger.info(f"Extracted scale ratio 1:{ratio}")
                return pixels_per_mm
            
            # Pattern 2: "1cm = 1m" format
            cm_pattern = r'(\d+)\s*cm\s*=\s*(\d+)\s*m'
            match = re.search(cm_pattern, text, re.IGNORECASE)
            if match:
                cm_val = float(match.group(1))
                m_val = float(match.group(2))
                # Convert to pixels per mm
                logger.info(f"Extracted scale: {cm_val}cm = {m_val}m")
                return (m_val * 1000) / (cm_val * 10)  # Approximate
            
        except Exception as e:
            logger.warning(f"Scale extraction failed: {e}")
        
        return None
    
    def detect_walls(self, preprocessed: np.ndarray) -> Tuple[np.ndarray, List]:
        """
        Detect walls using Hough Line Transform
        """
        # Edge detection
        edges = cv2.Canny(preprocessed, 50, 150, apertureSize=3)
        
        # Hough Line Transform
        lines = cv2.HoughLinesP(
            edges, 
            rho=1, 
            theta=np.pi/180, 
            threshold=100,
            minLineLength=50,
            maxLineGap=10
        )
        
        # Create wall mask
        wall_mask = np.zeros_like(preprocessed)
        
        if lines is not None:
            for line in lines:
                x1, y1, x2, y2 = line[0]
                # Draw thick lines to represent walls
                cv2.line(wall_mask, (x1, y1), (x2, y2), 255, 3)
        
        # Dilate to connect nearby walls
        kernel = np.ones((3, 3), np.uint8)
        wall_mask = cv2.dilate(wall_mask, kernel, iterations=1)
        
        return wall_mask, lines if lines is not None else []
    
    def segment_rooms(self, wall_mask: np.ndarray, scale_ratio: float) -> List[Dict]:
        """
        Segment individual rooms from wall mask using contour detection
        """
        # Invert wall mask to get room regions
        room_regions = cv2.bitwise_not(wall_mask)
        
        # Find contours
        contours, _ = cv2.findContours(
            room_regions, 
            cv2.RETR_EXTERNAL, 
            cv2.CHAIN_APPROX_SIMPLE
        )
        
        rooms = []
        for idx, contour in enumerate(contours):
            area = cv2.contourArea(contour)
            
            # Filter small contours
            if area < self.min_room_area_pixels:
                continue
            
            # Get bounding rectangle
            x, y, w, h = cv2.boundingRect(contour)
            
            # Convert contour to polygon points
            polygon_points = []
            epsilon = 0.01 * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, epsilon, True)
            
            for point in approx:
                polygon_points.append({
                    'x': float(point[0][0]),
                    'y': float(point[0][1])
                })
            
            # Calculate approximate area in square meters
            area_sqm = (area * (scale_ratio ** 2)) / 1_000_000
            
            rooms.append({
                'id': f'room_{idx + 1}',
                'contour_points': polygon_points,
                'bounding_box': {'x': int(x), 'y': int(y), 'width': int(w), 'height': int(h)},
                'area_pixels': float(area),
                'area_sqm_approx': round(area_sqm, 2)
            })
        
        logger.info(f"Detected {len(rooms)} rooms")
        return rooms
    
    def extract_room_labels(self, original_img: np.ndarray, rooms_data: List[Dict]) -> List[Dict]:
        """
        Extract room labels using OCR on each room region
        """
        room_keywords = {
            'master_bedroom': ['master', 'mbr', 'master bed', 'm.bed'],
            'bedroom': ['bedroom', 'bed room', 'br', 'bed'],
            'living_room': ['living', 'hall', 'drawing', 'lounge'],
            'kitchen': ['kitchen', 'pantry'],
            'bathroom': ['bathroom', 'bath', 'wc'],
            'toilet': ['toilet', 'wc', 'restroom'],
            'dining_room': ['dining', 'dining room'],
            'balcony': ['balcony', 'terrace']
        }
        
        for room in rooms_data:
            try:
                bbox = room['bounding_box']
                x, y, w, h = bbox['x'], bbox['y'], bbox['width'], bbox['height']
                
                # Extract region
                room_img = original_img[y:y+h, x:x+w]
                
                # OCR
                text = pytesseract.image_to_string(room_img).lower()
                
                # Match keywords
                room_type = 'unknown'
                for rtype, keywords in room_keywords.items():
                    for keyword in keywords:
                        if keyword in text:
                            room_type = rtype
                            break
                    if room_type != 'unknown':
                        break
                
                room['type'] = room_type
                room['detected_text'] = text.strip()
                
            except Exception as e:
                logger.warning(f"Room label extraction failed: {e}")
                room['type'] = 'unknown'
                room['detected_text'] = ''
        
        return rooms_data
    
    def calculate_dimensions(self, rooms_data: List[Dict], scale_ratio: float, 
                           default_height_mm: float) -> List[Dict]:
        """
        Calculate room dimensions in millimeters
        """
        for room in rooms_data:
            bbox = room['bounding_box']
            
            # Convert pixels to millimeters
            length_mm = bbox['width'] * scale_ratio
            width_mm = bbox['height'] * scale_ratio
            
            # Ensure length is the longer dimension
            if width_mm > length_mm:
                length_mm, width_mm = width_mm, length_mm
            
            room['dimensions'] = {
                'length_mm': round(length_mm, 2),
                'width_mm': round(width_mm, 2),
                'height_mm': default_height_mm,
                'length_m': round(length_mm / 1000, 2),
                'width_m': round(width_mm / 1000, 2),
                'height_m': round(default_height_mm / 1000, 2),
                'area_sqm': round((length_mm * width_mm) / 1_000_000, 2)
            }
            
            # Add measurement metadata
            room['measurement'] = {
                'source': 'floor_plan',
                'confidence': 0.7,
                'scale_ratio_used': scale_ratio
            }
        
        return rooms_data
