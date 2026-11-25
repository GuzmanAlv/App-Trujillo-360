"""Offline experimental clip classifier. Never publishes incidents or alerts."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import time

import cv2
import numpy as np
import torch
from torchvision.models.video import r2plus1d_18

ROOT = Path(__file__).resolve().parent
MODEL_REVISION = 'a744b6af7496f0cbfa4f0ba32acd46b65e52d4e1'


def load_model(path, device):
    checkpoint = torch.load(path, map_location='cpu', weights_only=True)
    model = r2plus1d_18(weights=None)
    # The published checkpoint wraps the backbone and uses Dropout + Linear.
    model.fc = torch.nn.Sequential(torch.nn.Dropout(.5), torch.nn.Linear(512, 2))
    state = checkpoint['model']
    model.load_state_dict({key.removeprefix('backbone.'): value for key, value in state.items()}, strict=True)
    return model.eval().to(device)


def windows(path, seconds):
    capture = cv2.VideoCapture(str(path))
    try:
        if not capture.isOpened():
            raise ValueError('No se pudo abrir el video.')
        fps = capture.get(cv2.CAP_PROP_FPS)
        if not math.isfinite(fps) or not 1 <= fps <= 240:
            raise ValueError('FPS del video inválidos o no compatibles (1–240).')
        size = round(fps * seconds)
        frames, start, total = [], 0, 0
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            # Bounded memory: retain only one resized window, not the full video.
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            frames.append(cv2.resize(rgb, (224, 224), interpolation=cv2.INTER_AREA))
            total += 1
            if len(frames) == size:
                yield start / fps, total / fps, frames
                frames, start = [], total
        if frames:
            yield start / fps, total / fps, frames
        if total == 0:
            raise ValueError('El video no contiene fotogramas decodificables.')
    finally:
        capture.release()


def tensor_from_frames(frames):
    indices = np.linspace(0, len(frames) - 1, 32).astype(int)
    array = np.stack([frames[index] for index in indices])
    tensor = torch.from_numpy(array).permute(3, 0, 1, 2).float().div(255)
    return tensor.sub(.45).div(.225).unsqueeze(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video', type=Path)
    parser.add_argument('--weights', type=Path, default=ROOT / 'weights/r2plus1d_best.pt')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--window-seconds', type=float, default=4)
    args = parser.parse_args()
    if not args.video.is_file() or not args.weights.is_file():
        parser.error('Falta el video o el archivo de pesos.')
    if not math.isfinite(args.window_seconds) or not 1 <= args.window_seconds <= 10:
        parser.error('La ventana debe durar entre 1 y 10 segundos.')
    if args.output.resolve() in (args.video.resolve(), args.weights.resolve()) or args.output.exists():
        parser.error('Usa una ruta de salida nueva, distinta al video y a los pesos.')
    if not torch.cuda.is_available():
        parser.error('CUDA no disponible. Ejecuta check_gpu.py.')
    device = torch.device('cuda:0')
    model = load_model(args.weights, device)
    rows = []
    started = time.perf_counter()
    with torch.inference_mode():
        for start, end, frames in windows(args.video, args.window_seconds):
            if len(frames) < 32:
                rows.append({'start_seconds': start, 'end_seconds': end,
                             'status': 'insufficient_frames', 'frames': len(frames)})
                continue
            inputs = tensor_from_frames(frames).to(device)
            torch.cuda.synchronize()
            tick = time.perf_counter()
            probabilities = model(inputs).softmax(dim=1)[0].cpu().tolist()
            elapsed = time.perf_counter() - tick
            row = {'start_seconds': start, 'end_seconds': end,
                   'status': 'scored', 'violence_score': probabilities[1],
                   'inference_seconds': elapsed, 'frames': len(frames)}
            rows.append(row)
            print(json.dumps(row), flush=True)
    with args.weights.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    report = {
        'experimental': True, 'validated_for_deployment': False,
        'model': 'visionlab-ai/r2plus1d_18', 'revision': MODEL_REVISION,
        'weights_sha256': digest, 'gpu': torch.cuda.get_device_name(0),
        'video': args.video.name, 'window_seconds': args.window_seconds,
        'preprocessing': '32 uniform RGB frames, resize 224x224, mean .45, std .225',
        'class_order_source': 'publisher README: non-violent=0, violent=1',
        'score_note': 'Salida del modelo; no es confirmación ni probabilidad calibrada.',
        'elapsed_seconds': time.perf_counter() - started,
        'peak_gpu_allocated_mib': torch.cuda.max_memory_allocated() / 1024**2,
        'windows': rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
    print(f'Resultado experimental guardado: {args.output}')


if __name__ == '__main__':
    main()
