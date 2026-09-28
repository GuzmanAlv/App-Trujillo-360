from pathlib import Path
from zipfile import ZipFile
from copy import deepcopy
import hashlib
from lxml import etree as E

root = Path(r'C:\Users\PC\Desktop\alerta_ciudadana')
src = Path(r'C:\Users\PC\Downloads\TAREA_GRUPAL_SEMANA_6_QDEHXP.docx')
out = root/'entregables/Tarea_semana_6_Trujillo_360.docx'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
ns={'w':W}
def tag(n): return '{'+W+'}'+n
with ZipFile(src) as z:
    parts={n:z.read(n) for n in z.namelist()}
tree=E.fromstring(parts['word/document.xml'])
tables=tree.findall('.//w:body/w:tbl',ns)
answers=[
[
'Trujillo 360, aplicación de seguridad ciudadana orientada a la ciudad de Trujillo.',
'Buscamos facilitar el registro de incidentes con una ubicación y una descripción claras. Suponemos que la información dispersa o incompleta dificulta comunicar lo ocurrido; esta necesidad debe contrastarse con usuarios.',
'Vecinos adultos de Trujillo que usan un teléfono inteligente. Como usuarios futuros consideramos a operadores autorizados de seguridad ciudadana, previa coordinación institucional.',
'Aplicación Flutter con reportes, ubicación GPS y mapa configurable. Actualmente guarda reportes locales; Firebase y WebSocket tienen adaptadores iniciales. La bandeja de IA está preparada, pero no hay cámaras ni inferencia conectadas.',
'Facilitar reportes comprensibles y ubicables. En una etapa posterior, apoyar su revisión por operadores. Aún no hemos demostrado una reducción de delitos ni de tiempos de respuesta.'
],
[
'Vecinos que necesitan comunicar un incidente observado o advertir una situación de riesgo en su entorno.',
'Describir qué ocurrió y dónde, sin completar un proceso confuso ni creer que un reporte local equivale a solicitar atención de emergencia.',
'Como supuesto inicial, pueden recurrir a llamadas, mensajes o grupos vecinales. Investigaremos qué canales usan realmente y cómo describen la ubicación; no contamos todavía con entrevistas.',
'Posibles dificultades: referencias ambiguas, datos incompletos, duplicados y dudas sobre quién recibe el aviso. También pueden existir barreras de conectividad y permisos de GPS.',
'Preguntar por su última experiencia comunicando un incidente, qué datos compartió y qué respuesta esperaba. Observar cómo registra un caso ficticio y qué hace cuando el GPS no está disponible, sin solicitar experiencias sensibles.'
],
[
'Formulario web sencillo, registro asistido por un representante vecinal o aplicación móvil con mapa. Compararemos facilidad de uso, claridad de ubicación y esfuerzo requerido.',
'Trujillo 360 en Flutter: formulario por categoría, lugar de referencia, descripción, coordenadas y consulta de reportes locales. El mapa requiere una clave configurada; las notificaciones y la sincronización siguen pendientes de integración.',
'La estructura del reporte puede reducir omisiones y permitir revisar la ubicación antes de guardarlo. Es una propuesta de valor por comprobar, no un beneficio ya medido.',
'El recorrido Reportar, elegir categoría, indicar lugar y ubicación, guardar y consultar el detalle. Usaremos la aplicación existente con datos ficticios y coordenadas manuales como alternativa al GPS.',
'Diez vecinos adultos con distintos niveles de experiencia digital y de al menos dos zonas de Trujillo. Dos potenciales operadores revisarán por separado la claridad de los reportes, si aceptan participar.'
],
[
'Creemos que los vecinos tienen dificultades para comunicar incidentes con datos de ubicación suficientemente claros mediante sus canales habituales.',
'Creemos que vecinos adultos que se desplazan habitualmente por Trujillo y usan teléfonos inteligentes presentan esta necesidad y pueden probar un registro digital.',
'Creemos que al menos 8 de 10 participantes podrán guardar y localizar un reporte ficticio completo en Trujillo 360, sin ayuda y en un máximo de 3 minutos, entendiendo que no se envía a emergencias.'
],
[
'La hipótesis de valor: el flujo de registro puede ser utilizado de forma autónoma, rápida y con comprensión de su alcance local.',
'Un MVP de aprendizaje basado en el prototipo Flutter actual. Permitirá crear y consultar reportes locales; la sesión será supervisada únicamente para observar y medir.',
'Categoría, referencia, descripción opcional, ubicación por coordenadas o GPS, validación de campos, guardado y consulta. Debe indicar que el reporte es local y no activa atención de emergencias.',
'Detección de agresiones en video, cámaras en vivo, cuentas, envío real a operadores, notificaciones push, sincronización WebSocket y despliegue masivo. No son necesarias para probar este primer flujo.',
'Diez adultos voluntarios de al menos dos zonas, procurando cinco con menor familiaridad digital. No seleccionaremos solo estudiantes de tecnología o miembros del equipo.',
'Sesiones individuales de 15 a 20 minutos. Tras explicar el alcance, cada persona registrará un caso ficticio y encontrará su detalle sin instrucciones sobre los botones. Cronometraremos, anotaremos errores y preguntaremos qué cree que ocurre al guardar.'
],
[
'Preparar la versión local, un caso ficticio común, coordenadas de prueba, una ficha de observación y una escala de utilidad de 1 a 5. Verificar previamente el flujo en los dispositivos elegidos.',
'Registrar tareas completadas, tiempo desde Reportar hasta consultar el detalle, ayuda solicitada, errores de ubicación, comprensión del modo local y utilidad percibida. Usar códigos P01 a P10, sin nombres en los resultados.',
'Determinar si el flujo permite reportar sin asistencia, qué campos generan confusión y si el usuario entiende sus límites. La prueba no permite concluir que disminuyan los delitos ni que los operadores respondan más rápido.'
],
[
'Usabilidad del registro, calidad de la ubicación, comprensión del alcance y utilidad percibida del MVP.',
'Éxito autónomo: participantes que completan registro y consulta sin ayuda y en ≤3 minutos, sobre 10. Además: ubicación correcta sobre 10, comprensión del modo local sobre 10 y valoraciones de utilidad ≥4 sobre 10.',
'Ficha por participante con hora de inicio y fin, tareas, errores y ayudas. Comparar categoría, referencia y coordenadas con el caso entregado. Al terminar, preguntar quién recibe el reporte y solicitar utilidad de 1 a 5 con una razón.',
'Diez vecinos adultos; muestra exploratoria, no representativa de toda la ciudad. Dos potenciales operadores pueden aportar comentarios cualitativos sobre legibilidad, sin mezclarlos con los indicadores de los vecinos.',
'Al menos 8 de 10 completan sin ayuda en ≤3 minutos; al menos 9 de 10 registran correctamente la ubicación; 10 de 10 entienden que no se avisa a emergencias; al menos 8 de 10 valoran la utilidad con 4 o 5. Se requieren todos los criterios.',
'Si falla algún criterio, revisaremos el flujo y repetiremos la prueba. Una confusión sobre atención de emergencias exige corregir los mensajes antes de otro piloto. Resultados bajos no implican automáticamente abandonar el problema.'
],
[
'Perseverar en el flujo validado, corregir detalles y probar la siguiente hipótesis: que operadores autorizados pueden recibir y revisar reportes útiles. La conexión real requerirá backend y acuerdos de operación.',
'Volver a entrevistar y redefinir el problema. Si la necesidad principal fuera conocer canales oficiales y no registrar incidentes, evaluar orientar la propuesta hacia esa necesidad.',
'Identificar si falla la interacción o la propuesta de valor. Simplificar campos o probar un registro asistido; repetir la medición antes de ampliar funciones.',
'Evaluar un piloto específico con ese grupo. Por ejemplo, si los operadores necesitan más la clasificación de avisos, estudiar un panel de revisión sin asumir que sustituye la necesidad ciudadana.'
],
[
'Cuando se cumplan todos los criterios de la sección 7 y las observaciones respalden la utilidad. Mejoraremos el recorrido y validaremos por separado la recepción institucional.',
'Cuando pruebas reiteradas, después de corregir problemas de uso, indiquen que el valor esperado no existe o que otro problema o segmento es prioritario. Un cambio de botones sería una mejora; cambiar el usuario o la solución principal sería un pivote.'
],
[
'Vecinos del piloto, un representante vecinal y operadores autorizados de la entidad que acepte participar. La adopción institucional depende de acuerdos aún no establecidos.',
'Preferencia por los canales habituales, desconfianza sobre el uso de ubicación, temor a reportes falsos y percepción de trabajo adicional para los operadores.',
'Puede no estar claro quién recibe los datos, qué respuesta se ofrece o qué ventaja existe frente al canal conocido. Los operadores pueden temer duplicar tareas sin recursos adicionales.',
'Proponemos 10 a 15 vecinos de una zona y dos operadores durante dos semanas. Se realizará solo después de validar el MVP y disponer de recepción autenticada y un proceso de atención acordado.',
'Aplicaremos ciclos de observar, proponer opciones y experimentar. Acordaremos el flujo con vecinos y operadores, haremos una demostración de 20 minutos y probaremos un cambio pequeño cada semana, con responsable y criterio de evaluación.',
'Dudas de registro y privacidad, abandonos, errores, reportes que requieren aclaración y carga de revisión. Recogeremos comentarios breves al final de cada semana y evaluaremos si la formación resolvió las dificultades.',
'Ajustaremos campos, mensajes, permisos y distribución de tareas. Para ampliar, proponemos ≥80 % de participantes que completen el flujo, ninguna confusión sobre emergencias y ≥80 % de reportes revisados dentro del plazo acordado. Si no se cumple, adaptaremos y repetiremos el piloto.'
],
[
['Comprender experiencias mediante entrevistas y observación; definir la necesidad y probar el recorrido de registro.', 'Qué necesita el vecino, cómo comunica un incidente y qué partes del flujo le generan dificultades.'],
['Priorizar una hipótesis de valor, probar el MVP local y comparar resultados con criterios definidos antes de la sesión.', 'Si el registro ofrece utilidad y puede completarse sin ayuda; evidencia para perseverar, mejorar o pivotar.'],
['Identificar resistencias, involucrar vecinos y operadores y experimentar con formación y ajustes en un piloto pequeño.', 'Qué condiciones de confianza, capacitación y organización favorecen el uso sostenido.']
]
]
def replace_paragraph(p,text):
    pr=p.find('w:pPr',ns)
    for c in list(p):
        if c is not pr: p.remove(c)
    r=E.SubElement(p,tag('r')); t=E.SubElement(r,tag('t')); t.text=text
def fill(cell,text):
    p=cell.find('w:p',ns)
    replace_paragraph(p,text)
    for other in cell.findall('w:p',ns)[1:]: cell.remove(other)
for i,(table,rows) in enumerate(zip(tables,answers)):
    for row,answer in zip(table.findall('w:tr',ns)[1:],rows):
        cells=row.findall('w:tc',ns)
        for cell,txt in zip(cells[1:],answer if isinstance(answer,list) else [answer]): fill(cell,txt)
    # Let answers span naturally while retaining the source table design.
    for row in table.findall('w:tr',ns):
        pr=row.find('w:trPr',ns)
        if pr is not None:
            for h in pr.findall('w:trHeight',ns): pr.remove(h)
    first=table.find('w:tr',ns)
    pr=first.find('w:trPr',ns)
    if pr is None: pr=E.SubElement(first,tag('trPr'))
    E.SubElement(pr,tag('tblHeader'))

blanks=iter([
'Priorizamos la hipótesis de valor: al menos 8 de 10 vecinos completarán el registro y la consulta sin ayuda en un máximo de 3 minutos, comprendiendo el alcance local.',
'Porque una solución que no permite comunicar bien el incidente no justifica incorporar cámaras, IA o sincronización. Primero debemos comprobar la interacción básica y, en paralelo, explorar si el problema supuesto existe.',
'Los vecinos pueden registrar y consultar información de un incidente de manera autónoma, con ubicación correcta y sin confundir la aplicación con un canal de emergencias.',
'El prototipo Flutter local, un caso ficticio y una prueba con 10 participantes. Mediremos éxito, tiempo, ubicación, comprensión y utilidad conforme a los umbrales definidos.',
'Un piloto gradual con vecinos y operadores, una demostración breve y ciclos semanales de retroalimentación. La publicación de reportes y la IA se validarán como etapas independientes.'
])
for p in tree.findall('w:body/w:p',ns):
    txt=''.join(p.itertext())
    if txt.startswith('___'): replace_paragraph(p,next(blanks))
    elif txt.startswith('Nuestro usuario necesita'): replace_paragraph(p,'Nuestro usuario necesita comunicar un incidente con una ubicación y una descripción claras porque la información incompleta puede dificultar su comprensión y posterior revisión.')
    elif txt.startswith('Aplicar Design Thinking,'): replace_paragraph(p,'Aplicamos Design Thinking, Lean Startup y Lean Change Management a Trujillo 360 para validar primero el registro ciudadano y planificar su adopción. Proponemos una prueba del prototipo local antes de ampliar la solución con conexión a operadores e inteligencia artificial. Las pruebas, metas y pilotos descritos son propuestas pendientes de ejecución.')
    elif txt=='TAREA GRUPAL – SEMANA 6':
        replace_paragraph(p,'Trujillo 360')
        pr=p.find('w:pPr',ns)
        if pr is None: pr=E.SubElement(p,tag('pPr'))
        style=pr.find('w:pStyle',ns)
        if style is None: style=E.SubElement(pr,tag('pStyle'))
        style.set(tag('val'),'Title')
    elif txt.startswith('Aplicación de Metodologías'): replace_paragraph(p,'Aplicación de metodologías de innovación')
    elif txt=='Sesiones 11 y 12': replace_paragraph(p,'Tarea grupal de la semana 6   Sesiones 11 y 12')
    elif txt.startswith('Cada equipo dispondrá'): replace_paragraph(p,'Guion propuesto para una exposición de 4 minutos. Presentaremos el problema y el estado local del prototipo durante 40 segundos; la hipótesis prioritaria durante 40 segundos; el MVP y la prueba durante 60 segundos; los indicadores y decisiones durante 50 segundos; y el piloto de adopción durante 50 segundos.')
    elif txt.startswith('¿Qué supuesto importante'): replace_paragraph(p,'Mensaje central: antes de conectar IA y cámaras, comprobaremos que los vecinos pueden registrar incidentes útiles y entienden qué hace la aplicación. Probaremos el flujo con 10 personas y criterios definidos; si funciona, avanzaremos hacia un piloto de recepción por operadores y acompañaremos su adopción.')

parts['word/document.xml']=E.tostring(tree,xml_declaration=True,encoding='UTF-8',standalone=True)
with ZipFile(out,'w') as z:
    for name,data in parts.items(): z.writestr(name,data)
contract=f'''# Referencia de la tarea
Fuente: {src}
SHA256: {hashlib.sha256(src.read_bytes()).hexdigest()}
Una sección, papel carta 21.59 x 27.94 cm; márgenes superior e inferior 2.499 cm, laterales 3 cm.
Tipografía normal Arial 10. Se preservan estilos, encabezados, pies, numeración, relaciones y todos los componentes externos a word/document.xml byte por byte.
Slots: columna de respuesta de las once tablas, cinco párrafos de líneas de respuesta, definición del problema, título, introducción y sustentación. Se conserva el orden de diez secciones y preguntas de la plantilla.
Se permiten ampliaciones naturales de filas y encabezados de tabla repetidos.
Render de referencia intentado con render_docx.py: no existe LibreOffice empaquetado en Windows; Word COM tampoco disponible. Página exacta y verificación visual pendientes por limitación del entorno.
'''
(root/'tmp_doc/artifact.md').write_text(contract,encoding='utf-8')
with ZipFile(out) as z:
    assert all(z.read(k)==v for k,v in parts.items())
assert not any('____' in t for t in tree.itertext())
print(out)
