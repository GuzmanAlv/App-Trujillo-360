# Reportes y mapa

Cerca de mí consulta incidentes activos de los últimos siete días a 1 km de la ubicación GPS, ordenados por distancia (hasta 200). El círculo verde translúcido del mapa tiene un radio independiente de 500 m. Inicialmente se centra en el GPS; al tocar el mapa se centra en el punto elegido. Un punto naranja marca el centro seleccionado. Volver a mi ubicación restaura su centro al GPS sin cambiar el zoom y elimina el punto naranja. El punto azul y Cerca de mí conservan la ubicación real. El círculo no limita los incidentes del área visible.

El mapa solo muestra incidentes corroborados por al menos tres cuentas diferentes, sin revisión ambigua, o verificados que también cumplen ese mínimo. Cada marcador representa un incidente agrupado. Se conservan las reglas: mismo tipo, hasta 100 m y dentro de 15 minutos desde el primer reporte; cada cuenta cuenta una vez. Los aportes posteriores compatibles siguen en el mismo grupo. Al abrir un marcador, GET /incidents/{id}/reports muestra los resúmenes de sus aportes (tipo, hora y coordenadas), sin identidades ni descripciones privadas; las fotos se consultan separadamente solo mientras el incidente cumple la corroboración. Los reportes pendientes permanecen en Mis reportes y Cerca de mí.

El mapa consulta GET /incidents/map con los límites del área visible al detenerse la cámara. Muestra incidentes de esa zona aunque estén lejos del GPS, con un máximo de 500 por vista. Si se alcanza el máximo, invita a acercar el mapa. Las respuestas de áreas o sesiones anteriores se descartan. Los filtros por categoría se aplican en ambas vistas. Los resúmenes comunitarios no incluyen identidad, descripción privada ni fotos.

Mis reportes consulta GET /reports al iniciar sesión, abrir el apartado o actualizarlo. RLS devuelve solo el historial de la cuenta activa. Se combina por request_id con sus copias y pendientes locales sin duplicados; las fotos se recuperan mediante el detalle privado. No incluye reportes anónimos ni de otras cuentas.

Aplicar python migrate.py desde backend hasta versión 011 y reiniciar el servidor. verify_map_database.py comprueba las consultas reales por área y por distancia, revirtiendo sus datos de prueba.

Cerca de mí permite alternar Todos (selección inicial) y Corroborados (al menos tres cuentas, estado corroborated o verified, sin coincidencia ambigua). Se combina con la categoría elegida y el radio de 1 km. Este filtro no se muestra ni se aplica en Mis reportes.

El mapa conserva marcadores superpuestos mientras consulta otra área, reutiliza hasta ocho áreas durante 20 segundos (solo respuestas completas para subáreas) y conserva iconos. La espera tras cámara detenida baja a 120 ms. Las imágenes se descargan por separado al abrir el detalle; cada lectura valida cuenta activa, incidente corroborado por al menos tres cuentas, sin revisión y vigente. No se incluyen imágenes en las respuestas del mapa.
