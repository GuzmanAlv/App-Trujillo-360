# Celular como cámara de simulación

El celular captura video en su navegador, la RTX analiza secuencias de 32 imágenes
distribuidas en unos 4 segundos, y la API registra los posibles forcejeos dentro
de la sesión de prueba. No requiere instalar otro modelo en el teléfono.

Esta primera conexión usa Android conectado por USB. El servicio se limita a
`127.0.0.1`; no abre un puerto en la red Wi-Fi. `getUserMedia` requiere localhost
o HTTPS, por lo que abrir `http://<IP-de-la-laptop>:8765` no habilita la cámara.
Fuente: https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia

## Preparar

Desde la raíz del repositorio:

```powershell
uv pip install --python vision/.venv/Scripts/python.exe -r vision/requirements-simulation.lock.txt --extra-index-url https://download.pytorch.org/whl/cu130
vision\.venv\Scripts\python.exe vision\check_gpu.py
```

Los pesos fijados en [MODEL.md](MODEL.md) deben existir en `vision/weights/`.
Se comprueba su SHA256 antes de cargar el modelo. Las pruebas de reglas de cámara
se ejecutan con:

```powershell
vision\.venv\Scripts\python.exe -m pytest -q vision/test_simulation_camera.py
```

## Crear la sesión y conectar el celular

1. Ingresar con la cuenta autorizada en el portal de operadores. Crear una sesión
   de cámara de simulación y elegir su ubicación. Copiar su ID y el `workerToken`
   que se muestra una sola vez. El servidor valida la cuenta y los permisos; el
   token efímero solo puede publicar resultados de esa sesión.
2. En PowerShell, definir el token de manera local. No guardarlo en archivos ni
   compartirlo con otros operadores. Dura como máximo lo que dure la sesión.
3. Iniciar el proceso en la laptop:

```powershell
$env:TRUJILLO_SIM_TOKEN = Read-Host 'Token efímero de la sesión'
vision\.venv\Scripts\python.exe vision\simulation_camera.py --session ID-DE-LA-SESION --api-base https://URL-DE-LA-API
```

Para una API local en la misma laptop se admite `--api-base http://127.0.0.1:8000`.
El token del worker se envía únicamente a esa API desde la laptop, nunca al
navegador del celular. No es un token Firebase ni una credencial administrativa.

4. Conectar Android por USB, habilitar depuración USB y autorizar esta laptop.
   Ejecutar `adb reverse tcp:8765 tcp:8765` (usar la ruta del SDK si `adb` no está
   en PATH). Si hay varios dispositivos, seleccionar el segundo celular con
   `adb -s SERIAL reverse tcp:8765 tcp:8765`.
5. Abrir en Chrome del celular el enlace `http://localhost:8765/#pair=...` que
   imprime el servicio local. El fragmento es una vinculación aleatoria de 30
   minutos y no se incluye en las solicitudes HTTP ni los logs de acceso.
6. Pulsar **Iniciar cámara** y aceptar el permiso del navegador. Mantener el
   celular fijo y esta pantalla visible. La ubicación del caso será la elegida
   al crear la sesión, no una ubicación inferida de los fotogramas.

El navegador solicita solo video; no solicita micrófono. La página envía una
secuencia a la vez y espera a que la RTX y la API respondan. Se detiene al ocultar
la página, perder conexión, vencer la sesión o fallar la API. Un resultado ya
enviado puede finalizar después de pulsar **Detener**; revisar la bandeja y cerrar
la sesión desde el portal al terminar. `Ctrl+C` cierra el servicio de la laptop.

## Resultado y límites

El backend decide cuándo registrar el caso: exige dos ventanas consecutivas por
encima del umbral de simulación y aplica un intervalo para evitar duplicados.
La página informa si espera otra secuencia, si creó un caso o si está en ese
intervalo. La puntuación es experimental; el operador revisa y atiende el caso.

Los JPEG se procesan en memoria y no se guardan como evidencia. Esta versión no
transmite audio, no ofrece reproducción histórica, no detecta armas y no tiene
captura continua durante el breve tiempo de inferencia/envío. Se comprueba la
secuencia temporal, tamaño de las imágenes, acceso de vinculación y permisos del
backend; sigue siendo una simulación con un modelo aún no validado en esta cámara.

No se ha realizado una prueba física con el segundo celular: requiere conectarlo,
conceder el permiso de cámara y crear la sesión con la cuenta correcta.

## Verificación realizada

- 16 pruebas de autenticación local, límites, formato, errores y reintentos
  idempotentes aprobadas.
- Solicitud completa al endpoint local con JPEG de un ejemplo público, modelo
  real en CUDA y publicador sustituido por una respuesta local. Verifica que la
  puntuación proviene de la RTX; no crea casos remotos ni mide exactitud.
