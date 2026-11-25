"""Private requests and operator actions. Authorization lives in database functions."""
from uuid import UUID
from typing import Literal
import psycopg
from fastapi import APIRouter, Depends, HTTPException, Response, Query
from pydantic import BaseModel, ConfigDict, Field
from app.auth import identity
from app.db import connect

router = APIRouter()

class HelpInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    category: Literal['Robo', 'Auxilio', 'Agresión', 'Riesgo']
    place: str = Field(min_length=3, max_length=100)
    description: str = Field(default='', max_length=500)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    priority: Literal['Baja', 'Media', 'Alta']

class SosInput(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    request_id: UUID
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)

class HelpDecision(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    stage: Literal['En revisión', 'Acción registrada', 'Cerrada', 'Descartada']
    priority: Literal['Baja', 'Media', 'Alta']
    reason: str = Field(min_length=5, max_length=500)

class IncidentDecision(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    decision: Literal['verified', 'discarded', 'closed']
    reason: str = Field(min_length=5, max_length=500)

def execute(claims, query, parameters=(), many=False):
    try:
        with connect() as conn:
            conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (claims['sub'],))
            name = str(claims.get('name') or 'Usuario').strip()[:100] or 'Usuario'
            conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,%s) ON CONFLICT(auth_provider,auth_subject) DO NOTHING", (claims['sub'], name))
            if claims.get('email') and claims.get('email_verified') is True:
                conn.execute('SELECT trujillo.sync_identity_email(%s)', (claims['email'],))
            cursor = conn.execute(query, parameters)
            result = [r[0] for r in cursor.fetchall()] if many else cursor.fetchone()[0]
        # Raised AFTER commit, so the limiter's counter survives the rejection.
        if isinstance(result,dict) and result.get('error_code')=='SOS_RATE_LIMIT':
            raise HTTPException(429,'Espera antes de iniciar otra llamada o un nuevo SOS. El caso actual sigue abierto.',
                headers={'Retry-After':str(result.get('retry_after',60))})
        return result
    except psycopg.errors.InsufficientPrivilege:
        raise HTTPException(403, 'Tu cuenta no tiene acceso a esta operación') from None
    except psycopg.errors.NoDataFound:
        raise HTTPException(404, 'Caso no disponible') from None
    except psycopg.errors.RaiseException:
        raise HTTPException(409, 'Identificador reutilizado con otros datos') from None
    except (psycopg.errors.InvalidParameterValue, psycopg.errors.CheckViolation):
        raise HTTPException(422, 'Datos o transición de estado inválidos') from None
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo completar la operación') from None

@router.post('/help-requests')
def submit(data: HelpInput, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',
        (data.request_id,data.category,data.place,data.description,data.latitude,data.longitude,data.priority))

@router.post('/sos')
def submit_sos(data: SosInput, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.submit_sos(%s,%s,%s)',
        (data.request_id,data.latitude,data.longitude))

@router.get('/help-requests')
def mine(response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT * FROM trujillo.list_help(false)', many=True)

@router.get('/operator/help-requests')
def inbox(response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT * FROM trujillo.list_help(true)', many=True)

@router.post('/operator/help-requests/{request_id}/decisions')
def decide_help(request_id: UUID, data: HelpDecision, claims=Depends(identity)):
    execute(claims, 'SELECT trujillo.update_help(%s,%s,%s,%s)', (request_id,data.stage,data.priority,data.reason))
    return {'status': 'saved'}

@router.get('/operator/incidents')
def incidents(response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT * FROM trujillo.operator_incidents()', many=True)

@router.get('/operator/incidents/{incident_id}/reports')
def evidence(incident_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    return execute(claims,'SELECT * FROM trujillo.operator_incident_reports(%s)',(incident_id,),many=True)

@router.get('/operator/incidents/{incident_id}/photos/{photo_id}')
def photo(incident_id: UUID,photo_id: UUID,claims=Depends(identity)):
    content=bytes(execute(claims,'SELECT trujillo.operator_photo(%s,%s)',(incident_id,photo_id)))
    return Response(content=content,media_type='image/jpeg',headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})

@router.post('/operator/incidents/{incident_id}/decisions')
def decide_incident(incident_id: UUID, data: IncidentDecision, claims=Depends(identity)):
    execute(claims, 'SELECT trujillo.review_incident(%s,%s,%s)', (incident_id,data.decision,data.reason))
    return {'status': 'saved'}

@router.get('/incidents/density')
def density(response: Response,
    south: float = Query(ge=-90,le=90,allow_inf_nan=False), north: float = Query(ge=-90,le=90,allow_inf_nan=False),
    west: float = Query(ge=-180,le=180,allow_inf_nan=False), east: float = Query(ge=-180,le=180,allow_inf_nan=False),
    hour_band: int = Query(default=-1,ge=-1,le=3), claims=Depends(identity)):
    if south>north:
        raise HTTPException(422,'Área inválida')
    response.headers['Cache-Control']='private, no-store'
    return execute(claims, "SELECT jsonb_build_object('latitude',latitude,'longitude',longitude,'count',incident_count) FROM trujillo.incident_density(%s,%s,%s,%s,%s)", (south,north,west,east,hour_band), many=True)
