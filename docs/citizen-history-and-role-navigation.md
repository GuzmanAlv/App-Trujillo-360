# Historial ciudadano y navegación por rol

Requiere migración **027** después de 026 y actualizar backend y APK.

- Operador/admin: pestañas Mapa, Operador y Configuración. Se retira la pestaña
  general Reportes; las herramientas de revisión dentro de Operador se conservan.
- Ciudadano: Mapa, Reportes y Configuración. Reportes abre «Mis reportes» con
  historial de SOS y reportes anteriores. «Cerca de mí» sigue disponible.
- El historial SOS conserva pendientes, confirmados, resueltos y descartados sin
  límite de antigüedad; pagina de 50 en 50 con «Cargar SOS anteriores». Solo devuelve
  solicitudes de la propia cuenta activa, sin comentarios internos ni datos del operador.
  Al tocar un registro se muestra su estado, fecha y datos del hecho disponibles.
- La consulta privada `/my-sos/history` es independiente de `/my-sos`: consultar
  el historial no vuelve a activar marcadores, alarmas ni llamadas de casos cerrados.
- El mapa público sigue compartido por todos los roles: confirmados recientes y
  resueltos durante siete días desde el cierre. Se conserva el color de categoría;
  los resueltos quedan estáticos y muestran fecha/hora al tocarlos. Descartados y
  SOS privados pendientes no se publican a ciudadanos.
- Se limpia y recarga el mapa al cambiar de sesión, sin depender de la pestaña Reportes.

Render anunció `resolved_map_version: 1` durante la revisión. Esto comprueba la
versión del servidor, no la instalada en cada celular. Para probar un segundo
operador, instalar el mismo APK nuevo, elegir «Recientes» y «Todos», y abrir la
zona del incidente. Las pruebas con PostgreSQL aislado verifican que tanto el
operador asignado como otro operador y un ciudadano pueden leer el incidente
confirmado/resuelto público. No se inspeccionó el segundo celular directamente.

## Activación

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_citizen_history.py
.\.venv\Scripts\python.exe migrate_citizen_history.py --apply
cd ..
```

Aplicar antes de desplegar. El primer comando solo comprueba; `/ready` debe incluir
`citizen_history_version: 1`. Después desplegar Render e instalar el APK nuevo en
ambos teléfonos, compilado con `MAPS_ENABLED=true` y `BACKEND_URL` del servicio.
La implementación no ejecuta migraciones ni despliegues en producción.
