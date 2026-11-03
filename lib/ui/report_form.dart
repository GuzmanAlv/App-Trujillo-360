import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/report_sender.dart';
import '../services/photo_store.dart';
import '../models/report_photo.dart';
import 'report_photo_view.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../data/incident_store.dart';
import '../models/incident.dart';
import '../services/location_service.dart';
import 'map_panel.dart';
import 'report_style.dart';

const categories = ['Todos', 'Robo', 'Auxilio', 'Agresión', 'Riesgo'];

class ReportForm extends StatefulWidget {
  const ReportForm({
    super.key,
    required this.store,
    this.onLocalSubmit,
    this.requestHelp = false,
    this.serverHelp = false,
  });
  final IncidentStore store;
  final Future<bool> Function(Incident, String)? onLocalSubmit;
  final bool requestHelp;
  final bool serverHelp;
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final form = GlobalKey<FormState>();
  final place = TextEditingController(), description = TextEditingController();
  final lat = TextEditingController(), lng = TextEditingController();
  String category = 'Robo';
  LatLng? selected;
  bool saving = false, locating = false;
  bool pickingPhotos = false, photosPersisted = false;
  final List<ReportPhoto> photos = [];
  final picker = ImagePicker();
  DateTime occurredAt = DateTime.now();
  String priority = 'Media';
  String? gpsAccuracy;
  late final draftId = ReportSender.requestId();
  bool get unifiedReport => !widget.requestHelp && widget.onLocalSubmit == null;

  Future<void> dialSecurity() async {
    try {
      await const MethodChannel(
        'trujillo360/proximity',
      ).invokeMethod<void>('dial');
    } catch (_) {
      message('No se pudo abrir el teléfono. Número: (044) 298734.');
    }
  }

  Future<void> pickOccurredAt() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: occurredAt,
      firstDate: now.subtract(const Duration(days: 6)),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(occurredAt),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (value.isAfter(DateTime.now())) {
      message('La hora del hecho no puede estar en el futuro.');
      return;
    }
    setState(() => occurredAt = value);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.serverHelp &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      recoverPhotos();
    }
  }

  Future<void> discard(ReportPhoto photo) async {
    try {
      await PhotoStore.remove(photo);
    } catch (_) {
      /* Cleanup can be retried later. */
    }
  }

  Future<void> recoverPhotos() async {
    setState(() => pickingPhotos = true);
    try {
      final recovered = await picker.retrieveLostData();
      if (mounted && recovered.files != null) {
        await keepPhotos(recovered.files!);
      }
    } catch (_) {
      message(
        'No se pudieron recuperar las fotos. Puedes seleccionarlas otra vez.',
      );
    } finally {
      if (mounted) setState(() => pickingPhotos = false);
    }
  }

  Future<void> keepPhotos(List<XFile> files) async {
    final remaining = PhotoStore.maxPhotos - photos.length;
    if (files.length > remaining) message('Puedes adjuntar hasta tres fotos.');
    for (final file in files.take(remaining)) {
      if (!mounted) return;
      try {
        if (await file.length() > PhotoStore.maxBytes) {
          message('Cada foto debe pesar como máximo 2 MB. Elige otra imagen.');
          continue;
        }
        final photo = await PhotoStore.save(
          ReportSender.requestId(),
          await file.readAsBytes(),
        );
        if (!mounted) {
          await discard(photo);
          return;
        }
        setState(() => photos.add(photo));
      } on FormatException catch (error) {
        message(error.message);
      } catch (_) {
        message(
          'No se pudo guardar la foto. Revisa los permisos e intenta otra vez.',
        );
      }
    }
  }

  Future<void> pickPhotos({required bool camera}) async {
    if (pickingPhotos || saving || photos.length >= PhotoStore.maxPhotos) {
      return;
    }
    setState(() => pickingPhotos = true);
    try {
      if (camera) {
        final file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 75,
        );
        if (file != null) await keepPhotos([file]);
      } else {
        await keepPhotos(
          await picker.pickMultiImage(
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 75,
          ),
        );
      }
    } catch (_) {
      message(
        'No se pudieron abrir las fotos. Revisa los permisos de cámara o galería.',
      );
    } finally {
      if (mounted) setState(() => pickingPhotos = false);
    }
  }

  @override
  void dispose() {
    if (!photosPersisted) {
      for (final photo in photos) {
        unawaited(discard(photo));
      }
    }
    for (final c in [place, description, lat, lng]) {
      c.dispose();
    }
    super.dispose();
  }

  void select(LatLng p) {
    setState(() {
      selected = p;
      lat.text = p.latitude.toStringAsFixed(6);
      lng.text = p.longitude.toStringAsFixed(6);
      gpsAccuracy = null;
    });
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> current() async {
    setState(() => locating = true);
    try {
      final p = await LocationService().current();
      if (mounted) {
        select(LatLng(p.latitude, p.longitude));
        setState(
          () => gpsAccuracy =
              'Precisión GPS aproximada: ±${p.accuracy.round()} m. Ajusta el punto si el hecho ocurrió en otro lugar.',
        );
      }
    } on LocationFailure catch (e) {
      message(e.message);
    } catch (_) {
      message(
        'No se pudo obtener la ubicación. Puedes escribir las coordenadas.',
      );
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  String? coordinate(String? value, double max) {
    final n = double.tryParse((value ?? '').replaceAll(',', '.'));
    return n == null || !n.isFinite || n.abs() > max
        ? 'Valor entre -$max y $max'
        : null;
  }

  Future<void> save() async {
    if (saving || pickingPhotos || !form.currentState!.validate()) return;
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user == null && (widget.onLocalSubmit == null || widget.serverHelp)) {
      message(
        'Inicia sesión con Google en Configuración para enviar reportes.',
      );
      return;
    }
    setState(() => saving = true);
    final now = DateTime.now();
    final report = Incident(
      id: draftId,
      ownerUid: widget.onLocalSubmit != null && !widget.serverHelp
          ? 'local-pilot'
          : user!.uid,
      type: category,
      place: place.text.trim(),
      description: description.text.trim(),
      latitude: double.parse(lat.text.replaceAll(',', '.')),
      longitude: double.parse(lng.text.replaceAll(',', '.')),
      createdAt: !widget.requestHelp ? occurredAt : now,
      photos: List.unmodifiable(photos),
      priority: unifiedReport ? priority : null,
    );
    bool ok;
    try {
      ok = widget.onLocalSubmit != null
          ? await widget.onLocalSubmit!(report, priority)
          : await widget.store.add(report);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        message(
          e is StateError
              ? e.message.toString()
              : 'No se pudo enviar. Conserva los datos y vuelve a intentar.',
        );
      }
      return;
    }
    photosPersisted = ok;
    final result = widget.serverHelp
        ? (ok
              ? 'Solicitud recibida por la plataforma. Consulta su seguimiento; no confirma atención ni envío de personal.'
              : 'No se confirmó la recepción de la solicitud. Vuelve a intentar.')
        : widget.onLocalSubmit != null
        ? (ok
              ? 'Guardado en la prueba local. No se avisó a ninguna institución.'
              : 'No se pudo guardar. Intenta nuevamente.')
        : ok
        ? await ReportSender.send(report, widget.store)
        : 'No se pudo guardar la copia local. Intenta nuevamente.';
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(result)));
    } else {
      message(
        'No se pudo guardar. Revisa el almacenamiento y vuelve a intentarlo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving && !pickingPhotos,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.requestHelp
              ? (widget.serverHelp
                    ? 'Solicitar ayuda'
                    : 'Solicitar ayuda · Prueba')
              : 'Nuevo reporte',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.serverHelp
                        ? 'Solicitud para revisión de un operador del proyecto. No contacta automáticamente a emergencias ni confirma envío de personal.'
                        : widget.onLocalSubmit != null
                        ? 'PRUEBA LOCAL: este caso solo se guarda en tu celular. Ninguna institución recibirá el aviso.'
                        : 'Se enviará al operador con el nivel de urgencia indicado. Solo será público al corroborarse o verificarse. No confirma atención inmediata.',
                  ),
                  if (widget.requestHelp || unifiedReport) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(
                        labelText: 'Nivel de urgencia',
                      ),
                      items: ['Baja', 'Media', 'Alta']
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) => setState(() => priority = value!),
                    ),
                    const Text(
                      'El operador debe revisar la prioridad. No depende del número de reportes.',
                    ),
                    if (unifiedReport && priority == 'Alta') ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: saving ? null : dialSecurity,
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Llamar a Seguridad Ciudadana'),
                      ),
                      const Text(
                        '(044) 298734 · Abre el marcador. El reporte se envía al pulsar Enviar reporte, aunque no llames.',
                      ),
                    ],
                  ],
                  if (!widget.requestHelp)
                    TextButton.icon(
                      onPressed: pickOccurredAt,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        'Hora del hecho: ${occurredAt.day}/${occurredAt.month} ${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')} · Cambiar',
                      ),
                    ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de incidente',
                    ),
                    items: categories
                        .skip(1)
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Row(
                              children: [
                                Icon(
                                  ReportStyle.forCategory(c).icon,
                                  color: ReportStyle.forCategory(c).color,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  c,
                                  style: TextStyle(
                                    color: ReportStyle.forCategory(c).color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (c) => setState(() => category = c!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: place,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Lugar o referencia (puerta, calle, esquina)',
                    ),
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Escribe una referencia de al menos 3 caracteres.'
                        : null,
                  ),
                  TextFormField(
                    controller: description,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!widget.serverHelp) ...[
                    Text(
                      'Fotos del reporte (opcional)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.onLocalSubmit != null
                          ? 'Hasta 3 fotos de 2 MB. En esta prueba permanecen privadas, incluso si el caso se publica en el mapa.'
                          : 'Hasta 3 fotos de 2 MB. Se compartirán al corroborarse o verificarse el incidente. Puedes ampliarlas antes de enviar.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final photo in photos)
                          SizedBox(
                            width: 100,
                            height: 110,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ReportPhotoView(photo: photo),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filled(
                                    tooltip: 'Quitar foto',
                                    onPressed: saving || pickingPhotos
                                        ? null
                                        : () {
                                            setState(
                                              () => photos.remove(photo),
                                            );
                                            unawaited(discard(photo));
                                          },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              saving ||
                                  pickingPhotos ||
                                  photos.length >= PhotoStore.maxPhotos
                              ? null
                              : () => pickPhotos(camera: false),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galería'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              saving ||
                                  pickingPhotos ||
                                  photos.length >= PhotoStore.maxPhotos
                              ? null
                              : () => pickPhotos(camera: true),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Tomar foto'),
                        ),
                      ],
                    ),
                    if (pickingPhotos) const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 240,
                    child: MapPanel(selected: selected, onPick: select),
                  ),
                  TextButton.icon(
                    onPressed: locating ? null : current,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      locating ? 'Buscando ubicación…' : 'Usar mi ubicación',
                    ),
                  ),
                  if (gpsAccuracy != null) Text(gpsAccuracy!),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('latitude'),
                          controller: lat,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitud',
                          ),
                          validator: (v) => coordinate(v, 90),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('longitude'),
                          controller: lng,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitud',
                          ),
                          validator: (v) => coordinate(v, 180),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Selecciona en el mapa, utiliza el GPS o escribe las coordenadas. No consultamos direcciones a Google.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed:
                        saving || pickingPhotos || widget.store.error != null
                        ? null
                        : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      saving
                          ? 'Guardando…'
                          : widget.requestHelp
                          ? (widget.serverHelp
                                ? 'Enviar solicitud de ayuda'
                                : 'Guardar solicitud de prueba')
                          : 'Enviar reporte',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
