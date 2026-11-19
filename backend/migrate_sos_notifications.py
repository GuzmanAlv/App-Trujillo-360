"""Apply SOS arrival/callback notifications (023). Default checks only."""
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
            if not conn.execute("SELECT to_regclass('trujillo.sos_arrival_samples') IS NOT NULL").fetchone()[0]:
                raise SystemExit('Primero aplica la migración 022.')
            if conn.execute("SELECT to_regprocedure('trujillo.push_register_sos(uuid,text)') IS NOT NULL").fetchone()[0]:
                print('Migración 023 ya instalada.');return
            if not args.apply:
                print('Migración 023 pendiente. Sin cambios.');return
            conn.execute((ROOT/'migrations/023_sos_attention_notifications.sql').read_text(encoding='utf-8'))
        print('Migración 023 aplicada en una transacción.')
    except (psycopg.Error,RuntimeError):
        raise SystemExit('No se pudo aplicar la migración; transacción revertida. Revisa conexión y permisos.') from None

if __name__=='__main__':main()
