# Reportes y verificación en la demostración local

Esta versión prueba la agrupación y revisión en un solo dispositivo. Los
perfiles Vecino 1–4 y Administrador de prueba son ficticios y cualquiera puede
seleccionarlos. No hay cuentas reales, autenticación, envío a otros dispositivos
ni conexión con autoridades. No usar esta demostración para evidencias reales.

## Regla inicial

- Cada observación es un `Report`; un `Incident` agrupa observaciones.
- Deben tener la misma categoría, estar a no más de 150 metros del primer
  reporte y dentro de los 30 minutos posteriores a su fecha.
- La ubicación y fecha del primer reporte quedan fijas para evitar que cadenas
  de reportes amplíen indefinidamente el área o el periodo.
- Si hay varios casos compatibles, se elige el más cercano; los empates se
  resuelven por identificador. Las categorías actuales son Robo, Auxilio,
  Agresión y Riesgo.
- Con tres perfiles de vecino distintos el caso aparece como **Sin verificar**.
  Repetir reportes del mismo perfil conserva las observaciones pero suma una
  sola persona. La coincidencia no demuestra que el hecho sea real.
- El administrador ve todos los casos desde el primer reporte, incluidos los
  reportes anteriores sin autor. Puede **Verificar** o **Descartar** con un motivo.
- Verificar permite mostrar el caso aunque tenga menos de tres perfiles.
  Descartar lo retira del mapa incluso si alcanza el umbral. Nuevas observaciones
  compatibles no revierten la decisión. El administrador puede corregirla con
  una nueva revisión y motivo.
- Se conserva la última revisión con perfil, fecha y motivo. No constituye un
  historial de auditoría de producción.
- La ventana de 30 minutos decide la agrupación, no la caducidad en el mapa.
  Los casos visibles permanecen en esta demo mientras no se descarten.
- No existen estados de atención ni asignación a equipos de emergencia.

## Probar sin clave de Maps

1. Ejecutar la app en modo local. Seleccionar **Vecino 1** en Perfil de prueba.
2. Pulsar Reportar. Elegir Robo, escribir una referencia y usar coordenadas
   ficticias, por ejemplo `-8.1116`, `-79.0288`. Guardar.
3. En Mis reportes se ve el caso, pero el contador del mapa sigue en cero.
4. Repetir con Vecino 2 y Vecino 3, la misma categoría y coordenadas, en menos
   de 30 minutos. Ahora hay un caso visible, con tres perfiles, sin verificar.
5. Seleccionar Administrador de prueba y abrir Revisión. Abrir el caso,
   escribir un motivo y Verificar. El estado cambia a Verificado.
6. Descartar con motivo lo oculta del mapa. Los reportes permanecen guardados.
7. También se puede verificar un caso de un solo perfil desde Revisión.

Con Maps desactivado se muestra una lista de los casos elegibles en el panel de
mapa. Con una clave configurada se representan por un único marcador por caso:
naranja sin verificar y verde verificado. El detalle y la lista incluyen texto
de estado para no depender solamente del color.

## Persistencia y migración

El formato v2 conserva los reportes asociados y la última revisión en
SharedPreferences. Al iniciar con datos v1, cada reporte se conserva como caso
sin verificar y autor desconocido; no se inventan personas para alcanzar el
umbral. El administrador puede revisarlo. El archivo lógico v1 no se borra:
el primer cambio exitoso guarda una copia migrada en v2. Datos ilegibles
bloquean cambios y se conservan sin sobrescribir.

## Paso posterior para usuarios reales

El servidor deberá asignar identidades autenticadas y roles, controlar el
conteo de personas, validar coordenadas y fechas, conservar auditoría y decidir
qué casos puede consultar cada usuario. Cambiar de perfil en esta demo no
equivale a tres personas reales y no implementa seguridad de producción.
