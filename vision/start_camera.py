"""One-click launcher for the RTX; session credentials are entered on the phone."""
import json
from pathlib import Path
import subprocess
import sys
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent


def main():
    tailscale = Path('C:/Program Files/Tailscale/tailscale.exe')
    if not tailscale.is_file():
        raise SystemExit('Instala e inicia sesión en Tailscale en esta laptop.')
    try:
        with urlopen('http://127.0.0.1:8765/health', timeout=2) as response:
            health = json.load(response)
    except OSError:
        health = None
    if health:
        raise SystemExit('Ya hay un servicio de cámara abierto. Usa esa ventana, o ciérrala con Ctrl+C antes de abrir el nuevo iniciador.')
    result = subprocess.run([str(tailscale), 'status', '--json'], capture_output=True, text=True, check=True)
    status = json.loads(result.stdout)
    if status.get('BackendState') != 'Running':
        raise SystemExit('Inicia sesión en Tailscale y vuelve a abrir este iniciador.')
    dns = status.get('Self', {}).get('DNSName', '').rstrip('.')
    if not dns or not dns.endswith('.ts.net'):
        raise SystemExit('La RTX no tiene una dirección privada HTTPS de Tailscale.')
    subprocess.run([str(tailscale), 'serve', '--bg', 'http://127.0.0.1:8765'], check=True)
    subprocess.run([sys.executable, '-u', str(ROOT / 'simulation_camera.py'),
                    '--standby', '--qr', '--api-base', 'https://trujillo-360-api.onrender.com',
                    '--public-origin', 'https://' + dns], check=True)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (subprocess.CalledProcessError, ValueError):
        raise SystemExit('No se pudo iniciar la cámara. Revisa el mensaje anterior y la conexión de Tailscale.') from None
