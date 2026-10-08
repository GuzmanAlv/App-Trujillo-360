from unittest.mock import patch
from app.db import connect

CONFIG = dict(PGHOST='pooler', PGPORT='5432', PGDATABASE='postgres', PGUSER='restricted', PGPASSWORD='test', PGSSLMODE='require')

def test_render_environment_supplies_runtime_credentials():
    with patch('app.db.dotenv_values', return_value={}), patch.dict('os.environ', CONFIG, clear=True), patch('app.db.psycopg.connect') as db:
        connect()
    assert db.call_args.kwargs['user'] == 'restricted'
    assert db.call_args.kwargs['host'] == 'pooler'


def test_environment_does_not_replace_admin_credentials():
    with patch('app.db.dotenv_values', return_value={**CONFIG, 'PGUSER': 'admin'}), patch.dict('os.environ', CONFIG, clear=True), patch('app.db.psycopg.connect') as db:
        connect(admin=True)
    assert db.call_args.kwargs['user'] == 'admin'
