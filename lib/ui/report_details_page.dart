import 'package:flutter/material.dart';
import '../data/incident_store.dart';
import '../models/incident.dart';
import '../services/report_sender.dart';
import '../services/report_details_client.dart';
import 'report_style.dart';
import 'report_photo_view.dart';

class ReportDetailsPage extends StatefulWidget {
  const ReportDetailsPage({
    super.key,
    required this.report,
    required this.store,
  });
  final Incident report;
  final IncidentStore store;
  @override
  State<ReportDetailsPage> createState() => _ReportDetailsPageState();
}

class _ReportDetailsPageState extends State<ReportDetailsPage> {
  RemoteReportDetails? remote;
  bool loading = false, sending = false;
  String? note;
  Incident get report =>
      widget.store.items
          .where((item) => item.id == widget.report.id)
          .firstOrNull ??
      widget.report;
  @override
  void initState() {
    super.initState();
    if (report.remoteId != null) refresh();
  }

  Future<void> refresh() async {
    if (loading || report.remoteId == null) return;
    setState(() {
      loading = true;
      note = null;
    });
    try {
      final value = await fetchReportDetails(report);
      await widget.store.add(
        report.delivered(
          report.remoteId!,
          status: value.status,
          count: value.corroborationCount,
          review: value.needsReview,
        ),
      );
      if (mounted) setState(() => remote = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => note =
              'No se pudo actualizar desde el servidor. Mostramos la copia de este dispositivo.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> retry() async {
    if (sending) return;
    setState(() => sending = true);
    final result = await ReportSender.send(report, widget.store);
    if (!mounted) return;
    setState(() => sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    if (report.remoteId != null) await refresh();
  }

  String date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String status(String value) => switch (value) {
    'verified' => 'Verificado',
    'corroborated' => 'Corroborado por la comunidad',
    'discarded' => 'Descartado',
    'closed' => 'Cerrado',
    _ => 'Pendiente de verificación',
  };
  Widget field(IconData icon, String title, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: ReportStyle.forCategory(report.type).color),
    title: Text(title, style: Theme.of(context).textTheme.labelLarge),
    subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final item = report;
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle del reporte')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    ReportCategoryIcon(category: item.type),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.type,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: ReportStyle.forCategory(item.type).color,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(
                      remote == null
                          ? item.deliveryLabel
                          : status(remote!.status),
                    ),
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                if (remote != null) ...[
                  Text(
                    '${remote!.corroborationCount} de 3 cuentas distintas para corroborar.',
                  ),
                  const Text(
                    'La corroboración comunitaria no equivale a una verificación por un operador.',
                  ),
                  if (remote!.needsReview)
                    const Text(
                      'Coincide con varios incidentes. Pendiente de revisión para agruparlo.',
                    ),
                ],
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(note!),
                  ),
                field(Icons.place_outlined, 'Lugar o referencia', item.place),
                field(
                  Icons.calendar_month_outlined,
                  'Fecha del reporte',
                  date(item.createdAt),
                ),
                field(
                  Icons.schedule,
                  'Hora del reporte',
                  '${reportTime(item.createdAt)}:${item.createdAt.toLocal().second.toString().padLeft(2, '0')} (hora local)',
                ),
                if (remote != null)
                  field(
                    Icons.cloud_done_outlined,
                    'Recibido por el servidor',
                    '${date(remote!.receivedAt)} · ${reportTime(remote!.receivedAt)}',
                  ),
                field(
                  Icons.my_location,
                  'Coordenadas',
                  '${item.latitude.toStringAsFixed(6)}, ${item.longitude.toStringAsFixed(6)}',
                ),
                const Divider(height: 32),
                Text(
                  'Descripción',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  item.description.isEmpty
                      ? 'Sin descripción adicional.'
                      : item.description,
                ),
                const SizedBox(height: 24),
                Text(
                  'Fotos adjuntas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (remote != null) ...[
                  if (remote!.photos.isEmpty)
                    const Text('Este reporte no tiene fotos.'),
                  for (var index = 0; index < remote!.photos.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Semantics(
                        label: 'Ampliar foto ${index + 1}',
                        button: true,
                        child: InkWell(
                          onTap: () =>
                              openReportPhoto(context, remote!.photos[index]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              remote!.photos[index],
                              height: 230,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 1000,
                              errorBuilder: (_, _, _) => const SizedBox(
                                height: 100,
                                child: Center(
                                  child: Text('No se pudo mostrar esta foto'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ] else ...[
                  if (item.photos.isEmpty)
                    const Text('Este reporte no tiene fotos.'),
                  for (final photo in item.photos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        height: 230,
                        child: ReportPhotoView(
                          key: ValueKey(photo.id),
                          photo: photo,
                        ),
                      ),
                    ),
                ],
                if (item.photos.isNotEmpty ||
                    (remote?.photos.isNotEmpty ?? false))
                  const Text(
                    'Toca una foto para ampliarla. Puedes hacer zoom con dos dedos.',
                  ),
                const SizedBox(height: 24),
                if (item.ownerUid != null && item.remoteId == null)
                  FilledButton.icon(
                    onPressed: sending ? null : retry,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(sending ? 'Enviando…' : 'Reintentar envío'),
                  ),
                if (item.remoteId != null)
                  OutlinedButton.icon(
                    onPressed: loading ? null : refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar detalle'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
