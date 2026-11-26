# Cámara mediante Tailscale Serve

Instalar Tailscale en la RTX y el teléfono y vincularlos a la misma red privada.
Obtener el DNSName de la RTX mediante `tailscale status --json`, quitar el punto
final y usarlo como origen HTTPS. No usar Funnel: este flujo es privado.

Desde la raíz del repositorio en la RTX, para comprobar red y permiso de cámara:

```powershell
vision\.venv\Scripts\python.exe vision\simulation_camera.py --check-connection --public-origin https://NOMBRE.TAILNET.ts.net
```

En otra terminal de la RTX:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' serve --bg http://127.0.0.1:8765
& 'C:\Program Files\Tailscale\tailscale.exe' serve status
```

Si Serve no está habilitado, el comando muestra un enlace: abrirlo e iniciar la
habilitación en la cuenta. Luego volver a comprobar Serve. El proceso Python
permanece en la primera terminal; Ctrl+C lo detiene.

En Chrome del teléfono, con Tailscale conectado, abrir el origen HTTPS. Debe
mostrar conexión confirmada. Pulsar **Probar cámara** y aceptar el permiso.
Esta vista previa permanece en el teléfono; no envía imágenes ni crea reportes.
Después apagar Wi-Fi y probar con datos móviles para verificar otra red.

Para analizar, detener primero la prueba y crear una sesión de simulación desde
la app como se explica en PHONE_SIMULATION.md. Iniciar en la RTX:

```powershell
$env:TRUJILLO_SIM_TOKEN = Read-Host 'Acceso temporal de la sesión'
vision\.venv\Scripts\python.exe vision\simulation_camera.py --session ID-SESION --api-base https://trujillo-360-api.onrender.com --public-origin https://NOMBRE.TAILNET.ts.net
```

Abrir en el teléfono el enlace HTTPS con vinculación que imprime el servicio.
La clave del backend permanece en la RTX; la página recibe otra clave local.
El programa acepta solo el hostname configurado y mantiene la validación de
origen y vinculación. Sigue escuchando en 127.0.0.1; Serve termina HTTPS y
reenvía a ese proceso. Requiere API, migraciones y permisos de cuenta habilitados.

Documentación: https://tailscale.com/docs/reference/tailscale-cli/serve
