# Continuar Trujillo 360 en otra laptop

## SOS simultáneos y aceptación de llamada (036)

Aplicar después de 035, antes de desplegar el backend y distribuir el APK nuevo:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_concurrency.py --apply
cd ..
```

`/ready` añade `sos_concurrency_version: 1`. El operador reserva el caso y acepta
su audio en una sola transacción (`POST /operator/sos-cases/{id}/take-call`). Una
unidad atiende una llamada a la vez; el resto sigue pendiente. Elegir otro SOS
sin audio activo libera únicamente la reserva pendiente anterior, sin cerrar ni
descartar el SOS. Un caso confirmado no se libera de esta forma.

La pestaña Pendientes muestra también los casos reservados sin decisión. Los
errores temporales del mapa conservan la última información con aviso de
reconexión. Las lecturas de estado y del mapa ya no renuevan reservas ni toman
el bloqueo global de asignación. Durante el audio aceptado, el operador envía
un heartbeat cada 30 segundos. La ficha mantiene su propio heartbeat.

El cierre incluye la sala/generación para que una petición atrasada no cierre
una llamada nueva. Los certificados públicos de Firebase se reutilizan según
su vigencia; cada token sigue verificándose. Se comparten GET simultáneos de
una misma cuenta, sin guardar resultados, y las pestañas ocultas no consultan
periódicamente. La sincronización de identidad evita escribir filas sin cambios.

El botón de transferencia manual está retirado temporalmente. Se conserva la
reasignación automática por desconexión. Probar en teléfonos: dos ciudadanos
llaman a la vez, atender uno, finalizar sin decisión, localizar ambos pendientes,
abrir el segundo y reconectar internet. Estas pruebas locales no certifican la
capacidad máxima ni sustituyen verificar Render y LiveKit en dispositivos reales.

## SOS pendiente visible al ciudadano (035)

Aplicar después de 034, antes de desplegar backend e instalar el APK nuevo:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_citizen_pending_sos.py --apply
cd ..
```

`/ready` incluye `citizen_pending_sos_version: 1`. La ruta privada `/my-sos/map`
lista los SOS pendientes y confirmados del usuario. El SOS sin respuesta queda
visible con un marcador SOS rojo animado en el GPS registrado al solicitar ayuda
(y no en un punto promedio ni en el GPS actual si se movió). Un aviso compacto
indica «SOS recibido · esperando atención». El pin y el aviso persisten mientras
esté pendiente, también al volver a abrir la app con la cuenta correspondiente.
No se publica en el mapa de otros ciudadanos ni anuncia envío de una unidad.

Al confirmar, el marcador se transforma al tipo de incidente y conserva el flujo
normal de atención. Solo los confirmados reemplazan el botón SOS por llamada al
operador/cámara; los reintentos de un pendiente reutilizan el mismo caso según
034. El detalle pendiente explica que la solicitud sigue activa y deshabilita
aportes hasta confirmar; `/my-sos` mantiene su contrato de confirmados para el
seguimiento de ubicación. Resolver/descartar retira el pin activo.

El botón del contador del operador usa `FloatingActionButton.small`, como el GPS,
y un triángulo rojo. La cabecera de su bandeja es más compacta, con triángulo
blanco y controles de sonido/actualización conservados. Verificar el cambio con
SOS sin contestar, vuelta al mapa, cierre/reinicio, confirmación y cuentas distintas.

## Escalamiento, transferencias y límites SOS (034)

Aplicar después de 033 y antes de desplegar backend/APK:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_dispatch.py --apply
cd ..
```

`/ready` incluye `sos_dispatch_version: 1`. El backend ejecuta un reloj de despacho
cada cinco segundos, independiente de `PUSH_ENABLED`. La instancia debe estar
activa; un proceso suspendido/apagado no ejecuta el reloj. El envío FCM sigue
requiriendo sus credenciales y configuración existentes.

- SOS pendiente sin asignar: 15 km inicialmente, 30 km a los 30 s, 60 km a los
  60 s y todos los operadores conectados con posición reciente a los 120 s.
  El reloj parte de la recepción del SOS; continúa si la llamada de 90 s termina.
  Cada nivel/dispositivo se notifica una sola vez. Contestar o confirmar detiene
  el escalamiento mientras exista una reserva/atención válida.
- El operador envía disponibilidad cada 30 s además del GPS. Al salir de sesión
  intenta marcarse desconectado; una pérdida de conexión tiene 120 s de gracia.
  La nueva versión del APK debe instalarse en TODOS los operadores antes de
  poner esta política en servicio. Los latidos/GPS atrasados no reactivan una
  cuenta marcada desconectada: el nuevo inicio de sesión declara disponibilidad.
  Solo los clientes que declaran disponibilidad con el endpoint nuevo pueden
  recibir ofertas automáticas de transferencia; se evita asignarlas a APK antiguos.
- Caso confirmado sin operador conectado: busca el más cercano por distancia
  geográfica, con GPS de menos de 120 s, latido de menos de 90 s y sin otra
  reserva, caso activo ni llamada. Ofrece el traslado durante 45 s. Hasta que
  acepte, el ciudadano ve que se está buscando otra unidad. Si no acepta, prueba
  otro; el anterior se excluye cinco minutos para evitar rebotes. Sin candidatos,
  conserva el mismo SOS abierto y sigue buscando. No representa un despacho
  oficial ni garantiza que haya una unidad disponible.
- «Transferir a otra unidad» permite solicitar el relevo sin cerrar el caso.
  Se conservan incidente, evidencias y notas, se registra el historial y se
  revoca el audio/ruta anteriores. Las salas antiguas se cierran mediante una
  cola con reintentos de LiveKit, además de la desconexión del cliente.
- La llamada del ciudadano conserva el caso. Si el asignado no está disponible
  o está ocupado, espera otro operador. Las solicitudes de contacto esperan
  hasta 90 s; que termine ese intento de audio NO cierra el SOS.
- Un único SOS abierto por ciudadano: pendientes y confirmados se reutilizan
  incluso con identificadores nuevos o envíos concurrentes. No se eliminan ni
  fusionan automáticamente duplicados históricos anteriores a esta migración.
- Límite de casos nuevos: 3 en 10 minutos y 10 en una hora por cuenta. Las
  reaperturas de audio requieren 15 s entre intentos y permiten 6 en 5 minutos.
  Reintentar una llamada todavía activa o recuperar el recibo no gasta otro
  intento; responder, cortar, consultar y aportar información no se bloquean.
  Se devuelve HTTP 429 con `Retry-After`; no hay suspensiones automáticas.

Prueba con tres teléfonos: ciudadano, operador asignado y otro libre. Apagar la
red del asignado; comprobar oferta al cercano libre, rechazo/expiración de oferta,
aceptación, nueva ruta/audio y búsqueda sin candidatos. También probar cierre de
sesión, dos operadores simultáneos intentando aceptar y reintentos de SOS.
Las pruebas automatizadas usan PostgreSQL aislado; no se aplica la migración ni
se despliega en producción automáticamente.

## Avisos por radio y recuperación de rutas (033)

Aplicar después de 032, antes de desplegar backend e instalar el APK nuevo:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_operator_sos_zones.py --apply
cd ..
```

`/ready` incluye `operator_sos_zones_version: 1`. El operador vuelve a calcular
la ruta de su SOS confirmado en camino al iniciar sesión o recuperar su asignación.
La consulta periódica no deshace «Quitar ruta» mientras continúe la misma sesión.

Los avisos de nuevos SOS (FCM, sonido, vibración, tarjetas y luz roja) usan un radio
fijo de **15 km desde el GPS reciente del operador**. Su ubicación se actualiza
aproximadamente cada 30 segundos, con notificación de ubicación en Android mientras
esté conectado como operador. Se requiere precisión de 100 m o mejor; la posición
caduca a los 10 minutos. Sin GPS válido no hay alarmas automáticas; el mapa sigue
mostrando todos los casos. Android puede interrumpir ubicación al forzar el cierre
o por restricciones de batería. La llamada de un ciudadano al operador ya asignado
continúa avisando a ese operador aunque esté fuera del radio.

El botón rojo de la esquina inferior derecha muestra el número de **SOS activos**
de la plataforma (incluye pendientes y confirmados, excluye resueltos/descartados).
Al tocarlo, el mapa encuadra todos. El listado no está limitado a los 200 de la
bandeja antigua. Un marcador lejano permite consultar o aceptar voluntariamente el
SOS; no genera tarjetas ni alarmas por proximidad. Los incidentes resueltos siguen
su historial público de siete días y no aumentan este contador.

Prueba física: iniciar/cerrar sesión con caso en camino; dos operadores a menos y
más de 15 km; un tercero sin permiso GPS; confirmar mapas/contador en todos, avisos
solo en el cercano, pulsar un marcador lejano y volver a abrir la app bloqueada.
No se han aplicado estas migraciones ni desplegado automáticamente.

## SOS activo y ruta en movimiento (032)

Después de la migración 031, aplicar antes de desplegar backend y generar el APK:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_live_navigation.py --apply
cd ..
```

`/ready` debe mostrar `sos_live_navigation_version: 1`. Un SOS confirmado activo
reemplaza el botón del ciudadano por «Llamar al operador» y acceso a fotos/Mi caso SOS.
El servidor devuelve el caso existente ante otro envío; no crea uno adicional.
La llamada reabre el audio del mismo caso con su operador asignado.

El ciudadano comparte GPS automático con notificación de ubicación en Android
mientras el caso siga activo; se detiene al cerrar o cambiar de cuenta. Posiciones
con precisión mayor de 50 m o antigüedad mayor de 30 s se rechazan. Solo el operador
asignado ve la posición actual; el punto del incidente público no se desplaza.
Si el GPS deja de actualizarse por 60 s, se conserva la última posición conocida
y se impide confirmar la llegada automáticamente hasta recibir GPS reciente.
Antes del primer GPS, se usa el lugar registrado del incidente.

El mapa del operador comprueba cambios cada 20 s en primer plano y recalcula
al desviarse 40 m, avanzar 100 m, moverse el destino 20 m o pasar dos minutos.
Conserva la última ruta si falla la red. Routes puede incorporar cierres conocidos
por Google; no detecta automáticamente una calle cerrada que Google desconozca.
La llegada utiliza el mismo destino actualizado. Verificar con dos celulares:
llamada al asignado, desplazamiento ciudadano, desvío del operador, pantalla
bloqueada, cierre del caso y detención de ubicación. Las restricciones de batería
o la detención forzada de Android pueden interrumpir el seguimiento.

## Recuperación de SOS y llegada en segundo plano

La mejora requiere la migración 031, backend y APK nuevos. Aplicar antes de
desplegar desde la raíz del proyecto:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_reliability.py --apply
cd ..
```

`/ready` debe incluir `sos_reliability_version: 1`. Las reservas pendientes duran
dos minutos sin actividad del operador y vuelven a ofrecerse al consultar la bandeja.
La ficha permite liberarlas voluntariamente. Confirmados en camino/en zona conservan
su asignación. El audio tolera fallos transitorios de verificación durante un minuto.
El SOS guarda su identificador y recibo por cuenta para reintentar tras reiniciar.
El SOS toma el GPS del dispositivo. Si falla, se debe activar ubicación y reintentar; no permite marcar manualmente otro punto.

Android inicia un servicio de ubicación con notificación al confirmar el SOS y lo
detiene al llegar o cerrar la atención. Permitir ubicación precisa y comprobar en
dos teléfonos el bloqueo de pantalla y cambio a otra app. La detención forzada o
restricciones del fabricante pueden detener el servicio. No se ha verificado esta
versión físicamente en un celular. No se aplican migraciones ni despliegues automáticamente.

Actualización: [solo SOS en Mis Solicitudes y Cerca de mí](sos-only-requests.md).
Requiere migración 028 y actualizar backend/APK. `/ready` incluye `nearby_sos_version: 1`.

Actualización: [historial ciudadano y navegación por rol](citizen-history-and-role-navigation.md).
Requiere migración 027 y actualizar backend/APK. `/ready` incluye `citizen_history_version: 1`.

Actualización: [casos resueltos en el mapa y avisos de trayecto](resolved-map-and-progress-cues.md).
Requiere migración 026, backend y APK nuevos. `/ready` incluye `resolved_map_version: 1`.

Nueva actualización: [descarte y suspensión, mapa ampliado y controles](sos-suspension-and-map-controls.md).
Requiere migración 025 y actualizar backend/APK. `/ready` incluye `sos_suspension_version: 1`.

Nueva versión: [mapa compacto y refuerzos](reinforcements-and-compact-map.md).
Requiere migración 024, despliegue del backend e instalación del APK. `/ready` incluye `reinforcements_version: 1`.

Actualización de experiencia SOS: [avisos, llamadas minimizadas y filtros](sos-notification-experience.md).
Requiere migración 023, backend y APK nuevos. `/ready` anuncia `sos_notifications_version: 1`.

Actualización de estados SOS: [salida al confirmar y llegada automática por GPS](sos-arrival.md).
Esta mejora requiere migración 022 antes de desplegar backend y actualizar ambos APK.

Actualización del 19 de noviembre: [ruta en el mapa al confirmar un SOS](sos-routes.md).
Requiere desplegar el backend, configurar `GOOGLE_ROUTES_API_KEY` en Render e
instalar la app nueva; no requiere otra migración. El cálculo real con Google
y la continuidad del audio al confirmar se deben comprobar en dos celulares.

Actualización de código del 18 de noviembre: [casos SOS y atención por operadores](sos-cases.md). Incluye migración 018, aviso flotante dentro de la app, evaluación durante/después de la llamada y presencia en el mapa. Consultar esa guía para activar y probar; su existencia no confirma un despliegue en Render.

Estado actualizado el 16 de noviembre de 2026. Esta guía sustituye las notas del 3 de noviembre sobre Firebase y la supuesta RTX 4060.

Actualización de implementación del 17 de noviembre: consultar [el piloto de llamadas SOS](audio-calls.md) antes de desplegar. Incluye migración 017 y configuración LiveKit; el estado histórico de abajo describe el SOS anterior al despliegue de llamadas.

## Obtener el proyecto

Repositorio: https://github.com/GuzmanAlv/App-Trujillo-360, rama compartida `main`.
El backend de Render despliega desde `codex/notificaciones-fcm`; ambas ramas se mantienen en el mismo commit.

```powershell
git clone https://github.com/GuzmanAlv/App-Trujillo-360.git
cd App-Trujillo-360
git switch main
```

Si ya tienes una copia, revisa `git status` antes de `git pull --ff-only origin main`. No uses `reset --hard` para resolver cambios ajenos.

## Estado funcional

- La app Flutter Android usa Google/Firebase y el backend `https://trujillo-360-api.onrender.com`. La app instalada no necesita cable ni laptop para reportar, recibir SOS o consultar información.
- `/ready` debe devolver `schema_version: 11`, `workflow_version: 1`, `push_version: 3` y `sos_version: 1`.
- Reportar guarda tipo, descripción, fotos, ubicación y hora del hecho. Ya no pide prioridad. El operador revisa el incidente; también puede quedar público por corroboración comunitaria según las reglas del servidor.
- SOS envía la ubicación como solicitud privada en Ayuda y avisa a operadores con notificaciones habilitadas. No hace una llamada ni confirma que se haya enviado personal.
- El acceso experimental «SOS con botón de volumen · prueba» detecta tres pulsaciones de volumen abajo en Android mediante Accesibilidad. Cada celular debe activarlo y conceder ubicación permanente. «Solo probar detección» vibra sin enviar; al desactivarlo, la vibración larga confirma recepción del servidor. En el Xiaomi de prueba el servicio llegó a desconectarse hasta reiniciar el teléfono, así que este acceso aún no es fiable como único medio para pedir ayuda.
- Las cuentas de operador ven Ayuda, Revisar reportes y Cámaras / IA. El servidor comprueba el rol en cada operación. Las cuentas ciudadanas no ven esa opción de avisos del operador.
- Los avisos FCM están configurados y el usuario confirmó recepción real. Para avisos ciudadanos según la ubicación actual, Android debe conceder notificaciones y ubicación “Permitir todo el tiempo”. La app muestra un aviso persistente mientras sigue la ubicación. El servidor descarta ubicaciones de más de 20 minutos.
- En Notificaciones, «Ahorrar batería» reduce las actualizaciones de zona de unos 5 minutos a 12–15 minutos; puede demorar avisos al cambiar de zona. El SOS solicita la ubicación al enviarse.
- La zona fija ya no aparece en la configuración nueva. Al abrir una instalación anterior, la suscripción fija se desactiva y se debe activar “Incidentes cerca de mí” otra vez.
- La pantalla Cámaras / IA es una bandeja temporal de prueba. Todavía no hay celular transmisor, modelo entrenado, inferencia en vivo ni decisiones de cámara conectadas al backend. El plan es un celular dedicado como cámara; el equipo de análisis está por definir. La laptop actual tiene gráficos AMD integrados, no RTX 4060.

## Probar avisos en Android

1. Abrir Configuración → Notificaciones y activar “Incidentes cerca de mí”.
2. Pulsar Guardar. Si Android abre ajustes, elegir Ubicación → “Permitir todo el tiempo”; regresar y pulsar Guardar de nuevo. Conceder notificaciones cuando se solicite.
3. Comprobar que aparece “Alertas por ubicación activas” mientras el seguimiento está activo.
4. Con otra cuenta operadora, activar “Nuevos reportes para el operador”, crear un reporte de prueba y confirmar el flujo. Un incidente solo debe avisar a ciudadanos cuando esté público y cerca de una ubicación reciente.
5. Probar con la app en segundo plano y con cambios de red. La detención forzada de Android y la falta de Internet pueden impedir avisos; medir el retraso real en un teléfono.

## Compilar e instalar

Instalar Flutter, Android SDK y Java compatibles. Ejecutar `flutter doctor -v`. La clave restringida de Maps se configura localmente en `android/maps.properties` tomando `android/maps.properties.example` como referencia; no está en Git. Una firma Android diferente puede requerir registrar su huella SHA para Google Sign-In y Maps.

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64 --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. El APK está ignorado por Git: hay que compartirlo como archivo aparte. El modo release actual usa una firma debug de este equipo para pruebas, no una firma de Play Store. Un APK construido en otra laptop puede no instalarse encima del anterior sin la misma firma.

Para verificar código: `flutter analyze` y, desde `backend`, `.\.venv\Scripts\python.exe -m pytest tests -q`. Para usar el backend público no se necesitan los `.env` ni Python local. Las migraciones de base requieren credenciales administrativas privadas y no se ejecutan al arrancar Render.

No subir `.env`, `android/maps.properties`, `backend/.secrets/`, `.venv/`, tokens ni claves privadas.

## Texto para continuar con otro asistente

```text
Estoy continuando Trujillo 360 desde el repositorio https://github.com/GuzmanAlv/App-Trujillo-360, rama main. Lee README.md y docs/continuar-en-otra-laptop.md antes de cambiar código. La app ciudadana, SOS, operadores y FCM ya están integrados. Los avisos ciudadanos siguen la ubicación Android con permiso “Permitir todo el tiempo”; la zona fija anterior se desactiva al abrir la versión nueva. El backend público está en https://trujillo-360-api.onrender.com y Render despliega desde codex/notificaciones-fcm. Cámaras / IA aún no tiene transmisión ni modelo: se planea un celular dedicado como cámara y el equipo de análisis está por definir. No asumas que tenemos RTX 4060. No subas claves ni el APK a Git. Verifica primero el estado actual de Git y /ready.
```
