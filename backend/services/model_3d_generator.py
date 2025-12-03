"""
3D Model Generator
Creates 3D building models from fused room data
Exports to glTF format for mobile viewing
"""
import trimesh
import numpy as np
from typing import Dict, List, Any, Tuple
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Model3DGenerator:
    def __init__(self, output_dir='backend/output'):
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
    
    def create_gltf(self, building_data: Dict[str, Any], building_id: str = 'building_1') -> str:
        """
        Create 3D glTF model from building data
        
        Args:
            building_data: Fused building data with rooms
            building_id: Unique identifier for the building
            
        Returns:
            Path to generated glTF file
        """
        try:
            rooms = building_data.get('rooms', [])
            if not rooms:
                raise ValueError("No rooms data provided")
            
            logger.info(f"Generating 3D model for {len(rooms)} rooms")
            
            # Create meshes for all rooms
            room_meshes = []
            for room in rooms:
                mesh = self.create_room_mesh(room)
                if mesh:
                    room_meshes.append(mesh)
            
            # Combine all room meshes
            if room_meshes:
                combined_mesh = trimesh.util.concatenate(room_meshes)
            else:
                raise ValueError("Failed to create any room meshes")
            
            # Create scene
            scene = trimesh.Scene(combined_mesh)
            
            # Export to glTF
            output_path = os.path.join(self.output_dir, f'{building_id}_model.glb')
            scene.export(output_path, file_type='glb')
            
            logger.info(f"3D model exported to: {output_path}")
            return output_path
            
        except Exception as e:
            logger.error(f"3D model generation error: {str(e)}")
            raise
    
    def create_room_mesh(self, room: Dict) -> trimesh.Trimesh:
        """
        Create 3D mesh for a single room (box with walls)
        
        Args:
            room: Room data dictionary
            
        Returns:
            Trimesh object
        """
        try:
            dims = room['dimensions']
            length = dims['length_m']
            width = dims['width_m']
            height = dims['height_m']
            
            # Create room as extruded box
            vertices, faces = self.create_box_mesh(length, width, height)
            
            # Create mesh
            mesh = trimesh.Trimesh(vertices=vertices, faces=faces)
            
            # Assign material based on room type
            mesh.visual = self.get_room_material(room.get('type', 'unknown'))
            
            return mesh
            
        except Exception as e:
            logger.error(f"Room mesh creation error for {room.get('name')}: {str(e)}")
            return None
    
    def create_box_mesh(self, length: float, width: float, height: float) -> Tuple[np.ndarray, np.ndarray]:
        """
        Create vertices and faces for a box mesh
        
        Returns:
            Tuple of (vertices, faces)
        """
        # Define 8 vertices of the box
        vertices = np.array([
            [0, 0, 0],          # 0: Bottom-front-left
            [length, 0, 0],     # 1: Bottom-front-right
            [length, 0, width], # 2: Bottom-back-right
            [0, 0, width],      # 3: Bottom-back-left
            [0, height, 0],     # 4: Top-front-left
            [length, height, 0],     # 5: Top-front-right
            [length, height, width], # 6: Top-back-right
            [0, height, width]       # 7: Top-back-left
        ])
        
        # Define faces (triangles)
        faces = np.array([
            # Bottom face
            [0, 1, 2], [0, 2, 3],
            # Top face
            [4, 6, 5], [4, 7, 6],
            # Front face
            [0, 5, 1], [0, 4, 5],
            # Back face
            [2, 7, 3], [2, 6, 7],
            # Left face
            [0, 7, 4], [0, 3, 7],
            # Right face
            [1, 6, 2], [1, 5, 6]
        ])
        
        return vertices, faces
    
    def get_room_material(self, room_type: str) -> trimesh.visual.ColorVisuals:
        """Get material/color for room type"""
        colors = {
            'master_bedroom': [200, 220, 240, 255],  # Light blue
            'bedroom': [220, 240, 200, 255],          # Light green
            'living_room': [240, 230, 200, 255],      # Cream
            'kitchen': [255, 240, 220, 255],          # Light orange
            'bathroom': [200, 240, 255, 255],         # Light cyan
            'toilet': [200, 240, 255, 255],
            'balcony': [220, 220, 220, 255],          # Gray
            'unknown': [230, 230, 230, 255]           # Light gray
        }
        
        color = colors.get(room_type, colors['unknown'])
        return trimesh.visual.ColorVisuals(face_colors=color)
    
    def create_floor_plan_2d(self, building_data: Dict[str, Any]) -> str:
        """
        Create 2D floor plan visualization (top-down view)
        """
        # TODO: Implement 2D floor plan generation
        pass
