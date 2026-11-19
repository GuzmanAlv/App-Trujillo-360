"""Private operator assistance beacons. Citizen SOS routing takes precedence."""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime
from app.auth import identity
from app.workflows import execute
from app.sos_routes import RouteOrigin, compute_route

router = APIRouter(prefix='/operator/reinforcements')

class Position(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float = Field(ge=0, le=100)
    observed_at: AwareDatetime

class Request(Position):
    request_id: UUID

def private(response): response.headers['Cache-Control'] = 'private, no-store'

@router.get('')
def listing(response: Response, claims=Depends(identity)):
    private(response)
    return execute(claims, 'SELECT trujillo.reinforcement_list()', many=True)

@router.post('')
def request(data: Request, response: Response, claims=Depends(identity)):
    private(response)
    return execute(claims, 'SELECT trujillo.reinforcement_request(%s,%s,%s,%s,%s)',
                   (data.request_id,data.latitude,data.longitude,data.accuracy,data.observed_at))

@router.put('/{request_id}/position')
def position(request_id: UUID, data: Position, response: Response, claims=Depends(identity)):
    private(response)
    execute(claims, 'SELECT trujillo.reinforcement_position(%s,%s,%s,%s,%s)',
            (request_id,data.latitude,data.longitude,data.accuracy,data.observed_at))
    return {'status':'updated'}

@router.post('/{request_id}/close')
def close(request_id: UUID, response: Response, claims=Depends(identity)):
    private(response)
    execute(claims, 'SELECT trujillo.reinforcement_close(%s)', (request_id,))
    return {'status':'closed'}

@router.post('/{request_id}/route')
def route(request_id: UUID, origin: RouteOrigin, response: Response, claims=Depends(identity)):
    private(response)
    try:
        target = execute(claims, 'SELECT trujillo.reinforcement_destination(%s)', (request_id,))
    except HTTPException as error:
        if error.status_code == 409:
            raise HTTPException(409, {'code':'SOS_PRIORITY'}) from None
        if error.status_code == 404:
            raise HTTPException(410, {'code':'REINFORCEMENT_CLOSED'}) from None
        raise
    destination = {k:target[k] for k in ('latitude','longitude')}
    result = compute_route('reinforcement:'+str(request_id), origin, destination, claims, 'Refuerzos')
    result.pop('case_id', None)
    result['reinforcement_id'] = str(request_id)
    return result
