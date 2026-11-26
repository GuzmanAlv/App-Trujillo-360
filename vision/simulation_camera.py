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
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator
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


class CameraAccess(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    schemaVersion: int = Field(strict=True, ge=1, le=1)
    id: UUID
    workerToken: str = Field(min_length=40, max_length=128)
    expiresAt: AwareDatetime


class SessionPublisher:
    """Keep the model running while the operator renews scoped sessions on the phone."""
    def __init__(self, base_url):
        self.base_url = base_url
        self.publisher = None
        self.expires_at = None
        self.binding = None

    def ready(self):
        return self.publisher is not None and self.expires_at > datetime.now(timezone.utc)

    def configure(self, access):
        if not datetime.now(timezone.utc) < access.expiresAt <= datetime.now(timezone.utc) + timedelta(minutes=31):
            raise HTTPException(410, 'El acceso venció. Crea otra sesión en la app y copia el nuevo acceso.')
        self.publisher = BackendPublisher(self.base_url, access.id, access.workerToken)
        self.expires_at = access.expiresAt
        self.binding = secrets.token_urlsafe(24)

    def bound_to(self, request):
        binding = request.headers.get('X-Camera-Binding', '')
        return self.ready() and bool(binding) and hmac.compare_digest(binding, self.binding)

    def __call__(self, confidence, request_id):
        if not self.ready():
            raise HTTPException(410, 'Conecta un acceso vigente desde la app antes de iniciar.')
        try:
            return self.publisher(confidence, request_id)
        except HTTPException as error:
            if error.status_code in (401, 403, 409, 410):
                self.publisher = None
            raise


def validate_public_origin(value):
    if value is None:
        return None
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
            or parsed.path not in ('', '/') or parsed.query or parsed.fragment
            or parsed.port not in (None, 443)):
        raise ValueError('La dirección pública debe ser un origen HTTPS sin ruta ni credenciales')
    return 'https://' + parsed.hostname


def create_app(pairing_token, scorer, publisher, expires_at=None, public_origin=None, connection_test=False):
    public_origin = validate_public_origin(public_origin)
    expires_at = expires_at or datetime.now(timezone.utc) + timedelta(minutes=30)
    app = FastAPI(title='Trujillo 360 · Cámara de simulación', docs_url=None, redoc_url=None, openapi_url=None)
    hosts = ['127.0.0.1', 'localhost', 'testserver']
    if public_origin:
        hosts.append(urlsplit(public_origin).hostname)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=hosts)
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
            if origin and origin not in (str(request.base_url).rstrip('/'), public_origin):
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
        page = 'connection_check.html' if connection_test else 'simulation_camera.html'
        return (ROOT / page).read_text(encoding='utf-8')

    @app.get('/health')
    def health():
        return {'status': 'ok', 'mode': 'connection_test' if connection_test else 'simulation',
                **({'standby': True} if isinstance(publisher, SessionPublisher) else {})}

    @app.get('/api/session')
    def session_status(request: Request):
        if not isinstance(publisher, SessionPublisher):
            return {'needsAccess': False, 'sessionReady': not connection_test}
        return {'needsAccess': True, 'sessionReady': publisher.bound_to(request),
                'expiresAt': publisher.expires_at if publisher.bound_to(request) else None}

    @app.post('/api/session')
    async def connect_session(access: CameraAccess):
        if not isinstance(publisher, SessionPublisher):
            raise HTTPException(409, 'Este iniciador ya tiene una sesión fija.')
        if busy.locked():
            raise HTTPException(409, 'Detén la cámara y espera a que termine el análisis antes de cambiar de sesión.')
        async with busy:
            publisher.configure(access)
        return {'sessionReady': True, 'expiresAt': publisher.expires_at, 'binding': publisher.binding}

    @app.post('/api/analyze')
    async def analyze(batch: FrameBatch, request: Request):
        if connection_test:
            raise HTTPException(409, 'Esta prueba solo verifica conexión y permiso de cámara')
        if isinstance(publisher, SessionPublisher) and not publisher.ready():
            raise HTTPException(410, 'Pega un acceso vigente de la app para iniciar la cámara.')
        if isinstance(publisher, SessionPublisher) and not publisher.bound_to(request):
            raise HTTPException(409, 'Se conectó otra sesión de cámara. Vuelve a pegar tu acceso para continuar.')
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
    parser.add_argument('--session', type=UUID)
    parser.add_argument('--api-base')
    parser.add_argument('--public-origin', help='Origen HTTPS privado asignado por Tailscale Serve')
    parser.add_argument('--check-connection', action='store_true', help='Prueba de red y cámara, sin IA ni reportes')
    parser.add_argument('--standby', action='store_true', help='Conectar sesiones desde el celular sin reiniciar el modelo')
    parser.add_argument('--qr', action='store_true', help='Mostrar un QR de vinculación en la terminal')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--weights', type=Path, default=ROOT / 'weights/r2plus1d_best.pt')
    args = parser.parse_args()
    token = os.environ.get('TRUJILLO_SIM_TOKEN', '').strip()
    try:
        public_origin = validate_public_origin(args.public_origin)
    except ValueError as error:
        parser.error(str(error))
    if args.standby and (args.check_connection or not args.api_base):
        parser.error('--standby requiere --api-base y no admite --check-connection')
    if not args.check_connection and not args.standby and (not token or not args.session or not args.api_base):
        parser.error('Define TRUJILLO_SIM_TOKEN con el workerToken efímero de la sesión de simulación')
    publisher = None if args.check_connection else (
        SessionPublisher(args.api_base) if args.standby else BackendPublisher(args.api_base, args.session, token))
    scorer = None if args.check_connection else GpuScorer(args.weights)
    pairing = secrets.token_urlsafe(32)
    lifetime = timedelta(hours=8) if args.standby else timedelta(minutes=30)
    print('Cámara de simulación lista. Mantén esta ventana abierta.')
    if not public_origin:
        print(f'En Android por USB: adb reverse tcp:{args.port} tcp:{args.port}')
    origin = public_origin or f'http://localhost:{args.port}'
    camera_url = f'{origin}/#pair={pairing}'
    print(f'Abre en el celular: {camera_url}')
    if args.qr:
        import qrcode
        qr = qrcode.QRCode(border=4)
        qr.add_data(camera_url)
        qr.make(fit=True)
        qr.print_ascii(invert=True)
    if args.standby:
        print('Escanea el QR. Copia el acceso completo desde la app y pégalo en la página del celular.')
        print('Vinculación de esta página: 8 horas. Las sesiones de la app siguen durando 30 minutos.')
    if args.check_connection:
        print('Modo prueba de conexión: no analiza ni envía reportes.')
    # Access logs are disabled; the backend worker credential never reaches the page.
    import uvicorn
    uvicorn.run(create_app(pairing, scorer, publisher, public_origin=public_origin,
                          connection_test=args.check_connection, expires_at=datetime.now(timezone.utc)+lifetime),
                host='127.0.0.1', port=args.port, access_log=False)


if __name__ == '__main__':
    main()
