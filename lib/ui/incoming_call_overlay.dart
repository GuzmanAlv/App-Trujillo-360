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
      timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (busy || !foreground || uid == null || ActiveCall.id.value != null) {
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
      final result = allowed
          ? await WorkflowClient.list('/operator/calls/incoming')
          : <Map<String, dynamic>>[];
      if (mounted && uid == owner) setState(() => incoming = result);
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
    ActiveCall.id.value = id;
    setState(() => incoming = []);
    try {
      await appNavigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => AudioCallPage(callId: id, operator: true),
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
      return Stack(
        children: [
          widget.child,
          if (active == null && queue.isNotEmpty)
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
                                const Expanded(
                                  child: Text(
                                    'Llamada SOS entrante',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      'Ocultar aviso; el SOS sigue pendiente',
                                  onPressed: () => setState(
                                    () => hidden.add('${queue.first['id']}'),
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const Text(
                              'Un ciudadano solicita hablar con un operador.',
                            ),
                            if (queue.length > 1)
                              Text('${queue.length} llamadas esperando'),
                            FilledButton.icon(
                              onPressed: () => accept('${queue.first['id']}'),
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
      );
    },
  );
}
