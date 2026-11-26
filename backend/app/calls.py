"""LiveKit credentials never leave this service; join grants are room-scoped."""
import os
from datetime import timedelta
from uuid import UUID
from urllib.parse import urlparse
from fastapi import APIRouter, Depends, HTTPException, Response
from starlette.concurrency import run_in_threadpool
from aiohttp import ClientTimeout
from livekit import api
from app.auth import identity
from app.workflows import execute
from pydantic import BaseModel,ConfigDict,Field

router = APIRouter(prefix='/calls')

class RoomGuard(BaseModel):
    model_config=ConfigDict(extra='forbid')
    room:str | None=Field(default=None,max_length=120)

def configuration():
    url = os.environ.get('LIVEKIT_URL', '').strip()
    key = os.environ.get('LIVEKIT_API_KEY', '').strip()
    secret = os.environ.get('LIVEKIT_API_SECRET', '').strip()
    parsed = urlparse(url)
    if parsed.scheme != 'wss' or not parsed.hostname or parsed.username or not key or not secret:
        raise HTTPException(503, 'Las llamadas todavía no están configuradas. Tu SOS sigue disponible.')
    return url, key, secret

def action(call_id, operation, claims):
    try:
        return execute(claims, 'SELECT trujillo.call_action(%s,%s)', (call_id, operation))
    except HTTPException as error:
        if error.status_code == 409:
            raise HTTPException(409, 'La llamada ya fue atendida, terminó o tienes otra llamada activa.') from None
        raise

def private(response):
    response.headers['Cache-Control'] = 'private, no-store'

@router.post('/{call_id}/start')
def start(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    configuration()
    result = action(call_id, 'start', claims)
    result.pop('participant', None)
    return result

@router.post('/{call_id}/redial')
def redial(call_id:UUID,response:Response,claims=Depends(identity)):
    private(response)
    configuration()
    result=execute(claims,'SELECT trujillo.citizen_call_operator(%s)',(call_id,))
    result.pop('participant',None)
    return result

@router.get('/incoming/assigned')
def assigned_calls(response:Response,claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.assigned_incoming_calls()',many=True)

@router.get('/{call_id}')
def status(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    result = action(call_id, 'status', claims)
    result.pop('participant', None)
    return result

@router.post('/{call_id}/accept')
def accept(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    configuration()
    result=execute(claims,'SELECT trujillo.take_sos_call(%s,NULL)',(call_id,))
    if not result['call_accepted']:raise HTTPException(409,{'code':'SOS_CALL_CHANGED'})
    return result['call']

@router.post('/{call_id}/heartbeat')
def heartbeat(call_id:UUID,response:Response,claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.call_heartbeat(%s)',(call_id,))

@router.post('/{call_id}/token')
def token(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    url, key, secret = configuration()
    result = action(call_id, 'token', claims)
    grant = api.VideoGrants(room_join=True, room=result['room'],
        can_publish=True, can_subscribe=True, can_publish_data=False,
        can_publish_sources=['microphone'])
    jwt = (api.AccessToken(key, secret).with_identity(result['participant'])
           .with_ttl(timedelta(seconds=60)).with_grants(grant).to_jwt())
    return {'url': url, 'token': jwt, 'room':result['room']}

@router.post('/{call_id}/end')
async def end(call_id: UUID, response: Response, data:RoomGuard=RoomGuard(), claims=Depends(identity)):
    private(response)
    generation=None
    if data.room:
        prefix='sos-'+str(call_id)+'-'
        try:
            if not data.room.startswith(prefix):raise ValueError()
            generation=UUID(data.room[len(prefix):])
        except ValueError:raise HTTPException(422,'Sala no válida para este SOS') from None
    result=await run_in_threadpool(execute,claims,'SELECT trujillo.end_call_generation(%s,%s)',(call_id,generation))
    result.pop('participant', None)
    # Mark ended before contacting LiveKit: no further tokens may be issued.
    url, key, secret = configuration()
    try:
        async with api.LiveKitAPI(url=url, api_key=key, api_secret=secret, timeout=ClientTimeout(total=10)) as client:
            await client.room.delete_room(api.DeleteRoomRequest(room=result['room']))
    except api.TwirpError as error:
        if error.code != 'not_found':
            raise HTTPException(503, 'Cierre de audio pendiente. Vuelve a pulsar Finalizar.') from None
    except Exception:
        raise HTTPException(503, 'Cierre de audio pendiente. Vuelve a pulsar Finalizar.') from None
    return result

@router.post('/{call_id}/callback')
def callback(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    configuration()
    result = action(call_id, 'callback', claims)
    result.pop('participant', None)
    return result

@router.post('/{call_id}/answer')
def answer(call_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    configuration()
    result = action(call_id, 'answer', claims)
    result.pop('participant', None)
    return result

@router.get('/incoming/return')
def return_calls(response: Response, claims=Depends(identity)):
    private(response)
    return execute(claims, 'SELECT trujillo.return_calls()', many=True)
