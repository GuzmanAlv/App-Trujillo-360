# Estados SOS y llegada automática

Confirmar SOS ahora guarda **confirmed + en_route** en una sola transacción:
el ciudadano ve «Unidad en camino», la bandeja y el mapa se actualizan al refrescar,
y el operador vuelve al mapa con su ruta. Si Routes o el GPS fallan, el caso sigue
en camino y se muestra el error. Ya no hay botones manuales de salida/llegada.

Mientras la app del operador permanece abierta, revisa aproximadamente cada 12
segundos sus casos asignados en camino. Solo obtiene GPS si tiene alguno. Al pausar
la app detiene esta comprobación. Requiere GPS y permiso de ubicación habilitados.
El servidor comprueba asignación, cuenta activa, estado del caso y ubicación:

- Distancia máxima de 50 m al punto del incidente guardado en la ficha.
- Precisión declarada por GPS de 30 m o mejor y lectura de hasta 30 s de antigüedad.
- Dos lecturas distintas, con al menos 10 s entre comprobaciones; se reinicia al
  salir del radio, perder precisión o pasar más de 60 s sin lecturas válidas.

Al cumplirlo guarda **on_scene**, visible como «Unidad en la zona», y actualiza
el incidente público en la misma transacción. Registra la llegada en el historial
privado con hora, operador y última posición. No almacena un trayecto GPS público.
Reintentar no duplica eventos ni revierte casos resueltos. El GPS del celular es
evidencia técnica de proximidad; no certifica identidad ni evita ubicaciones simuladas.

Los SOS en camino usan el icono de su categoría con animación de crecimiento y
retorno en el mapa del operador, del titular y público. Al llegar, los mapas
de operador/público distinguen presencia en zona; se respeta desactivar animaciones.
Estas comprobaciones no consultan Google Routes ni recalculan la ruta.

## Activación

Aplicar **022_sos_automatic_arrival.sql** antes del nuevo backend. Conserva cuentas,
reportes e incidentes; migra casos confirmados antiguos sin despliegue al estado
en camino y deja auditoría. El comando sin `--apply` solo comprueba:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_arrival.py
.\.venv\Scripts\python.exe migrate_sos_arrival.py --apply
```

Usa las credenciales administrativas locales ya configuradas, nunca las subas a Git.
Después desplegar Render e instalar APK nuevo en ambos dispositivos. `/ready`
debe incluir `sos_arrival_version: 1`. Esta implementación no ejecuta migraciones
en producción por sí sola.

## Prueba real

1. Solicitar SOS, tomar llamada y confirmar: ver en camino para ambos usuarios,
   ruta en operador y categoría animada. Verificar que el audio continúa.
2. Acercar el teléfono del operador al punto del hecho con GPS activo y app abierta;
   esperar dos lecturas (normalmente 12–30 s) y el siguiente refresco del mapa.
3. Comprobar «Unidad en la zona» en ambos dispositivos y el historial privado.
4. Probar lejos del punto, GPS impreciso, app pausada y otro operador: no marcar llegada.
5. Resolver y volver a acercarse: conservar resuelto sin nuevos eventos.
