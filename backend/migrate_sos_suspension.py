"""Apply SOS discard during travel and accountable citizen suspension (025). Default checks only."""
import argparse
import psycopg
from app.db import ROOT, connect

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    try:
        with connect(admin=True) as conn:
            conn.execute('SELECT pg_advisory_xact_lock(360001)')
            if not conn.execute("SELECT to_regprocedure('trujillo.reinforcement_destination(uuid)') IS NOT NULL").fetchone()[0]:
                raise SystemExit('Primero aplica la migración 024.')
            if conn.execute("SELECT to_regprocedure('trujillo.sos_suspension_version()') IS NOT NULL").fetchone()[0]:
                print('Migración 025 ya instalada.');return
            if not args.apply:
                print('Migración 025 pendiente. Sin cambios.');return
            conn.execute((ROOT/'migrations/025_sos_discard_and_suspend.sql').read_text(encoding='utf-8'))
        print('Migración 025 aplicada en una transacción.')
    except (psycopg.Error,RuntimeError):
        raise SystemExit('No se pudo aplicar la migración; transacción revertida. Revisa conexión y permisos.') from None

if __name__=='__main__':main()
