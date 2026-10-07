# Reportes cercanos y propios

La pantalla Reportes contiene Cerca de mí y Mis reportes. Cerca de mí requiere activar la ubicación e iniciar sesión; consulta incidentes activos de los últimos siete días dentro de 3 km (hasta 200), ordenados por distancia. El movimiento actualiza la distancia y consulta el servidor como máximo una vez cada diez segundos. El seguimiento se detiene al cambiar de apartado o salir de la aplicación.

Mis reportes consulta GET /reports al iniciar sesión, abrir el apartado o actualizarlo. El servidor aplica RLS para devolver solo el historial de la cuenta activa. Se combina por request_id con sus copias locales y pendientes sin duplicados. No incluye reportes anónimos ni de otras cuentas. Las fotos se recuperan mediante el detalle privado del reporte.

Aplicar la migración 006 con el procedimiento habitual (`python migrate.py` desde backend) y reiniciar el backend para habilitar GET /incidents/nearby. La consulta devuelve resúmenes de incidentes; no devuelve identidad, descripción privada ni fotos de los autores. El detalle comunitario muestra categoría, distancia, hora, coordenadas y estado.
