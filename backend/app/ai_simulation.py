"""Operator-only camera simulation. Cases never enter the public incident feed."""
import hashlib
import secrets
from typing import Literal
from uuid import UUID

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field

from app.auth import identity
from app.db import connect
from app.workflows import execute

router = APIRouter(prefix='/operator/ai/simulation', tags=['Camera simulation'])
worker_bearer = HTTPBearer(auto_error=False)


class SessionInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    cameraId: str = Field(min_length=1, max_length=200)
    latitude: float = Field(ge=-90, le=90, strict=True)
    longitude: float = Field(ge=-180, le=180, strict=True)


class EventInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    confidence: float = Field(ge=0, le=1, strict=True)
    modelVersion: str = Field(min_length=1, max_length=200)


class CaseDecision(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    stage: Literal['En revisión', 'Acción registrada', 'Cerrada', 'Descartada']
    reason: str = Field(min_length=5, max_length=500)


def no_cache(response):
    response.headers['Cache-Control'] = 'private, no-store'


@router.get('/config')
def config(response: Response, claims=Depends(identity)):
    no_cache(response)
    return execute(claims, 'SELECT trujillo.simulation_config()')


@router.post('/sessions')
def create_session(data: SessionInput, response: Response, claims=Depends(identity)):
    no_cache(response)
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    result = execute(claims, 'SELECT trujillo.create_sim_session(%s,%s,%s,%s)',
                     (data.cameraId, data.latitude, data.longitude, token_hash))
    return {**result, 'workerToken': token}


@router.post('/sessions/{session_id}/stop')
def stop_session(session_id: UUID, response: Response, claims=Depends(identity)):
    no_cache(response)
    return execute(claims, 'SELECT trujillo.stop_sim_session(%s)', (session_id,))


def worker_hash(credentials: HTTPAuthorizationCredentials | None = Depends(worker_bearer)):
    if credentials is None or credentials.scheme.lower() != 'bearer' or not 40 <= len(credentials.credentials) <= 128:
        raise HTTPException(401, 'Clave de simulación requerida')
    return hashlib.sha256(credentials.credentials.encode()).hexdigest()


@router.post('/sessions/{session_id}/events')
def receive(session_id: UUID, data: EventInput, response: Response, token_hash=Depends(worker_hash)):
    no_cache(response)
    try:
        with connect() as conn:
            return conn.execute('SELECT trujillo.receive_sim_event(%s,%s,%s,%s,%s)',
                (session_id, token_hash, data.request_id, data.confidence, data.modelVersion)).fetchone()[0]
    except psycopg.errors.InvalidAuthorizationSpecification:
        raise HTTPException(401, 'Clave de simulación inválida') from None
    except psycopg.errors.InsufficientPrivilege:
        raise HTTPException(403, 'Simulación no autorizada') from None
    except psycopg.errors.RaiseException:
        raise HTTPException(409, 'Sesión finalizada o solicitud reutilizada') from None
    except psycopg.errors.InvalidParameterValue:
        raise HTTPException(422, 'Datos de simulación inválidos') from None
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo registrar el análisis') from None


@router.get('/cases')
def cases(response: Response, claims=Depends(identity)):
    no_cache(response)
    return execute(claims, 'SELECT * FROM trujillo.sim_cases()', many=True)


@router.post('/cases/{case_id}/decisions')
def decide(case_id: UUID, data: CaseDecision, response: Response, claims=Depends(identity)):
    no_cache(response)
    return execute(claims, 'SELECT trujillo.review_sim_case(%s,%s,%s)', (case_id, data.stage, data.reason))
