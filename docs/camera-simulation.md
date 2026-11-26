# Cámara Android → RTX → mapa de operadores

La cuenta elegida para emitir video de prueba es `kinley.guzman.2015@gmail.com`.
El permiso lo concede el servidor; cambiar el correo o rol en Flutter no lo habilita.
Todos los operadores activos pueden ver y atender los casos de simulación.

## Estado de esta entrega

Implementados el servicio local de cámara, análisis con el modelo existente,
sesiones temporales, casos persistentes, mapa e historial de atención.
Se probaron por separado API, reglas PostgreSQL, Flutter y procesamiento GPU.
Falta aplicar las migraciones y autorizar la cuenta en la base real de Trujillo-360,
desplegar la API actualizada y actualizar la app del operador. El proyecto de
Supabase conectado durante esta implementación no contiene el esquema `trujillo`;
no se modificó ese proyecto. No había un Android conectado al ejecutar `adb devices`.
La prueba física con el teléfono está pendiente.

## Preparación del servidor

Desde `backend`, con las credenciales administrativas de la base usada por la API:

```powershell
.\.venv\Scripts\python.exe migrate.py
.\.venv\Scripts\python.exe authorize_sim_camera.py --email kinley.guzman.2015@gmail.com --camera-id phone-sim-1 --replace-email ansleyalvarado15@gmail.com
```

`migrate.py` aplica primero los candidatos IA (versión 1) y luego la simulación
(versión 2), manteniendo el migrador existente. La nueva migración fue generada
con Supabase CLI y está en `backend/supabase/migrations/20261125193721_ai_camera_simulation.sql`.
No ejecutarla sola en una base vacía: requiere las tablas/roles del backend.
Al reiniciar la API, `/ready` debe indicar `ai_version: 2`.

El script administrativo invita/promueve solo la cuenta elegida a operador,
habilita su cámara de simulación y permite crear sesiones cuando el perfil Firebase
sincroniza su correo verificado.

`--replace-email` sustituye el permiso anterior y detiene sus sesiones de cámara
en una sola transacción, conservando su rol de aplicación. Si todavía no existe
ese permiso, autoriza directamente la cuenta nueva. Repetir el comando es seguro.

Para revocar solo la cámara:

```powershell
.\.venv\Scripts\python.exe authorize_sim_camera.py --email kinley.guzman.2015@gmail.com --revoke
```

## Prueba con dos teléfonos

1. Instalar la app actualizada y entrar con la cuenta elegida. Abrir
   **Seguridad ciudadana → Cámaras / IA → Cámara y mapa de simulación**.
2. Pulsar **Preparar cámara de prueba**. Elegir la ubicación real/fija de la
   cámara con coordenadas manuales o la ubicación del teléfono; crear sesión.
3. Copiar ID de sesión y clave temporal de análisis (disponible para copiar una
   vez). La clave dura 30 minutos, solo registra resultados de esa sesión y no
   permite consultar o atender casos. Crear otra sesión invalida la anterior.
4. En la laptop, instalar/iniciar el puente de cámara siguiendo
   [conexión por USB](../vision/PHONE_SIMULATION.md). Conectar el segundo Android
   por USB, autorizar depuración y abrir en Chrome el enlace local que imprime
   el puente. Pulsar **Iniciar cámara** y aceptar permiso de video.
5. Mantener el teléfono fijo y la página visible. Probar caminar/abrazos y
   forcejeos simulados. La RTX analiza 32 imágenes por secuencia; el programa
   no conserva una grabación. Al superar el umbral .85 en dos ventanas seguidas
   se crea un **Simulación IA · Posible forcejeo** en el mapa de simulación.
6. En otro teléfono, un operador abre esa misma pantalla para revisar y atender:
   **Recibida → En revisión → Acción registrada → Cerrada**, o descartar con motivo.
   El mapa/bandeja se actualiza cada 10 segundos mientras está visible.
7. Detener la cámara, detener la sesión en la app y cerrar el puente con Ctrl+C.

## Reglas y alcance

- La ubicación proviene de la sesión; la IA no deduce coordenadas desde las imágenes.
- La puntuación .85 es un umbral de demostración, pendiente de validación; no es
  una probabilidad calibrada de agresión. El modelo puede omitir forcejeos o
  confundir otras actividades. Las dos ventanas deben llegar con menos de 10 s
  de separación; una pausa reinicia la cuenta. Hay 60 s de espera por cámara
  después de cada caso y deduplicación al reintentar peticiones.
- Casos y decisiones viven en tablas privadas de simulación. Se muestran en el
  mapa de operadores de esa pantalla y no alimentan el mapa ciudadano ni push.
- Las claves temporales se guardan como hash en la base y el token real del worker
  permanece en la laptop. El teléfono usa otra vinculación local aleatoria.
- No se guarda evidencia de video ni se ofrece revisión histórica del clip.
  La revisión de esta primera prueba se realiza observando la escena simulada.
  El modelo actual no detecta armas.
- Retención del piloto: máximo 1024 ventanas por sesión y 30 minutos por sesión;
  la consulta muestra los últimos 200 casos con activos primero. El historial
  permanece en PostgreSQL hasta que se establezca una política administrativa.

## Comprobaciones

```powershell
# API
cd backend
.\.venv\Scripts\python.exe -m pytest -q
# Volver a raíz antes de ejecutar Flutter y vision
cd ..
flutter test --no-pub test/ai_simulation_test.dart test/ai_review_test.dart
vision\.venv\Scripts\python.exe -m pytest -q vision/test_simulation_camera.py
```

`backend/verify_ai_simulation.mjs` ejecuta reglas reales en PostgreSQL/PGlite
aislado, sin modificar Supabase. Recibe como argumento la ruta a `@electric-sql/pglite`;
ver el comentario inicial del archivo. Incluye permisos, expiración, revocación,
deduplicación, umbral, transición e historial.
