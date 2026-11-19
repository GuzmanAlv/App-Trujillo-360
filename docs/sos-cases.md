# Evaluación y atención del SOS

## Seguimiento del ciudadano y persistencia de pendientes

La luz, sonido y pulsación del marcador del operador dependen de `decision=pending`, incluso después de aceptar y terminar una llamada. Atender, colgar o retroceder no verifica ni descarta el caso. La alerta se pausa mientras se conversa o se abre otra pantalla y regresa al mapa si el caso sigue pendiente. Confirmar o descartar quita esa alerta; las peticiones explícitas de apoyo conservan su aviso propio.

El ciudadano ve sus propios SOS confirmados activos en el mapa, con resplandor naranja silencioso y un marcador animado según categoría. Tocar el marcador o el aviso abre «Mi caso SOS». Se distinguen los mensajes:

- Confirmado sin despliegue: «Incidente confirmado. Esperando asignación de personal».
- **Unidad en camino** registrada por el operador: «La policía se encuentra en camino. Mantente en calma».
- Llegada confirmada: «Personal en el lugar».
- Resuelto: se retira el aviso activo del mapa y se conserva el historial.

Confirmar no afirma automáticamente que se despachó una unidad. Esta capa solo muestra casos del titular autenticado; evita duplicar su incidente público vinculado y se actualiza aproximadamente cada seis segundos. La animación naranja nunca activa sonido ni vibración.

La ficha permite aportar descripción de hasta 1000 caracteres y hasta tres fotos de 2 MB por caso, dentro de siete días desde el SOS. Los aportes son opcionales; no bloquean atención ni cambian la verificación o corroboración. Se normalizan fotos JPEG/PNG y se retiran sus metadatos. El titular y operadores autorizados pueden leerlos; las respuestas públicas no incluyen sus fotos ni sus descripciones adicionales. El operador dispone de «Aportes del ciudadano» en la ficha, con actualización manual.

**Activación:** aplicar migración 021 antes de desplegar el backend y actualizar el APK en ambos teléfonos:

```powershell
cd C:\Users\PC\Desktop\alerta_ciudadana\backend
.\.venv\Scripts\python.exe migrate_sos_citizen.py
.\.venv\Scripts\python.exe migrate_sos_citizen.py --apply
```

`/ready` del backend actualizado debe incluir `citizen_sos_version: 1`. No requiere credenciales nuevas. La migración añade almacenamiento privado para aportes y funciones autorizadas; conserva los casos existentes. Los reintentos reutilizan el identificador del aporte. La prueba automatizada usa PostgreSQL/PostGIS temporal, nunca Supabase: verifica titularidad, acceso de operadores, aislamiento del mapa público, fotos, reintentos y conservación de un único incidente.

Prueba en dos celulares: atender SOS y regresar sin decidir (alerta roja debe continuar); confirmar (aviso naranja del ciudadano con estado confirmado); marcar unidad en camino (mensaje de desplazamiento); adjuntar foto y texto como ciudadano; actualizar aportes en el operador; resolver (aviso activo desaparece). Comprobar también que otra cuenta ciudadana no puede abrir la ficha ni sus fotos.

## Lista de llamadas vivas desde el mapa

El rótulo «SOS Ayuda solicitada» se muestra exclusivamente cuando el mapa tiene llamadas que continúan esperando (`call_waiting`). Con una llamada, tocarlo centra el mapa en su posición. Con varias, despliega tarjetas desplazables; elegir una cierra la lista y centra el mapa, sin aceptar la llamada automáticamente. El operador puede tocar el marcador para abrir el caso y tomarla. La selección puede repetirse después de mover el mapa.

Al desaparecer las llamadas vivas, se retira el rótulo y su lista. Los SOS que superaron 10 segundos sin respuesta conservan su marcador, resplandor y alarma mientras sigan pendientes. El control de silenciar sigue disponible en la esquina del mapa, junto a actualizar. La lista se actualiza con la consulta del mapa; una llamada atendida por otro operador o finalizada se retira en la siguiente respuesta.

El resplandor ahora es más intenso y ancho, sin línea de borde. Android utiliza un patrón de tres tonos de emergencia repetido cada 2,2 segundos con mayor amplitud y vibración triple. No cambia el volumen del sistema ni ignora silencio/No molestar. Se conservan la salida al aceptar, el silencio manual y la cancelación al pausar la app. Esta extensión solo requiere instalar el APK nuevo sobre el backend que ya incorpora la migración 020; no añade rutas ni migraciones.

## Alerta localizada en el mapa y estado de la llamada

Esta actualización sustituye la tarjeta de llamada entrante **del operador** por un rótulo compacto rojo «SOS Ayuda solicitada», arriba al centro del mapa. La luz roja se dibuja como un resplandor suave dentro del mapa, sin línea de borde ni iluminación en las demás pantallas. El sonido y vibración se pueden silenciar desde el rótulo y se detienen al salir del mapa o tomar una llamada. El aviso de devolución de llamada al ciudadano se conserva para que pueda aceptarla.

- Teléfono rojo animado: llamada del ciudadano que sigue esperando y no ha caducado.
- Advertencia roja con halo naranja animado: SOS pendiente cuya llamada esperó al menos 10 segundos sin aceptación, aunque el ciudadano haya colgado o se haya agotado la espera.
- Un corte antes de 10 segundos conserva el caso pendiente y su marcador, sin activar esa alerta persistente. Una llamada atendida tampoco se clasifica como llamada sin respuesta. Confirmar, descartar o resolver continúa dependiendo del operador.

La medición se hace en PostgreSQL a partir del inicio, aceptación, fin y caducidad de la llamada; no depende de que el teléfono operador haya visto la llamada desde el inicio. El mapa recibe los cambios en su siguiente consulta, aproximadamente cada seis segundos. El marcador usa un lienzo y punta fijos; solo cambia el tamaño de su símbolo y halo.

**Activación de esta versión:** requiere migración 020 antes de desplegar el backend y luego instalar el APK nuevo:

```powershell
cd C:\Users\PC\Desktop\alerta_ciudadana\backend
.\.venv\Scripts\python.exe migrate_sos_waiting.py
.\.venv\Scripts\python.exe migrate_sos_waiting.py --apply
```

La migración añade únicamente una función de consulta autorizada para operadores y conserva todos los datos. Las pruebas usan una base temporal y cubren llamada esperando, corte antes/después de 10 segundos, espera caducada, llamada atendida y rechazo a cuentas ciudadanas.

Las secciones siguientes conservan el historial de versiones; esta sección define el comportamiento actual de la alerta.

## Alerta de llamadas pendientes en primer plano

Con la app abierta, una llamada SOS esperando atención activa un borde rojo pulsante alrededor de la interfaz del operador, doble pitido breve y vibración cada cuatro segundos. Un solo aviso «SOS Alerta» agrupa la cola y permite tomar la primera llamada. El botón de sonido silencia pitido y vibración durante ese episodio; el borde sigue visible. Ocultar un aviso no descarta el caso.

Al tomar una llamada, salir de la app, cerrar sesión o dejar de haber llamadas esperando, se detiene la alarma. Android cancela los efectos al pausar la actividad y limita el aviso a una concesión de 12 segundos que la app renueva mientras sigue activa. Se respetan el volumen de notificaciones, modo silencioso y No molestar. No se implementó una nueva alarma en segundo plano; se mantienen los avisos FCM existentes.

Los marcadores pendientes del mapa privado utilizan advertencia roja, halo naranja y una pulsación suave de tamaño con la punta anclada a la ubicación. Las imágenes se preparan una vez y se reutilizan para todos los pendientes. La capa consulta cambios cada seis segundos y pausa la animación cuando el mapa no está activo. Reducir animaciones en el teléfono deja una representación estática. Los casos con apoyo solicitado conservan su icono de apoyo para distinguirlos.

Activación de esta mejora: instalar el APK nuevo en el teléfono del operador. No requiere nuevas migraciones ni cambios en Render sobre la versión que ya contiene `/operator/sos-map`. Probar en un Android real el volumen, doble pitido, vibración, botón de silenciar, llegada de varias llamadas y apagado al aceptar o poner la app en segundo plano.

## SOS privados en el mapa del operador

Las cuentas de operador ven los SOS activos de Ayuda sobre el mapa reciente. Cada marcador conserva el color/icono del estado (incluido apoyo solicitado), utiliza el punto del hecho corregido y abre la ficha del caso al tocarlo. Los casos cerrados o descartados se conservan en Ayuda y no se muestran en esta capa. Si existe un incidente público vinculado, el operador ve un solo marcador del SOS.

La capa se actualiza cada seis segundos mientras el mapa está activo, al volver a él y al cerrar una ficha. El botón «Actualizar casos SOS» permite actualizarla manualmente. Cambiar o cerrar sesión borra los marcadores privados. El endpoint `/operator/sos-map` comprueba el rol activo en PostgreSQL y devuelve únicamente ID, posición, estado y vínculo del incidente; las cuentas ciudadanas no tienen acceso. La consulta usa la misma bandeja autorizada y su límite de 200 casos.

Activación: desplegar el backend nuevo e instalar el APK actualizado. No requiere una migración adicional si ya se aplicaron 018 y 019. La comprobación automatizada usa PostgreSQL/PostGIS temporal y verifica rechazo a ciudadanos, ubicación corregida, privacidad de notas y retirada de casos descartados.

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
