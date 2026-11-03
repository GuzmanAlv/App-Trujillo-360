"""Administrative invitation. Never included in the app or exposed as an endpoint."""
import argparse
from app.db import connect

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--email',required=True)
    parser.add_argument('--revoke',action='store_true')
    args=parser.parse_args()
    email=args.email.strip().lower()
    if email.count('@')!=1 or len(email)>254:
        raise SystemExit('Correo inválido')
    try:
        with connect(admin=True) as conn:
            conn.execute('INSERT INTO trujillo.operator_invitations(email,active) VALUES(%s,%s) ON CONFLICT(email) DO UPDATE SET active=excluded.active', (email,not args.revoke))
            if args.revoke:
                conn.execute("UPDATE trujillo.users SET role='citizen' WHERE auth_email=%s AND role='operator'",(email,))
            else:
                conn.execute("UPDATE trujillo.users SET role='operator' WHERE auth_email=%s AND role='citizen' AND status='active'", (email,))
    except Exception:
        raise SystemExit('No se pudo registrar la autorización. Revisa migración y conexión.') from None
    print('Autorización registrada. La cuenta debe iniciar sesión y actualizar su perfil.')

if __name__=='__main__': main()
