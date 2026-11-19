import 'sos_incoming_attention.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/active_call.dart';
import '../services/workflow_client.dart';
import 'audio_call_page.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

/// In-app overlay above all routes, not a system overlay or lock-screen call UI.
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key, required this.child});
  final Widget child;
  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with WidgetsBindingObserver {
  Timer? timer;
  StreamSubscription<User?>? auth;
  List<Map<String, dynamic>> incoming = [];
  final hidden = <String>{};
  String? uid;
  bool busy = false, foreground = true, allowed = false;
  DateTime roleChecked = DateTime(2000);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      auth = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (uid != user?.uid) {
          uid = user?.uid;
          if (mounted) {
            setState(() {
              incoming = [];
              hidden.clear();
              allowed = false;
              roleChecked = DateTime(2000);
            });
          }
        }
        unawaited(refresh());
      });
      timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() {});
        unawaited(refresh());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => foreground = state == AppLifecycleState.resumed);
    if (foreground) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!mounted ||
        busy ||
        !foreground ||
        uid == null ||
        ActiveCall.id.value != null) {
      return;
    }
    busy = true;
    final owner = uid;
    try {
      if (DateTime.now().difference(roleChecked) >
          const Duration(seconds: 30)) {
        final profile = await WorkflowClient.profile();
        if (!mounted || uid != owner) return;
        allowed =
            profile['status'] == 'active' &&
            ['operator', 'admin'].contains(profile['role']);
        roleChecked = DateTime.now();
      }
      final returns = await WorkflowClient.list('/calls/incoming/return');
      final result = allowed
          ? await WorkflowClient.list('/operator/calls/incoming')
          : <Map<String, dynamic>>[];
      if (mounted && uid == owner) {
        setState(() => incoming = [...returns, ...result]);
      }
    } catch (_) {
      if (mounted) setState(() => incoming = []);
    } finally {
      busy = false;
    }
  }

  Future<void> accept(String id) async {
    if (ActiveCall.id.value != null || appNavigatorKey.currentState == null) {
      return;
    }
    final returning = incoming.any(
      (r) => r['id'] == id && r['callback'] == true,
    );
    ActiveCall.id.value = id;
    setState(() => incoming = []);
    try {
      await appNavigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              AudioCallPage(callId: id, operator: allowed, answer: returning),
        ),
      );
    } finally {
      if (ActiveCall.id.value == id) ActiveCall.id.value = null;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: ActiveCall.id,
    builder: (context, active, _) {
      final queue = incoming
          .where(
            (r) =>
                !hidden.contains(r['id']) &&
                (DateTime.tryParse(
                      '${r['expires_at']}',
                    )?.isAfter(DateTime.now()) ??
                    false),
          )
          .toList();
      final shown = active == null && foreground
          ? queue
          : <Map<String, dynamic>>[];
      return SosIncomingAttention(
        active: allowed && shown.any((r) => r['callback'] != true),
        builder: (muted, toggleMute) => IncomingCallView(
          muted: muted,
          onMute: allowed ? toggleMute : null,
          queue: shown,
          onAccept: accept,
          onHide: (id) => setState(() => hidden.add(id)),
          child: widget.child,
        ),
      );
    },
  );
}

/// MaterialApp.builder sits above the Navigator's Overlay. Give both the
/// navigator and the floating card an outer overlay, so tooltips on the card
/// have a valid ancestor without losing the current route on queue updates.
class IncomingCallView extends StatelessWidget {
  const IncomingCallView({
    super.key,
    required this.child,
    required this.queue,
    required this.onAccept,
    required this.onHide,
    this.muted = false,
    this.onMute,
  });
  final bool muted;
  final VoidCallback? onMute;
  final Widget child;
  final List<Map<String, dynamic>> queue;
  final ValueChanged<String> onAccept, onHide;
  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(
      child: Stack(
        children: [
          child,
          if (queue.isNotEmpty)
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone_in_talk,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    queue.first['callback'] == true
                                        ? 'El operador te llama'
                                        : 'SOS Alerta',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                if (onMute != null)
                                  IconButton(
                                    tooltip: muted
                                        ? 'Activar sonido y vibración'
                                        : 'Silenciar sonido y vibración',
                                    onPressed: onMute,
                                    icon: Icon(
                                      muted
                                          ? Icons.volume_off
                                          : Icons.volume_up,
                                    ),
                                  ),
                                IconButton(
                                  tooltip:
                                      'Ocultar aviso; el SOS sigue pendiente',
                                  onPressed: () =>
                                      onHide('${queue.first['id']}'),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Text(
                              queue.first['callback'] == true
                                  ? 'Devolución de llamada de tu caso SOS.'
                                  : '${queue.length} ${queue.length == 1 ? 'llamada esperando atención' : 'llamadas esperando atención'}',
                            ),

                            FilledButton.icon(
                              onPressed: () => onAccept('${queue.first['id']}'),
                              icon: const Icon(Icons.call),
                              label: const Text('Tomar llamada'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
