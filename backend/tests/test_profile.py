from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

def test_profile_and_suspension():
    app.dependency_overrides[identity] = lambda: {'sub': 'uid', 'name': 'Ana'}
    try:
        for status, expected in [('active', 200), ('suspended', 403)]:
            connection = MagicMock()
            connection.__enter__.return_value = connection
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.fetchone.return_value = dict(id='id', display_name='Ana', role='citizen', status=status, created_at='now')
            with patch('app.main.connect', return_value=connection):
                response = TestClient(app).get('/me')
            assert response.status_code == expected
    finally:
        app.dependency_overrides.clear()
