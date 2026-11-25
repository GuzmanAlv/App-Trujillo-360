# Prototipo de visión — preparación del entorno

Para usar un segundo Android por USB como cámara y crear casos en el mapa de
operadores, consultar [cámara de simulación](../docs/camera-simulation.md).

Entorno independiente del backend. Incluye verificación GPU y un clasificador
experimental de clips violentos/no violentos. No detecta armas ni envía candidatos
a la API. Ver [modelo y ejecución](MODEL.md) antes de interpretar resultados.

La conexión de un celular Android por USB para una **sesión de simulación** se
prepara con el servicio independiente descrito en [PHONE_SIMULATION.md](PHONE_SIMULATION.md).
Ese servicio puede enviar puntuaciones al backend de la sesión autorizada.

Desde la raíz del repositorio, en PowerShell o CMD:

```text
uv venv vision/.venv --python 3.12
uv pip install --python vision/.venv/Scripts/python.exe -r vision/requirements-gpu.txt
uv pip install --python vision/.venv/Scripts/python.exe opencv-python-headless==5.0.0.93
vision\.venv\Scripts\python.exe vision\check_gpu.py
```

No es necesario activar el entorno ni modificar el Python global. La distribución
CUDA se toma del índice oficial de PyTorch. Combinación publicada para Windows:
https://pytorch.org/get-started/previous-versions/#v2100

La verificación debe indicar `cuda_available: true`, `computation_device: cuda:0`
y `computation_verified: true`. Compara una multiplicación ejecutada en GPU con
el resultado CPU; no representa una evaluación de velocidad del modelo.

Comprobación local realizada: Python 3.12.13, PyTorch 2.10.0+cu130, runtime
CUDA 13.0, RTX 4060 Laptop GPU (8187 MiB informados por PyTorch), cálculo en
`cuda:0` verificado correctamente. Dependencias instaladas en `requirements.lock.txt`.
Para reproducirlas, usar el mismo entorno Python y:

```text
uv pip install --python vision/.venv/Scripts/python.exe -r vision/requirements.lock.txt --extra-index-url https://download.pytorch.org/whl/cu130
```

## Siguiente paso: evaluación con videos representativos

Guardar grabaciones locales en `vision/data/` (excluido de Git), con dos grupos:

- `development/`: selección y ajuste inicial del modelo.
- `evaluation/`: evaluación con grabaciones distintas que no se usen para ajustar.

Incluir caminar, correr, abrazos, juegos y forcejeos simulados sin causar daño.
Procurar la perspectiva y distancia de la cámara final. Para cada grabación,
anotar inicio y fin de los eventos, actividad, iluminación y obstrucciones.
No dividir una misma grabación entre ambos grupos. Los videos no se suben a GitHub.

Primero elegir y evaluar un modelo temporal para posibles forcejeos. La detección
de personas/posturas por sí sola no demuestra agresión. Las armas visibles serán
una evaluación separada. Medir eventos omitidos, falsas alarmas por hora, demora
de detección, velocidad y memoria antes de conectar el backend o una cámara en vivo.

## Fuentes de videos por evaluar

- UCF-Crime: https://www.crcv.ucf.edu/projects/real-world/ — página de los autores
  con ejemplos y enlace de descarga; incluye Fighting y Assault. Revisar condiciones
  de acceso/uso antes de incorporar videos al conjunto de pruebas.
- RWF-2000: https://github.com/mchengny/RWF2000-Video-Database-for-Violence-Detection
  — referencia de 2000 clips violentos/no violentos. Los autores indican que los
  videos ya no están disponibles allí por privacidad; requieren autorización para
  usos comerciales y modificación/redistribución. No se ha descargado este conjunto.

Los conjuntos públicos sirven para exploración inicial. La evaluación final debe
incluir escenas representativas de la cámara prevista. Se descargaron únicamente
los ejemplos públicos `fighting.gif` y `normal.gif` de la página de UCF en
`data/public_examples/`. No se descargó el dataset completo ni se entrenó un modelo.
Los ejemplos animados tienen una tasa de fotogramas reducida y no sirven para
estimar precisión. `normal.gif` solo contiene 20 fotogramas por ventana de 4 segundos:
el script lo registra como insuficiente. La ejecución exploratoria con ventanas de
8 segundos cambia la escala temporal y tampoco equivale a una evaluación válida.
