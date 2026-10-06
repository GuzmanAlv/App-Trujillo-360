from unittest.mock import patch
import psycopg
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from test_reports import payload

def test_same_user_conflict_is_explained():
    app.dependency_overrides[identity] = lambda: {'sub':'uid'}
    try:
        with patch('app.reports.connect', side_effect=psycopg.errors.NoDataFound()):
            response=TestClient(app).post('/reports',json=payload())
        assert response.status_code==409
        assert 'solo cuenta una vez' in response.json()['detail']
    finally:
        app.dependency_overrides.clear()
