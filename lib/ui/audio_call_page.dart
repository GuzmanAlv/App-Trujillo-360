import 'operator_call_bar.dart';
import 'call_page_layout.dart';
import 'sos_case_panel.dart';
import '../services/active_call.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/workflow_client.dart';
import '../services/call_cleanup.dart';

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
  final room = Room();
  final caseKey = GlobalKey<SosCasePanelState>();
  Timer? poll;
  StreamSubscription<User?>? auth;
  String message = 'Preparando llamada…';
  String? failure;
  bool checking = false, joining = false, joined = false, finished = false;
  bool closing = false, muted = false, speaker = false, started = false;
  bool beginning = false, allowPop = false;
  String get path => '/calls/${widget.callId}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ActiveCall.id.value = widget.callId;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != uid) {
        finished = true;
        started = false;
        poll?.cancel();
        unawaited(room.disconnect());
        if (mounted) {
          setState(() => message = 'La sesión cambió. Audio desconectado.');
        }
      }
    });
    room.addListener(roomChanged);
    unawaited(begin());
  }

  void roomChanged() {
    if (!mounted || finished || !joined) return;
    setState(
      () => message = room.connectionState == ConnectionState.connected
          ? (room.remoteParticipants.isEmpty
                ? 'Esperando que se conecte la otra persona…'
                : 'Participante conectado · Audio habilitado')
          : 'Conexión de audio interrumpida.',
    );
  }

  Future<void> begin() async {
    if (beginning || finished) return;
    beginning = true;
    try {
      if (!await Permission.microphone.request().isGranted) {
        throw StateError(
          'Permite el micrófono para conversar. El SOS sigue registrado.',
        );
      }
      if (!mounted || finished) return;
      await WorkflowClient.request(
        'POST',
        '$path/${widget.callback
            ? 'callback'
            : widget.answer
            ? 'answer'
            : widget.operator
            ? 'accept'
            : 'start'}',
      );
      started = true;
      if (!mounted || finished) {
        await WorkflowClient.request('POST', '$path/end');
        return;
      }
      poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
      await refresh();
    } catch (e) {
      showFailure(e);
    } finally {
      beginning = false;
    }
  }

  void showFailure(Object e) {
    if (mounted) {
      setState(
        () => failure = e is StateError
            ? e.message.toString()
            : 'No se pudo conectar el audio. Tu solicitud de ayuda sigue registrada.',
      );
    }
  }

  Future<void> refresh() async {
    if (checking || finished) return;
    checking = true;
    try {
      final data = await WorkflowClient.request('GET', path);
      if (!mounted || finished) return;
      if (['ended', 'unanswered'].contains(data['state'])) {
        finished = true;
        poll?.cancel();
        await room.disconnect();
        if (mounted) {
          setState(() {
            failure = null;
            message = data['state'] == 'unanswered'
                ? 'Ningún operador aceptó a tiempo. El SOS sigue registrado.'
                : 'Llamada finalizada. El caso sigue en seguimiento.';
          });
        }
      } else if (data['state'] == 'accepted' &&
          data['can_join'] == true &&
          !joined &&
          !joining) {
        joining = true;
        try {
          final access = await WorkflowClient.request('POST', '$path/token');
          if (!mounted || finished) return;
          await room.connect(
            access['url'] as String,
            access['token'] as String,
          );
          if (!mounted || finished) {
            await room.disconnect();
            return;
          }
          await room.localParticipant?.setMicrophoneEnabled(!muted);
          if (!mounted || finished) {
            await room.disconnect();
            return;
          }
          await AudioManager.instance.setSpeakerOutputPreferred(speaker);
          joined = true;
          failure = null;
          roomChanged();
        } finally {
          joining = false;
        }
      } else if (data['state'] == 'waiting') {
        setState(() {
          failure = null;
          message = widget.callback
              ? 'Llamando al ciudadano…'
              : 'Buscando operador · puedes cancelar';
        });
      }
    } catch (e) {
      // Stop audio if we cannot confirm that the private session is still active.
      await room.disconnect();
      joined = false;
      showFailure(e);
    } finally {
      checking = false;
    }
  }

  Future<void> finish({bool exit = false}) async {
    if (closing) return;
    if (exit && !(await caseKey.currentState?.mayLeave() ?? true)) return;
    if (!mounted || closing) return;
    setState(() => closing = true);
    finished = true;
    poll?.cancel();
    try {
      final complete = await closeCallResources([
        // Stop microphone capture separately from signaling/disconnect.
        for (final publication
            in room.localParticipant?.audioTrackPublications ?? [])
          () async {
            await publication.track?.stop();
          },
        if (joined ||
            joining ||
            room.connectionState != ConnectionState.disconnected)
          () async {
            await room.disconnect();
          },
        if (started)
          () async {
            await WorkflowClient.request('POST', '$path/end');
          },
      ]);
      if (!complete && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se confirmó todo el cierre de la llamada. El SOS sigue registrado.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => closing = false);
        if (!widget.operator || exit) {
          leave();
        } else {
          setState(() {
            message = 'Llamada finalizada. Continúa con la evaluación.';
            joined = false;
          });
        }
      }
    }
  }

  void leave() {
    if (!mounted) return;
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    finished = true;
    poll?.cancel();
    auth?.cancel();
    room.removeListener(roomChanged);
    unawaited(
      closeCallResources([
        () async {
          await room.dispose();
        },
      ]),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ActiveCall.id.value == widget.callId) ActiveCall.id.value = null;
    });
    super.dispose();
  }

  Future<void> toggleMicrophone() async {
    try {
      await room.localParticipant?.setMicrophoneEnabled(muted);
      if (mounted) setState(() => muted = !muted);
    } catch (e) {
      showFailure(e);
    }
  }

  Future<void> toggleSpeaker() async {
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(!speaker);
      if (mounted) setState(() => speaker = !speaker);
    } catch (e) {
      showFailure(e);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(finish(exit: true));
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Llamada SOS'), centerTitle: true),
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
                          onPressed: () async {
                            try {
                              await room.localParticipant?.setMicrophoneEnabled(
                                muted,
                              );
                              if (mounted) setState(() => muted = !muted);
                            } catch (e) {
                              showFailure(e);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Altavoz',
                          icon: Icon(speaker ? Icons.volume_up : Icons.hearing),
                          onPressed: () async {
                            try {
                              await AudioManager.instance
                                  .setSpeakerOutputPreferred(!speaker);
                              if (mounted) setState(() => speaker = !speaker);
                            } catch (e) {
                              showFailure(e);
                            }
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffba303a),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                    onPressed: closing || (widget.operator && finished)
                        ? null
                        : () => finish(),
                    icon: const Icon(Icons.call_end),
                    label: Text(
                      closing
                          ? 'Cerrando…'
                          : widget.operator
                          ? (finished ? 'Audio cerrado' : 'Finalizar llamada')
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
                )
              : null,
        ),
      ),
    ),
  );
}
