"""Persistent AI candidates for the operator pilot; no automatic publication."""
from typing import Literal
from datetime import datetime, timezone, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response
from psycopg.types.json import Jsonb
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator
from fastapi import Path

from app.auth import identity
from app.workflows import execute

router = APIRouter(prefix='/operator/ai', tags=['AI review'])


class Candidate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True, allow_inf_nan=False)
    schemaVersion: Literal[1]
    type: Literal['aggression_candidate']
    id: str = Field(min_length=1, max_length=200)
    cameraId: str = Field(min_length=1, max_length=200)
    modelVersion: str = Field(min_length=1, max_length=200)
    confidence: float = Field(ge=0, le=1, strict=True)
    latitude: float = Field(ge=-90, le=90, strict=True)
    longitude: float = Field(ge=-180, le=180, strict=True)
    detectedAt: AwareDatetime

    @field_validator('schemaVersion', mode='before')
    @classmethod
    def version_is_integer(cls, value):
        if type(value) is not int:
            raise ValueError('schemaVersion must be an integer')
        return value

    @field_validator('detectedAt', mode='before')
    @classmethod
    def timestamp_is_text(cls, value):
        if not isinstance(value, str):
            raise ValueError('detectedAt must be an ISO timestamp')
        return value

    @field_validator('detectedAt')
    @classmethod
    def timestamp_not_future(cls, value):
        if value > datetime.now(timezone.utc) + timedelta(minutes=5):
            raise ValueError('detectedAt is in the future')
        return value.astimezone(timezone.utc)


class Decision(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    decision: Literal['confirmed', 'discarded']
    reason: str = Field(min_length=5, max_length=500)


@router.post('/candidates')
def ingest(data: Candidate, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.submit_ai_candidate(%s)',
                   (Jsonb(data.model_dump(mode='json')),))


@router.get('/candidates')
def candidates(response: Response, before: int | None = Query(default=None, ge=1, le=9223372036854775807),
               limit: int = Query(default=50, ge=1, le=100), claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    rows = execute(claims, 'SELECT * FROM trujillo.list_ai_candidates(%s,%s)',
                   (before, limit + 1), many=True)
    return {'items': rows[:limit],
            'nextCursor': rows[limit - 1]['sequence'] if len(rows) > limit else None}


@router.post('/candidates/{sequence}/decisions')
def decide(sequence: Annotated[int, Path(ge=1, le=9223372036854775807)], data: Decision, response: Response, claims=Depends(identity)):
    response.headers['Cache-Control'] = 'private, no-store'
    return execute(claims, 'SELECT trujillo.review_ai_candidate(%s,%s,%s)',
                   (sequence, data.decision, data.reason))
