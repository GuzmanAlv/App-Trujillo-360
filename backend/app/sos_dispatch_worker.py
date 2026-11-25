"""Server clock for unanswered SOS and reassignment; independent of FCM settings."""
import asyncio
import logging
import threading
from aiohttp import ClientTimeout
from livekit import api
from app.db import connect
from app.calls import configuration

logger=logging.getLogger('uvicorn.error')

async def delete_room(room):
    url,key,secret=configuration()
    async with api.LiveKitAPI(url=url,api_key=key,api_secret=secret,timeout=ClientTimeout(total=8)) as client:
        try:
            await client.room.delete_room(api.DeleteRoomRequest(room=room))
        except api.TwirpError as error:
            if error.code!='not_found':raise

def dispatch_once():
    with connect() as conn:
        conn.execute('SELECT trujillo.sos_dispatch_tick()')

def cleanup_once():
    # Provider timeouts must never delay escalation or reassignment.
    for _ in range(2):
        with connect() as conn:
            room=conn.execute('SELECT trujillo.sos_cleanup_claim()').fetchone()[0]
        if not room:break
        try:
            asyncio.run(delete_room(room))
        except Exception:
            logger.warning('SOS_AUDIO_CLEANUP_RETRY')
            continue
        with connect() as conn:
            conn.execute('SELECT trujillo.sos_cleanup_finish(%s)',(room,))

class SosDispatchWorker:
    def __init__(self):
        self.stop=threading.Event()
        self.thread=None
        self.cleanup_thread=None
    def start(self):
        self.thread=threading.Thread(target=self.run,name='sos-dispatch',daemon=True)
        self.thread.start()
        self.cleanup_thread=threading.Thread(target=self.run_cleanup,name='sos-audio-cleanup',daemon=True)
        self.cleanup_thread.start()
    def run(self):
        while not self.stop.is_set():
            try:dispatch_once()
            except Exception:logger.warning('SOS_DISPATCH_RETRY')
            self.stop.wait(5)
    def run_cleanup(self):
        while not self.stop.is_set():
            try:cleanup_once()
            except Exception:logger.warning('SOS_AUDIO_CLEANUP_RETRY')
            self.stop.wait(5)
    def close(self):
        self.stop.set()
        if self.thread:self.thread.join(timeout=2)
        if self.cleanup_thread:self.cleanup_thread.join(timeout=2)
