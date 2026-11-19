"""Operator-only Google Routes proxy. Key and arbitrary destinations never reach clients."""
import math
import os
import re
import threading
import time
from datetime import datetime,timezone
from uuid import UUID
import requests
from fastapi import APIRouter,Depends,HTTPException,Response
from pydantic import BaseModel,ConfigDict,Field
from app.auth import identity
from app.workflows import execute

router=APIRouter(prefix='/operator/sos-cases')
_lock=threading.Lock()
_recent={}

class RouteOrigin(BaseModel):
    model_config=ConfigDict(extra='forbid',allow_inf_nan=False)
    latitude:float=Field(ge=-90,le=90)
    longitude:float=Field(ge=-180,le=180)

def failure(status,code):raise HTTPException(status,{'code':code})

@router.post('/{case_id}/route')
def route(case_id:UUID,origin:RouteOrigin,response:Response,claims=Depends(identity)):
    response.headers['Cache-Control']='private, no-store'
    case=execute(claims,'SELECT trujillo.sos_case_read(%s)',(case_id,))
    if not case.get('can_edit'):raise HTTPException(403,'Caso asignado a otro operador')
    if case['decision']!='confirmed' or case['attention']=='resolved':failure(409,'ROUTE_CLOSED')
    key=os.getenv('GOOGLE_ROUTES_API_KEY','').strip()
    if not key:failure(503,'ROUTES_NOT_CONFIGURED')
    # Small per-process throttle, after authorization. No coordinate or response cache.
    now=time.monotonic();identity_key=(claims['sub'],str(case_id))
    with _lock:
        for old in [k for k,v in _recent.items() if now-v>60]:_recent.pop(old,None)
        if identity_key in _recent and now-_recent[identity_key]<10:failure(429,'ROUTES_RATE_LIMIT')
        if len(_recent)>=1024:_recent.pop(next(iter(_recent)))
        _recent[identity_key]=now
    destination={'latitude':case['latitude'],'longitude':case['longitude']}
    body={'origin':{'location':{'latLng':origin.model_dump()}},
        'destination':{'location':{'latLng':destination}},'travelMode':'DRIVE',
        'routingPreference':'TRAFFIC_AWARE_OPTIMAL','computeAlternativeRoutes':True,
        'polylineQuality':'OVERVIEW','languageCode':'es','units':'METRIC'}
    try:
        result=requests.post('https://routes.googleapis.com/directions/v2:computeRoutes',json=body,
            headers={'X-Goog-Api-Key':key,'X-Goog-FieldMask':'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline'},
            timeout=(3,15),allow_redirects=False)
        if result.status_code!=200:failure(503,'ROUTES_REJECTED')
        routes=result.json().get('routes',[])
        valid=[]
        for candidate in routes[:4]:
            duration=str(candidate.get('duration',''))
            polyline=candidate.get('polyline',{}).get('encodedPolyline','')
            distance=candidate.get('distanceMeters')
            if not re.fullmatch(r'\d+(\.\d+)?s',duration) or not isinstance(polyline,str) or not polyline or len(polyline)>200000:continue
            seconds=float(duration[:-1])
            if not math.isfinite(seconds) or seconds<0 or not isinstance(distance,(int,float)) or not math.isfinite(distance) or distance<0:continue
            valid.append((seconds,distance,polyline))
        if not valid:failure(422,'ROUTE_NOT_FOUND')
        seconds,distance,polyline=min(valid,key=lambda r:r[0])
        return {'case_id':str(case_id),'origin':origin.model_dump(),'destination':destination,
            'duration_seconds':seconds,'distance_meters':distance,'encoded_polyline':polyline,
            'calculated_at':datetime.now(timezone.utc).isoformat(),'category':case['category']}
    except (requests.RequestException,ValueError,TypeError,AttributeError):failure(503,'ROUTES_UNAVAILABLE')
