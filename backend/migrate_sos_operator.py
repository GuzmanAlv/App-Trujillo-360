"""Apply only the operator SOS extension (019). Default checks without changes."""
import argparse
import psycopg
from app.db import ROOT,connect

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    try:
        with connect(admin=True) as conn:
            conn.execute('SELECT pg_advisory_xact_lock(360001)')
            if not conn.execute("SELECT to_regclass('trujillo.sos_cases') IS NOT NULL").fetchone()[0]:
                raise SystemExit('Primero aplica la migración 018.')
            if conn.execute("SELECT to_regprocedure('trujillo.return_calls()') IS NOT NULL").fetchone()[0]:
                print('Migración 019 ya instalada.'); return
            if not args.apply:
                print('Migración 019 pendiente. Sin cambios.'); return
            conn.execute((ROOT/'migrations/019_sos_operator_actions.sql').read_text(encoding='utf-8'))
        print('Migración 019 aplicada en una transacción.')
    except (psycopg.Error,RuntimeError):
        raise SystemExit('No se pudo aplicar la migración; transacción revertida. Revisa conexión y permisos.') from None
if __name__=='__main__': main()
