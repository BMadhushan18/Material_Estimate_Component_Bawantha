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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
