# Fotos y detalle del reporte

En Android, el formulario permite adjuntar hasta tres fotos opcionales desde la
galería o la cámara. Se solicita una imagen reducida a 1600 píxeles y calidad 75;
se rechazan archivos de más de 2 MB. Se pueden quitar antes de enviar. La selección
interrumpida por Android se recupera al abrir de nuevo el formulario; esto no
recupera los demás campos de un formulario que el sistema haya destruido.

Las imágenes se copian a report_photos dentro del directorio persistente de la app.
SharedPreferences solo guarda sus identificadores y nombres relativos. Cancelar
el formulario limpia las fotos del borrador; enviar conserva la copia local,
también si no hay conexión. No borrar los datos de la app antes de reintentar.

POST /reports acepta photos: [{id, content_base64}], con hasta tres JPEG/PNG.
El backend comprueba tamaño, contenido real, resolución (hasta 12 megapíxeles),
orientación y ausencia de animación. Convierte a JPEG de hasta 1600 píxeles y
elimina EXIF, incluida ubicación incrustada. La petición tiene un límite de 9 MB.

La migración 004 almacena las imágenes en una tabla privada de PostgreSQL en
Supabase. Reporte, incidente y fotos se guardan en una misma transacción. Los
reintentos con el mismo UUID y contenido devuelven el registro existente; cambiar
las fotos, su orden o el texto devuelve conflicto. Para un despliegue de mayor
volumen conviene migrar los bytes a un bucket privado de Supabase Storage.

GET /reports/{id} devuelve detalle, fecha de recepción, estado y fotos únicamente
al autor activo autenticado. La separación de identidades se aplica mediante RLS.
No se habilitó publicación, historial entre dispositivos ni acceso administrativo
adicional. El mapa y la lista abren la misma pantalla de detalle, con fotos
ampliables. Sin servidor se muestra la copia local; con servidor se puede actualizar
el estado y recuperar sus fotos aunque falte una copia de imagen en el celular.

La fecha/hora mostrada corresponde al registro del reporte. Todavía no existe un
campo independiente para la hora en que ocurrió el hecho.

## Actualizar y probar

1. En la raíz: git pull origin main y flutter pub get.
2. En backend, con su entorno virtual: python -m pip install -r requirements.lock.txt.
3. Ejecutar python migrate.py para aplicar la migración 004 y reiniciar FastAPI.
   /ready debe devolver schema_version: 4. Las migraciones previas se conservan.
4. Mantener BACKEND_URL y adb reverse como en firebase-fastapi.md. Ejecutar Flutter
   de nuevo: los plugins nuevos requieren reinicio completo, no solo hot reload.
5. Crear un reporte con fotos; abrirlo desde la lista o marcador, ampliar las fotos
   y actualizar el detalle. Apagar FastAPI, enviar otro, reiniciar la app y comprobar
   que sigue pendiente con fotos; encender FastAPI y reintentar.
6. Para probar aislamiento e idempotencia en la base: python verify_photos_database.py.
   El script revierte todos sus datos de prueba. Requiere migración 004 aplicada.

Pruebas de código: flutter test y, desde backend, python -m pytest.
