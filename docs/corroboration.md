# Corroboración del piloto

Tres UID distintos de Firebase deben enviar reportes compatibles. El primer autor
cuenta. Google identifica cuentas, no garantiza que correspondan a tres personas
independientes. Corroborado no equivale a verificado por un operador.

Reglas de migración 005:
- Igual categoría y máximo 100 metros respecto al punto del primer reporte.
- Fecha del reporte dentro de los 15 minutos siguientes a la fecha del primero,
  incluyendo ambos extremos. Un reporte anterior al ancla queda separado.
- Solo se agrupa con incidentes pending/corroborated que no requieran revisión.
- El punto y la hora ancla no cambian con nuevos reportes; no hay expansión en cadena.
- Si hay varias coincidencias, se crea uno pendiente con needs_review=true.
  Se conserva el reporte para revisión; no se elige una coincidencia arbitraria.
- Una cuenta puede aportar una vez por incidente. Un UUID repetido con el mismo
  contenido recupera la respuesta; otro UUID de la misma cuenta para ese incidente
  devuelve 409. No aumenta el conteo ni agrega fotos a otro reporte.
- Un bloqueo por categoría serializa búsqueda, inserción y conteo, incluidos los
  primeros reportes simultáneos. Esta decisión prioriza consistencia en el piloto.

El conteo considera autores distintos de reportes no retirados. Una suspensión
posterior no elimina automáticamente un aporte histórico. No hay aún flujo de
retirada/recuento; esas acciones deben incorporarse con el panel de revisión.
La migración inicializa el conteo histórico sin fusionar ni corroborar incidentes
anteriores automáticamente. Nuevos aportes pueden corroborar candidatos existentes.

La app muestra el conteo y el estado al enviar y al abrir/actualizar el detalle.
La lista conserva el último estado consultado. No hay actualización push ni mapa
comunitario todavía. Los reportes y fotos siguen accesibles solo a su autor;
la consulta del propio detalle incluye el conteo agregado sin revelar otros autores.

## Prueba con cuentas reales

1. Enviar un reporte nuevo con cuenta A: 1 de 3.
2. Cambiar a cuenta B y enviar misma categoría y punto dentro de la ventana: 2 de 3.
3. Cambiar a cuenta C y repetir: corroborado, 3 de 3.
4. Regresar a A, abrir su reporte y pulsar Actualizar detalle: corroborado.
5. Un nuevo envío con A al mismo incidente devuelve que ya aportó.

Puede hacerse en un celular cambiando de cuenta; usar datos marcados como prueba.
En Supabase, reports comparte incident_id y incidents muestra status y
corroboration_count. No se necesitan tres cuentas reales para los tests de base:
verify_corroboration.py usa fixtures revertidos; verify_corroboration_concurrent.py
usa fixtures confirmados temporalmente y los elimina al terminar. Este último
requiere credenciales administrativas y no debe interrumpirse durante la limpieza.
