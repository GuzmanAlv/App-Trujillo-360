from datetime import datetime, timezone, timedelta
from typing import Literal
from uuid import UUID
import base64
import psycopg
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime, field_validator
from app.auth import identity
from app.db import connect
from app.photos import PhotoInput, normalize_photo
from psycopg.types.json import Jsonb
from psycopg.rows import dict_row

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
    photos: list[PhotoInput] = Field(default_factory=list, max_length=3)

    @field_validator('occurred_at')
    @classmethod
    def not_future(cls, value):
        if value > datetime.now(timezone.utc) + timedelta(minutes=5):
            raise ValueError('Fecha futura')
        return value

@router.post('/reports')
def submit_report(report: ReportInput, claims=Depends(identity)):
    try:
        if len({photo.id for photo in report.photos}) != len(report.photos):
            raise ValueError('Fotos duplicadas')
        photos = [normalize_photo(photo) for photo in report.photos]
    except ValueError:
        raise HTTPException(422, 'Fotos inválidas: JPEG o PNG, hasta tres de 2 MB') from None
    try:
        with connect() as conn:
            conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (claims['sub'],))
            name = str(claims.get('name') or 'Usuario').strip()[:100] or 'Usuario'
            conn.execute("""INSERT INTO trujillo.users(auth_provider,auth_subject,display_name)
                VALUES ('firebase',%s,%s) ON CONFLICT(auth_provider,auth_subject) DO NOTHING""", (claims['sub'],name))
            return conn.execute('SELECT trujillo.submit_report_with_photos(%s,%s,%s,%s,%s,%s,%s,%s)',
                (report.request_id, report.category, report.place, report.description,
                 report.latitude, report.longitude, report.occurred_at, Jsonb(photos))).fetchone()[0]
    except psycopg.errors.InsufficientPrivilege:
        raise HTTPException(403, 'Cuenta no disponible para reportar') from None
    except psycopg.errors.RaiseException:
        raise HTTPException(409, 'Identificador de envío reutilizado con datos diferentes') from None
    except (psycopg.errors.InvalidParameterValue, psycopg.errors.CheckViolation):
        raise HTTPException(422, 'Datos inválidos o reporte de más de siete días') from None
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo guardar el reporte') from None


@router.get('/reports/{report_id}')
def report_details(report_id: UUID, response: Response, claims=Depends(identity)):
    """Only the active owner can retrieve the report and its private photos."""
    try:
        with connect() as conn:
            conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (claims['sub'],))
            with conn.cursor(row_factory=dict_row) as cursor:
                cursor.execute('''SELECT r.id, r.request_id, r.category, r.place, r.description,
                    extensions.ST_Y(r.location::extensions.geometry) AS latitude,
                    extensions.ST_X(r.location::extensions.geometry) AS longitude,
                    r.occurred_at, r.received_at, i.status
                    FROM trujillo.reports r JOIN trujillo.incidents i ON i.id=r.incident_id
                    WHERE r.id=%s''', (report_id,))
                report = cursor.fetchone()
                if report is None:
                    raise HTTPException(404, 'Reporte no disponible')
                cursor.execute('SELECT id, content FROM trujillo.report_photos WHERE report_id=%s ORDER BY position', (report_id,))
                report['photos'] = [{'id': str(photo['id']), 'content_base64': base64.b64encode(photo['content']).decode('ascii')}
                                    for photo in cursor.fetchall()]
                response.headers['Cache-Control'] = 'private, no-store'
                return report
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo consultar el reporte') from None
