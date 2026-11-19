"""Apply only the citizen SOS follow-up (021). Default checks without changes."""
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
            if not conn.execute("SELECT to_regprocedure('trujillo.sos_map_call_status(uuid)') IS NOT NULL").fetchone()[0]:
                raise SystemExit('Primero aplica la migración 020.')
            if conn.execute("SELECT to_regclass('trujillo.sos_citizen_updates') IS NOT NULL").fetchone()[0]:
                print('Migración 021 ya instalada.'); return
            if not args.apply:
                print('Migración 021 pendiente. Sin cambios.'); return
            conn.execute((ROOT/'migrations/021_citizen_sos_updates.sql').read_text(encoding='utf-8'))
        print('Migración 021 aplicada en una transacción.')
    except (psycopg.Error,RuntimeError):
        raise SystemExit('No se pudo aplicar la migración; transacción revertida. Revisa conexión y permisos.') from None
if __name__=='__main__': main()
