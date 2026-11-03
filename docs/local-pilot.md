# Prueba local del flujo ciudadano y operador

Referencia histórica del prototipo separado. Ya no es el inicio de la aplicación.
Para la versión integrada actual, consultar [flujo integrado](integrated-workflows.md).

Compilar con `--dart-define=LOCAL_PILOT=true`. Este modo inicia sin Firebase,
no crea clientes HTTP ni WebSocket y guarda los casos bajo una clave separada
`trujillo360.pilot.cases.v1`. No modifica los reportes anteriores ni la base remota.
La selección Ciudadano/Operador es una simulación en un dispositivo, no un control
de acceso. No hay notificaciones entre teléfonos ni recepción institucional.

El ciudadano puede reportar un hecho con hora independiente del envío o solicitar
ayuda con urgencia indicada. Se muestra un aviso local al crear una solicitud;
la bandeja prioriza solicitudes abiertas y urgencia. El operador debe registrar
un motivo para revisar, publicar, registrar acciones, cerrar o descartar.
La publicación es independiente de la prioridad. No se inventa corroboración
de varias cuentas. Fotos, descripción y seguimiento no aparecen en vistas públicas.

Políticas provisionales: mapa activo y Cerca de ti muestran solo casos revisados
de menos de dos horas, no cerrados ni descartados. Cerca de ti exige GPS y 1 km.
Caducar no cierra solicitudes. El historial por horario usa siete días e incluye
cerrados previamente publicados, pero excluye descartados. Se actualiza cada
30 segundos y al regresar al primer plano. Los datos persistidos se conservan.

La concentración agrupa por celdas de 0.001 grados (~110 m de latitud en Trujillo),
con círculos ilustrativos de 80 m. Naranja: 3–5 casos; rojo: 6 o más.
No representa calles exactas, tasas de delitos ni predicciones. Sin color no
significa seguridad. Los umbrales y la vigencia requieren validación con usuarios.
La franja se calcula a partir de la hora local del hecho, no de recepción.

GPS muestra precisión aproximada y permite tocar o arrastrar el punto, además
de escribir coordenadas y una referencia. No se altera el punto hacia una calle.
Abrir teléfono usa ACTION_DIAL sin número ni llamada automática. No se incorporan
números sin verificar el servicio destinatario. Cámaras e IA siguen desconectadas.

Prueba: crear un caso ficticio, pasar a Operador, revisar y publicar con motivo,
volver a Ciudadano y consultar mapa/Mis casos. Cerrar y comprobar que sale del
mapa activo pero conserva seguimiento e historial. Para concentración, registrar
al menos tres casos ficticios revisados en la misma celda y franja.

Ejemplo Android (SDK local):
`flutter build apk --release --target-platform android-arm64 --dart-define=LOCAL_PILOT=true --dart-define=MAPS_ENABLED=true`
La configuración Android de Maps sigue siendo necesaria. La firma actual es de
desarrollo. No publicar esta compilación como servicio de emergencias real.
