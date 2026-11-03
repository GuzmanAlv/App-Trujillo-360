# Backend en Render

Actualización 3/11/2026: el servicio srv-db41goei0phs73el3ms0 usa la rama
codex/notificaciones-fcm. Deploy dep-dbl0sfvf3r2c73850340, commit ad57a66,
confirmado Live. /ready devuelve schema_version 11, workflow_version 1 y
push_version 1. El envío FCM sigue deshabilitado por falta de credencial;
Google bloqueó su creación mediante iam.disableServiceAccountKeyCreation.
Ver docs/push-notifications.md. Continúa el plan Free.

Antes de desplegar: aplicar migrate.py desde la laptop con las credenciales administrativas. /ready debe responder schema_version 11. No ejecutar migraciones durante el arranque de Render.

Crear un Web Service conectado a este repositorio y rama. Runtime Python, Root Directory backend, Build Command pip install -r requirements.lock.txt, Start Command python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT, Health Check /ready. render.yaml contiene la misma configuración para Blueprint.

Variables del servicio: FIREBASE_PROJECT_ID del proyecto Android; PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD y PGSSLMODE de backend/.env.runtime. Usar el rol trujillo_api con el sufijo del proyecto para Session pooler. Nunca usar las credenciales administrativas de .env ni subir archivos de secretos al repositorio. PYTHON_VERSION=3.12.8. El backend lee estas variables sobre su configuración local.

Después de desplegar, abrir https://NOMBRE.onrender.com/ready. Compilar la app con --dart-define=BACKEND_URL=https://NOMBRE.onrender.com y --dart-define=MAPS_ENABLED=true. Un APK distribuible necesita además firma de release y configuración de Google Sign-In para esa firma.

Verificación final desde Android: iniciar sesión, comprobar perfil conectado, enviar un reporte y confirmar Enviado, actualizar Mis reportes desde otra instalación con la misma cuenta, comprobar aislamiento de otra cuenta, activar ubicación para Cerca de mí. Un resultado de /ready o una prueba transaccional de base de datos por sí solos no verifican el token y la conexión del teléfono.

Servicio configurado: https://trujillo-360-api.onrender.com (región Ohio).
APK de pruebas conectado a Render:
flutter build apk --debug --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com --dart-define=MAPS_ENABLED=true
El plan gratuito puede tardar al reactivarse; las consultas a Render esperan hasta 90 segundos. No requieren adb reverse ni servidor local.
