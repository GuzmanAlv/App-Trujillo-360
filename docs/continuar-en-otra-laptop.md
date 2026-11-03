# Continuar Trujillo 360 en otra laptop

Guía de traspaso al 3 de noviembre de 2026. No requiere la conversación original.

## 1. Obtener la versión actual

Repositorio: https://github.com/GuzmanAlv/App-Trujillo-360
Rama de trabajo compartida: `main`.

Si aún no tienes el proyecto:

```powershell
git clone https://github.com/GuzmanAlv/App-Trujillo-360.git
cd App-Trujillo-360
git switch main
```

Si ya lo tienes, guarda o confirma primero tu trabajo pendiente; después:

```powershell
git status
git fetch origin
git switch main
git pull --ff-only origin main
```

Si Git indica conflictos o que las ramas divergieron, revisarlos antes de continuar.
No usar `reset --hard`, borrar archivos ni forzar el push para resolverlos.

Para un ChatGPT con acceso al repositorio, abrir esta carpeta y pegar el texto
de la última sección. Si el chat no puede leer archivos, adjuntar esta guía y
los documentos relacionados; no adjuntar archivos privados de configuración.

## 2. Estado actual y reglas que se deben conservar

- App Flutter Android con cuenta Google/Firebase y backend FastAPI en Render;
  los datos están en Supabase/PostgreSQL, esquema `trujillo`.
- Backend público: https://trujillo-360-api.onrender.com.
  `GET /ready` debe devolver `schema_version: 11`, `workflow_version: 1`,
  `push_version: 1`. No necesita laptop ni USB.
- Inicio real: `lib/main.dart` → app integrada. `lib/pilot/` y `docs/local-pilot.md`
  conservan un prototipo histórico: NO son el flujo actual. `LOCAL_PILOT` no
  cambia la pantalla inicial; no reactivar la selección simulada de roles.
- Un solo formulario **Reportar**, con urgencia Baja/Media/Alta, fotos, ubicación
  ajustable y hora del hecho. Alta muestra llamada opcional a `(044) 298734`.
  Abrir el marcador no llama ni envía el formulario automáticamente.
- Enviar guarda reporte y solicitud privada al operador en una transacción.
  La urgencia no verifica ni publica el reporte.
- Ambos roles usan Google. El operador se autoriza en el servidor; no existe
  un selector público para volverse operador. Ya existe una cuenta autorizada.
- El operador dispone de Ayuda, Revisar reportes y Cámaras / IA. Registra motivos
  y acciones; la app no garantiza despacho policial ni atención inmediata.
- Mapa reciente y Cerca de ti: solo incidentes verificados por operador o
  corroborados por tres cuentas, sin revisión pendiente, durante siete días
  desde el hecho. No hay reinicio semanal ni caducidad de dos horas.
- Historial: 90 días, franjas horarias de Lima y zonas aproximadas. Amarillo:
  1–2 incidentes; rojo: 3 o más. Sin color NO significa seguro. No pinta calles
  exactas ni considera cada corroboración como un incidente nuevo.
- IA está dentro del panel del operador. Aún no hay cámaras ni inferencia conectadas.
- Configuración → Notificaciones sustituye la antigua alerta de 500 m que solo
  funcionaba con la app abierta. Permite zona fija/radio y avisos de operador;
  no solicita ubicación en segundo plano.

## 3. Pendiente principal: habilitar los avisos reales de Firebase

La implementación de FCM, registro de dispositivos, permisos, cola y reintentos
está en el código. Las pruebas no sustituyen una entrega real entre dispositivos.
El emisor sigue deshabilitado: no hay credencial privada de envío.

Datos para identificar exactamente el recurso:

- Proyecto Firebase/Google Cloud: `Trujillo360`.
- Project ID: `project-43edb74d-04c5-4d00-962`.
- Project number: `20186172766`.
- API Firebase Cloud Messaging V1: ya habilitada.
- Cuenta de servicio: **Trujillo 360 Notificaciones**, ID `trujillo-notificaciones`.
- Correo: `trujillo-notificaciones@project-43edb74d-04c5-4d00-962.iam.gserviceaccount.com`.
- ID único: `118356006504227170586`.
- Rol de esa cuenta: `roles/firebasecloudmessaging.admin`.
- No se generó ni descargó ninguna clave; no crear otra cuenta por error.

### Bloqueo confirmado

Google rechazó crear una clave JSON por la política heredada
`iam.disableServiceAccountKeyCreation`, que figura **Aplicada** en el proyecto.
La cuenta que hizo la prueba no tenía
`orgpolicy.policies.create`, `orgpolicy.policies.delete` ni `orgpolicy.policies.update`.
Ser administrador de Firebase o del proyecto no implica tener esos permisos.
El administrador adecuado debe revisar `roles/orgpolicy.policyAdmin` en la
organización. Si tampoco los tiene el propietario del proyecto, solicitar ayuda
al administrador de la organización; no intentar eludir la restricción.

Enlace al bloqueo:
https://console.cloud.google.com/iam-admin/orgpolicies/iam-disableServiceAccountKeyCreation?project=project-43edb74d-04c5-4d00-962

Enlace a las claves de la cuenta existente:
https://console.cloud.google.com/iam-admin/serviceaccounts/details/118356006504227170586/keys?project=project-43edb74d-04c5-4d00-962

### Cómo continuar con un administrador autorizado

1. Iniciar sesión con su propia cuenta y comprobar el proyecto y la política
   efectiva. No compartir contraseñas ni asumir que basta con el rol de Firebase.
2. Acordar una excepción limitada al proyecto o a la cuenta, preferiblemente
   temporal. No desactivar la protección de toda la organización. Cualquier
   cambio de política requiere aprobación expresa del administrador.
3. Si se permite, usar la cuenta YA creada → Claves → Agregar clave → Crear
   clave nueva → JSON. Guardar el archivo privado fuera del repositorio público.
4. Restaurar la política previa tras generar la clave si se usó una excepción
   temporal. No quitar la protección que inhabilita claves filtradas.
5. En Render, abrir el servicio `trujillo-360-api` y configurar un **Secret File**
   llamado `fcm-service-account.json` con ese JSON. Usar estas variables:

   ```text
   GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/fcm-service-account.json
   PUSH_ENABLED=true
   ```

   El backend también admite `FIREBASE_SERVICE_ACCOUNT_JSON` como variable secreta
   en lugar del archivo. Elegir un solo mecanismo, no copiar el secreto al código.
   Comprobar que `FIREBASE_PROJECT_ID` coincide con el proyecto indicado arriba.
6. Guardar y desplegar. Los registros deben dejar de indicar
   `PUSH_DISABLED missing_configuration`. No imprimir tokens ni claves para
   depurar. `sender_configured` confirma configuración, no entrega real de FCM.
7. Hacer la prueba funcional indicada en la sección siguiente antes de afirmar
   que las notificaciones funcionan.

El backend actual se desplegó correctamente en Render desde
`codex/notificaciones-fcm`, commit `ad57a66`, deploy `dep-dbl0sfvf3r2c73850340`.
Comprobar en Settings → Branch la rama activa antes de desplegar cambios nuevos;
subir a `main` no cambia por sí solo esa configuración de Render.
Servicio: `srv-db41goei0phs73el3ms0`, plan Free, región Ohio.
No contratar un plan de pago automáticamente. Render Free puede suspenderse por
inactividad y demorar el arranque; tener la app cerrada y tener el servidor dormido
son situaciones distintas. La opción de OIDC administrado de Render requiere un
workspace Pro o superior; no se activó ni se configuró esa alternativa.

Referencias oficiales para confirmar permisos y pasos antes de actuar:
- https://docs.cloud.google.com/iam/docs/troubleshoot-org-policies
- https://firebase.google.com/docs/cloud-messaging/send/v1-api
- https://render.com/docs/oidc

## 4. Prueba real de notificaciones

Preferiblemente usar dos celulares/cuentas y casos identificados como **PRUEBA**.
Se guardan en la base compartida del proyecto; no son recepción institucional.

1. Ciudadano: iniciar sesión, Configuración → Notificaciones, elegir zona/radio,
   activar avisos y conceder el permiso de Android.
2. Operador autorizado: activar Nuevos reportes para el operador en Notificaciones.
3. Poner la app del operador en segundo plano y enviar un reporte. Comprobar el
   aviso con urgencia y que tocarlo abre el caso correcto.
4. Verificar el incidente desde el panel. Con la app ciudadana en segundo plano,
   comprobar el aviso si el incidente queda dentro de su zona.
5. Comprobar que un pendiente, un incidente fuera de zona y los avisos desactivados
   no generan notificación ciudadana. La prioridad Alta no debe publicar un caso.
6. Probar apertura desde app cerrada, cierre/cambio de sesión y permisos revocados.
   Forzar detención desde Ajustes de Android requiere abrir la app otra vez.

## 5. Ejecutar o compilar desde otra laptop

Para ver el código no hacen falta claves. Para instalar una nueva compilación se
necesitan Flutter, Android SDK y Java compatibles; comenzar con `flutter doctor -v`.

```powershell
flutter pub get
flutter run --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
```

La clave restringida de Maps se configura en `android/maps.properties`, tomando
`android/maps.properties.example` como referencia. No está subida a Git. Solicitarla
al responsable por un canal privado o crear una clave debidamente restringida.
`android/app/google-services.json` ya contiene la configuración cliente del
proyecto; NO es la clave privada del servidor. Con una firma nueva de Android,
Google Sign-In y Maps pueden requerir registrar su huella SHA en el proyecto.
No sobrescribir huellas ni cambiar el paquete para resolverlo.

APK Android ARM64 de pruebas, conectado al backend público:

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
```

Salida: `build/app/outputs/flutter-apk/app-release.apk`. El APK no está en Git;
se puede compartir por separado para probar la misma instalación. Actualmente
la configuración release usa la firma debug de cada equipo: no es una publicación
de Play Store. Un APK firmado en otra laptop podría no actualizar la instalación
anterior; no desinstalarla sin revisar primero sus datos locales.

Para usar el backend público NO se necesitan archivos `.env` ni ejecutar Python
localmente. Para desarrollar el backend local, usar los ejemplos de configuración
y pedir las credenciales por un canal privado. No recrear Supabase ni repetir
migraciones sobre la base compartida sin comprobar el estado y acordar el cambio.

## 6. Verificaciones y documentos

```powershell
flutter analyze
flutter test
flutter test --dart-define=MAPS_ENABLED=true test/nearby_map_test.dart
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock.txt
.\.venv\Scripts\python.exe -m pytest tests -q
```

`verify_push.py` y `verify_workflows.py` verifican la base real en transacciones
que revierten sus datos, pero requieren credenciales administrativas locales.
No son necesarios para simplemente ver la app ni para iniciar sesión en Google.

Leer también:
- [Flujo integrado](integrated-workflows.md).
- [Notificaciones y emisor](push-notifications.md).
- [Despliegue Render](render-deployment.md).
- [Integración IA pendiente](ai-integration.md).

Los archivos `.env`, `android/maps.properties`, claves JSON privadas,
`backend/.secrets/`, `.venv/` y APK de build no se suben a Git. No pegar tokens,
contraseñas ni claves privadas en un chat o capturas.

## 7. Texto para pegar en su ChatGPT o Codex

```text
Estoy continuando el proyecto Trujillo 360 sin tener la conversación anterior.
Repositorio: https://github.com/GuzmanAlv/App-Trujillo-360, rama main.
Primero lee README.md, docs/continuar-en-otra-laptop.md,
docs/integrated-workflows.md, docs/push-notifications.md y docs/render-deployment.md.
Si no tienes acceso a los archivos, pídeme esos documentos; no supongas su contenido.

La app integrada ya está implementada y existe un backend público funcionando.
No vuelvas a crear el piloto ni los roles. El pendiente es activar y comprobar
las notificaciones reales FCM. Ya existe la cuenta trujillo-notificaciones con
el permiso de mensajería, pero Google bloquea la clave JSON por la política
heredada iam.disableServiceAccountKeyCreation. No se ha generado ninguna clave.
Ser administrador de Firebase no garantiza poder modificar esa política.

Ayúdame primero a comprobar mi cuenta, la organización y el permiso necesario.
Después explícame una excepción limitada y solicita mi aprobación antes de
cambiar políticas o credenciales. No desactives restricciones para toda la
organización, no contrates planes de pago y no crees cuentas duplicadas.
No me pidas pegar claves privadas aquí ni las subas a Git. Si logro generar la
clave, guíame para configurarla como secreto en el servicio existente de Render,
activar PUSH_ENABLED y comprobar avisos con la app en segundo plano.
Antes de desplegar, verifica la rama activa de Render y el estado de /ready.
Conserva los reportes de siete días, el historial de 90 días, el formulario único
con urgencia y los permisos de operador existentes. Informa lo que verificaste
y lo que siga pendiente; no afirmes que FCM funciona solo porque el código compila.
```
