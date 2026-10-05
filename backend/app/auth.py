import os
import time
import requests
from functools import partial
from dotenv import dotenv_values
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.auth import exceptions
from google.auth.transport.requests import Request
from google.oauth2 import id_token
from app.db import ROOT

bearer = HTTPBearer(auto_error=False)


def verify_token(token):
    project = os.getenv('FIREBASE_PROJECT_ID') or dotenv_values(ROOT / '.env.auth').get('FIREBASE_PROJECT_ID')
    if not project:
        raise HTTPException(503, 'Autenticación no configurada')
    # Public Firebase signing certificates suffice; no private service key needed.
    with requests.Session() as session:
        request = Request(session=session)
        claims = id_token.verify_firebase_token(
            token, partial(request, timeout=10), audience=project)
    if (claims.get('iss') != f'https://securetoken.google.com/{project}'
            or not isinstance(claims.get('sub'), str)
            or not 1 <= len(claims['sub']) <= 128
            or not claims['sub'].strip()
            or claims.get('firebase', {}).get('sign_in_provider') != 'google.com'
            or claims.get('email_verified') is not True
            or not isinstance(claims.get('auth_time'), (int, float))
            or claims['auth_time'] > time.time()):
        raise ValueError('Invalid identity')
    return claims


def identity(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if credentials is None or credentials.scheme.lower() != 'bearer' or len(credentials.credentials) > 16384:
        raise HTTPException(401, 'Sesión requerida', headers={'WWW-Authenticate': 'Bearer'})
    try:
        return verify_token(credentials.credentials)
    except exceptions.TransportError:
        raise HTTPException(503, 'No se pudo verificar la sesión') from None
    except (ValueError, exceptions.GoogleAuthError):
        raise HTTPException(401, 'Sesión inválida o vencida', headers={'WWW-Authenticate': 'Bearer'}) from None
