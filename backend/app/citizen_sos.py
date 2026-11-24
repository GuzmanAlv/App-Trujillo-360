from uuid import UUID
from fastapi import APIRouter,Depends,Response,HTTPException,Query
from pydantic import BaseModel,ConfigDict,Field,AwareDatetime
from psycopg.types.json import Jsonb
from app.auth import identity
from app.workflows import execute
from app.photos import PhotoInput,normalize_photo

router=APIRouter()

class SosContribution(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    request_id: UUID
    description: str=Field(default='',max_length=1000)
    photos: list[PhotoInput]=Field(default_factory=list,max_length=3)

def private(response): response.headers['Cache-Control']='private, no-store'

class LivePosition(BaseModel):
    model_config=ConfigDict(extra='forbid',allow_inf_nan=False)
    latitude:float=Field(ge=-90,le=90)
    longitude:float=Field(ge=-180,le=180)
    accuracy:float=Field(ge=0,le=50)
    observed_at:AwareDatetime

@router.post('/my-sos/{case_id}/position')
def update_position(case_id:UUID,data:LivePosition,response:Response,claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.sos_live_position(%s,%s,%s,%s,%s)',
        (case_id,data.latitude,data.longitude,data.accuracy,data.observed_at))

@router.get('/my-sos')
def own_cases(response:Response,claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.citizen_sos_cases()',many=True)

@router.get('/incidents/nearby-sos')
def nearby_sos(response:Response,latitude:float=Query(ge=-90,le=90,allow_inf_nan=False),longitude:float=Query(ge=-180,le=180,allow_inf_nan=False),claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.nearby_sos(%s,%s)',(latitude,longitude),many=True)

@router.get('/my-sos/history')
def own_history(response:Response,limit:int=Query(default=50,ge=1,le=100),offset:int=Query(default=0,ge=0),claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.citizen_sos_history(%s,%s)',(limit,offset),many=True)

@router.get('/my-sos/{case_id}')
def own_case(case_id:UUID,response:Response,claims=Depends(identity)):
    private(response)
    rows=execute(claims,'SELECT trujillo.citizen_sos_cases(%s)',(case_id,),many=True)
    if not rows: raise HTTPException(404,'Caso no disponible')
    return rows[0]

@router.get('/sos-cases/{case_id}/contributions')
def contributions(case_id:UUID,response:Response,claims=Depends(identity)):
    private(response)
    return execute(claims,'SELECT trujillo.sos_citizen_evidence(%s)',(case_id,),many=True)

@router.post('/my-sos/{case_id}/contributions')
def contribute(case_id:UUID,data:SosContribution,response:Response,claims=Depends(identity)):
    private(response)
    try:
        if len({p.id for p in data.photos})!=len(data.photos): raise ValueError()
        photos=[normalize_photo(p) for p in data.photos]
    except ValueError: raise HTTPException(422,'Fotos inválidas: JPEG/PNG hasta 2 MB') from None
    return execute(claims,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',(case_id,data.request_id,data.description,Jsonb(photos)))

@router.get('/sos-cases/{case_id}/photos/{photo_id}')
def photo(case_id:UUID,photo_id:UUID,claims=Depends(identity)):
    content=bytes(execute(claims,'SELECT trujillo.sos_citizen_photo(%s,%s)',(case_id,photo_id)))
    return Response(content,media_type='image/jpeg',headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})
