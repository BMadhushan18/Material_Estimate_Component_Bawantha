import os
import tempfile
import shutil
from typing import List
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
import pdfplumber
from PIL import Image
import pytesseract
import openai
from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
if not OPENAI_API_KEY:
    print('Warning: OPENAI_API_KEY not set. Set it in environment or .env file')

openai.api_key = OPENAI_API_KEY

app = FastAPI(title='Building Plan Analyzer')


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
