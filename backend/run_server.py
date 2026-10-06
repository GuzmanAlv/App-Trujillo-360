"""Windows task entry point: supervise local FastAPI and rotate diagnostic logs."""
import logging
from logging.handlers import RotatingFileHandler
import msvcrt
from pathlib import Path
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
LOGS = ROOT / 'logs'


def port_in_use():
    try:
        with socket.create_connection(('127.0.0.1', 8000), timeout=2):
            return True
    except OSError:
        return False


def main():
    LOGS.mkdir(exist_ok=True)
    # Windows releases the lock if the supervisor exits or is terminated.
    lock = (LOGS / 'supervisor.lock').open('a+b')
    lock.write(b'0')
    lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        lock.close()
        return
    handler = RotatingFileHandler(LOGS / 'server.log', maxBytes=2_000_000,
                                  backupCount=3, encoding='utf-8')
    logging.basicConfig(level=logging.INFO, handlers=[handler],
                        format='%(asctime)s %(levelname)s %(message)s')
    logging.info('Supervisor started; listening only on localhost:8000.')
    child = None
    waiting = False
    try:
        while True:
            if port_in_use():
                if not waiting:
                    logging.warning('Port 8000 already occupied; waiting without starting a duplicate.')
                waiting = True
                time.sleep(10)
                continue
            waiting = False
            logging.info('Starting FastAPI.')
            try:
                child = subprocess.Popen(
                    [str(Path(sys.executable).with_name('python.exe')), '-u', '-m', 'uvicorn', 'app.main:app',
                     '--host', '127.0.0.1', '--port', '8000'], cwd=ROOT,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, encoding='utf-8', errors='replace',
                    creationflags=subprocess.CREATE_NO_WINDOW)
                for line in child.stdout:
                    logging.info('%s', line.rstrip())
                code = child.wait()
                logging.error('FastAPI exited with code %s; retry in 10 seconds.', code)
            except OSError:
                logging.exception('Could not start FastAPI; retry in 10 seconds.')
            time.sleep(10)
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
        lock.close()


if __name__ == '__main__':
    main()
