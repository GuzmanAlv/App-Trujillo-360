import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'workflow_client.dart';
import 'call_cleanup.dart';

class CallSession extends ChangeNotifier {
  CallSession({
    required this.callId,
    required this.operator,
    this.callback = false,
    this.answer = false,
    Room? room,
  }) : room = room ?? Room();
  final String callId;
  final bool operator, callback, answer;
  final Room room;
  Timer? poll;
  StreamSubscription<User?>? auth;
  String message = 'Preparando llamada…';
  String? failure;
  bool checking = false, joining = false, joined = false, finished = false;
  bool closing = false, muted = false, speaker = false, started = false;
  bool beginning = false;
  bool minimized = false, _disposed = false;
  bool get mounted => !_disposed;
  void setState(VoidCallback change) {
    if (mounted) {
      change();
      notifyListeners();
    }
  }

  String get path => '/calls/$callId';
  Future<void> notice(bool enabled) async {
    if (operator || answer) return;
    try {
      await const MethodChannel(
        'trujillo360/proximity',
      ).invokeMethod('sosCallNotice', {'enabled': enabled});
    } catch (_) {
      /* Device voice may not be installed. */
    }
  }

  void start() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != uid) {
        finished = true;
        started = false;
        poll?.cancel();
        unawaited(notice(false));
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
        '$path/${callback
            ? 'callback'
            : answer
            ? 'answer'
            : operator
            ? 'accept'
            : 'start'}',
      );
      started = true;
      if (!finished && mounted) await notice(true);
      if (!mounted || finished) {
        await WorkflowClient.request('POST', '$path/end');
        return;
      }
      poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
      await refresh();
    } catch (e) {
      unawaited(notice(false));
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
        await notice(false);
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
          await notice(false);
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
          message = callback
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

  Future<bool> finish() async {
    unawaited(notice(false));
    if (closing) return false;
    setState(() => closing = true);
    finished = true;
    poll?.cancel();
    final complete = await closeCallResources([
      for (final p in room.localParticipant?.audioTrackPublications ?? [])
        () async {
          await p.track?.stop();
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
    if (mounted) {
      setState(() {
        closing = false;
        joined = false;
        message = 'Llamada finalizada. El caso sigue en seguimiento.';
      });
    }
    return complete;
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(notice(false));
    _disposed = true;
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
}
