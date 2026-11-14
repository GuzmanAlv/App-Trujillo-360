# SOS privado

El botón SOS está junto a Reportar en Mapa y Reportes. Requiere una cuenta Google
activa, ubicación habilitada y conexión con el backend. Al pulsarlo obtiene una
ubicación actual (hasta 20 segundos) y envía una solicitud privada de prioridad
Alta. No inicia una llamada, no crea un incidente público y no aparece en el mapa.

El servidor guarda la solicitud en `help_requests` con `source='sos'` y la muestra
en Ayuda al operador. Encola un aviso FCM para cada dispositivo de operador que
tenga activados los avisos de nuevos reportes. La bandeja se actualiza cada 15 s
en primer plano. El aviso push puede retrasarse o fallar; la solicitud permanece
guardada para consulta. La app solo muestra confirmación cuando el servidor
responde con el identificador y el origen SOS. Si no se confirma, permite
reintentar con el mismo identificador durante esa sesión para evitar duplicados.

Reportar conserva la hora del hecho y la hora de recepción, pero ya no pide una
urgencia al ciudadano. Los reportes normales van a Revisar reportes; SOS queda
en Ayuda. Los reportes de versiones anteriores pueden conservar su historial de
ayuda y urgencia para no perder su seguimiento.

Para activar en el servidor público: ejecutar `backend/migrate.py` con la cuenta
administrativa y después desplegar el backend que incluye `/sos`. `/ready` debe
devolver `sos_version: 1`. Solo entonces instalar la app nueva conectada al
backend público. Antes de la prueba real, activar Nuevos reportes para el
operador en Configuración → Notificaciones. Probar con cuentas distintas y una
solicitud marcada como prueba; comprobar bandeja, aviso, apertura y reintento.
`backend/verify_sos.py` valida la base en una transacción que revierte sus datos.
