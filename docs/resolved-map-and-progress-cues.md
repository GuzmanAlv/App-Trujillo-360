# Casos resueltos en el mapa y avisos durante el trayecto

Requiere migración **026** después de 025, backend y APK nuevos.

Los incidentes públicos resueltos permanecen siete días desde su resolución.
Se conserva la fecha original del hecho; no se sustituye por la fecha de cierre.
El marcador conserva el color y símbolo del tipo de incidente y no pulsa.
Al tocarlo se muestra una ventana sobre el icono con «Caso resuelto», fecha y
hora del hecho (hora local del teléfono). No abre automáticamente otra pantalla.
Los descartados, privados y pendientes siguen fuera del mapa público.

La base guarda `incidents.resolved_at` al cerrar y no prolonga el plazo por
editar otra información. Para cierres anteriores, la migración utiliza su
`updated_at` existente. Mapa, cercanía y campos públicos comparten el plazo;
los incidentes resueltos no generan nuevos avisos de peligro por proximidad.
Los datos privados de ciudadano y operador no se agregan a esa ventana.

En Android, mientras el operador va hacia un caso (resplandor azul), se emite
un pitido de 120 ms cada seis segundos, a menor volumen que una alarma SOS.
Mientras el ciudadano tiene una unidad en camino, vibra 120 ms cada dos segundos,
sin sonido adicional. Se detienen al llegar/resolver, durante llamadas y en
segundo plano. No elevan el volumen ni sobrepasan Silencio/No molestar.
Los avisos entrantes y de llegada tienen prioridad. Una concesión de 12 segundos,
renovada cada ocho, evita que una sesión perdida mantenga los avisos indefinidamente.
La vibración y el volumen efectivos dependen del dispositivo y sus ajustes.

## Activación

En PowerShell, desde la raíz del proyecto:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_resolved_map.py
.\.venv\Scripts\python.exe migrate_resolved_map.py --apply
cd ..
```

El primer comando solo comprueba. Aplicar 026 **antes** de desplegar Render.
Después `/ready` debe incluir `resolved_map_version: 1` e instalar el APK nuevo
en ambos celulares. No se ejecuta la migración automáticamente.

## Prueba en dispositivos

1. Confirmar un SOS: operador azul con pitido suave, ciudadano naranja con
   vibración cada dos segundos. Iniciar una llamada: comprobar suspensión del aviso.
2. Llegar: comprobar que se detienen ambos avisos de trayecto y se mantiene
   el aviso de llegada ya existente. Probar también segundo plano y No molestar.
3. Resolver: comprobar en ambos mapas el icono estático con su color de categoría, tocarlo y verificar
   fecha/hora del hecho. No debe continuar la sirena de presencia ni la ruta.
4. Descartar otro SOS: comprobar que no aparece como caso resuelto público.
5. El vencimiento exacto a siete días se verifica en PostgreSQL aislado y en el
   modelo de Flutter, sin alterar fechas de la base compartida.
