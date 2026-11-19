# Atención SOS, avisos y llamadas minimizadas

Esta versión requiere **migración 023**, backend y APK nuevos. No modifica claves.

## Operador

- Al confirmar se conserva la ruta y el estado `en_route`. El mapa muestra un
  resplandor azul y una tarjeta del caso asignado. Quitar la ruta no quita el caso.
- Mientras tenga un caso asignado confirmado en camino o en zona, los otros SOS
  se mantienen en la cola y en notificaciones discretas: sin alarma ni luz roja.
  La asignación se comprueba en el servidor al preparar el aviso FCM y en la app.
- Al llegar, el estado `on_scene` actualiza la tarjeta azul a «Ya llegaste a la
  zona · Evaluar SOS»; tocarla abre la evaluación. Al resolver vuelve a estar disponible.
- En una evaluación entrante, el botón de llamada tiene halo rojo suave y pulso;
  el resplandor rojo ocupa los bordes de la pantalla hasta tomar la llamada.
  Se conserva la excepción de avisos discretos si ya está atendiendo otro caso.

## Ciudadano

- Al enviar SOS, se solicita permiso de notificaciones si falta y se registra el
  celular para los avisos de su propio caso. Esto no activa «Incidentes cerca de mí»
  ni requiere ubicación permanente. El registro conserva las preferencias existentes.
- La llegada se notifica solo al titular, con una tarjeta inferior del mapa y
  señal de sonido/vibración durante 5 s. Se deduplican el sondeo y el FCM en primer
  plano. La hora de llegada permite evitar alertar por casos antiguos al abrir la app.
- Una devolución de llamada muestra «El operador te llama», reproduce timbre y
  vibración. Se detienen al aceptar, ocultar o silenciar. Las nuevas devoluciones
  del mismo caso vuelven a avisar. Las invitaciones caducadas/contestadas se descartan.
- Retroceder desde el audio vuelve al mapa **sin colgar**. La barra compacta
  conserva micrófono, altavoz, colgar y «Abrir llamada», para ambos roles.
  Solo finalizar explícitamente, cerrar sesión o terminar la llamada remotamente
  cierra esa sesión de audio. La ejecución de llamadas con la app cerrada sigue
  dependiendo de las restricciones del sistema; no hay interfaz de llamada de bloqueo.

Android usa canales separados para SOS entrante, avisos discretos, devoluciones
y llegada. Respeta el volumen, silencio y No molestar del dispositivo. Los tonos
en primer plano tienen renovación acotada para que no queden sonando al cerrar
la pantalla. FCM avisa en segundo plano cuando hay permiso, conectividad y envío
Firebase habilitado; no requiere una segunda cuenta de servicio.

## Menú del mapa

El menú conserva los filtros existentes y organiza periodo, categorías con iconos
y franja horaria en tarjetas. El historial continúa agrupando todas las categorías.

## Activación

Desde la carpeta del proyecto, comprobar y aplicar antes de desplegar:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_notifications.py
.\.venv\Scripts\python.exe migrate_sos_notifications.py --apply
```

El comando sin `--apply` solo consulta. Conserva datos y preferencias, añade avisos
privados y no reenvía llegadas antiguas. Después publicar el código en la rama de
Render, esperar `Live` e instalar el nuevo APK en ambos celulares. `/ready` debe
devolver `sos_notifications_version: 1`. Las pruebas usan una base temporal local;
no se ha aplicado esta migración ni desplegado producción automáticamente.

## Prueba con dos celulares

1. Permitir notificaciones en el ciudadano y enviar SOS. Revisar el halo del botón
   y los bordes al abrir la evaluación. Tomar la llamada y confirmar.
2. Retroceder en ambos teléfonos y verificar audio continuo, controles compactos
   y reapertura sin nueva llamada. Colgar desde la barra y comprobar fin remoto.
3. Enviar otro SOS desde otra cuenta: el operador asignado recibe solo la cola
   discreta; otro operador disponible mantiene la alerta roja habitual.
4. Acercarse al punto con GPS válido y app del operador abierta: tarjeta azul de
   llegada y acceso a evaluación; en ciudadano, tarjeta inferior y señal de 5 s.
5. Repetir con ciudadano en segundo plano y comprobar la notificación FCM.
6. Devolver la llamada, silenciar/ocultar y repetir desde el mismo caso. Comprobar
   que vuelve a timbrar y que al responder se detiene.
7. Cerrar sesión/cambiar cuenta: no conservar audio, tarjetas ni avisos del titular anterior.
