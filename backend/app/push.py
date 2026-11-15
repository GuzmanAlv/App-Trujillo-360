"""Authenticated device preferences; tokens never appear in API responses."""
from uuid import UUID
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator
from fastapi import APIRouter, Depends, Response
from app.auth import identity
from app.workflows import execute
from app.push_worker import configured

router = APIRouter(prefix='/push')

class DeviceInput(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    token: str = Field(min_length=20, max_length=4096)
    citizen_enabled: bool = False
    operator_enabled: bool = False
    moving_enabled: bool = False
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    radius: int = Field(default=500, ge=100, le=3000)

    @model_validator(mode='after')
    def area_required(self):
        if self.citizen_enabled and (self.latitude is None or self.longitude is None):
            raise ValueError('Falta la ubicación actual')
        if self.moving_enabled and not self.citizen_enabled:
            raise ValueError('Activa los avisos para seguir tu ubicación')
        return self

class LocationInput(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)

@router.get('/devices/{device_id}')
def preferences(device_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    result = execute(claims, 'SELECT trujillo.push_preferences(%s)', (device_id,))
    return {'preferences': result, 'sender_configured': configured()}

@router.put('/devices/{device_id}')
def register(device_id: UUID, data: DeviceInput, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    result = execute(claims, 'SELECT trujillo.push_register(%s,%s,%s,%s,%s,%s,%s,%s)',
        (device_id,data.token,data.citizen_enabled,data.operator_enabled,data.latitude,data.longitude,data.radius,data.moving_enabled))
    return {'preferences': result, 'sender_configured': configured()}

@router.put('/devices/{device_id}/location')
def update_location(device_id: UUID, data: LocationInput, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    execute(claims, 'SELECT trujillo.push_update_location(%s,%s,%s)',
        (device_id,data.latitude,data.longitude))
    return {'status':'updated'}

@router.delete('/devices/{device_id}')
def remove(device_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    execute(claims, 'SELECT trujillo.push_remove(%s)', (device_id,))
    return {'status':'removed'}

@router.get('/targets/{kind}/{target_id}')
def target(kind: Literal['citizen','operator_help','operator_incident'], target_id: UUID, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.push_target(%s,%s)', (kind,target_id))
