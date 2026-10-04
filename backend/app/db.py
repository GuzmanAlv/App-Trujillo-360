from pathlib import Path
import psycopg
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]


def connect(admin=False):
    # No import-time network access. Administrative credentials are used only
    # by explicit migration commands, never by the HTTP application.
    env = dotenv_values(ROOT / ('.env' if admin else '.env.runtime'))
    fields = {'host': 'PGHOST', 'port': 'PGPORT', 'dbname': 'PGDATABASE',
              'user': 'PGUSER', 'password': 'PGPASSWORD', 'sslmode': 'PGSSLMODE'}
    if any(not env.get(key) for key in fields.values()):
        raise RuntimeError('Configuración de base incompleta')
    return psycopg.connect(**{key: env[value] for key, value in fields.items()},
                           connect_timeout=10, options='-c statement_timeout=10000')
