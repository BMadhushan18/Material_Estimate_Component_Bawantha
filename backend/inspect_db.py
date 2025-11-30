import sqlite3, os
DB_PATH = os.path.join(os.path.dirname(__file__), 'users_flask.db')
print('DB_PATH:', DB_PATH)
conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row
c = conn.cursor()
c.execute('SELECT id, first_name, last_name, email, phone, password_hash FROM users')
rows = c.fetchall()
print('Users found:', len(rows))
for r in rows:
    print(dict(r))
conn.close()
