import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/workflow_client.dart';
import '../services/report_sender.dart';
import 'report_style.dart';

String citizenSosMessage(
  String attention, {
  String? assignmentState,
  String? decision,
}) => decision == 'pending'
    ? 'SOS recibido · esperando atención.'
    : assignmentState == 'searching' || assignmentState == 'offered'
    ? 'Estamos buscando otra unidad disponible para tu SOS. Tu solicitud sigue abierta.'
    : switch (attention) {
        'en_route' => 'La policía se encuentra en camino. Mantente en calma.',
        'on_scene' => 'Unidad en la zona.',
        'resolved' => 'La atención ha finalizado.',
        _ => 'Incidente confirmado. Esperando asignación de personal.',
      };

class CitizenSosPage extends StatefulWidget {
  const CitizenSosPage({super.key, required this.caseId});
  final String caseId;
  @override
  State<CitizenSosPage> createState() => _CitizenSosPageState();
}

class _CitizenSosPageState extends State<CitizenSosPage> {
  Map<String, dynamic>? data, retry;
  List<Map<String, dynamic>> updates = [];
  final description = TextEditingController();
  final photos = <({String id, Uint8List bytes})>[];
  bool busy = false, stale = false;
  String? error, notice;
  StreamSubscription<User?>? auth;
  String get path => '/my-sos/${widget.caseId}';
  int get uploaded =>
      updates.fold(0, (count, row) => count + (row['photos'] as List).length);
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      final owner = FirebaseAuth.instance.currentUser?.uid;
      auth = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user?.uid != owner && mounted) {
          setState(() {
            stale = true;
            data = null;
            updates = [];
            photos.clear();
            description.clear();
          });
        }
      });
    }
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final values = await Future.wait([
        WorkflowClient.request('GET', path),
        WorkflowClient.list('/sos-cases/${widget.caseId}/contributions'),
      ]);
      if (mounted && !stale) {
        setState(() {
          data = Map<String, dynamic>.from(values[0] as Map);
          updates = (values[1] as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    }
  }

  String readable(Object e) => e is StateError
      ? e.message.toString()
      : 'No se pudo completar la operación.';
  Future<void> pick(ImageSource source) async {
    if (busy ||
        stale ||
        data?['can_contribute'] == false ||
        uploaded + photos.length >= 3) {
      return;
    }
    setState(() => busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        throw StateError('La foto debe pesar como máximo 2 MB.');
      }
      if (mounted && !stale) {
        setState(
          () => photos.add((id: ReportSender.requestId(), bytes: bytes)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send([Map<String, dynamic>? frozen]) async {
    if (busy || stale || data?['can_contribute'] == false) return;
    if (frozen == null && description.text.trim().isEmpty && photos.isEmpty) {
      setState(
        () =>
            error = 'Agrega una descripción o una foto para enviar un aporte.',
      );
      return;
    }
    final body =
        frozen ??
        {
          'request_id': ReportSender.requestId(),
          'description': description.text.trim(),
          'photos': [
            for (final p in photos)
              {'id': p.id, 'content_base64': base64Encode(p.bytes)},
          ],
        };
    retry = body;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await WorkflowClient.request('POST', '$path/contributions', body: body);
      if (mounted && !stale) {
        setState(() {
          retry = null;
          photos.clear();
          description.clear();
          notice = 'Aporte enviado al operador.';
        });
        await load();
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    auth?.cancel();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mi caso SOS')),
    body: stale
        ? const Center(child: Text('La sesión cambió. Vuelve a abrir el caso.'))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (data == null && error == null)
                const LinearProgressIndicator(),
              if (data != null) ...[
                Row(
                  children: [
                    ReportCategoryIcon(category: '${data!['category']}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${data!['category']}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  citizenSosMessage(
                    '${data!['attention']}',
                    decision: data!['decision'] as String?,
                    assignmentState: data!['assignment_state'] as String?,
                  ),
                ),
                if (data!['decision'] == 'pending')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Tu solicitud sigue activa aunque nadie haya contestado. Todavía está pendiente de atención de un operador.',
                    ),
                  ),
                if ('${data!['description']}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${data!['description']}'),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Información adicional (opcional)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (data?['can_contribute'] == false)
                  Text(
                    data?['decision'] == 'pending'
                        ? 'Podrás agregar fotos y detalles cuando el operador confirme el caso.'
                        : 'El plazo para agregar información a este caso ha terminado.',
                  ),
                const Text(
                  'Puedes aportar detalles o fotos al operador. No es necesario para recibir atención.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  enabled: !busy && data?['can_contribute'] != false,
                  maxLength: 1000,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descripción adicional (opcional)',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          !busy &&
                              data?['can_contribute'] != false &&
                              uploaded + photos.length < 3
                          ? () => pick(ImageSource.camera)
                          : null,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar foto'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          !busy &&
                              data?['can_contribute'] != false &&
                              uploaded + photos.length < 3
                          ? () => pick(ImageSource.gallery)
                          : null,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Elegir foto'),
                    ),
                  ],
                ),
                Text('Fotos: ${uploaded + photos.length}/3'),
                for (final p in photos)
                  Card(
                    child: Column(
                      children: [
                        Image.memory(p.bytes, height: 150, fit: BoxFit.contain),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => photos.remove(p)),
                          child: const Text('Quitar foto'),
                        ),
                      ],
                    ),
                  ),
                FilledButton(
                  onPressed: busy || data?['can_contribute'] == false
                      ? null
                      : () => send(),
                  child: const Text('Enviar información adicional'),
                ),
                if (retry != null && error != null)
                  TextButton(
                    onPressed: busy ? null : () => send(retry),
                    child: const Text('Reintentar el mismo aporte'),
                  ),
                if (notice != null) Text(notice!),
                const SizedBox(height: 20),
                const Text(
                  'Mis aportes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SosEvidenceList(caseId: widget.caseId, updates: updates),
              ],
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              TextButton(
                onPressed: busy ? null : load,
                child: const Text('Actualizar caso'),
              ),
            ],
          ),
  );
}

class SosEvidencePanel extends StatefulWidget {
  const SosEvidencePanel({super.key, required this.caseId});
  final String caseId;
  @override
  State<SosEvidencePanel> createState() => _SosEvidencePanelState();
}

class _SosEvidencePanelState extends State<SosEvidencePanel> {
  List<Map<String, dynamic>> updates = [];
  String? error;
  bool stale = false;
  StreamSubscription<User?>? auth;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      final owner = FirebaseAuth.instance.currentUser?.uid;
      auth = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u?.uid != owner && mounted) {
          setState(() {
            stale = true;
            updates = [];
          });
        }
      });
    }
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final rows = await WorkflowClient.list(
        '/sos-cases/${widget.caseId}/contributions',
      );
      if (mounted && !stale) {
        setState(() {
          updates = rows;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudieron consultar los aportes del ciudadano.',
        );
      }
    }
  }

  @override
  void dispose() {
    auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => stale
      ? const SizedBox.shrink()
      : ExpansionTile(
          title: const Text('Aportes del ciudadano'),
          children: [
            if (error != null) Text(error!),
            TextButton(
              onPressed: load,
              child: const Text('Actualizar aportes'),
            ),
            SosEvidenceList(caseId: widget.caseId, updates: updates),
          ],
        );
}

class SosEvidenceList extends StatelessWidget {
  const SosEvidenceList({
    super.key,
    required this.caseId,
    required this.updates,
  });
  final String caseId;
  final List<Map<String, dynamic>> updates;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in updates)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${row['description']}'),
                Text(
                  DateTime.tryParse(
                        '${row['at']}',
                      )?.toLocal().toString().split('.').first ??
                      '',
                ),
                for (final p in row['photos'] as List)
                  SosEvidencePhoto(
                    key: ValueKey('${row['id']}-${p['id']}'),
                    path: '/sos-cases/$caseId/photos/${p['id']}',
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}

class SosEvidencePhoto extends StatefulWidget {
  const SosEvidencePhoto({super.key, required this.path});
  final String path;
  @override
  State<SosEvidencePhoto> createState() => _SosEvidencePhotoState();
}

class _SosEvidencePhotoState extends State<SosEvidencePhoto> {
  late Future<dynamic> photo;
  @override
  void initState() {
    super.initState();
    photo = WorkflowClient.request('GET', widget.path, bytes: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: photo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(
            () =>
                photo = WorkflowClient.request('GET', widget.path, bytes: true),
          ),
          child: const Text('Reintentar foto'),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.memory(
          snapshot.data as Uint8List,
          height: 180,
          fit: BoxFit.contain,
        ),
      );
    },
  );
}
