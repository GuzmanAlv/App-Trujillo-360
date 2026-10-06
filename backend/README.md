# Backend de Trujillo 360

Para mantenerlo activo en Windows y reconectar el celular por USB, consultar
[servidor local persistente](../docs/local-server.md).

FastAPI en la laptop y PostgreSQL/PostGIS en Supabase mediante Session pooler.
Incluye esquema, endpoints de salud y GET /me autenticado con Firebase.
POST /reports guarda reportes autenticados e incidentes pendientes; Flutter conserva
una copia local y permite reintentos sin duplicados. Publicación y corroboración
están pendientes. Ver [envío de reportes](../docs/report-delivery.md).
Consultar [la guía de conexión de identidad](../docs/firebase-fastapi.md).
Reportes con fotos opcionales y consulta de detalle: [guía de fotos](../docs/report-photos.md).
Aplicar `python migrate.py` para actualizar el esquema a la versión 4 antes de
iniciar esta versión del backend.

## Ejecutar

Desde la carpeta backend en PowerShell:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Abrir http://127.0.0.1:8000/docs. GET /health comprueba el proceso; GET /ready
verifica conexión y versión del esquema con un usuario limitado.
Para pruebas en Wi-Fi se puede cambiar el host a 0.0.0.0 y usar la IP local de
la laptop, permitiendo el puerto 8000 solo en la red privada de Windows.
La prueba actual de Flutter usa USB con adb reverse y localhost; no requiere cambiar
el firewall. El cliente solo permite HTTP local en debug; para Wi-Fi usar HTTPS.

## Configuración y permisos

.env contiene credenciales administrativas para migraciones; .env.runtime contiene
las credenciales del rol trujillo_api, generadas por migrate.py. Ambos están
excluidos de Git. El servidor HTTP solo carga .env.runtime. No incluirlos en el APK.
El rol lee la versión del esquema y crea/consulta el perfil de la identidad
validada con RLS. Puede ejecutar submit_report, pero no escribir directamente
en reports/incidents ni modificar roles o suspensiones.
TLS está habilitado con sslmode=require. Antes del despliegue público configurar
verify-full y el certificado CA correspondiente.

## Tablas en el esquema trujillo

- users: identidad del proveedor de login, nombre, rol y suspensión.
- incidents: categoría, punto PostGIS, fecha y estado del hecho agrupado.
- reports: observación individual, autor, ubicación, fecha y clave de reintento.
- reviews: decisión, operador, motivo y fecha.
- schema_migrations: versión aplicada.

RLS está habilitado; anon y authenticated no tienen acceso. Una cuenta solo
puede aportar una vez por incidente y request_id es único por usuario. Una revisión
requiere un operador o administrador activo. Hay índices espaciales y temporales.
Las relaciones no eliminan datos en cascada.

## Instalación y pruebas

En otro equipo, instalar Python 3.12 y ejecutar desde backend:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock.txt
```

Configurar credenciales locales antes de ejecutar:

```powershell
.\.venv\Scripts\python.exe migrate.py
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe verify_database.py
```

La migración es transaccional y usa un bloqueo para evitar ejecuciones simultáneas.
Repetirla no recrea las tablas. Requiere PostGIS en extensions y un esquema trujillo
libre en la primera ejecución. verify_database.py revierte todos los datos de prueba.

## Próxima etapa

Agregar límites de envío y recuperación del historial desde el servidor.
La agrupación transaccional y el paso de pending a corroborated con tres cuentas
ya están implementados; consultar [reglas y pruebas](../docs/corroboration.md).
Faltan consulta comunitaria del mapa y revisión auditada por operadores.
