# Descarte durante el trayecto y controles sobre el mapa

Esta versión sustituye la restricción de «descartar solo después de llegar».
Requiere **migración 025**, backend y APK actualizados.

## Descarte y suspensión

El operador asignado o un administrador puede descartar un SOS pendiente,
confirmado en camino o en zona. El diálogo tiene tres opciones:

- **Cancelar:** no envía cambios.
- **Descartar:** retira el caso/incidente del mapa y finaliza la llamada;
  conserva activa la cuenta del ciudadano.
- **Descartar y bloquear:** hace lo anterior y deja la cuenta ciudadana con
  `status = suspended`, con el motivo vinculado al SOS.

Ambos descartes requieren un motivo nuevo de al menos 5 caracteres. Se guardan
operador, fecha, acción, motivo y estado en el historial privado. No se eliminan
evidencias ni se crea otro incidente. Los reintentos reutilizan la solicitud y no
duplican sanciones/revisiones. La transacción hace juntos el descarte y la suspensión.

Un ciudadano o un operador no asignado no puede ejecutar esta acción. El flujo
no permite suspender cuentas de operador/admin. La suspensión es de acceso al
backend de Trujillo 360; Google/Firebase pueden seguir autenticando al usuario,
pero las operaciones de la app se rechazan mientras esté suspendido. No se
implementan cobros ni deudas. No hay reactivación automática ni un nuevo botón
de reactivación; una revisión administrativa debe restablecer el estado cuando
corresponda. Los otros reportes del titular se conservan para revisión.

El servidor marca terminada la llamada del caso. La app operadora también cierra
su sesión de audio y solicita cerrar la sala LiveKit. El otro teléfono detecta el
fin o la denegación de acceso en su siguiente comprobación de sesión.

## Mapa ampliado

Se elimina el pie de acciones que restaba altura al mapa y se conservan el logo,
la cabecera y la navegación de la app.

- El icono rojo de llamada está abajo a la izquierda y abre audio/evaluación.
  Micrófono, altavoz y cortar están a su derecha, sin una tarjeta ancha con texto.
- Si hay ruta, su icono azul y tiempo/km quedan debajo de la llamada.
- Solo una cuenta ciudadana activa con rol ya comprobado ve el SOS de mantener
  tres segundos, superpuesto en el centro inferior del mapa.
- El operador no tiene botón SOS ni botón para iniciar refuerzos. Los avisos de
  refuerzos ya existentes se conservan y su titular puede finalizarlos tocando su
  propio marcador. No se borran registros de refuerzos.
- Los controles se ordenan en una columna de altura variable y dejan libre el
  borde derecho para GPS. Google Maps recibe un margen para sus elementos nativos.
  El aviso de GPS del operador es un icono con detalle al tocarlo, sin otra fila
  que reduzca el mapa.
- En Evaluación SOS, el resplandor rojo ocupa 28 px y la mitad de la intensidad
  anterior. El resto de las alertas del mapa conserva su presentación.

## Activación

Desde la carpeta del proyecto:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_suspension.py
.\.venv\Scripts\python.exe migrate_sos_suspension.py --apply
```

El primer comando solo comprueba. Aplicar 025 después de 024 y **antes** de
desplegar. Luego publicar a Render e instalar el APK nuevo. `/ready` debe incluir
`sos_suspension_version: 1`. La implementación no aplica migraciones a la base
compartida ni despliega por sí sola.

## Prueba real

1. Confirmar un SOS, abrirlo durante el trayecto y cancelar el diálogo: conservar
   caso, llamada y cuenta. Repetir con Descartar: quitar caso/ruta y cerrar audio.
2. Con otra cuenta ciudadana de prueba, elegir Descartar y bloquear y registrar
   motivo: verificar estado suspendido, historial y rechazo a nuevos SOS/operaciones.
3. Comprobar que otra cuenta operadora no asignada no puede sancionar el caso.
4. En un celular estrecho, verificar llamada encima de ruta/SOS, GPS libre y el
   botón ciudadano de tres segundos. Abrir la llamada con el icono rojo.
5. Probar reducción de luz en la evaluación y mantener funcionamiento del aviso
   hasta tomar la llamada. Verificar que el mapa del otro celular se actualiza.
