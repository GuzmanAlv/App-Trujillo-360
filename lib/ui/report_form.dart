import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../data/incident_store.dart';
import '../models/report.dart';
import '../services/location_service.dart';
import 'map_panel.dart';

class ReportForm extends StatefulWidget {
  const ReportForm({super.key, required this.store});
  final IncidentStore store;
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
  @override
  void dispose() {
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
      if (mounted) select(LatLng(p.latitude, p.longitude));
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
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    final now = DateTime.now();
    final ok = await widget.store.add(
      Report(
        id: now.microsecondsSinceEpoch.toString(),
        reporterId: widget.store.profile.id,
        type: category,
        place: place.text.trim(),
        description: description.text.trim(),
        latitude: double.parse(lat.text.replaceAll(',', '.')),
        longitude: double.parse(lng.text.replaceAll(',', '.')),
        createdAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) {
      Navigator.pop(context);
      message(
        'Reporte guardado en este dispositivo. No se ha enviado al servidor.',
      );
    } else {
      message(
        widget.store.actionError ?? 'No se pudo guardar. Inténtalo de nuevo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nuevo reporte')),
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
                const Text(
                  'Demostración local: 3 perfiles distintos hacen visible un caso '
                  'sin verificar. Misma categoría, hasta 150 m y 30 minutos. '
                  'No contacta a emergencias ni publica a otros dispositivos.',
                ),
                Text('Reportando como: ${widget.store.profile.label}'),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de incidente',
                  ),
                  items: incidentCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                    labelText: 'Lugar o referencia',
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
                        decoration: const InputDecoration(labelText: 'Latitud'),
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
                      saving ||
                          widget.store.error != null ||
                          widget.store.profile.isAdmin
                      ? null
                      : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(saving ? 'Guardando…' : 'Guardar reporte local'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
