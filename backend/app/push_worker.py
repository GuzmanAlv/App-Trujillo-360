"""Durable outbox delivery via FCM HTTP v1. No private keys or tokens in logs."""
import json
import logging
import os
import threading
from pathlib import Path
from dotenv import dotenv_values
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from app.db import ROOT, connect

logger = logging.getLogger('uvicorn.error')
SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

def settings():
    return {**dotenv_values(ROOT / '.env.push'), **os.environ}

def credentials():
    env = settings()
    project = env.get('FIREBASE_PROJECT_ID') or dotenv_values(ROOT / '.env.auth').get('FIREBASE_PROJECT_ID')
    raw = env.get('FIREBASE_SERVICE_ACCOUNT_JSON')
    path = env.get('GOOGLE_APPLICATION_CREDENTIALS') or str(ROOT / '.secrets/fcm-service-account.json')
    info = json.loads(raw) if raw else json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not project or info.get('project_id') != project:
        raise ValueError('Proyecto de mensajería no coincide')
    return project, service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])

def configured():
    if str(settings().get('PUSH_ENABLED','false')).lower() != 'true':
        return False
    try:
        credentials()
        return True
    except (ValueError, OSError, KeyError):
        return False

def message(job):
    data = {key:str(job[key]) for key in ('kind','target_id','account_uid')}
    data['event_id'] = str(job['job_id'])
    if 'incident' in job:
        data['incident'] = job['incident']
    title, body = job['title'], job['body']
    if job['kind'] == 'citizen':
        category = body.partition('.')[0].strip()
        moving = job.get('moving') is True
        title = f'🚨 Alerta: {category} cerca de ti' if category and moving else f'🚨 Alerta: {category} en tu zona' if category else '🚨 Incidente cerca de ti' if moving else '🚨 Incidente en tu zona'
        body = ('Se confirmó un reporte cerca de tu ubicación reciente. ' if moving else
                'Se confirmó un reporte cerca de tu zona configurada. ') + 'Toca para ver los detalles.'
    return {'message': {
        'token':job['token'], 'notification':{'title':title,'body':body},
        'data': data,
        'android': {'priority':'high', 'ttl':'300s', 'notification':{
            'channel_id':'trujillo_push', 'icon':'ic_notification', 'color':'#D32F2F',
            'tag':str(job['job_id']), 'visibility':'PRIVATE', 'click_action':'FLUTTER_NOTIFICATION_CLICK'}},
    }}

def outcome(response):
    if response.status_code == 200:
        return 'sent'
    try:
        details = response.json().get('error',{}).get('details',[])
        if any(d.get('errorCode') == 'UNREGISTERED' for d in details):
            return 'unregistered'
    except (ValueError, AttributeError, TypeError):
        pass
    # Authorization/configuration failures are retryable, never invalidate devices.
    return 'retry' if response.status_code in (401,403,408,429) or response.status_code >= 500 else 'permanent'

def deliver_one(session, project):
    with connect() as conn:
        job = conn.execute('SELECT trujillo.push_claim()').fetchone()[0]
    if not job:
        return False
    if job.get('skipped'):
        return True
    result = 'retry'
    try:
        response = session.post(f'https://fcm.googleapis.com/v1/projects/{project}/messages:send',
            json=message(job), timeout=20)
        result = outcome(response)
    except Exception:
        logger.warning('PUSH_SEND retry')
    with connect() as conn:
        conn.execute('SELECT trujillo.push_finish(%s,%s,%s)',(job['job_id'],job['lease'],result))
    return True

class PushWorker:
    def __init__(self):
        self.stop = threading.Event()
        self.thread = None

    def start(self):
        if not configured():
            logger.info('PUSH_DISABLED missing_configuration')
            return
        self.thread = threading.Thread(target=self.run, name='push-outbox', daemon=True)
        self.thread.start()

    def run(self):
        project, auth = credentials()
        with AuthorizedSession(auth) as session:
            while not self.stop.is_set():
                try:
                    for _ in range(20):
                        if self.stop.is_set() or not deliver_one(session, project):
                            break
                except Exception:
                    logger.warning('PUSH_WORKER retry')
                self.stop.wait(10)

    def close(self):
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=2)
