# Evaluación y atención del SOS

## Actualización de la ficha del operador

La migración **019_sos_operator_actions.sql** agrega estados visuales en la ficha y Ayuda, referencia/descripcion pública opcionales, solicitud de apoyo con borde rojo animado y devolución de llamada al ciudadano del caso. El operador dispone de botones para centrar el mapa en su posición GPS o en la posición del ciudadano al solicitar el SOS. El pin del hecho sigue siendo editable tocando o arrastrando; las coordenadas ya no se muestran como campos.

Para activar esta extensión en la base existente, desde `backend`:

```powershell
.\.venv\Scripts\python.exe migrate_sos_operator.py
.\.venv\Scripts\python.exe migrate_sos_operator.py --apply
```

Luego desplegar el nuevo backend e instalar el APK nuevo en ambos teléfonos. `/ready` devuelve `sos_cases_version: 2`. La devolución requiere una llamada anterior del mismo caso; el servidor comprueba asignación, disponibilidad de ambos participantes y aceptación del ciudadano. Cada intento nuevo utiliza una sala LiveKit distinta. La ventana entrante de devolución se consulta **con la app abierta**; esta extensión no añade un aviso de llamada del sistema en segundo plano. Mantener la app abierta para probarla.

«Solicitar más patrullas» registra la petición en el caso y la destaca en la bandeja de otros operadores cuando se actualiza (o al pulsar Actualizar); no constituye una asignación automática de unidades. El operador puede marcar «Apoyo atendido» para quitar el resaltado. Confirmar, descartar y resolver conservan sus controles del servidor. Quitar «Guardar ficha» no agrega guardado automático: las acciones de evaluación guardan los datos que acompañan la decisión.

Implementación del 18 de noviembre de 2026. Requiere migración 018, backend y app nuevos. Este documento describe el código; no implica que ya esté desplegado.

## Flujo

1. Mantener SOS tres segundos conserva la solicitud privada y crea la llamada.
2. Con la app abierta, el operador recibe una tarjeta flotante sobre cualquier pantalla con **Tomar llamada**. Consulta cada cuatro segundos las llamadas que aún esperan; desaparece si otra cuenta acepta o expira. Ocultar la tarjeta no descarta el SOS. En segundo plano se conserva el aviso FCM existente: no se implementó una ventana de llamada del sistema ni una pantalla de bloqueo.
3. La llamada conserva micrófono, altavoz y finalizar en un área separada de la ficha desplazable. La ficha muestra el teléfono en azul (posición al enviar SOS, no seguimiento en vivo) y un pin editable para el lugar del hecho. También se pueden editar las coordenadas.
4. El operador elige categoría, referencia y descripción públicas, y comentario interno independiente. **Guardar ficha** conserva el borrador. **Dejar pendiente** y **Descartar alarma** requieren motivo interno. La falta de respuesta nunca descarta automáticamente.
5. **Confirmar incidente** publica un único incidente `verified` vinculado al SOS. No crea un reporte ciudadano ficticio ni requiere tres cuentas. La ubicación pública es el pin elegido, no un promedio. El servidor comprueba rol activo, asignación, versión y solicitud idempotente. Dos confirmaciones simultáneas no duplican incidentes.
6. **Unidad en camino** no activa la sirena. **Personal en el lugar** requiere confirmación explícita y guarda hora y actor en el historial. Si se obtiene permiso/GPS, se guarda adicionalmente la posición del dispositivo; no altera el pin público ni prueba automáticamente presencia policial.
7. **Resolver caso** requiere resultado interno. Cierra el incidente, retira la presencia activa del mapa reciente y conserva el historial privado y la concentración histórica. Los casos descartados/resueltos no se reabren desde esta versión.

La ficha permanece después de colgar. También se abre desde Ayuda o desde el incidente vinculado en Revisar reportes. El operador asignado y administradores pueden modificarla; otros operadores pueden consultarla. Nadie puede evaluar su propio SOS. Las pantallas antiguas de decisión no pueden modificar un SOS por fuera de este flujo.

El mapa reciente consulta cambios cada 30 segundos mientras está activo; también se actualiza al cambiar de zona o regresar a la app. No es una suscripción en tiempo real. El historial privado incluye instantáneas de las evaluaciones; ningún comentario interno, identidad del ciudadano ni GPS de llegada se incluye en las respuestas públicas.

## Activación

1. Revisar `backend/migrations/018_sos_cases.sql`. Para una base ya desplegada con 017, desde `backend`:
   ```powershell
   .\.venv\Scripts\python.exe migrate_sos_cases.py
   .\.venv\Scripts\python.exe migrate_sos_cases.py --apply
   ```
   El primer comando solo comprueba. El segundo aplica únicamente 018, atómicamente, usando la credencial administrativa local. No cambia políticas de Google, cuentas de servicio ni claves. Para una base nueva, `migrate.py` incluye toda la secuencia.
2. Desplegar este código del backend en Render. No requiere nuevas variables ni claves de LiveKit.
3. Verificar `/ready`: debe incluir `sos_cases_version: 1`, además de `calls_version: 1` y las versiones anteriores.
4. Instalar la app nueva en ambos dispositivos:
   ```powershell
   flutter build apk --debug --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
   ```
5. Probar audio y el flujo con cuentas distintas (ciudadano / operador). Una compilación correcta no demuestra recepción FCM ni audio real.

## Prueba en dos celulares

- Operador en otra pantalla de la app; ciudadano envía SOS. Debe aparecer la tarjeta y permitir aceptar. Con un segundo operador, solo uno debe tomar la llamada.
- Hablar en ambos sentidos, silenciar, activar altavoz. Desplazarse por la ficha manteniendo acceso a los controles. Finalizar sin perder la evaluación escrita.
- Corregir el pin, escribir textos públicos/internos diferentes y confirmar. Ver un único incidente en el mapa ciudadano, sin texto interno ni punto del teléfono original.
- Desconectar la red durante un guardado y usar **Reintentar el mismo envío**. Si el caso cambió en otra sesión, recargar antes de editar.
- Marcar en camino: marcador normal. Confirmar llegada: sirena y «Personal en el lugar». Resolver con resultado: desaparece de recientes, historial conservado.
- Repetir con llamada sin respuesta y con alarma descartada. Ninguna debe aparecer públicamente sin confirmación.

## Comprobaciones automatizadas

Las pruebas de base crean un PostgreSQL/PostGIS temporal aislado. Nunca usan Supabase ni los `.env` del proyecto:

```powershell
$env:PG_TEST_BIN='C:/Program Files/PostgreSQL/18/bin'
cd backend
.\.venv\Scripts\python.exe -m pytest tests -q
cd ..
dart analyze lib test/sos_case_panel_test.dart
flutter test test/sos_case_panel_test.dart test/call_cleanup_test.dart test/hold_sos_button_test.dart
```
