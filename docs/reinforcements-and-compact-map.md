# Mapa compacto, refuerzos y reevaluación del SOS

Esta versión requiere la **migración 024**, backend y APK actualizados. Conserva
los datos existentes y no cambia claves ni políticas de Google.

## Interfaz y llamadas

- Se retira `+Reportar` del inicio para todos los roles. Se conserva la consulta
  de reportes existentes. El ciudadano conserva SOS; el operador ve un botón
  naranja de «Solicitar refuerzos» en su lugar.
- La tarjeta de llamada es más baja y se abre tocando su área de texto/tarjeta.
  En operador abre audio con evaluación; en ciudadano abre audio. Micrófono,
  altavoz y colgar conservan sus acciones y no abren la tarjeta al pulsarlos.
- La ruta usa una pequeña insignia de vehículo en la esquina inferior izquierda
  del mapa y una etiqueta de minutos/km. Tocarla abre el detalle, el error si lo
  hay, actualizar y quitar ruta. La ruta de refuerzos se dibuja naranja.
- El aviso previo a la llamada usa la síntesis de voz española del teléfono:
  «Este canal es para emergencias reales. El uso malicioso de las llamadas puede
  ocasionar la revisión y suspensión de tu cuenta». Se detiene antes de conectar
  el micrófono y al cancelar, salir de la app o terminar. No anuncia multas,
  deudas ni cobros inexistentes; no implementa cobros ni suspensión automática.
  Si el dispositivo no tiene voz española, queda el aviso escrito.
- Los diálogos de evaluación separan título de 17 px y texto de 14 px.

## Refuerzos privados entre operadores

Solicitar refuerzos obtiene GPS reciente (hasta 45 s y precisión máxima 100 m).
Se permite una solicitud activa por operador; los reintentos no duplican avisos.
La posición inicial y sus actualizaciones solo se consultan con rol operador/admin.
No entran al mapa ciudadano ni se publican como incidente comunitario.

Los otros operadores reciben una tarjeta naranja durante 5 s, debajo de la cola
de SOS ciudadanos. Permanece un botón lateral de patrulla que pulsa suavemente.
Si hay varias solicitudes, abre una lista; elegir una centra su posición y pide
la ruta al backend. Tocar la tarjeta centra sin calcular; tocar el marcador pide
la ruta. Los marcadores naranjas representan una patrulla con una baliza.

La ruta a un SOS ciudadano asignado tiene prioridad: el cliente conserva esa
ruta y el servidor rechaza una ruta a refuerzos hasta registrar `on_scene`.
El resplandor azul prevalece mientras está en camino. Tras llegar puede aparecer
el naranja si no hay una cola ciudadana que tenga prioridad visual. Los SOS
ciudadanos permanecen arriba y los trabajos FCM de refuerzos se despachan después
de los demás avisos pendientes. No se añade una sirena sonora de refuerzos.

La ubicación se actualiza aproximadamente cada 30 s con la app abierta. Una
solicitud sin renovación caduca a los 15 minutos; el botón inferior permite
finalizarla explícitamente. Al finalizar/caducar se retiran marcador y ruta al
actualizar. Se mantiene el historial privado de solicitudes en la base.

## Descartar después de confirmar

Antes de la llegada, un caso confirmado no se puede descartar. Después de
`on_scene`, el operador asignado (o admin autorizado) puede usar «Descartar
incidente · falsa alarma» con motivo interno obligatorio de al menos 5 caracteres.
El servidor guarda la decisión, la revisión y el historial, marca el mismo
incidente como `discarded` y retira su presencia activa. No elimina evidencias ni
crea un incidente nuevo. La ruta local se quita y el mapa ciudadano se refresca
al detectar el cambio de su caso. Una llamada sin respuesta sigue sin demostrar
que hubo una falsa alarma.

## Activar

Desde la carpeta del proyecto:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_reinforcements.py
.\.venv\Scripts\python.exe migrate_reinforcements.py --apply
```

El primer comando solo comprueba. Aplicar 024 después de 023 y **antes** del
despliegue. Después publicar a la rama de Render, esperar `Live` e instalar el
APK nuevo en ambos roles. `/ready` debe incluir `reinforcements_version: 1`.
La implementación y las pruebas no aplican automáticamente cambios a Supabase.

## Pruebas reales pendientes

1. Dos operadores y un ciudadano: confirmar SOS, solicitar apoyo desde el otro
   operador y comprobar prioridad azul, cola roja encima del aviso naranja de 5 s.
2. Llegar al SOS con GPS: habilitar la ruta naranja, probar lista de varias
   patrullas, nuevos GPS, finalizar solicitud y desaparición de su marcador/ruta.
3. Minimizar/reabrir audio tocando la tarjeta sin perder conversación. Comprobar
   voz previa y que no se transmita al operador al conectar.
4. Descartar después de llegar con motivo: retirar de ambos mapas y conservar
   revisión e historial. Probar que otro operador no asignado y el ciudadano no
   pueden hacer esa reevaluación.
