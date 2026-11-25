"""Operator-only SOS evaluation. Public readers use a separate field allowlist."""
from typing import Literal
from uuid import UUID
from fastapi import APIRouter, Depends, Response, HTTPException
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime
from psycopg.types.json import Jsonb
from app.auth import identity
from app.workflows import execute

router = APIRouter(prefix='/operator')

class TakeCall(BaseModel):
    model_config=ConfigDict(extra='forbid')
    generation: UUID | None = None

@router.post('/sos-cases/{case_id}/take-call')
def take_call(case_id:UUID,data:TakeCall,response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT trujillo.take_sos_call(%s,%s)',(case_id,data.generation))

@router.post('/availability/online')
def availability_online(response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT trujillo.operator_begin_duty()')

@router.post('/availability/heartbeat')
def availability_heartbeat(response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT trujillo.operator_heartbeat(true)')

@router.post('/availability/offline')
def availability_offline(response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    result=execute(claims,'SELECT trujillo.operator_heartbeat(false)')
    execute(claims,'SELECT trujillo.sos_dispatch_tick()')
    return result

@router.post('/sos-cases/{case_id}/handoff')
def handoff(case_id:UUID,response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT trujillo.operator_handoff(%s)',(case_id,))

@router.get('/sos-map')
def map_cases(response: Response, claims=Depends(identity)):
    """Same authorized queue as Ayuda; publish only marker fields to operators."""
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.operator_sos_map_data()', many=True)

@router.post('/sos-cases/{case_id}/claim')
def claim(case_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.claim_sos(%s)', (case_id,))

class ArrivalPosition(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float = Field(ge=0)

class OperatorPosition(ArrivalPosition):
    observed_at: AwareDatetime
    accuracy: float = Field(ge=0,le=100)

@router.post('/position')
def position(data:OperatorPosition,response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT trujillo.operator_position(%s,%s,%s,%s)',
        (data.latitude,data.longitude,data.accuracy,data.observed_at))

@router.delete('/position')
def clear_position(response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    execute(claims,'SELECT trujillo.clear_operator_position()')
    return {'cleared':True}

@router.post('/sos-cases/{case_id}/heartbeat')
def heartbeat(case_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims, "SELECT jsonb_build_object('owned',trujillo.renew_sos_claim(%s))", (case_id,))

@router.post('/sos-cases/{case_id}/release')
def release(case_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    execute(claims, 'SELECT trujillo.release_sos_claim(%s)', (case_id,))
    return {'released': True}

class CaseUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    version: int = Field(ge=0)
    action: Literal['save','pending','confirm','discard','discard_block','en_route','on_scene','resolve','support','support_clear']
    category: Literal['Robo','Auxilio','Agresión','Riesgo']
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    place: str = Field(default='', max_length=100)
    public_description: str = Field(default='', max_length=500)
    internal_note: str = Field(default='', max_length=2000)
    outcome: str = Field(default='', max_length=1000)
    arrival_position: ArrivalPosition | None = None

class ArrivalCheck(ArrivalPosition):
    observed_at: AwareDatetime

@router.post('/sos-cases/{case_id}/arrival')
def arrival(case_id: UUID, data: ArrivalCheck, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.sos_arrival_check(%s,%s,%s,%s,%s)',
                   (case_id,data.latitude,data.longitude,data.accuracy,data.observed_at))

@router.get('/calls/incoming')
def incoming(response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.incoming_calls()', many=True)

@router.get('/sos-cases/{case_id}')
def read(case_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.sos_case_read(%s) || trujillo.sos_map_call_status(%s)', (case_id,case_id))

@router.post('/sos-cases/{case_id}')
def update(case_id: UUID, data: CaseUpdate, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    payload = data.model_dump(mode='json', exclude={'request_id','version'})
    try:
        return execute(claims,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',
                       (case_id,data.request_id,data.version,Jsonb(payload)))
    except HTTPException as error:
        if error.status_code == 409:
            raise HTTPException(409, 'El caso cambió o la transición no está disponible. Actualiza antes de continuar.') from None
        raise
