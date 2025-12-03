# Multi-Modal Building Analysis & Material Estimation System

## Overview
This system uses AI and computer vision to analyze building structures through multiple data sources and generate accurate Bills of Quantities (BOQ) for finishing materials.

## Features

### 1. Multi-Modal Data Collection
- **Floor Plan Analysis**: Upload 2D floor plans for automatic room detection using OpenCV
- **AR Measurements**: Use ARCore to measure rooms with your phone camera
- **Voice Input**: Describe your building structure verbally using speech-to-text
- **Photo Analysis**: Upload photos for additional dimensional data

### 2. Data Fusion Engine
- Combines data from all sources using weighted confidence scoring
- AR measurements: 90% confidence
- Floor plans: 70% confidence  
- Photos: 60% confidence
- Voice input: 50% confidence
- Outlier detection using statistical z-scores
- Validates against Sri Lankan construction standards

### 3. BOQ Generation
Automatically calculates material quantities for:
- **Paint**: Coverage rate 12 sqm/liter × 2 coats + 5% wastage
- **Putty**: Coverage rate 15 sqm/kg × 2 coats + 8% wastage
- **Floor Tiles**: 600×600mm ceramic with 10% wastage
- **Wall Tiles**: Full-height bathroom tiling with 10% wastage

### 4. 3D Model Generation
- Creates glTF 3D models from room data
- AR-enabled viewing on supported devices
- Interactive controls (rotate, zoom, pan)

### 5. Cost Estimation
Prices based on Sri Lankan market rates (LKR):
- Paint: 1600 LKR/liter
- Putty: 800 LKR/kg
- Ceramic tiles: 1200 LKR/sqm
- Labor included in material costs

## Architecture

### Backend (Python/Flask)
```
backend/
├── services/
│   ├── floor_plan_processor.py    # OpenCV image processing
│   ├── ar_data_processor.py       # ARCore data validation
│   ├── voice_nlp_processor.py     # NLP dimension extraction
│   ├── data_fusion_engine.py      # Multi-source fusion
│   ├── boq_calculator.py          # Material quantity calculation
│   └── model_3d_generator.py      # Trimesh 3D generation
├── models/
│   └── building_schema.py         # Pydantic data models
└── database/
    └── sl_construction_standards.db
```

### Frontend (Flutter)
```
frontend/lib/
├── screens/
│   ├── input_wizard_screen.dart      # Main orchestrator
│   ├── floor_plan_input_screen.dart  # Image upload
│   ├── ar_measurement_screen.dart    # ARCore integration
│   ├── voice_input_screen.dart       # Speech-to-text
│   ├── data_review_screen.dart       # Fusion review
│   ├── boq_display_screen.dart       # Results & charts
│   └── model_3d_viewer_screen.dart   # 3D visualization
├── models/
│   ├── building_model.dart
│   ├── room_model.dart
│   └── boq_model.dart
└── services/
    └── api_service.dart
```

## API Endpoints

### POST /api/process-floor-plan
Upload floor plan image for room detection
```json
{
  "scale_ratio": 0.01,
  "height_mm": 3000
}
```

### POST /api/process-ar-data
Submit ARCore plane detection data
```json
{
  "planes": [
    {
      "room": "Master Bedroom",
      "type": "floor",
      "width": 3.5,
      "length": 4.2,
      "confidence": 0.9
    }
  ]
}
```

### POST /api/process-voice
Submit voice transcription
```json
{
  "transcription": "There are 3 bedrooms. The master bedroom is 12 feet by 10 feet..."
}
```

### POST /api/fuse-and-generate-boq
Fuse all data sources and generate BOQ
```json
{
  "floor_plan_data": {...},
  "ar_data": [...],
  "voice_transcription": "..."
}
```

## Setup Instructions

### Backend Setup
```bash
cd backend
pip install -r requirements.txt
python database/init_standards_db.py
python flask_app.py
```

### Frontend Setup
```bash
cd frontend
flutter pub get
flutter run
```

### Environment Variables
```env
BACKEND_URL=http://localhost:5000
```

## Usage Workflow

1. **Launch App** → Open "Multi-Modal BOQ" from sidebar menu
2. **Step 1: Floor Plan** → Upload 2D floor plan image, set scale ratio
3. **Step 2: AR Scan** → Scan rooms with phone camera using ARCore
4. **Step 3: Voice Input** → Describe building verbally
5. **Step 4: Review** → Check fused data and confidence scores
6. **Generate BOQ** → View material quantities, costs, and 3D model
7. **Export PDF** → Save or share BOQ report

## Sri Lankan Construction Standards

Based on UDA (Urban Development Authority) guidelines:

### Minimum Room Sizes
- Master Bedroom: 9 sqm
- Bedroom: 7 sqm
- Living Room: 12 sqm
- Kitchen: 4.5 sqm
- Bathroom: 2 sqm

### Standard Heights
- Ceiling Height: 2750mm (minimum)
- Door Height: 2100mm
- Window Height: 1200mm

## Dependencies

### Backend
- Flask 3.0.0
- OpenCV 4.8.1
- Trimesh 4.0.5
- NumPy 1.24.3
- PyTorch 2.1.0
- Whisper (OpenAI)
- spaCy 3.7.2

### Frontend
- Flutter 3.10.1
- arcore_flutter_plugin 0.1.0
- fl_chart 0.70.1
- model_viewer_plus 1.0.3
- speech_to_text 6.6.2
- image_picker 1.1.2

## Known Limitations

1. ARCore only available on supported Android devices
2. Floor plan OCR requires clear, high-resolution images
3. Voice NLP best with structured descriptions
4. 3D models simplified (no detailed features)
5. Cost estimates based on 2024 LKR market rates

## Future Enhancements

- [ ] Photo-based dimension extraction using depth estimation
- [ ] Integration with supplier catalogs for real-time pricing
- [ ] Multi-language support (Sinhala, Tamil)
- [ ] Cloud sync for multi-device access
- [ ] Historical cost tracking and trend analysis
- [ ] Material recommendation engine
- [ ] AR visualization of finished rooms

## License
Proprietary - All rights reserved

## Contact
Madhushan S.M.P.B - Project Owner
