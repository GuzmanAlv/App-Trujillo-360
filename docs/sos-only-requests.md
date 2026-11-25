# Reportes del ciudadano: solo solicitudes SOS

Requiere migración **028**, después de 027, backend y APK nuevos.

La pestaña Reportes conserva dos opciones:

- **Mis Solicitudes:** solo el historial SOS de la cuenta activa. Incluye
  pendientes, confirmados, resueltos y descartados, sin límite de antigüedad y
  con paginación. No mezcla reportes manuales ni solicitudes de otras cuentas.
- **Cerca de mí:** SOS públicos confirmados y resueltos de cualquier ciudadano,
  incluidos los propios, a un máximo de 1.000 metros del GPS del dispositivo.
  Conserva la ventana pública: siete días desde el hecho para casos activos y
  siete días desde la resolución para los cerrados. Se muestran estado y fecha;
  los resueltos no se presentan como pendientes de corroboración.

Se retiran de esta pantalla el enlace de solicitudes antiguas, la consulta de
reportes manuales y su listado. No se borran los registros anteriores de la base.

`GET /incidents/nearby-sos` consulta `trujillo.nearby_sos`, que filtra por vínculo
real con un SOS confirmado antes del límite de resultados y calcula el radio
geográfico con PostGIS. No se excluye al solicitante. No expone identidad,
coordenadas originales del teléfono ni comentarios internos. Los SOS pendientes
y descartados no se convierten en información pública.

El mapa público general conserva su consulta independiente. El adaptador de
cercanía ahora usa la consulta SOS y la pantalla también comprueba `is_sos` para
no mostrar elementos manuales provenientes de copias anteriores.

## Activación

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_nearby_sos.py
.\.venv\Scripts\python.exe migrate_nearby_sos.py --apply
cd ..
```

El primer comando solo comprueba. Aplicar 028 antes de desplegar; `/ready` debe
incluir `nearby_sos_version: 1`. Instalar el APK nuevo en ambos celulares.
No se aplican migraciones ni despliegues automáticamente.
