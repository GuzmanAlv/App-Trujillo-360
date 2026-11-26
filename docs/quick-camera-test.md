# Prueba corta de cámara IA

## Una sola vez

Instalar la app actualizada, configurar Tailscale en la RTX y el teléfono y
mantener las claves de Google/Maps de la instalación existente. La RTX usa el
entorno `vision/.venv-rtx` y Python local en `vision/.python-rtx`.
Dependencia nueva del iniciador: `qrcode==8.2`, incluida en los requisitos.
El backend y la base de datos no cambian para este flujo.

## Inicio normal

1. En la RTX, abrir con doble clic **INICIAR_CAMARA_IA.cmd**. Esperar al QR y
   dejar esa ventana abierta. El modelo se carga una vez. Escanear el QR desde
   el celular con Tailscale conectado.
2. En Trujillo 360, abrir **Operador → Cámaras / IA → Cámara y mapa de simulación
   → Preparar cámara de prueba**. Pulsar **Crear con mi ubicación** (o introducir
   coordenadas de cámara y crear). Pulsar **Copiar acceso completo de cámara**.
3. Regresar a la página de cámara, pegar ese único acceso, pulsar **Conectar
   sesión** y **Iniciar cámara**. No se copian IDs ni claves a la laptop.

El iniciador sirve durante 8 horas por arranque; cada sesión de la app sigue
durando 30 minutos y se puede renovar en el teléfono sin reiniciar el modelo.
El acceso combina ID/clave/vencimiento de esa sesión. No compartirlo. La página
lo envía por HTTPS a la RTX y vacía el campo; la RTX lo conserva solo en memoria.
La vinculación local del navegador se conserva en esa pestaña para poder recargar.
Al conectar otra sesión, la pestaña anterior deja de poder enviar análisis.

Si ya existe un servicio anterior en el puerto 8765, cerrarlo con Ctrl+C una sola
vez antes de usar el nuevo iniciador. El teléfono sigue deteniendo la cámara al
ocultar la página. Usar otro teléfono para consultar el mapa de operadores.

## Prueba de aceptación, aún pendiente en el teléfono actualizado

- 20 segundos de actividad normal: comprobar puntuaciones y si hay falsos avisos.
- 15–20 segundos de forcejeo simulado sin causar daño: comprobar puntuaciones y
  si se registra un caso después de dos ventanas altas. No se garantiza detección.
- En otro teléfono, abrir el caso en el mapa y guardar una atención con motivo.
- Detener la cámara. Repetir con datos móviles del teléfono para comprobar otra red.

Registrar ventanas/eventos omitidos y falsos avisos. Un caso creado y atendido
verifica la integración; no certifica exactitud del modelo ni prueba armas.

## Verificación realizada en desarrollo

- 25 pruebas del servicio de cámara: activación, expiración, renovación sin
  recargar modelo, aislamiento de pestañas, formatos, límites y errores.
- Prueba JavaScript del acceso completo, clave borrada del campo, código inválido
  y recuperación de vinculación tras recarga: `node vision/test_camera_page.cjs`.
- Flutter verifica el contenido copiado del acceso y el flujo de operadores.
- Prueba del servicio con GPU real y fotogramas del ejemplo público de UCF:
  puntuación 0.948 en esta ejecución. Backend sustituido por una respuesta de
  prueba; no se crearon casos remotos. QR generado y decodificado con OpenCV.
  Son comprobaciones de ejecución/transporte, no resultados de precisión.
