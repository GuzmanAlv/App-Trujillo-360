# Modelo candidato para evaluación offline

Fuente: https://huggingface.co/visionlab-ai/school-violence-detection-models
Revisión fijada: `a744b6af7496f0cbfa4f0ba32acd46b65e52d4e1`.
Pesos: `r2plus1d_18/r2plus1d_best.pt`, descargados en `weights/` (fuera de Git).
Carga con `torch.load(weights_only=True)`; no se ejecuta código del repositorio.

R(2+1)D-18 ajustado por el publicador para clasificar clips como violentos o no
violentos. Modelo de terceros, no entrenado ni validado por Trujillo-360. La ficha
indica entrenamiento con RWF-2000; sus resultados publicados no son resultados
en nuestras cámaras. No detecta armas ni identifica al agresor o a la víctima.

La tarjeta declara MIT, pero su descripción añade uso de investigación/no comercial;
el dataset de origen también tiene restricciones. Se mantiene como experimento
local: no se considera aclarada su autorización para un despliegue comercial.

El script usa ventanas consecutivas de 4 segundos, 32 fotogramas uniformes, RGB,
224x224, media .45 y desviación .225 según configuración/ficha. El redimensionado
directo es una decisión de este prototipo; el preprocesamiento exacto de entrenamiento
no está totalmente documentado. La última ventana puede ser más corta; si tiene
menos de 32 fotogramas se registra sin clasificar. No hay agrupación de eventos,
umbral validado, procesamiento en vivo ni envío al backend.

Documentación del publicador:
https://huggingface.co/visionlab-ai/school-violence-detection-models/blob/main/r2plus1d_18/MODEL_CARD.md

Para descargar de nuevo desde PowerShell/CMD, desde la raíz del repositorio:

```text
curl.exe --fail --location --output vision/weights/r2plus1d_best.pt https://huggingface.co/visionlab-ai/school-violence-detection-models/resolve/a744b6af7496f0cbfa4f0ba32acd46b65e52d4e1/r2plus1d_18/r2plus1d_best.pt
```

Ejecutar con un video local autorizado:

```text
vision\.venv\Scripts\python.exe vision\analyze_video.py vision\data\development\ejemplo.mp4 --output vision\outputs\ejemplo.json
```

Comparar los intervalos/puntuaciones con anotaciones humanas. Evaluar por separado
escenas normales, abrazos, juegos/deportes y peleas; no interpretar una puntuación
alta aislada como agresión confirmada. Los resultados y videos quedan fuera de Git.
