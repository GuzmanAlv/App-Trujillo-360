import logging
from unittest.mock import patch
import psycopg
import pytest
from fastapi.testclient import TestClient
from app.main import app


@pytest.mark.parametrize('error,reason', [
    (RuntimeError('Configuración de base incompleta'), 'configuracion_incompleta'),
    (RuntimeError('Migración pendiente'), 'migracion_pendiente'),
    (psycopg.OperationalError('password authentication failed: private-password'), 'credenciales_rechazadas'),
    (psycopg.OperationalError('Tenant or user not found: private-password'), 'usuario_o_proyecto_pooler_incorrecto'),
    (psycopg.OperationalError('could not translate host name: private-password'), 'host_no_resuelto'),
    (psycopg.OperationalError('connection timeout expired: private-password'), 'conexion_agoto_tiempo'),
    (psycopg.OperationalError('unknown private-password'), 'error_base_de_datos'),
])
def test_readiness_logs_only_safe_reason(error, reason, caplog):
    with caplog.at_level(logging.ERROR, logger='uvicorn.error'), patch('app.main.connect', side_effect=error):
        response = TestClient(app).get('/ready')
    assert response.status_code == 503
    assert 'READY_FAIL reason='+reason in caplog.text
    assert 'private-password' not in caplog.text
    assert 'private-password' not in response.text
    assert reason not in response.text
