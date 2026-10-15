# Alertas cercanas y arranque

En Configuración, activar «Alertas a 500 metros» y conceder ubicación y notificaciones. Requiere iniciar sesión. En Android se muestra una notificación del sistema y dentro de la app un aviso con «Ver ubicación». En web se muestra el aviso dentro de la app.

La consulta existente de Cerca de mí se repite cada 15 segundos aunque el GPS no cambie, mientras la app esté en primer plano. El radio de alerta es 500 m desde el GPS real; los filtros visuales y el círculo de exploración no lo alteran. Se admiten incidentes pending/corroborated/verified sin exigir corroboración. Solo se avisan incidentes ocurridos después de activar/iniciar la sesión de alertas y con antigüedad máxima de 15 minutos. Cada incidente se avisa una vez por sesión. La preferencia de activación se conserva. El feed existente devuelve hasta 200 incidentes por proximidad; ese límite también aplica a esta primera versión.

Tocar la notificación abre el detalle con categoría, hora, distancia disponible y minimapa ampliable. Cerca de mí abre ese mismo detalle. Un pendiente mantiene su etiqueta y no se agrega al mapa comunitario. No se consultan fotos ni descripciones privadas. La distancia mostrada al abrir depende de la última ubicación disponible.

La detección se detiene al minimizar/cerrar la app. Esta versión no implementa ubicación en segundo plano ni envío FCM desde el servidor. El registro FCM antiguo no activa esas funciones. Una notificación ya emitida sí puede abrirse después; representa un reporte histórico y no confirma vigencia ni atención oficial.

El arranque muestra el icono en Android y el logo durante la inicialización de Flutter/Firebase/almacenamiento, con reintento si falla. Web muestra el logo mientras descarga Flutter.

## Prueba en dos dispositivos

1. Instalar una compilación Android nueva (hot reload no incorpora Kotlin ni los recursos nativos). Iniciar sesión, activar alertas y GPS en A; mantener la app visible.
2. Desde B crear un incidente nuevo, con hora actual y a menos de 500 m de A. Puede ser el primer reporte, sin corroboración.
3. En A esperar una consulta (15 segundos más la latencia del servidor), abrir el aviso y comprobar el detalle y minimapa. El incidente pendiente no debe aparecer en el mapa comunitario.
4. Esperar otra consulta: no debe repetirse. Probar uno a más de 500 m y uno cerrado: no deben alertar.
5. Reiniciar la app para comprobar el logo y la preferencia. Minimizarla para comprobar que el seguimiento se pausa.
