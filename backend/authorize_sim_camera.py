"""Explicit administrative camera permission; never shipped inside the app."""
import argparse

from app.db import connect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--email', required=True)
    parser.add_argument('--camera-id', default='phone-sim-1')
    parser.add_argument('--revoke', action='store_true')
    parser.add_argument('--replace-email', help='Transfer this existing camera permission to --email')
    args = parser.parse_args()
    email, camera = args.email.strip().lower(), args.camera_id.strip()
    previous = args.replace_email.strip().lower() if args.replace_email else None
    if email.count('@') != 1 or len(email) > 254 or not 1 <= len(camera) <= 200:
        parser.error('Correo o cámara inválidos')
    if previous and (previous.count('@') != 1 or len(previous) > 254 or previous == email or args.revoke):
        parser.error('Correo anterior inválido o incompatible con --revoke')
    try:
        with connect(admin=True) as conn:
            if args.revoke:
                conn.execute('UPDATE trujillo.sim_camera_permissions SET enabled=false WHERE email=%s', (email,))
                conn.execute('UPDATE trujillo.sim_sessions s SET stopped=true FROM trujillo.users u WHERE s.owner_id=u.id AND u.auth_email=%s', (email,))
            else:
                if previous:
                    # Keep camera ownership unique and revoke running sessions in
                    # the same transaction. Never change the previous user's role.
                    conn.execute('LOCK TABLE trujillo.sim_camera_permissions IN SHARE ROW EXCLUSIVE MODE')
                    old = conn.execute('SELECT camera_id,threshold FROM trujillo.sim_camera_permissions WHERE email=%s', (previous,)).fetchone()
                    if old:
                        if old[0] != camera:
                            raise ValueError('La cámara indicada no corresponde al permiso anterior')
                        conn.execute('UPDATE trujillo.sim_sessions s SET stopped=true FROM trujillo.users u WHERE s.owner_id=u.id AND u.auth_email=%s AND NOT s.stopped', (previous,))
                        conn.execute('DELETE FROM trujillo.sim_camera_permissions WHERE email=%s', (previous,))
                        conn.execute('INSERT INTO trujillo.sim_camera_permissions(email,camera_id,threshold,enabled) VALUES(%s,%s,%s,true) ON CONFLICT(email) DO UPDATE SET camera_id=excluded.camera_id,threshold=excluded.threshold,enabled=true', (email,camera,old[1]))
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
