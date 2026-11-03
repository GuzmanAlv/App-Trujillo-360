# Notificaciones por Firebase Cloud Messaging

Estado al 3 de noviembre de 2026: backend ad57a66 desplegado en Render desde
codex/notificaciones-fcm, deploy dep-dbl0sfvf3r2c73850340. /ready confirma base 11,
workflows 1 y push 1. El emisor permanece deshabilitado: la organización aplica
iam.disableServiceAccountKeyCreation y la cuenta actual no tiene permisos
orgpolicy.policies.create/delete/update. No se generó ni descargó ninguna clave.
La cuenta trujillo-notificaciones está creada con roles/firebasecloudmessaging.admin.
El propietario/administrador debe resolver la política antes de probar envíos reales.
No se cambió la política de la organización ni se contrató un plan de pago.

La app Android usa la configuración Firebase existente. Configuración →
Notificaciones reemplaza las antiguas alertas por consulta en primer plano.
Cada instalación/cuenta puede activar una zona fija (100–3000 m) y los operadores
autorizados pueden activar avisos de reportes. Solo se pide permiso al guardar
una suscripción activa. No se requiere ubicación en segundo plano.

El backend guarda tokens en tablas privadas con RLS, sin exponerlos por HTTP.
Una cola transaccional anuncia cada reporte al operador y cada transición a
incidente público a los ciudadanos suscritos cuya zona coincide. La urgencia no
publica un reporte. Los avisos públicos requieren menos de siete días de antigüedad.
No se anuncian incidentes antiguos al habilitar una suscripción.

La cola usa claves únicas por evento/dispositivo, leases, reintentos con espera y
caducidad. Antes de enviar se comprueban de nuevo rol, cuenta activa, suscripción,
zona y estado público. FCM usa un tag estable para reemplazar posibles duplicados
visuales. Como con cualquier sistema push, no hay garantía de entrega exactamente
una vez ni de atención inmediata. Los textos no contienen direcciones, identidades
de denunciantes ni descripciones privadas. Al tocar el aviso se consulta de nuevo
el caso con autenticación y permisos actuales. Cerrar sesión desvincula el registro
o invalida el token antes de salir; se borran los avisos visibles del dispositivo.

## Credencial del servidor

La API de Firebase Cloud Messaging V1 ya está habilitada en el proyecto
project-43edb74d-04c5-4d00-962. Falta una credencial privada autorizada de servidor.
Crear preferiblemente una cuenta de servicio exclusiva con el rol
roles/firebasecloudmessaging.admin. Su clave JSON debe guardarse en
backend/.secrets/fcm-service-account.json (directorio ignorado por Git), o indicar
GOOGLE_APPLICATION_CREDENTIALS en backend/.env.push. El proyecto de la clave debe
coincidir con FIREBASE_PROJECT_ID. Nunca imprimir, subir a Git ni incluir en el APK.

Copiar backend/.env.push.example a backend/.env.push y poner PUSH_ENABLED=true
solo cuando exista esa credencial. Reiniciar el backend para iniciar el worker.
Sin credencial o sin habilitación explícita la app permite guardar preferencias
pero indica que el envío aún no está operativo. No simula una recepción exitosa.

Aplicar python migrate.py antes de arrancar la versión nueva del servidor.
La extensión de notificaciones usa push_migrations versión 1 y conserva la base 11.
La prueba python verify_push.py ejercita permisos, geografía y cola en una sola
transacción que siempre revierte. No envía mensajes a Firebase.

## Servidor público y prueba real

Un APK USB requiere laptop y servidor local para generar y despachar avisos.
El backend público ya está desplegado; aún falta habilitar la credencial como Secret File (GOOGLE_APPLICATION_CREDENTIALS)
o variable secreta FIREBASE_SERVICE_ACCOUNT_JSON, y PUSH_ENABLED=true. Recompilar
el APK con BACKEND_URL=https://trujillo-360-api.onrender.com, sin USB_BACKEND.
El proceso del servidor debe permanecer disponible: un alojamiento suspendido
puede retrasar el procesamiento de la cola. No se activa ningún plan de pago
automáticamente.

Verificación final: activar permisos y zona con una cuenta ciudadana; activar
avisos con la cuenta de operador autorizada, preferiblemente en otro teléfono.
Con las apps en segundo plano, crear un reporte y comprobar el aviso al operador;
verificarlo y comprobar el aviso al ciudadano de la zona. Comprobar que fuera de
zona, desactivando avisos o usando un reporte pendiente, no llega aviso ciudadano.
Tocar cada aviso debe abrir el caso correspondiente. Probar también con arranque
en frío, renovación del token y cierre/cambio de cuenta. Forzar detención desde
Android impide recibir hasta volver a abrir la app.

Referencias oficiales:
- https://firebase.google.com/docs/cloud-messaging/send/v1-api
- https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- https://firebase.google.com/pricing
