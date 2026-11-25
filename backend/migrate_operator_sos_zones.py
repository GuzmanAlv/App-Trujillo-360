"""Apply operator SOS zones (033). Default checks only."""
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
            if not conn.execute("SELECT to_regprocedure('trujillo.sos_navigation_target(uuid)') IS NOT NULL").fetchone()[0]:
                raise SystemExit('Primero aplica la migración 032.')
            if conn.execute("SELECT to_regprocedure('trujillo.operator_sos_map_data()') IS NOT NULL").fetchone()[0]:
                print('Migración 033 ya instalada.');return
            if not args.apply:
                print('Migración 033 pendiente. Sin cambios.');return
            conn.execute((ROOT/'migrations/033_operator_sos_zones.sql').read_text(encoding='utf-8'))
        print('Migración 033 aplicada en una transacción.')
    except (psycopg.Error,RuntimeError):
        raise SystemExit('No se pudo aplicar la migración; transacción revertida. Revisa conexión y permisos.') from None

if __name__=='__main__':main()
