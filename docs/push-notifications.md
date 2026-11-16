# Notificaciones por Firebase Cloud Messaging

Estado al 16 de noviembre de 2026: FCM está configurado en el backend público. El backend usa `push_migrations` versión 3 para conservar el envío de SOS junto con el seguimiento de ubicación. Render despliega desde `codex/notificaciones-fcm`; `/ready` debe devolver `push_version: 3`. La credencial privada del emisor se conserva fuera de Git y del APK.

## Avisos ciudadanos

En Configuración → Notificaciones se activa “Incidentes cerca de mí” y se elige un radio de 100 a 3000 metros. Android solicita notificaciones y ubicación “Permitir todo el tiempo”. La app inicia un servicio de ubicación con aviso permanente; actualiza el servidor al desplazarse y renueva la posición periódicamente. No es necesario elegir un centro en el mapa. Las suscripciones antiguas de zona fija se desactivan al abrir la versión nueva y deben activarse de nuevo.

El servidor solo encola un aviso cuando el incidente pasa a estado público y está dentro del radio de una ubicación reciente. Para el modo móvil, una posición de más de 20 minutos no se usa ni al crear el aviso ni antes de enviarlo. No se anuncian incidentes antiguos al activar avisos. Un reporte pendiente no genera aviso ciudadano.

## Operadores y SOS

“Nuevos reportes para el operador” solo aparece para cuentas con rol `operator` o `admin` activo. El servidor también verifica el rol al registrar el dispositivo y antes de enviar. Los reportes nuevos y solicitudes SOS generan avisos privados para los operadores suscritos. SOS no crea un incidente público ni promete atención inmediata.

Los tokens FCM están en tablas privadas. La cola usa claves únicas por dispositivo/evento, reintentos, caducidad y comprobación de permisos antes del envío. El texto del aviso evita direcciones, identidad de denunciantes y descripciones privadas. Tocar el aviso consulta el caso con la sesión y los permisos actuales. Al cerrar sesión se desvincula el dispositivo o se invalida el token.

La entrega depende de Internet, Firebase y Android. Una detención forzada o permisos revocados impiden mantener la ubicación y recibir avisos hasta volver a abrir/configurar la app. El aviso no sustituye un servicio de emergencias.

## Prueba

1. Activar los permisos y “Incidentes cerca de mí” en un celular ciudadano.
2. Activar avisos de operador en una cuenta autorizada, preferiblemente en otro celular.
3. Enviar un reporte de prueba: debe avisar al operador. Confirmarlo o corroborarlo según las reglas de publicación: debe avisar al ciudadano solo si está cerca de una ubicación reciente.
4. Probar incidentes fuera del radio, reportes pendientes, app en segundo plano, renovación de token y cambio de sesión.
5. Medir el retraso de actualización de ubicación y entrega en un dispositivo real. Las pruebas automáticas no garantizan recepción en Android.

Para desarrollar el backend local, configurar la credencial FCM mediante secretos fuera del repositorio y aplicar `backend/migrate.py` antes de iniciar la API. Nunca imprimir, copiar al APK ni subir a Git tokens o credenciales privadas.
