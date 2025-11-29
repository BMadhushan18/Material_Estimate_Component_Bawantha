Python FastAPI backend for Building Plan analysis

Overview
- Accepts multipart uploads of building plan files (PDF/Image) and a transcript.
- Runs OCR (pytesseract for images, pdfplumber for PDFs) to extract text.
- Calls an LLM (OpenAI) with a structured prompt to return a JSON analysis report.

Configuration
- Create a `.env` file with:
  - `OPENAI_API_KEY=your_api_key_here`
  - `HOST=0.0.0.0`
  - `PORT=8000`

Run locally
```bash
python -m venv .venv
.venv\\Scripts\\activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Notes
- This is a minimal PoC. For production, secure endpoints with API keys, use HTTPS, add rate limiting and file size limits.
