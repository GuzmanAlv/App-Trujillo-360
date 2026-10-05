# Identidad Firebase → FastAPI → Supabase

GET /me recibe un Firebase ID token (no el token OAuth de Google). Verifica
firma, audiencia del proyecto, caducidad, emisor, UID, proveedor Google y correo
verificado mediante google-auth. No requiere clave privada de servicio.
La verificación consulta certificados públicos con un timeout de 10 segundos.
No consulta revocaciones ni cuentas deshabilitadas en Firebase en cada petición:
un token ya emitido puede seguir válido hasta expirar. La suspensión en
trujillo.users sí se revisa en cada petición y devuelve 403.

Configurar backend/.env.auth con FIREBASE_PROJECT_ID. El archivo está ignorado
por Git; usar .env.auth.example en otro equipo. Instalar requirements.txt y
ejecutar migrate.py para aplicar la migración 2. El runtime solo puede insertar
su identidad y consultar su fila mediante RLS; no puede asignar roles o estados.
La identidad se establece con set_config local a la transacción.

## Prueba con celular por USB

Desde backend:
```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

En otra terminal, desde la raíz del proyecto:
```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s L7VOEAX8TOHAVKIZ reverse tcp:8000 tcp:8000
flutter run -d L7VOEAX8TOHAVKIZ --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

En Configuración → Mi cuenta se conecta el perfil automáticamente al tener
sesión, incluso si la sesión se recupera al abrir la app. Actualizar conexión
permite reintentar sin cerrar sesión. Solo se confirma la conexión tras un 200.
Se renueva el token una vez si el servidor devuelve 401. No se siguen redirecciones.
El HTTP local se permite únicamente en debug y para localhost/127.0.0.1;
release requiere HTTPS. Repetir adb reverse si se desconecta el USB.

Consultar Supabase → esquema trujillo → tabla users: debe aparecer una fila por
UID de Firebase, incluso tras repetir la conexión. Los reportes se envían mediante
POST /reports; ver report-delivery.md y report-photos.md.

Pruebas: python -m pytest; python verify_identity_database.py (utiliza el rol
restringido; todas sus filas de prueba se revierten). La comprobación real del
token del usuario se hace desde el celular; no copiar tokens al chat ni a logs.
La prueba de aislamiento utiliza el rol restringido de .env.runtime.
