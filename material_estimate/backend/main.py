import os
import tempfile
import shutil
from typing import List
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import pdfplumber
from PIL import Image
import pytesseract
import openai
import requests
from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
if not OPENAI_API_KEY:
    print('Warning: OPENAI_API_KEY not set. Set it in environment or .env file')

openai.api_key = OPENAI_API_KEY

# Optional Hugging Face configuration (server-side). If set, HF will be tried first.
HF_API_KEY = os.getenv('HF_API_KEY')
HF_MODEL = os.getenv('HF_MODEL', 'gpt2')

app = FastAPI(title='Building Plan Analyzer')

# Allow local app to call this API (adjust origins in production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get('/health')
async def health():
    return JSONResponse({'status': 'ok'})


def extract_text_from_pdf(path: str) -> str:
    texts = []
    try:
        with pdfplumber.open(path) as pdf:
            for page in pdf.pages:
                txt = page.extract_text() or ''
                texts.append(txt)
    except Exception:
        return ''
    return '\n'.join(texts)


def build_prompt(extracted: str, transcript: str, user_data: str) -> str:
    prompt = (
        "You are an expert construction estimator. Analyze the provided building plan text and the user's spoken notes.\n"
        "Return a JSON object ONLY with the following keys: summary, rooms (array of {name, area_m2, tile_count, notes}), total_materials (tiles, adhesive_kg, grout_kg), confidence (0-1).\n"
        "If any numeric values are uncertain, include an approximate value and mention it in notes. Use tile size and wastage from user_data when provided.\n"
        "Provide numeric values. Do not include any other keys.\n\n"
        "Building plan extracted text:\n```\n" + extracted + "\n```\n"
        "User transcript:\n```\n" + transcript + "\n```\n"
        "User metadata (JSON):\n```\n" + (user_data or '') + "\n```\n"
    )
    return prompt


@app.post('/analyze-plan')
async def analyze_plan(
    files: List[UploadFile] = File(...),
    transcript: str = Form(''),
    userData: str = Form('{}'),
):
    if not OPENAI_API_KEY:
        raise HTTPException(status_code=500, detail='OpenAI API key not configured')

    # Save files to temp dir and run OCR
    tmpdir = tempfile.mkdtemp(prefix='plan_')
    try:
        extracted_texts = []
        for f in files:
            filename = os.path.join(tmpdir, f.filename)
            with open(filename, 'wb') as out:
                contents = await f.read()
                out.write(contents)

            lower = f.filename.lower()
            if lower.endswith('.pdf'):
                t = extract_text_from_pdf(filename)
                if not t.strip():
                    # try render pages to images? (omitted here)
                    pass
                extracted_texts.append(t)
            elif lower.endswith(('.png', '.jpg', '.jpeg')):
                try:
                    txt = pytesseract.image_to_string(Image.open(filename))
                    extracted_texts.append(txt)
                except Exception:
                    extracted_texts.append('')
            else:
                extracted_texts.append('')

        combined = '\n\n'.join(extracted_texts)
        prompt = build_prompt(combined, transcript, userData)

        # Call OpenAI ChatCompletion (gpt-4o or gpt-4-0613 depending on account)
        try:
            resp = openai.chat.completions.create(
                model='gpt-4o-mini',
                messages=[{'role': 'system', 'content': 'You are a helpful assistant.'},
                          {'role': 'user', 'content': prompt}],
                temperature=0.0,
                max_tokens=1400,
            )
            text = resp.choices[0].message.content
        except Exception as e:
            # fallback to completion if ChatCompletion unsupported
            resp = openai.completions.create(
                model='text-davinci-003', prompt=prompt, max_tokens=1400, temperature=0.0
            )
            text = resp.choices[0].text

        # Attempt to parse JSON from LLM output
        import json
        try:
            # LLM should return pure JSON; try to find first '{'
            start = text.find('{')
            if start >= 0:
                body = text[start:]
                parsed = json.loads(body)
            else:
                parsed = {'summary': text}
        except Exception:
            parsed = {'summary': text}

        # compute a conservative confidence if missing
        parsed.setdefault('confidence', 0.5)

        return JSONResponse(parsed)
    finally:
        try:
            shutil.rmtree(tmpdir)
        except Exception:
            pass


from pydantic import BaseModel


class ChatRequest(BaseModel):
    message: str


@app.post('/chat')
async def chat_endpoint(req: ChatRequest):
    """Simple chat proxy endpoint.

    Tries Hugging Face Inference API first (if HF_API_KEY or public model available).
    Falls back to OpenAI if configured.
    Returns JSON: {"reply": "..."}
    """
    msg = req.message

    # Try Hugging Face Inference API
    if HF_MODEL:
        try:
            hf_url = f'https://api-inference.huggingface.co/models/{HF_MODEL}'
            headers = {'Content-Type': 'application/json'}
            if HF_API_KEY:
                headers['Authorization'] = f'Bearer {HF_API_KEY}'

            payload = {'inputs': msg, 'options': {'wait_for_model': True}}
            hf_res = requests.post(hf_url, headers=headers, json=payload, timeout=30)
            if hf_res.status_code == 200:
                try:
                    parsed = hf_res.json()
                    # HF may return a list or dict with generated_text
                    if isinstance(parsed, list) and len(parsed) > 0:
                        first = parsed[0]
                        if isinstance(first, dict) and 'generated_text' in first:
                            reply = first['generated_text']
                        else:
                            reply = str(parsed[0])
                    elif isinstance(parsed, dict) and 'generated_text' in parsed:
                        reply = parsed['generated_text']
                    else:
                        reply = hf_res.text
                except Exception:
                    reply = hf_res.text
                return JSONResponse({'reply': reply})
            # If HF gave an auth or server error, continue to fallback
        except Exception as e:
            # log but continue
            print('HF request failed:', e)

    # Fallback to OpenAI
    if not OPENAI_API_KEY:
        raise HTTPException(status_code=500, detail='No AI provider configured on server')

    try:
        # Prefer Chat Completions if available
        try:
            resp = openai.chat.completions.create(
                model='gpt-3.5-turbo',
                messages=[{'role': 'user', 'content': msg}],
                temperature=0.7,
                max_tokens=512,
            )
            # new api returns choices[0].message.content
            text = ''
            if hasattr(resp, 'choices') and len(resp.choices) > 0:
                # try to access new style
                try:
                    text = resp.choices[0].message.content
                except Exception:
                    text = str(resp.choices[0])
        except Exception:
            # fallback to older completions
            resp = openai.Completion.create(model='text-davinci-003', prompt=msg, max_tokens=512, temperature=0.7)
            text = resp.choices[0].text

        return JSONResponse({'reply': text})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f'OpenAI request failed: {e}')


    if __name__ == '__main__':
        # Allow running directly: read HOST/PORT from env or default to 0.0.0.0:8000
        host = os.getenv('HOST', '0.0.0.0')
        port = int(os.getenv('PORT', '8000'))
        try:
            import uvicorn

            uvicorn.run('main:app', host=host, port=port, reload=False)
        except Exception as e:
            print('Failed to start uvicorn:', e)
