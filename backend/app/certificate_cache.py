"""Cache Google's public Firebase certificates, never identities or ID tokens."""
import json
import re
import threading
import time
from dataclasses import dataclass

CERTS_URL='https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com'

@dataclass(frozen=True)
class CertificateResponse:
    status:int
    data:bytes
    headers:dict

class CertificateCache:
    def __init__(self,clock=time.monotonic):
        self.clock=clock
        self.lock=threading.Lock()
        self.response=None
        self.until=0
    def request(self,fetch,url,method='GET',**kwargs):
        if url!=CERTS_URL or method.upper()!='GET':return fetch(url,method=method,**kwargs)
        with self.lock:
            if self.response is not None and self.clock()<self.until:return self.response
            response=fetch(url,method=method,**kwargs)
            headers={k.lower():v for k,v in response.headers.items()}
            control=headers.get('cache-control','').lower()
            age=re.search(r'(?:^|,)\s*max-age=(\d+)',control)
            if response.status==200 and age and 'no-store' not in control and 'no-cache' not in control:
                try:
                    if not isinstance(json.loads(response.data),dict):return response
                    ttl=max(0,min(3600,int(age[1]))-int(headers.get('age','0')))
                except (ValueError,TypeError):return response
                self.response=CertificateResponse(response.status,bytes(response.data),dict(response.headers))
                self.until=self.clock()+ttl
            return response

certificate_cache=CertificateCache()
