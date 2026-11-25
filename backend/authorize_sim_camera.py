"""Explicit administrative camera permission; never shipped inside the app."""
import argparse

from app.db import connect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--email', required=True)
    parser.add_argument('--camera-id', default='phone-sim-1')
    parser.add_argument('--revoke', action='store_true')
    args = parser.parse_args()
    email, camera = args.email.strip().lower(), args.camera_id.strip()
    if email.count('@') != 1 or len(email) > 254 or not 1 <= len(camera) <= 200:
        parser.error('Correo o cámara inválidos')
    try:
        with connect(admin=True) as conn:
            if args.revoke:
                conn.execute('UPDATE trujillo.sim_camera_permissions SET enabled=false WHERE email=%s', (email,))
                conn.execute('UPDATE trujillo.sim_sessions s SET stopped=true FROM trujillo.users u WHERE s.owner_id=u.id AND u.auth_email=%s', (email,))
            else:
                conn.execute('INSERT INTO trujillo.operator_invitations(email,active) VALUES(%s,true) ON CONFLICT(email) DO UPDATE SET active=true', (email,))
                conn.execute("UPDATE trujillo.users SET role='operator' WHERE auth_email=%s AND role='citizen' AND status='active'", (email,))
                conn.execute('INSERT INTO trujillo.ai_cameras(id) VALUES(%s) ON CONFLICT(id) DO UPDATE SET active=true', (camera,))
                conn.execute('INSERT INTO trujillo.sim_camera_permissions(email,camera_id,enabled) VALUES(%s,%s,true) ON CONFLICT(email) DO UPDATE SET camera_id=excluded.camera_id,enabled=true', (email, camera))
                conn.execute('SELECT enabled FROM trujillo.sim_camera_permissions WHERE email=%s', (email,)).fetchone()
    except Exception:
        raise SystemExit('No se pudo guardar el permiso. Revisa credenciales administrativas y migración de simulación.') from None
    print('Permiso de simulación guardado. La cuenta debe iniciar sesión y verificar su perfil.')


if __name__ == '__main__':
    main()
