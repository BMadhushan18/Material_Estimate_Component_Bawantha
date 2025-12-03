"""
Sri Lankan Construction Standards Database Initialization
"""
import sqlite3
import os
from datetime import datetime


class StandardsDatabase:
    def __init__(self, db_path=None):
        if db_path is None:
            # Get absolute path relative to this file
            current_dir = os.path.dirname(os.path.abspath(__file__))
            db_path = os.path.join(current_dir, 'sl_construction_standards.db')
        self.db_path = db_path
        self.conn = None
    
    def connect(self):
        """Create database connection"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        return self.conn
    
    def create_tables(self):
        """Create all required tables"""
        conn = self.connect()
        c = conn.cursor()
        
        # Paint standards table
        c.execute('''
        CREATE TABLE IF NOT EXISTS paint_standards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            paint_type TEXT NOT NULL,
            surface_type TEXT,
            coverage_sqm_per_liter REAL,
            coats_required INTEGER,
            drying_time_hours INTEGER,
            primer_required INTEGER,
            primer_coverage_sqm_per_liter REAL,
            typical_brands TEXT,
            created_at TEXT
        )''')
        
        # Putty standards table
        c.execute('''
        CREATE TABLE IF NOT EXISTS putty_standards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            putty_type TEXT NOT NULL,
            thickness_mm REAL,
            coverage_sqm_per_kg REAL,
            coats_required INTEGER,
            drying_time_hours INTEGER,
            typical_brands TEXT,
            created_at TEXT
        )''')
        
        # Tile standards table
        c.execute('''
        CREATE TABLE IF NOT EXISTS tile_standards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tile_type TEXT,
            size_mm TEXT,
            application TEXT,
            adhesive_kg_per_sqm REAL,
            grout_kg_per_sqm REAL,
            wastage_factor REAL,
            typical_brands TEXT,
            price_per_sqm_lkr REAL,
            created_at TEXT
        )''')
        
        # Room standards (Sri Lankan building regulations)
        c.execute('''
        CREATE TABLE IF NOT EXISTS room_standards (
            room_type TEXT PRIMARY KEY,
            min_area_sqm REAL,
            min_length_m REAL,
            min_width_m REAL,
            min_height_m REAL,
            typical_height_m REAL,
            wall_finish TEXT,
            floor_finish TEXT,
            ceiling_finish TEXT,
            created_at TEXT
        )''')
        
        # Material costs (approximate LKR prices)
        c.execute('''
        CREATE TABLE IF NOT EXISTS material_costs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_category TEXT,
            material_name TEXT,
            brand TEXT,
            unit TEXT,
            price_lkr REAL,
            quality_grade TEXT,
            updated_at TEXT
        )''')
        
        conn.commit()
        conn.close()
    
    def populate_paint_standards(self):
        """Insert Sri Lankan paint standards"""
        conn = self.connect()
        c = conn.cursor()
        
        paints = [
            ('emulsion', 'smooth', 12.0, 2, 4, 1, 14.0, 'Robbialac,Nippon Paint,Asian Paints,Berger', datetime.now().isoformat()),
            ('emulsion', 'rough', 10.0, 2, 4, 1, 14.0, 'Robbialac,Nippon Paint,Asian Paints', datetime.now().isoformat()),
            ('enamel', 'smooth', 14.0, 2, 6, 1, 16.0, 'Berger,Nippon Paint,Dulux', datetime.now().isoformat()),
            ('enamel', 'wood', 12.0, 2, 8, 1, 15.0, 'Berger,Nippon Paint', datetime.now().isoformat()),
            ('weather_shield', 'exterior', 10.0, 2, 6, 1, 12.0, 'Robbialac,Nippon Paint', datetime.now().isoformat()),
        ]
        
        c.executemany('''INSERT INTO paint_standards 
                        (paint_type, surface_type, coverage_sqm_per_liter, coats_required, 
                         drying_time_hours, primer_required, primer_coverage_sqm_per_liter, 
                         typical_brands, created_at) 
                        VALUES (?,?,?,?,?,?,?,?,?)''', paints)
        
        conn.commit()
        conn.close()
    
    def populate_putty_standards(self):
        """Insert putty standards"""
        conn = self.connect()
        c = conn.cursor()
        
        putty_data = [
            ('wall_putty', 1.5, 15.0, 2, 6, 'Nippon,Asian Paints,Dulux', datetime.now().isoformat()),
            ('acrylic_putty', 1.0, 18.0, 2, 4, 'Nippon,Dulux', datetime.now().isoformat()),
        ]
        
        c.executemany('''INSERT INTO putty_standards 
                        (putty_type, thickness_mm, coverage_sqm_per_kg, coats_required, 
                         drying_time_hours, typical_brands, created_at) 
                        VALUES (?,?,?,?,?,?,?)''', putty_data)
        
        conn.commit()
        conn.close()
    
    def populate_tile_standards(self):
        """Insert Sri Lankan tile standards"""
        conn = self.connect()
        c = conn.cursor()
        
        tiles = [
            ('ceramic', '600x600', 'floor', 5.0, 1.5, 0.10, 'Rocell,Lanka Tiles,Royal Ceramics', 1200.0, datetime.now().isoformat()),
            ('ceramic', '300x300', 'floor', 4.5, 1.5, 0.10, 'Rocell,Lanka Tiles', 800.0, datetime.now().isoformat()),
            ('porcelain', '600x600', 'floor', 5.5, 1.5, 0.12, 'Royal Ceramics,Rocell Premium', 2500.0, datetime.now().isoformat()),
            ('porcelain', '800x800', 'floor', 6.0, 1.5, 0.12, 'Royal Ceramics,Rocell Premium', 3200.0, datetime.now().isoformat()),
            ('ceramic', '300x600', 'wall', 4.5, 1.0, 0.08, 'Rocell,Lanka Tiles', 900.0, datetime.now().isoformat()),
            ('ceramic', '200x300', 'wall', 4.0, 1.0, 0.08, 'Rocell,Lanka Tiles', 600.0, datetime.now().isoformat()),
        ]
        
        c.executemany('''INSERT INTO tile_standards 
                        (tile_type, size_mm, application, adhesive_kg_per_sqm, grout_kg_per_sqm, 
                         wastage_factor, typical_brands, price_per_sqm_lkr, created_at) 
                        VALUES (?,?,?,?,?,?,?,?,?)''', tiles)
        
        conn.commit()
        conn.close()
    
    def populate_room_standards(self):
        """Insert Sri Lankan room standards (based on UDA/ICTAD guidelines)"""
        conn = self.connect()
        c = conn.cursor()
        
        rooms = [
            ('master_bedroom', 9.0, 2.7, 2.7, 2.75, 3.0, 'paint', 'tiles', 'paint', datetime.now().isoformat()),
            ('bedroom', 7.5, 2.4, 2.4, 2.75, 3.0, 'paint', 'tiles', 'paint', datetime.now().isoformat()),
            ('living_room', 12.0, 3.0, 3.0, 2.75, 3.3, 'paint', 'tiles', 'paint', datetime.now().isoformat()),
            ('dining_room', 8.0, 2.4, 2.4, 2.75, 3.0, 'paint', 'tiles', 'paint', datetime.now().isoformat()),
            ('kitchen', 5.5, 2.1, 1.8, 2.75, 3.0, 'tiles_partial', 'tiles', 'paint', datetime.now().isoformat()),
            ('bathroom', 3.0, 1.5, 1.2, 2.4, 2.75, 'tiles_full', 'tiles', 'paint', datetime.now().isoformat()),
            ('toilet', 1.5, 1.2, 0.9, 2.4, 2.75, 'tiles_full', 'tiles', 'paint', datetime.now().isoformat()),
            ('balcony', 3.0, 1.5, 1.2, 2.4, 3.0, 'paint', 'tiles', 'none', datetime.now().isoformat()),
        ]
        
        c.executemany('''INSERT INTO room_standards 
                        (room_type, min_area_sqm, min_length_m, min_width_m, min_height_m, 
                         typical_height_m, wall_finish, floor_finish, ceiling_finish, created_at) 
                        VALUES (?,?,?,?,?,?,?,?,?,?)''', rooms)
        
        conn.commit()
        conn.close()
    
    def populate_material_costs(self):
        """Insert approximate material costs in LKR"""
        conn = self.connect()
        c = conn.cursor()
        
        costs = [
            ('paint', 'Emulsion Paint', 'Robbialac', 'liter', 1800.0, 'premium', datetime.now().isoformat()),
            ('paint', 'Emulsion Paint', 'Asian Paints', 'liter', 1600.0, 'standard', datetime.now().isoformat()),
            ('paint', 'Enamel Paint', 'Berger', 'liter', 2200.0, 'premium', datetime.now().isoformat()),
            ('paint', 'Primer', 'Nippon', 'liter', 1400.0, 'standard', datetime.now().isoformat()),
            ('putty', 'Wall Putty', 'Nippon', 'kg', 180.0, 'standard', datetime.now().isoformat()),
            ('putty', 'Acrylic Putty', 'Dulux', 'kg', 220.0, 'premium', datetime.now().isoformat()),
            ('adhesive', 'Tile Adhesive', 'Rocell', 'kg', 85.0, 'standard', datetime.now().isoformat()),
            ('grout', 'Tile Grout', 'Rocell', 'kg', 120.0, 'standard', datetime.now().isoformat()),
        ]
        
        c.executemany('''INSERT INTO material_costs 
                        (material_category, material_name, brand, unit, price_lkr, quality_grade, updated_at) 
                        VALUES (?,?,?,?,?,?,?)''', costs)
        
        conn.commit()
        conn.close()
    
    def initialize_database(self):
        """Complete database initialization"""
        print("Creating construction standards database...")
        self.create_tables()
        
        print("Populating paint standards...")
        self.populate_paint_standards()
        
        print("Populating putty standards...")
        self.populate_putty_standards()
        
        print("Populating tile standards...")
        self.populate_tile_standards()
        
        print("Populating room standards...")
        self.populate_room_standards()
        
        print("Populating material costs...")
        self.populate_material_costs()
        
        print(f"Database initialized successfully at: {self.db_path}")


if __name__ == '__main__':
    # Initialize the database
    db = StandardsDatabase()
    db.initialize_database()
