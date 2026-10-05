# Envío de reportes del piloto

POST /reports requiere un Firebase ID token de Google y una cuenta activa.
El autor se obtiene del token, nunca del formulario. El servidor crea el perfil
si todavía no existe. La migración 003 habilita una función transaccional con
permisos restringidos al rol del backend; anon/authenticated no pueden invocarla.

Se validan categoría, texto, coordenadas y fecha con zona horaria. Los reportes
nuevos deben tener como máximo siete días y no más de cinco minutos de adelanto.
El reporte y su incidente pendiente se insertan juntos o ninguno se guarda.
Cada envío nuevo crea un incidente pendiente; no hay agrupación ni corroboración
automática todavía. No se asignan operadores ni se publican a otros usuarios.

Flutter exige login y guarda primero una copia con UID propietario e identificador
UUID. Solo tras recibir un 200 válido muestra Enviado. Si falla la conexión, el
reporte persiste como Pendiente de envío incluso al reiniciar. Abrir sus detalles
y pulsar Reintentar envío reutiliza el mismo UUID y contenido. Solo su cuenta
original puede enviarlo. Reportes locales anteriores no se suben automáticamente.

Una respuesta perdida se recupera repitiendo la misma petición: el servidor
devuelve el reporte existente. Un bloqueo transaccional serializa reintentos
simultáneos por usuario/UUID. El mismo UUID con otro contenido devuelve 409.
No hay sincronización de historial entre celulares ni consulta de estados posteriores
todavía. La etiqueta local refleja la recepción, no una verificación del incidente.

## Prueba manual

Usar la conexión USB y BACKEND_URL descritos en firebase-fastapi.md. Reiniciar
FastAPI tras aplicar `python migrate.py` y compilar Flutter con config/local.json.

1. Iniciar sesión y crear un reporte marcado como prueba.
2. Esperar Reporte enviado. Pendiente de verificación.
3. En Supabase, esquema trujillo, revisar reports y su incident_id en incidents.
4. Apagar el backend y enviar otro: debe quedar Pendiente de envío.
5. Reiniciar el backend, abrir el reporte y reintentar; debe existir una sola fila.

Pruebas automáticas: `python -m pytest`, `python verify_reports_database.py`
(datos de prueba revertidos) y `flutter test`.
