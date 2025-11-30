Simple FastAPI backend for signup/login used by the Flutter frontend.

Quick start (Windows):

1. Create a virtual environment and activate it:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2. Install dependencies:

```powershell
pip install -r requirements.txt
```

3. Run the app:

```powershell
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

By default the server stores users in `backend/users.db` (SQLite). The API endpoints:
- `POST /signup` accepts JSON {first_name, last_name, email, phone, password}
- `POST /login` accepts JSON {email, password} and returns `{ "token": "..." }` on success

Notes:
- Update `JWT_SECRET` environment variable if you want a custom JWT secret. The default is set in code for convenience.
- CORS is enabled for all origins for ease of local development.
