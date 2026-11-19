"""Operator-only SOS evaluation. Public readers use a separate field allowlist."""
from typing import Literal
from uuid import UUID
from fastapi import APIRouter, Depends, Response, HTTPException
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime
from psycopg.types.json import Jsonb
from app.auth import identity
from app.workflows import execute

router = APIRouter(prefix='/operator')

@router.get('/sos-map')
def map_cases(response: Response, claims=Depends(identity)):
    """Same authorized queue as Ayuda; publish only marker fields to operators."""
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, '''SELECT jsonb_build_object(
        'id',h->>'id','latitude',c->'latitude','longitude',c->'longitude',
        'decision',c->'decision','attention',c->'attention','category',c->'category','can_track',c->'can_track',
        'support_requested',c->'support_requested','incident_id',c->'incident_id')
        || trujillo.sos_map_call_status((h->>'id')::uuid)
        FROM trujillo.list_help(true) h
        CROSS JOIN LATERAL (SELECT trujillo.sos_case_read((h->>'id')::uuid) AS c) details
        WHERE h->>'source'='sos' AND h->>'stage' NOT IN ('Cerrada','Descartada')''', many=True)

class ArrivalPosition(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float = Field(ge=0)

class CaseUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    version: int = Field(ge=0)
    action: Literal['save','pending','confirm','discard','en_route','on_scene','resolve','support','support_clear']
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
