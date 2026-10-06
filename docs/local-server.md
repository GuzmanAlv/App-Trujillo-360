# Servidor local persistente en Windows

La tarea `Trujillo360-FastAPI` inicia el supervisor `backend/run_server.py` al
iniciar sesión en Windows con el usuario que la instaló. Se ejecuta sin ventana
con permisos normales, independientemente de la terminal de Codex.

El supervisor inicia FastAPI en 127.0.0.1:8000 y reintenta diez segundos después
si el proceso termina. Un bloqueo de archivo evita supervisores duplicados;
si el puerto está ocupado, espera sin detener el proceso que lo utiliza.
Windows reintenta iniciar el supervisor si este falla.

Los registros están en `backend/logs/server.log`, con rotación de 2 MB y hasta
tres copias anteriores. No se registran tokens ni cuerpos de reportes. La carpeta
está excluida de Git. Los logs permiten observar arranque, cierre y errores;
una desconexión externa puede aparecer sin motivo detallado.

## Reconectar el celular

Desde la raíz del proyecto, después de conectar y autorizar el USB:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect-phone.ps1
```

Si hay varios dispositivos, agregar `-DeviceId L7VOEAX8TOHAVKIZ`.
La orden restaura adb reverse y comprueba /ready. Se necesita repetirla al perder
el enlace USB; arrancar FastAPI automáticamente no restablece ADB automáticamente.

## Instalar en otro equipo

Preparar backend/.venv, instalar requirements.lock.txt, configurar los archivos
.env.runtime y .env.auth, aplicar migraciones y ejecutar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-backend-task.ps1
```

El bypass se limita a esa ejecución; no cambia la política de Windows.
Para revisar el estado abrir el Programador de tareas y buscar
`Trujillo360-FastAPI`. Para impedir próximos arranques, deshabilitar esa tarea.
No mover la carpeta sin volver a registrar la tarea con su nueva ruta.

La laptop debe estar encendida y sin suspender. El inicio ocurre al entrar a la
sesión, no antes. Esto no convierte la laptop en un hosting accesible por Internet.
La confirmación final de reportes con foto se hace desde la app: iniciar sesión,
enviar un reporte marcado como prueba y verificar el registro en Supabase.
