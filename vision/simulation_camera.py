"""Local phone camera bridge to the RTX and authenticated simulation backend."""
import argparse
import asyncio
import base64
import binascii
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import math
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit
from uuid import UUID, uuid4

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator
from starlette.concurrency import run_in_threadpool
from starlette.middleware.trustedhost import TrustedHostMiddleware

ROOT = Path(__file__).resolve().parent
MAX_BODY = 3 * 1024 * 1024
MODEL_VERSION = 'r2plus1d-rwf2000-a744b6a-simulation-v1'
EXPECTED_WEIGHTS_SHA256 = 'fa5aa0d7d4427ea7b81d410f5b5186ed64285ff8bebdd12462d976a36e86cdc0'


class FrameBatch(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    frames: list[str] = Field(min_length=32, max_length=32)
    offsets_ms: list[float] = Field(min_length=32, max_length=32)

    @model_validator(mode='after')
    def validate_frames(self):
        if any(not 1 <= len(frame) <= 100_000 for frame in self.frames):
            raise ValueError('Tamaño de fotograma inválido')
        offsets = self.offsets_ms
        if offsets[0] < 0 or offsets[-1] > 8_000 or not 3_000 <= offsets[-1] - offsets[0] <= 8_000:
            raise ValueError('La secuencia debe cubrir entre 3 y 8 segundos')
        if any(not 40 <= after - before <= 600 for before, after in zip(offsets, offsets[1:])):
            raise ValueError('Los fotogramas deben estar ordenados y espaciados regularmente')
        return self


def decode_frames(batch):
    import cv2
    import numpy as np
    frames = []
    for encoded in batch.frames:
        try:
            content = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError('JPEG inválido') from None
        if not content.startswith(b'\xff\xd8'):
            raise ValueError('Solo se admiten fotogramas JPEG')
        # The client sends 224x224, and dimensions are bounded before decompression.
        from PIL import Image
        from io import BytesIO
        try:
            with Image.open(BytesIO(content)) as image:
                if image.format != 'JPEG' or image.size != (224, 224):
                    raise ValueError('Se requieren fotogramas JPEG de 224x224')
            frame = cv2.imdecode(np.frombuffer(content, dtype=np.uint8), cv2.IMREAD_COLOR)
        except Exception:
            raise ValueError('No se pudo decodificar un fotograma JPEG de 224x224') from None
        if frame is None or frame.shape != (224, 224, 3):
            raise ValueError('JPEG inválido')
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    return frames


class GpuScorer:
    def __init__(self, weights):
        import torch
        from analyze_video import load_model
        if not torch.cuda.is_available():
            raise RuntimeError('CUDA no disponible; ejecuta vision/check_gpu.py')
        with Path(weights).open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != EXPECTED_WEIGHTS_SHA256:
                raise RuntimeError('Los pesos no coinciden con el modelo de simulación fijado')
        self.device = torch.device('cuda:0')
        self.model = load_model(weights, self.device)

    def __call__(self, frames):
        import torch
        from analyze_video import tensor_from_frames
        with torch.inference_mode():
            inputs = tensor_from_frames(frames).to(self.device)
            confidence = self.model(inputs).softmax(dim=1)[0, 1].item()
        if not math.isfinite(confidence) or not 0 <= confidence <= 1:
            raise RuntimeError('Salida del modelo inválida')
        return confidence


class BackendPublisher:
    def __init__(self, base_url, session, token):
        parsed = urlsplit(base_url)
        loopback = parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1')
        if parsed.username or parsed.password or parsed.query or parsed.fragment or not parsed.hostname or not (parsed.scheme == 'https' or loopback):
            raise ValueError('La API debe usar HTTPS o HTTP loopback para USB')
        self.url = base_url.rstrip('/') + f'/operator/ai/simulation/sessions/{UUID(str(session))}/events'
        self.token = token

    def __call__(self, confidence, request_id):
        # A retry uses the same event UUID so a lost response cannot duplicate cases.
        for attempt in range(2):
            try:
                response = httpx.post(self.url,
                    json={'request_id': str(request_id), 'confidence': confidence, 'modelVersion': MODEL_VERSION},
                    headers={'Authorization': 'Bearer ' + self.token}, timeout=20, follow_redirects=False)
                if response.status_code != 200:
                    raise HTTPException(response.status_code if response.status_code in (401, 403, 404, 409, 410, 422) else 503,
                                        'La sesión de simulación no está disponible. Verifica la cuenta y vuelve a iniciar.')
                return response.json()
            except (httpx.TransportError, ValueError):
                if attempt:
                    raise HTTPException(503, 'No se confirmó el registro en el servidor. Se detuvo la cámara; revisa la bandeja antes de reintentar.') from None


def create_app(pairing_token, scorer, publisher, expires_at=None):
    expires_at = expires_at or datetime.now(timezone.utc) + timedelta(minutes=30)
    app = FastAPI(title='Trujillo 360 · Cámara de simulación', docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=['127.0.0.1', 'localhost', 'testserver'])
    busy = asyncio.Lock()

    @app.middleware('http')
    async def guard(request: Request, call_next):
        if request.url.path.startswith('/api/'):
            token = request.headers.get('X-Pairing-Token', '')
            if not hmac.compare_digest(token.encode(), pairing_token.encode()):
                return JSONResponse({'detail': 'Vinculación de cámara inválida'}, status_code=401)
            if datetime.now(timezone.utc) >= expires_at:
                return JSONResponse({'detail': 'La vinculación de cámara venció'}, status_code=410)
            origin = request.headers.get('origin')
            if origin and origin != str(request.base_url).rstrip('/'):
                return JSONResponse({'detail': 'Origen de cámara no permitido'}, status_code=403)
            chunks, size = [], 0
            async for chunk in request.stream():
                size += len(chunk)
                if size > MAX_BODY:
                    return JSONResponse({'detail': 'Secuencia demasiado grande'}, status_code=413)
                chunks.append(chunk)
            request._body = b''.join(chunks)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Permissions-Policy'] = 'camera=(self), microphone=()'
        return response

    @app.get('/', response_class=HTMLResponse)
    def camera_page():
        return (ROOT / 'simulation_camera.html').read_text(encoding='utf-8')

    @app.post('/api/analyze')
    async def analyze(batch: FrameBatch):
        if busy.locked():
            raise HTTPException(429, 'La RTX está procesando otra secuencia; espera y reintenta')
        async with busy:
            def process():
                try:
                    frames = decode_frames(batch)
                except ValueError as error:
                    raise HTTPException(422, str(error)) from None
                try:
                    confidence = scorer(frames)
                except Exception:
                    raise HTTPException(503, 'No se pudo analizar la secuencia en la RTX') from None
                result = publisher(confidence, uuid4())
                return {'confidence': confidence, 'modelVersion': MODEL_VERSION,
                        'simulation': True, 'result': result}
            return await run_in_threadpool(process)

    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=UUID, required=True)
    parser.add_argument('--api-base', required=True)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--weights', type=Path, default=ROOT / 'weights/r2plus1d_best.pt')
    args = parser.parse_args()
    token = os.environ.get('TRUJILLO_SIM_TOKEN', '').strip()
    if not token:
        parser.error('Define TRUJILLO_SIM_TOKEN con el workerToken efímero de la sesión de simulación')
    publisher = BackendPublisher(args.api_base, args.session, token)
    scorer = GpuScorer(args.weights)
    pairing = secrets.token_urlsafe(32)
    print('Cámara de simulación lista en loopback. Vinculación local válida por 30 minutos.')
    print(f'En Android por USB: adb reverse tcp:{args.port} tcp:{args.port}')
    print(f'Abre en el celular: http://localhost:{args.port}/#pair={pairing}')
    # Access logs are disabled; the backend worker credential never reaches the page.
    import uvicorn
    uvicorn.run(create_app(pairing, scorer, publisher), host='127.0.0.1', port=args.port, access_log=False)


if __name__ == '__main__':
    main()
