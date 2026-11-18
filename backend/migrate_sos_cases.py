"""Install only migration 018 on an existing deployment; never prints credentials.

Default is read-only. Run with --apply after reviewing the migration.
"""
import argparse
import psycopg
from app.db import ROOT, connect

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    try:
        with connect(admin=True) as conn:
            if args.apply:
                conn.execute('SELECT pg_advisory_xact_lock(360001)')
            if not conn.execute("SELECT to_regprocedure('trujillo.call_action(uuid,text)') IS NOT NULL").fetchone()[0]:
                raise RuntimeError('Falta la migración 017 de llamadas.')
            if conn.execute("SELECT to_regclass('trujillo.sos_cases') IS NOT NULL").fetchone()[0]:
                if not conn.execute("SELECT to_regprocedure('trujillo.sos_case_update(uuid,uuid,integer,jsonb)') IS NOT NULL").fetchone()[0]:
                    raise RuntimeError('La migración está incompleta. Requiere revisión manual.')
                print('Casos SOS ya instalados; no se realizaron cambios.')
                return
            if not args.apply:
                print('Llamadas instaladas. Migración 018 pendiente. No se realizaron cambios.')
                return
            conn.execute((ROOT/'migrations/018_sos_cases.sql').read_text(encoding='utf-8'))
        print('Migración 018 aplicada en una transacción.')
    except psycopg.Error:
        raise SystemExit('No se pudo comprobar o aplicar la migración. La transacción se revirtió; revisa conexión y permisos.') from None
    except RuntimeError as error:
        raise SystemExit(str(error)) from None

if __name__=='__main__':
    main()
