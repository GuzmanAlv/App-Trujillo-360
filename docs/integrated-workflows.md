# Flujo integrado

La app vuelve a iniciar con Firebase y la interfaz original. Conserva la cuenta,
fotos, categorías, consultas comunitarias, historial por cuenta y configuración.
El prototipo aislado en lib/pilot se conserva como referencia, no como inicio.

## Ventanas y mapa

Cada incidente público dura exactamente siete días desde occurred_at, sin reinicio
semanal. Pendientes y futuras fechas no aparecen en Cerca de ti ni generan alertas.
Verificado por operador no exige tres autores. Corroborado sí exige tres cuentas.
Una caducidad no cierra ayuda, no prueba el fin del peligro ni elimina historial.

El historial usa los últimos 90 días; puede filtrarse por cuatro franjas de seis
horas de America/Lima. Agrupa incidentes, no aportes individuales, en celdas de
0.001 grados. Círculos de 80 m ilustran zonas aproximadas, no calles exactas.
Amarillo representa uno o dos incidentes, rojo tres o más; sin color significa
datos insuficientes, no seguridad. Estos umbrales son reglas iniciales por validar.
Los cerrados previamente públicos siguen aportando; los descartados no.
Se conservan registros más antiguos sin incorporarlos a ese color indefinidamente.

## Accesos y seguimiento

La entrada principal tiene Reportar y SOS. Reportar conserva fotos, hora del hecho
y ubicación, sin pedir urgencia. El backend conserva también la hora de recepción.
Los reportes normales van a Revisar reportes, sin crear una solicitud nueva en Ayuda.
SOS envía una ubicación actual como solicitud privada de prioridad Alta a Ayuda;
no inicia una llamada ni crea un incidente público. Ver [SOS](sos.md).
El identificador estable evita duplicados al reintentar y la copia local conserva
la urgencia. Los reportes antiguos sin urgencia conservan su comportamiento.
El seguimiento continúa en Mis solicitudes de ayuda; no hay un botón SOS separado.

Ambos roles usan Google. La invitación administrativa de una cuenta verificada
habilita operator al actualizar /me. No existe elección pública del rol. Ejecutar
`python authorize_operator.py --email CORREO` desde backend para autorizar, o
agregar `--revoke` para retirar autorización y rol. Ninguna contraseña va en la app.

La base comprueba rol y suspensión en cada consulta, foto y decisión de operador.
La validación firmada de Firebase admite un desfase máximo de 60 s entre relojes
para iat, exp y auth_time; no omite firma, issuer, audiencia ni proveedor Google.
Solicitudes de ayuda son privadas: autor y operadores. Urgencia no publica el caso.
Un operador registra motivo para revisar, actuar, cerrar o descartar. El ciudadano
consulta los eventos, sin identidad de trabajadores. La bandeja consulta cada 15 s
en primer plano. El envío FCM usa una cola privada y preferencias por zona;
requiere habilitar la credencial del servidor y verificar la entrega real. Ver
docs/push-notifications.md.
Las ayudas no caducan como el mapa. Recibida no confirma revisión o envío de agentes.

Los operadores pueden consultar aportes y fotos del incidente antes de decidir
verificar/publicar, descartar o cerrar. Las decisiones se auditan en reviews.
Cámaras/IA conservan la bandeja previa, todavía sin cámaras o inferencia conectadas.
El icono de llamada abre el marcador con 044298734, número indicado por el equipo,
sin iniciar la llamada automáticamente. La persona debe pulsar Llamar.

## Backend y prueba por USB

`python migrate.py` aplica una ampliación transaccional. Conserva la versión base
11 para no romper /ready de la API ya desplegada; la extensión usa workflow_migrations
versión 1. No elimina reportes existentes. El backend nuevo comprueba ambas versiones.

Iniciar FastAPI en localhost:8001 y ejecutar `adb reverse tcp:8001 tcp:8001`.
También se puede ejecutar `scripts/start-workflow-backend.ps1` y después
`scripts/connect-phone.ps1 -Port 8001`. El primero inicia el proceso oculto sin
crear tareas de Windows ni modificar el servidor anterior en el puerto 8000.
Compilar con `--dart-define=BACKEND_URL=http://127.0.0.1:8001
--dart-define=USB_BACKEND=true --dart-define=MAPS_ENABLED=true`.
USB_BACKEND solo admite HTTP en localhost/127.0.0.1; otros destinos requieren HTTPS.
Android solo permite tráfico claro hacia loopback. Sin USB o laptop el servidor
local no estará disponible. La base sigue siendo Supabase, no almacenamiento ficticio.
La API en Render no se actualiza automáticamente por modificar estos archivos.

Validar backend con pytest y verify_workflows.py (datos y membresía de prueba
siempre revertidos); Flutter con analyze y test. Probar login Google en el teléfono
y entrar con la cuenta de operador autorizada para verificar su interfaz real.
