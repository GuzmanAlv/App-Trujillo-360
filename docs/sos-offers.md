# Solicitudes SOS directas para operadores

La bandeja del mapa muestra cada SOS disponible como tarjeta, sin desplegar un
menú. Ordena por minutos aproximados desde el GPS del operador y permite ver el
punto o pulsar **Aceptar**. Si no hay ubicación válida, se muestra «Tiempo de
llegada no disponible». La cifra es una aproximación basada en distancia; la ruta
real se consulta después de confirmar el caso y puede tardar más por tráfico.

**Aceptar** reclama el caso en PostgreSQL bajo el mismo bloqueo usado por las
llamadas y la evaluación. Solo el primer operador consigue tomarlo. Al resto se
le retira en la siguiente actualización del mapa (cada seis segundos) o al
actualizar manualmente. Si dos aceptan a la vez, el segundo recibe un aviso y
recarga la bandeja. Los otros SOS siguen disponibles. El caso tomado abre la
ficha de evaluación existente.

Requiere migraciones **029 y 030**, después de 028, backend y APK nuevos:

```powershell
cd backend
.\.venv\Scripts\python.exe migrate_sos_offers.py
.\.venv\Scripts\python.exe migrate_sos_offers.py --apply
.\.venv\Scripts\python.exe migrate_sos_offer_status.py --apply
```

Después del despliegue, `/ready` debe incluir `sos_offers_version: 2`.
Esta entrega no cambia el envío de notificaciones FCM en segundo plano: todavía
pueden llegar a varios operadores. Tampoco calcula ETA por tráfico antes de
aceptar. Esos dos puntos requieren un servicio de despacho geográfico adicional.
