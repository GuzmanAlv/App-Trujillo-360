import '../services/call_session.dart';
import '../services/sos_navigation.dart';
import 'operator_call_bar.dart';
import 'call_page_layout.dart';
import 'sos_case_panel.dart';
import '../services/active_call.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide ConnectionState;

/// Foreground pilot: notifications lead operators to the SOS case, where they accept.
class AudioCallPage extends StatefulWidget {
  const AudioCallPage({
    super.key,
    required this.callId,
    this.operator = false,
    this.callback = false,
    this.answer = false,
  });
  final String callId;
  final bool operator, callback, answer;
  @override
  State<AudioCallPage> createState() => _AudioCallPageState();
}

class _AudioCallPageState extends State<AudioCallPage> {
  final caseKey = GlobalKey<SosCasePanelState>();
  late final CallSession session;
  bool minimized = false, allowPop = false;
  String get message => session.message;
  String? get failure => session.failure;
  bool get joined => session.joined;
  bool get started => session.started;
  bool get finished => session.finished;
  bool get closing => session.closing;
  bool get muted => session.muted;
  bool get speaker => session.speaker;
  @override
  void initState() {
    super.initState();
    final existing = ActiveCall.session.value;
    session =
        existing != null &&
            existing.callId == widget.callId &&
            !existing.finished
        ? existing
        : CallSession(
            callId: widget.callId,
            operator: widget.operator,
            callback: widget.callback,
            answer: widget.answer,
          );
    session.minimized = false;
    session.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ActiveCall.bind(session)) {
        session.finished = true;
        session.showFailure(StateError('Tienes otra llamada activa.'));
        return;
      }
      if (!identical(existing, session)) session.start();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> begin() => session.begin();
  Future<void> redial() async {
    if (closing || !finished ||
        !(await caseKey.currentState?.mayLeave() ?? true) || !mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => AudioCallPage(
        callId: widget.callId, operator: true, callback: true)),
    );
  }
  Future<void> toggleMicrophone() => session.toggleMicrophone();
  Future<void> toggleSpeaker() => session.toggleSpeaker();
  Future<void> finish({bool exit = false}) async {
    if (closing) return;
    if (exit && !(await caseKey.currentState?.mayLeave() ?? true)) return;
    if (!mounted) return;
    final complete = await session.finish();
    if (!mounted) return;
    if (!complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se confirmó todo el cierre de audio.'),
        ),
      );
    }
    if (!widget.operator || exit) leave();
  }

  void leave() {
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> backToMap() async {
    if (closing) return;
    if (widget.operator && !(await caseKey.currentState?.mayLeave() ?? true)) {
      return;
    }
    if (!mounted) return;
    if (!session.finished) {
      minimized = true;
      ActiveCall.minimize(session);
    }
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        SosNavigation.showMap();
      }
    });
  }

  Future<void> confirmed(Map<String, dynamic> data) async {
    if (!mounted) return;
    minimized = !session.finished;
    if (minimized) ActiveCall.minimize(session);
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((r) => r.isFirst);
      SosNavigation.open(widget.callId);
    });
  }

  @override
  void dispose() {
    session.removeListener(changed);
    if (!minimized) {
      scheduleMicrotask(() => ActiveCall.release(session));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(backToMap());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Llamada SOS'),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Volver al mapa sin colgar',
          onPressed: backToMap,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: CallPageLayout(
          compactControls: widget.operator
              ? OperatorCallBar(
                  message: message,
                  muted: muted,
                  speaker: speaker,
                  finished: finished,
                  closing: closing,
                  connected: joined,
                  onMute: toggleMicrophone,
                  onSpeaker: toggleSpeaker,
                  onHangUp: () => finish(),
                )
              : null,
          controls: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xffdbe6df)),
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.operator ? 16 : 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: widget.operator ? 52 : 80,
                    height: widget.operator ? 52 : 80,
                    decoration: const BoxDecoration(
                      color: Color(0xffe0f2eb),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      finished ? Icons.call_end : Icons.support_agent,
                      size: widget.operator ? 28 : 40,
                      color: const Color(0xff087f68),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.operator
                        ? 'Atención SOS'
                        : finished
                        ? 'Llamada finalizada'
                        : joined
                        ? 'Llamada SOS'
                        : 'Conectando con un operador',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(failure!, textAlign: TextAlign.center),
                    ),
                  if (failure != null && !started && !finished)
                    TextButton(
                      onPressed: begin,
                      child: const Text('Reintentar conexión'),
                    ),
                  const SizedBox(height: 8),
                  if (joined && !finished)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: [
                        IconButton(
                          tooltip: muted ? 'Activar micrófono' : 'Silenciar',
                          icon: Icon(muted ? Icons.mic_off : Icons.mic),
                          onPressed: toggleMicrophone,
                        ),
                        IconButton(
                          tooltip: 'Altavoz',
                          icon: Icon(speaker ? Icons.volume_up : Icons.hearing),
                          onPressed: toggleSpeaker,
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (!widget.operator &&
                      !widget.answer &&
                      !joined &&
                      !finished)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Solo para emergencias reales. El uso malicioso puede ocasionar la revisión y suspensión de tu cuenta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.operator && finished
                          ? const Color(0xff16834a)
                          : const Color(0xffba303a),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                    onPressed: closing ? null : widget.operator && finished
                        ? redial
                        : () => finish(),
                    icon: Icon(widget.operator && finished
                        ? Icons.call_rounded : Icons.call_end),
                    label: Text(
                      closing
                          ? 'Cerrando…'
                          : widget.operator
                          ? (finished ? 'Volver a llamar' : 'Finalizar llamada')
                          : 'Finalizar y volver',
                    ),
                  ),
                ],
              ),
            ),
          ),
          evaluation: widget.operator
              ? SosCasePanel(
                  key: caseKey,
                  caseId: widget.callId,
                  guardNavigation: false,
                  showCallButton: false,
                  onConfirmed: confirmed,
                )
              : null,
        ),
      ),
    ),
  );
}
