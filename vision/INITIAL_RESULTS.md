# Prueba exploratoria local — no es validación de precisión

Equipo: RTX 4060 Laptop GPU, PyTorch 2.10.0+cu130.
Modelo/revisión y limitaciones: [MODEL.md](MODEL.md).
SHA256 de los pesos: `fa5aa0d7d4427ea7b81d410f5b5186ed64285ff8bebdd12462d976a36e86cdc0`.

Se comprobó carga estricta de pesos y ejecución completa con un video sintético.
Luego se procesaron dos ejemplos animados publicados por UCF:

| Ejemplo | Ventanas | Salida clase violencia |
|---|---|---|
| fighting.gif | una de 4 s, 40 fotogramas | 0.639 |
| normal.gif | tres de 8 s, 40 fotogramas cada una | 0.052, 0.060, 0.084 |

El ejemplo normal no pudo clasificarse con ventanas de 4 s porque solo contiene
20 fotogramas por ventana. La prueba adicional usa 8 s; no es una comparación
controlada con la escena de pelea. El tramo final de 6 s/30 fotogramas quedó sin
clasificar. No se interpolaron fotogramas para simular información inexistente.

Estas cifras son puntuaciones sin calibrar, no probabilidades de agresión ni
medidas de exactitud. Son dos ejemplos seleccionados, de baja tasa de fotogramas,
sin garantía de independencia respecto al entrenamiento. No permiten elegir un
umbral ni estimar falsas alarmas. No se generaron alertas ni candidatos remotos.

Fuentes de los ejemplos (no se redistribuyen en Git):
- https://www.crcv.ucf.edu/projects/real-world/fighting.gif
- https://www.crcv.ucf.edu/projects/real-world/normal.gif
- Contexto: https://www.crcv.ucf.edu/projects/real-world/

Próxima evaluación: videos originales con FPS y duración suficientes, etiquetas
humanas e intervalos de evento; incluir negativos difíciles como abrazos y deportes.
Separar grabaciones de desarrollo y evaluación, registrar su origen y permiso de
uso, y medir resultados por evento y falsas alarmas por hora. Mantener armas como
otra tarea. Aclarar las condiciones de licencia antes de desplegar el modelo.
