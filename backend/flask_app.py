from flask import Flask, request, jsonify
import sqlite3
from werkzeug.security import generate_password_hash, check_password_hash
import os
import logging
from flask import make_response
from flask import send_file

# Note: heavy libraries (Pillow, numpy, OpenCV, shapely, trimesh, ezdxf)
# are imported lazily inside the conversion endpoint so the server can
# start without them. For DXF handling we will attempt to import ezdxf
# when a DXF file is uploaded.
_ezdxf_enabled = False

DB_PATH = os.path.join(os.path.dirname(__file__), 'users_flask.db')

# Optional Firebase admin integration. To enable, place a service account
# JSON at `backend/firebase_service_account.json` and install `firebase-admin`.
FIREBASE_SERVICE_ACCOUNT = os.path.join(os.path.dirname(__file__), 'firebase_service_account.json')
firebase_enabled = False
firebase_client = None
try:
    if os.path.exists(FIREBASE_SERVICE_ACCOUNT):
        import firebase_admin
        from firebase_admin import credentials, firestore

        cred = credentials.Certificate(FIREBASE_SERVICE_ACCOUNT)
        firebase_admin.initialize_app(cred)
        firebase_client = firestore.client()
        firebase_enabled = True
        logging.info('Firebase admin initialized, Firestore enabled')
    else:
        logging.info('Firebase service account not found; Firestore disabled')
except Exception as e:
    logging.exception('Failed to initialize Firebase admin; Firestore disabled: %s', e)

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    c.execute('''
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT,
        password_hash TEXT NOT NULL
    )
    ''')
    conn.commit()
    conn.close()

app = Flask(__name__)
init_db()


@app.after_request
def add_cors_headers(response):
    # Allow browser-based frontends to call the API (development only).
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,PUT,DELETE,OPTIONS'
    return response


@app.before_request
def handle_options():
    # Short-circuit OPTIONS preflight with 200
    if request.method == 'OPTIONS':
        resp = make_response('', 200)
        resp.headers['Access-Control-Allow-Origin'] = '*'
        resp.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
        resp.headers['Access-Control-Allow-Methods'] = 'GET,POST,PUT,DELETE,OPTIONS'
        return resp

@app.route('/signup', methods=['POST'])
def signup():
    data = request.get_json() or {}
    required = ['first_name','last_name','email','password']
    for r in required:
        if not data.get(r):
            return jsonify({'message': f'{r} is required'}), 400
    email = data['email'].lower()
    conn = get_db()
    c = conn.cursor()
    c.execute('SELECT id FROM users WHERE email = ?', (email,))
    if c.fetchone():
        conn.close()
        return jsonify({'message': 'Email already registered'}), 400
    pw_hash = generate_password_hash(data['password'])
    c.execute('INSERT INTO users (first_name,last_name,email,phone,password_hash) VALUES (?,?,?,?,?)',
              (data['first_name'], data['last_name'], email, data.get('phone',''), pw_hash))
    conn.commit()
    uid = c.lastrowid
    conn.close()
    # If Firestore is enabled, also save the user document there
    if firebase_enabled and firebase_client is not None:
        try:
            doc_ref = firebase_client.collection('users').document(str(uid))
            doc_ref.set({
                'first_name': data['first_name'],
                'last_name': data['last_name'],
                'email': email,
                'phone': data.get('phone', ''),
                'created_at': sqlite3.datetime.datetime.now().isoformat() if hasattr(sqlite3, 'datetime') else None,
            })
        except Exception as e:
            # Log but don't fail the signup if Firestore write fails
            logging.exception('Failed to write user to Firestore: %s', e)

    return jsonify({'message': 'User created', 'user_id': uid}), 200

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    if not data.get('email') or not data.get('password'):
        logging.info('Login attempt with missing fields from %s', request.remote_addr)
        return jsonify({'message': 'email and password required'}), 400

    email = data['email'].lower()
    logging.info('Login attempt for email=%s from %s', email, request.remote_addr)

    conn = get_db()
    c = conn.cursor()
    c.execute('SELECT id, password_hash FROM users WHERE email = ?', (email,))
    row = c.fetchone()
    conn.close()

    if not row:
        logging.info('Login failed: user not found for email=%s', email)
        return jsonify({'message': 'Invalid credentials'}), 401

    pw_hash = row['password_hash']
    try:
        ok = check_password_hash(pw_hash, data['password'])
    except Exception as e:
        logging.exception('Password check error for email=%s: %s', email, e)
        ok = False

    if not ok:
        logging.info('Login failed: invalid password for email=%s (uid=%s)', email, row['id'])
        return jsonify({'message': 'Invalid credentials'}), 401

    logging.info('Login succeeded for email=%s (uid=%s)', email, row['id'])
    # For simplicity return a dummy token (in production use real JWT)
    return jsonify({'token': f'user-{row[0]}-token'}), 200


@app.route('/plan2dto3d', methods=['POST'])
def plan2dto3d():
    """Convert an uploaded 2D plan image to a simple extruded 3D model (GLB).

    This endpoint accepts multipart form with field `plan` (PNG/JPG/SVG). Optional
    form field `height_mm` sets extrusion height in millimeters (default 3000).

    Note: This is a simple, open-source pipeline suitable for clean scanned
    floorplans. It finds the largest contour, treats it as the building outline,
    extrudes it and returns a GLB file.
    """
    # Attempt to import optional conversion libraries (do not fail startup if absent)
    try:
        import io
        import tempfile
        import numpy as np
        from PIL import Image
        import cv2
        from shapely.geometry import Polygon
        from shapely.ops import unary_union
        import trimesh
    except Exception as _e:
        # We'll return an informative error if the user tries to convert
        # and the server does not have the optional libraries installed.
        logging.debug('Optional conversion libraries not available: %s', _e)

    # Accept either image uploads (field 'plan') or generic file (field 'file')
    file_key = 'file' if 'file' in request.files else 'plan' if 'plan' in request.files else None
    if file_key is None:
        return jsonify({'message': 'No file uploaded (use form field `plan` or `file`)'}), 400

    f = request.files[file_key]
    filename = (f.filename or '').lower()

    # If DXF provided, attempt to import ezdxf and parse
    if filename.endswith('.dxf'):
        try:
            import ezdxf
            ezdxf_available = True
        except Exception:
            ezdxf_available = False
        if not ezdxf_available:
            return jsonify({'message': 'DXF support not available on server (missing ezdxf)'}), 500
        # Save uploaded DXF to a temp file and read with ezdxf
        tmpf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
        try:
            f.save(tmpf.name)
            doc = ezdxf.readfile(tmpf.name)
            msp = doc.modelspace()
            polygons = []
            # collect closed lwpolyline / polyline entities
            for e in msp:
                if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
                    try:
                        pts = [(float(x), float(y)) for x, y, *rest in e.get_points()]
                    except Exception:
                        # POLYLINE older versions
                        try:
                            pts = [(float(v[0]), float(v[1])) for v in e.vertices()]
                        except Exception:
                            pts = []
                    if len(pts) >= 3:
                        poly = Polygon(pts)
                        if not poly.is_valid:
                            poly = poly.buffer(0)
                        if poly.is_valid and not poly.is_empty:
                            polygons.append(poly)
            if not polygons:
                return jsonify({'message': 'No closed polylines found in DXF'}), 400
            merged = unary_union(polygons)
        finally:
            try:
                tmpf.close()
                os.unlink(tmpf.name)
            except Exception:
                pass
    else:
        # Treat as raster image
        try:
            img = Image.open(f.stream).convert('L')
        except Exception:
            return jsonify({'message': 'Failed to open image'}), 400

        # Read image as numpy array
        arr = np.array(img)
    # Simple threshold to binary
    try:
        _, bw = cv2.threshold(arr, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    except Exception:
        bw = (arr > 127).astype('uint8') * 255

    # Invert if necessary so walls/lines are white on black background
    white_ratio = (bw > 0).mean()
    if white_ratio < 0.5:
        bw = 255 - bw

    # Find contours
        # Find contours with hierarchy to detect holes
        contours, hierarchy = cv2.findContours(bw, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return jsonify({'message': 'No contours found in image'}), 400

        hierarchy = hierarchy[0] if hierarchy is not None and len(hierarchy) > 0 else None
        # Build polygons with holes: parent contours are exteriors, children are holes
        polygons = []
        used = set()
        for idx, c in enumerate(contours):
            if idx in used:
                continue
            # Only consider top-level contours (no parent)
            parent = hierarchy[idx][3] if hierarchy is not None else -1
            if parent != -1:
                continue
            exterior = c.squeeze()
            if exterior.ndim != 2 or exterior.shape[0] < 3:
                continue
            exterior_coords = [(float(p[0]), float(p[1])) for p in exterior]
            # collect holes (children)
            holes = []
            child_idx = hierarchy[idx][2] if hierarchy is not None else -1
            while child_idx != -1 and hierarchy is not None:
                ch = contours[child_idx].squeeze()
                if ch.ndim == 2 and ch.shape[0] >= 3:
                    holes.append([(float(p[0]), float(p[1])) for p in ch])
                used.add(child_idx)
                child_idx = hierarchy[child_idx][0]

            poly = Polygon(exterior_coords, holes=holes if holes else None)
            if not poly.is_valid:
                poly = poly.buffer(0)
            if poly.is_valid and not poly.is_empty:
                polygons.append(poly)

        if not polygons:
            return jsonify({'message': 'No valid polygons extracted from image'}), 400

        merged = unary_union(polygons)
        if merged.geom_type == 'MultiPolygon':
            # keep all polygons, but for 3D we can merge into a single MultiPolygon
            # leave as MultiPolygon for trimesh extrusion which supports holes per polygon
            pass

    # Read extrusion height (mm) and scale parameters from form
    try:
        height_mm = float(request.form.get('height_mm', 3000))
    except Exception:
        height_mm = 3000.0
    height_m = height_mm / 1000.0

    # scale: for raster images user can pass `scale_m_per_px`; for DXF user can pass `scale_m_per_unit` (default 0.001 m/unit)
    try:
        scale_m_per_px = float(request.form.get('scale_m_per_px', 0.01))
    except Exception:
        scale_m_per_px = 0.01

    # Convert merged geometry coordinates using scale
    def scale_geom(g):
        if g.geom_type == 'Polygon':
            exterior = [(x * scale_m_per_px, y * scale_m_per_px) for x, y in g.exterior.coords]
            holes = []
            for h in g.interiors:
                holes.append([(x * scale_m_per_px, y * scale_m_per_px) for x, y in h.coords])
            return Polygon(exterior, holes=holes if holes else None)
        elif g.geom_type == 'MultiPolygon':
            parts = [scale_geom(p) for p in g]
            return unary_union(parts)
        else:
            return g

    scaled_geom = scale_geom(merged)

    # Create trimesh extrusion. If the geometry is MultiPolygon, extrude each polygon and combine meshes.
    try:
        if scaled_geom.geom_type == 'Polygon':
            mesh = trimesh.creation.extrude_polygon(scaled_geom, height_m)
        elif scaled_geom.geom_type == 'MultiPolygon':
            meshes = []
            for p in scaled_geom:
                try:
                    m = trimesh.creation.extrude_polygon(p, height_m)
                    meshes.append(m)
                except Exception:
                    continue
            if not meshes:
                return jsonify({'message': 'Failed to extrude polygons'}), 500
            mesh = trimesh.util.concatenate(meshes)
        else:
            return jsonify({'message': 'Unsupported geometry type for extrusion'}), 400
    except Exception as e:
        logging.exception('Extrusion failed: %s', e)
        return jsonify({'message': 'Failed to extrude geometry'}), 500

    # Export to GLB in-memory
    tmp = io.BytesIO()
    try:
        mesh.export(tmp, file_type='glb')
    except Exception:
        try:
            # fallback to gltf
            tmp = io.BytesIO(mesh.export(file_type='gltf'))
        except Exception as e:
            logging.exception('Export failed: %s', e)
            return jsonify({'message': 'Failed to export mesh'}), 500

    tmp.seek(0)
    # Send as attachment
    return send_file(tmp, mimetype='model/gltf-binary', as_attachment=True, download_name='plan_model.glb')

@app.route('/api/process-floor-plan', methods=['POST'])
def api_process_floor_plan():
    """Process floor plan image and extract room structure"""
    try:
        from services.floor_plan_processor import FloorPlanProcessor
        
        if 'plan' not in request.files:
            return jsonify({'error': 'No plan file uploaded'}), 400
        
        file = request.files['plan']
        scale_ratio = request.form.get('scale_ratio', type=float)
        height_mm = request.form.get('height_mm', 3000.0, type=float)
        
        processor = FloorPlanProcessor()
        result = processor.process(file, scale_ratio, height_mm)
        
        return jsonify(result)
    except Exception as e:
        logging.exception('Floor plan processing error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/process-ar-data', methods=['POST'])
def api_process_ar_data():
    """Process AR measurement data from mobile device"""
    try:
        from services.ar_data_processor import ARDataProcessor
        
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No AR data provided'}), 400
        
        processor = ARDataProcessor()
        result = processor.process(data)
        
        return jsonify(result)
    except Exception as e:
        logging.exception('AR data processing error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/process-voice', methods=['POST'])
def api_process_voice():
    """Process voice transcription to extract building information"""
    try:
        from services.voice_nlp_processor import VoiceNLPProcessor
        
        data = request.get_json()
        if not data or 'text' not in data:
            return jsonify({'error': 'No transcription text provided'}), 400
        
        text = data['text']
        
        processor = VoiceNLPProcessor()
        result = processor.process(text)
        
        return jsonify(result)
    except Exception as e:
        logging.exception('Voice processing error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/fuse-and-generate-boq', methods=['POST'])
def api_fuse_and_generate_boq():
    """Fuse all data sources and generate complete BOQ"""
    try:
        from services.data_fusion_engine import DataFusionEngine
        from services.model_3d_generator import Model3DGenerator
        from services.boq_calculator import BOQCalculator
        
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Fuse all data sources
        fusion_engine = DataFusionEngine()
        fusion_result = fusion_engine.fuse_all_sources(data)
        
        if not fusion_result.get('success'):
            return jsonify(fusion_result), 400
        
        building_data = {
            'rooms': fusion_result['rooms'],
            'building': fusion_result['building']
        }
        
        # Generate 3D model
        model_generator = Model3DGenerator()
        building_id = data.get('building_id', 'building_1')
        try:
            model_path = model_generator.create_gltf(building_data, building_id)
            model_url = f'/output/{building_id}_model.glb'
        except Exception as e:
            logging.warning(f'3D model generation failed: {e}')
            model_url = None
        
        # Calculate BOQ
        boq_calculator = BOQCalculator()
        boq = boq_calculator.generate_complete_boq(building_data)
        
        return jsonify({
            'success': True,
            'building': fusion_result['building'],
            'rooms': fusion_result['rooms'],
            'fusion_metadata': fusion_result['fusion_metadata'],
            'model_url': model_url,
            'boq': boq
        })
        
    except Exception as e:
        logging.exception('BOQ generation error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/calibrate-stereo', methods=['POST'])
def calibrate_stereo():
    """Calibrate stereo cameras using live URLs"""
    try:
        import cv2
        import numpy as np
        import os

        left_url = 'http://10.15.173.155:4747/video'
        right_url = 'http://10.15.173.254:4747/video'

        # Capture multiple frames for calibration
        objpoints = []
        imgpointsR = []
        imgpointsL = []

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
        objp = np.zeros((7*6, 3), np.float32)
        objp[:, :2] = np.mgrid[0:7, 0:6].T.reshape(-1, 2)

        capL = cv2.VideoCapture(left_url)
        capR = cv2.VideoCapture(right_url)

        if not capL.isOpened() or not capR.isOpened():
            return jsonify({'error': 'Cannot open camera streams'}), 500

        try:
            for i in range(10):  # Capture 10 frames
                retL, frameL = capL.read()
                retR, frameR = capR.read()

                if not retL or not retR:
                    continue

                grayL = cv2.cvtColor(frameL, cv2.COLOR_BGR2GRAY)
                grayR = cv2.cvtColor(frameR, cv2.COLOR_BGR2GRAY)

                retL_corners, cornersL = cv2.findChessboardCorners(grayL, (7, 6), None)
                retR_corners, cornersR = cv2.findChessboardCorners(grayR, (7, 6), None)

                if retL_corners and retR_corners:
                    objpoints.append(objp)
                    cv2.cornerSubPix(grayL, cornersL, (11, 11), (-1, -1), criteria)
                    cv2.cornerSubPix(grayR, cornersR, (11, 11), (-1, -1), criteria)
                    imgpointsL.append(cornersL)
                    imgpointsR.append(cornersR)

            if len(objpoints) < 5:
                return jsonify({'error': 'Not enough valid chessboard images captured'}), 400

            # Calibrate
            retL, mtxL, distL, rvecsL, tvecsL = cv2.calibrateCamera(objpoints, imgpointsL, grayL.shape[::-1], None, None)
            hL, wL = grayL.shape[:2]
            OmtxL, roiL = cv2.getOptimalNewCameraMatrix(mtxL, distL, (wL, hL), 1, (wL, hL))

            retR, mtxR, distR, rvecsR, tvecsR = cv2.calibrateCamera(objpoints, imgpointsR, grayR.shape[::-1], None, None)
            hR, wR = grayR.shape[:2]
            OmtxR, roiR = cv2.getOptimalNewCameraMatrix(mtxR, distR, (wR, hR), 1, (wR, hR))

            # Save calibration data
            calibration_dir = os.path.join(os.path.dirname(__file__), 'calibration_data')
            os.makedirs(calibration_dir, exist_ok=True)

            np.save(os.path.join(calibration_dir, 'mtxL.npy'), mtxL)
            np.save(os.path.join(calibration_dir, 'distL.npy'), distL)
            np.save(os.path.join(calibration_dir, 'OmtxL.npy'), OmtxL)
            np.save(os.path.join(calibration_dir, 'roiL.npy'), roiL)

            np.save(os.path.join(calibration_dir, 'mtxR.npy'), mtxR)
            np.save(os.path.join(calibration_dir, 'distR.npy'), distR)
            np.save(os.path.join(calibration_dir, 'OmtxR.npy'), OmtxR)
            np.save(os.path.join(calibration_dir, 'roiR.npy'), roiR)

            # Write a human-readable calibration summary file (text) for convenience.
            summary_path = os.path.join(calibration_dir, 'calibration_data.txt')
            try:
                with open(summary_path, 'w') as f:
                    f.write('Right camera Omtx:\n')
                    f.write(str(OmtxR.tolist()) + '\n')
                    f.write('Right ROI: ' + str(roiR) + '\n')
                    f.write('\n')
                    f.write('Left camera Omtx:\n')
                    f.write(str(OmtxL.tolist()) + '\n')
                    f.write('Left ROI: ' + str(roiL) + '\n')
                    f.write('\n')
                    f.write('Saved npy files:\n')
                    f.write(', '.join(sorted([f for f in os.listdir(calibration_dir) if f.endswith('.npy')])) + '\n')
            except Exception as _e:
                logging.warning('Could not write calibration summary: %s', _e)

            return jsonify({'status': 'success', 'message': 'Calibration data saved'})

        finally:
            capL.release()
            capR.release()

    except Exception as e:
        logging.exception('Calibration error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/calibrate-left', methods=['POST'])
def calibrate_left():
    """Calibrate left camera"""
    try:
        import cv2
        import numpy as np
        import os

        left_url = 'http://10.15.173.155:4747/video'

        objpoints = []
        imgpointsL = []

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
        objp = np.zeros((7*6, 3), np.float32)
        objp[:, :2] = np.mgrid[0:7, 0:6].T.reshape(-1, 2)

        capL = cv2.VideoCapture(left_url)

        if not capL.isOpened():
            return jsonify({'error': 'Cannot open left camera stream'}), 500

        try:
            # Allow manual mode: open a window, detect and let user save frames with 's', 'c', 'space'
            data_json = None
            try:
                data_json = request.get_json(silent=True) or {}
            except Exception:
                data_json = {}
            mode = data_json.get('mode') or request.form.get('mode') or 'auto'

            if str(mode).lower() == 'manual':
                manual_dir = os.path.join(os.path.dirname(__file__), 'calibration_data', 'data')
                os.makedirs(manual_dir, exist_ok=True)
                existing = [f for f in os.listdir(manual_dir) if f.startswith('chessboard-L') and f.endswith('.png')]
                idx = len(existing)
                cv2.namedWindow('Left Camera', cv2.WINDOW_NORMAL)
                while True:
                    retL, frameL = capL.read()
                    if not retL:
                        continue
                    grayL = cv2.cvtColor(frameL, cv2.COLOR_BGR2GRAY)
                    find_flags = cv2.CALIB_CB_ADAPTIVE_THRESH | cv2.CALIB_CB_NORMALIZE_IMAGE
                    retL_corners, cornersL = cv2.findChessboardCorners(grayL, (7, 6), find_flags)
                    disp = frameL.copy()
                    if retL_corners:
                        cv2.drawChessboardCorners(disp, (7, 6), cornersL, retL_corners)
                    cv2.putText(disp, "Press 's' to save, 'c' to skip, 'space' to finish", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255,255,255), 2)
                    cv2.imshow('Left Camera', disp)
                    key = cv2.waitKey(10) & 0xFF
                    if key == ord('s'):
                        # Save the frame even if chessboard not detected (helps debug)
                        if retL_corners:
                            fname = os.path.join(manual_dir, f'chessboard-L{idx}.png')
                            cv2.imwrite(fname, grayL)
                            idx += 1
                            print(f"Saved {fname} (detected)")
                        else:
                            fname = os.path.join(manual_dir, f'chessboard-L{idx}_raw.png')
                            cv2.imwrite(fname, grayL)
                            idx += 1
                            print(f"Saved {fname} (raw, not detected)")
                    elif key == ord('c'):
                        continue
                    elif key == 32:  # space to finish
                        break
                try:
                    cv2.destroyWindow('Left Camera')
                except Exception:
                    pass
                # reload saved images for calibration
                for file in sorted(os.listdir(manual_dir)):
                    if file.startswith('chessboard-L') and file.endswith('.png'):
                        img = cv2.imread(os.path.join(manual_dir, file), 0)
                        ret_c, corners = cv2.findChessboardCorners(img, (7, 6), None)
                        if ret_c:
                            objpoints.append(objp)
                            cv2.cornerSubPix(img, corners, (11, 11), (-1, -1), criteria)
                            imgpointsL.append(corners)
            else:
                for i in range(10):
                    retL, frameL = capL.read()
                    if not retL:
                        continue
                    grayL = cv2.cvtColor(frameL, cv2.COLOR_BGR2GRAY)
                    retL_corners, cornersL = cv2.findChessboardCorners(grayL, (7, 6), None)
                    if retL_corners:
                        objpoints.append(objp)
                        cv2.cornerSubPix(grayL, cornersL, (11, 11), (-1, -1), criteria)
                        imgpointsL.append(cornersL)

            if len(objpoints) < 5:
                return jsonify({'error': 'Not enough valid chessboard images for left camera'}), 400

            retL, mtxL, distL, rvecsL, tvecsL = cv2.calibrateCamera(objpoints, imgpointsL, grayL.shape[::-1], None, None)
            hL, wL = grayL.shape[:2]
            OmtxL, roiL = cv2.getOptimalNewCameraMatrix(mtxL, distL, (wL, hL), 1, (wL, hL))

            calibration_dir = os.path.join(os.path.dirname(__file__), 'calibration_data')
            os.makedirs(calibration_dir, exist_ok=True)

            np.save(os.path.join(calibration_dir, 'mtxL.npy'), mtxL)
            np.save(os.path.join(calibration_dir, 'distL.npy'), distL)
            np.save(os.path.join(calibration_dir, 'OmtxL.npy'), OmtxL)
            np.save(os.path.join(calibration_dir, 'roiL.npy'), roiL)

            # Write a local summary file with left camera data only; if right data is present, include it too.
            summary_path = os.path.join(calibration_dir, 'calibration_data.txt')
            try:
                with open(summary_path, 'w') as f:
                    f.write('Left camera Omtx:\n')
                    f.write(str(OmtxL.tolist()) + '\n')
                    f.write('Left ROI: ' + str(roiL) + '\n')
                    f.write('\n')
                    if os.path.exists(os.path.join(calibration_dir, 'OmtxR.npy')):
                        try:
                            OmtxR_read = np.load(os.path.join(calibration_dir, 'OmtxR.npy'))
                            roiR_read = np.load(os.path.join(calibration_dir, 'roiR.npy'))
                            f.write('Right camera Omtx:\n')
                            f.write(str(OmtxR_read.tolist()) + '\n')
                            f.write('Right ROI: ' + str(list(roiR_read)) + '\n')
                        except Exception:
                            pass
                    f.write('\n')
            except Exception as _e:
                logging.warning('Could not write left calibration summary: %s', _e)

            return jsonify({'status': 'success', 'message': 'Left camera calibrated'})

        finally:
            capL.release()
            try:
                cv2.destroyAllWindows()
            except Exception:
                pass

    except Exception as e:
        logging.exception('Left calibration error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/calibrate-right', methods=['POST'])
def calibrate_right():
    """Calibrate right camera"""
    try:
        import cv2
        import numpy as np
        import os

        right_url = 'http://10.15.173.254:4747/video'

        objpoints = []
        imgpointsR = []

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
        objp = np.zeros((7*6, 3), np.float32)
        objp[:, :2] = np.mgrid[0:7, 0:6].T.reshape(-1, 2)

        capR = cv2.VideoCapture(right_url)

        if not capR.isOpened():
            return jsonify({'error': 'Cannot open right camera stream'}), 500

        try:
            # Allow manual mode: open a window, detect and let user save frames with 's', 'c', 'space'
            data_json = None
            try:
                data_json = request.get_json(silent=True) or {}
            except Exception:
                data_json = {}
            mode = data_json.get('mode') or request.form.get('mode') or 'auto'

            if str(mode).lower() == 'manual':
                manual_dir = os.path.join(os.path.dirname(__file__), 'calibration_data', 'data')
                os.makedirs(manual_dir, exist_ok=True)
                existing = [f for f in os.listdir(manual_dir) if f.startswith('chessboard-R') and f.endswith('.png')]
                idx = len(existing)
                cv2.namedWindow('Right Camera', cv2.WINDOW_NORMAL)
                while True:
                    retR, frameR = capR.read()
                    if not retR:
                        continue
                    grayR = cv2.cvtColor(frameR, cv2.COLOR_BGR2GRAY)
                    # Try with adaptive threshold and normalization to improve detection
                    find_flags = cv2.CALIB_CB_ADAPTIVE_THRESH | cv2.CALIB_CB_NORMALIZE_IMAGE
                    retR_corners, cornersR = cv2.findChessboardCorners(grayR, (7, 6), find_flags)
                    disp = frameR.copy()
                    if retR_corners:
                        cv2.drawChessboardCorners(disp, (7, 6), cornersR, retR_corners)
                    cv2.putText(disp, "Press 's' to save, 'c' to skip, 'space' to finish", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255,255,255), 2)
                    cv2.imshow('Right Camera', disp)
                    key = cv2.waitKey(10) & 0xFF
                    if key == ord('s'):
                        # Save the frame even if chessboard not detected (helps debug)
                        if retR_corners:
                            fname = os.path.join(manual_dir, f'chessboard-R{idx}.png')
                            cv2.imwrite(fname, grayR)
                            idx += 1
                            print(f"Saved {fname} (detected)")
                        else:
                            fname = os.path.join(manual_dir, f'chessboard-R{idx}_raw.png')
                            cv2.imwrite(fname, grayR)
                            idx += 1
                            print(f"Saved {fname} (raw, not detected)")
                    elif key == ord('c'):
                        continue
                    elif key == 32:  # space to finish
                        break
                try:
                    cv2.destroyWindow('Right Camera')
                except Exception:
                    pass
                for file in sorted(os.listdir(manual_dir)):
                    if file.startswith('chessboard-R') and file.endswith('.png'):
                        img = cv2.imread(os.path.join(manual_dir, file), 0)
                        ret_c, corners = cv2.findChessboardCorners(img, (7, 6), None)
                        if ret_c:
                            objpoints.append(objp)
                            cv2.cornerSubPix(img, corners, (11, 11), (-1, -1), criteria)
                            imgpointsR.append(corners)
            else:
                for i in range(10):
                    retR, frameR = capR.read()
                    if not retR:
                        continue
                    grayR = cv2.cvtColor(frameR, cv2.COLOR_BGR2GRAY)
                    retR_corners, cornersR = cv2.findChessboardCorners(grayR, (7, 6), None)
                    if retR_corners:
                        objpoints.append(objp)
                        cv2.cornerSubPix(grayR, cornersR, (11, 11), (-1, -1), criteria)
                        imgpointsR.append(cornersR)

            if len(objpoints) < 5:
                return jsonify({'error': 'Not enough valid chessboard images for right camera'}), 400

            retR, mtxR, distR, rvecsR, tvecsR = cv2.calibrateCamera(objpoints, imgpointsR, grayR.shape[::-1], None, None)
            hR, wR = grayR.shape[:2]
            OmtxR, roiR = cv2.getOptimalNewCameraMatrix(mtxR, distR, (wR, hR), 1, (wR, hR))

            calibration_dir = os.path.join(os.path.dirname(__file__), 'calibration_data')
            os.makedirs(calibration_dir, exist_ok=True)

            np.save(os.path.join(calibration_dir, 'mtxR.npy'), mtxR)
            np.save(os.path.join(calibration_dir, 'distR.npy'), distR)
            np.save(os.path.join(calibration_dir, 'OmtxR.npy'), OmtxR)
            np.save(os.path.join(calibration_dir, 'roiR.npy'), roiR)

            # Write a local summary file with right camera data; if left data is present, include it too.
            summary_path = os.path.join(calibration_dir, 'calibration_data.txt')
            try:
                with open(summary_path, 'w') as f:
                    f.write('Right camera Omtx:\n')
                    f.write(str(OmtxR.tolist()) + '\n')
                    f.write('Right ROI: ' + str(roiR) + '\n')
                    f.write('\n')
                    if os.path.exists(os.path.join(calibration_dir, 'OmtxL.npy')):
                        try:
                            OmtxL_read = np.load(os.path.join(calibration_dir, 'OmtxL.npy'))
                            roiL_read = np.load(os.path.join(calibration_dir, 'roiL.npy'))
                            f.write('Left camera Omtx:\n')
                            f.write(str(OmtxL_read.tolist()) + '\n')
                            f.write('Left ROI: ' + str(list(roiL_read)) + '\n')
                        except Exception:
                            pass
                    f.write('\n')
            except Exception as _e:
                logging.warning('Could not write right calibration summary: %s', _e)

            return jsonify({'status': 'success', 'message': 'Right camera calibrated'})

        finally:
            capR.release()
            try:
                cv2.destroyAllWindows()
            except Exception:
                pass

    except Exception as e:
        logging.exception('Right calibration error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/balance-cameras', methods=['POST'])
def balance_cameras():
    """Balance cameras by displaying feeds with alignment lines"""
    try:
        import cv2
        import numpy as np

        left_url = 'http://10.15.173.155:4747/video'
        right_url = 'http://10.15.173.254:4747/video'  # Assuming different IP for right

        captureL = cv2.VideoCapture(left_url)
        captureR = cv2.VideoCapture(right_url)

        if not captureL.isOpened() or not captureR.isOpened():
            return jsonify({'error': 'Cannot open camera streams'}), 500

        def lines(img):
            h, w = img.shape[:2]
            for i in range(0, h, 20):
                cv2.line(img, (0, i), (w, i), (0, 255, 0), 1)

        cv2.namedWindow('imgL', cv2.WINDOW_NORMAL)
        cv2.namedWindow('imgR', cv2.WINDOW_NORMAL)

        try:
            while True:
                ret, imgL = captureL.read()
                ret, imgR = captureR.read()
                
                if ret:
                    lines(imgL)
                    lines(imgR)
                    
                    cv2.imshow('imgL', imgL)
                    cv2.imshow('imgR', imgR)
                    key = cv2.waitKey(10)
                    
                    if key == 27:  # ESC to exit
                        break
        finally:
            captureL.release()
            captureR.release()
            cv2.destroyAllWindows()

        return jsonify({'status': 'success', 'message': 'Camera balancing completed'})

    except Exception as e:
        logging.exception('Balance cameras error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/api/distance-detection-preview', methods=['POST'])
def distance_detection_preview():
    """Preview distance detection with stereo vision"""
    try:
        import cv2
        import numpy as np
        import os

        # Load calibration data
        calibration_dir = os.path.join(os.path.dirname(__file__), 'calibration_data')
        
        try:
            mtxL = np.load(os.path.join(calibration_dir, 'mtxL.npy'))
            distL = np.load(os.path.join(calibration_dir, 'distL.npy'))
            OmtxL = np.load(os.path.join(calibration_dir, 'OmtxL.npy'))
            roiL = np.load(os.path.join(calibration_dir, 'roiL.npy'))

            mtxR = np.load(os.path.join(calibration_dir, 'mtxR.npy'))
            distR = np.load(os.path.join(calibration_dir, 'distR.npy'))
            OmtxR = np.load(os.path.join(calibration_dir, 'OmtxR.npy'))
            roiR = np.load(os.path.join(calibration_dir, 'roiR.npy'))
        except Exception as e:
            return jsonify({'error': f'Calibration data not found. Please calibrate cameras first: {str(e)}'}), 400

        # Camera parameters (these should ideally come from calibration)
        fxR = OmtxR[0, 0] if OmtxR is not None else 823.98175049
        fyR = OmtxR[1, 1] if OmtxR is not None else 818.34320068
        
        ps = 0.0028
        focal_length = fyR * ps
        baseLine = 110

        # Load face cascade classifier
        cascade_path = os.path.join(os.path.dirname(__file__), 'Cascades', 'Face & Eyes', 'haarcascade_frontalface_default.xml')
        if not os.path.exists(cascade_path):
            # Try alternative path
            cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        
        face_clsfr = cv2.CascadeClassifier(cascade_path)

        left_url = 'http://10.15.173.155:4747/video'
        right_url = 'http://10.15.173.254:4747/video'

        captureL = cv2.VideoCapture(left_url)
        captureR = cv2.VideoCapture(right_url)

        if not captureL.isOpened() or not captureR.isOpened():
            return jsonify({'error': 'Cannot open camera streams'}), 500

        cv2.namedWindow('Left Camera - Distance Detection', cv2.WINDOW_NORMAL)
        cv2.namedWindow('Right Camera - Distance Detection', cv2.WINDOW_NORMAL)

        try:
            while True:
                ret, imgL = captureL.read()
                ret, imgR = captureR.read()

                if not ret:
                    continue

                # Apply calibration correction
                try:
                    w, h = imgL.shape[:2]
                    Left_Stereo_Map = cv2.initUndistortRectifyMap(mtxL, distL, None, OmtxL, (w, h), 5)
                    frame_niceL = cv2.remap(imgL, Left_Stereo_Map[0], Left_Stereo_Map[1], cv2.INTER_LINEAR, 0)
                    x, y, w, h = roiL
                    frame_niceL = frame_niceL[y:y+h, x:x+w]

                    w, h = imgR.shape[:2]
                    Right_Stereo_Map = cv2.initUndistortRectifyMap(mtxR, distR, None, OmtxR, (w, h), 5)
                    frame_niceR = cv2.remap(imgR, Right_Stereo_Map[0], Right_Stereo_Map[1], cv2.INTER_LINEAR, 0)
                    x, y, w, h = roiR
                    frame_niceR = frame_niceR[y:y+h, x:x+w]

                    imgL = frame_niceL
                    imgR = frame_niceR
                except Exception as e:
                    logging.warning(f'Calibration correction skipped: {e}')

                # Process for object detection
                blurL = cv2.blur(imgL, (3, 3))
                blurR = cv2.blur(imgR, (3, 3))

                grayL = cv2.cvtColor(blurL, cv2.COLOR_BGR2GRAY)
                grayR = cv2.cvtColor(blurR, cv2.COLOR_BGR2GRAY)

                facesL = face_clsfr.detectMultiScale(grayL, 1.3, 5)
                facesR = face_clsfr.detectMultiScale(grayR, 1.3, 5)

                faceL_mid = None
                faceR_mid = None
                faceLx, faceLy = 0, 0
                faceRx, faceRy = 0, 0

                for (x, y, w, h) in facesL:
                    faceLx = x
                    faceLy = y
                    faceL_mid = [int(x + (w / 2.0)), int(y + (h / 2.0))]

                    cv2.rectangle(imgL, (x, y), (x + w, y + h), (0, 255, 0), 2)
                    cv2.rectangle(imgL, (x - 1, y - 40), (x + w + 1, y), (0, 255, 0), -1)
                    cv2.putText(imgL, 'OBJECT', (x + 4, y - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 3)
                    cv2.circle(imgL, tuple(faceL_mid), 5, (0, 0, 255), -1)

                for (x, y, w, h) in facesR:
                    faceRx = x
                    faceRy = y
                    faceR_mid = [int(x + (w / 2.0)), int(y + (h / 2.0))]

                    cv2.rectangle(imgR, (x, y), (x + w, y + h), (0, 255, 0), 2)
                    cv2.rectangle(imgR, (x - 1, y - 40), (x + w + 1, y), (0, 255, 0), -1)
                    cv2.putText(imgR, 'OBJECT', (x + 4, y - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 3)
                    cv2.circle(imgR, tuple(faceR_mid), 5, (0, 0, 255), -1)

                # Calculate distance if object detected in both cameras
                if faceL_mid is not None and faceR_mid is not None:
                    disp = abs(faceR_mid[0] - faceL_mid[0])
                    if disp > 0:
                        depth = (focal_length * float(baseLine)) / (float(disp) * ps)
                        distance_text = str(round(depth - 100, 2)) + 'mm'
                        cv2.putText(imgL, distance_text, (faceLx + 150, faceLy - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 3)
                        cv2.putText(imgR, distance_text, (faceRx + 150, faceRy - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 3)

                cv2.imshow('Left Camera - Distance Detection', imgL)
                cv2.imshow('Right Camera - Distance Detection', imgR)
                
                key = cv2.waitKey(1)
                if key == 27:  # ESC to exit
                    break

        finally:
            captureL.release()
            captureR.release()
            cv2.destroyAllWindows()

        return jsonify({'status': 'success', 'message': 'Distance detection preview completed'})

    except Exception as e:
        logging.exception('Distance detection preview error: %s', e)
        return jsonify({'error': str(e)}), 500


@app.route('/output/<filename>')
def serve_output_file(filename):
    """Serve generated output files (3D models, PDFs, etc.)"""
    import os
    from flask import send_from_directory
    output_dir = os.path.join(os.path.dirname(__file__), 'output')
    return send_from_directory(output_dir, filename)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
