from datetime import datetime, timezone, timedelta
from typing import Literal
from uuid import UUID
import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime, field_validator
from app.auth import identity
from app.db import connect

router = APIRouter()

class ReportInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    category: Literal['Robo', 'Auxilio', 'Agresión', 'Riesgo']
    place: str = Field(min_length=3, max_length=100)
    description: str = Field(default='', max_length=500)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    occurred_at: AwareDatetime

    @field_validator('occurred_at')
    @classmethod
    def not_future(cls, value):
        if value > datetime.now(timezone.utc) + timedelta(minutes=5):
            raise ValueError('Fecha futura')
        return value

@router.post('/reports')
def submit_report(report: ReportInput, claims=Depends(identity)):
    try:
        with connect() as conn:
            conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (claims['sub'],))
            name = str(claims.get('name') or 'Usuario').strip()[:100] or 'Usuario'
            conn.execute("""INSERT INTO trujillo.users(auth_provider,auth_subject,display_name)
                VALUES ('firebase',%s,%s) ON CONFLICT(auth_provider,auth_subject) DO NOTHING""", (claims['sub'],name))
            return conn.execute('SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)',
                (report.request_id, report.category, report.place, report.description,
                 report.latitude, report.longitude, report.occurred_at)).fetchone()[0]
    except psycopg.errors.InsufficientPrivilege:
        raise HTTPException(403, 'Cuenta no disponible para reportar') from None
    except psycopg.errors.RaiseException:
        raise HTTPException(409, 'Identificador de envío reutilizado con datos diferentes') from None
    except (psycopg.errors.InvalidParameterValue, psycopg.errors.CheckViolation):
        raise HTTPException(422, 'Datos inválidos o reporte de más de siete días') from None
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo guardar el reporte') from None
