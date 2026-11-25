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
    this.redial = false,
    this.prepared = false,
    String? expectedRoom,
    this.readStatus,
    Room? room,
  }) : selectedRoom = expectedRoom,
       room = room ?? Room();
  final String callId;
  final bool prepared;
  String? selectedRoom;
  DateTime? lastHeartbeat;
  final bool operator, callback, answer, redial;
  final Room room;
  final Future<dynamic> Function()? readStatus;
  Timer? poll;
  Timer? verificationDeadline;
  StreamSubscription<User?>? auth;
  String message = 'Preparando llamada…';
  String? failure;
  String? joinedRoom;
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
    if (room.connectionState == ConnectionState.disconnected) joined = false;
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
      if (prepared) started = true;
      if (!await Permission.microphone.request().isGranted) {
        throw StateError(
          'Permite el micrófono para conversar. El SOS sigue registrado.',
        );
      }
      if (!mounted || finished) return;
      if (!prepared) {
        final initial = await WorkflowClient.request(
          'POST',
          '$path/${redial
              ? 'redial'
              : callback
              ? 'callback'
              : answer
              ? 'answer'
              : operator
              ? 'accept'
              : 'start'}',
        );
        selectedRoom = initial['room'] as String?;
      }
      started = true;
      if (!finished && mounted) await notice(true);
      if (!mounted || finished) {
        await WorkflowClient.request(
          'POST',
          '$path/end',
          body: {'room': selectedRoom ?? joinedRoom},
        );
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
      final data = readStatus != null
          ? await readStatus!()
          : await WorkflowClient.request(
              'GET',
              path,
              timeout: const Duration(seconds: 8),
            );
      if (!mounted || finished) return;
      if (operator && selectedRoom != null && data['room'] != selectedRoom) {
        finished = true;
        poll?.cancel();
        await room.disconnect();
        showFailure(
          StateError('La llamada cambió. Vuelve a abrir el caso SOS.'),
        );
        return;
      }
      selectedRoom ??= data['room'] as String?;
      if (operator &&
          started &&
          data['state'] == 'accepted' &&
          (lastHeartbeat == null ||
              DateTime.now().difference(lastHeartbeat!).inSeconds >= 30)) {
        await WorkflowClient.request('POST', '$path/heartbeat');
        lastHeartbeat = DateTime.now();
      }
      if (joined && data['room'] != joinedRoom) {
        await room.disconnect();
        joined = false;
        joinedRoom = null;
      }
      verificationDeadline?.cancel();
      verificationDeadline = null;
      if (joined) setState(() => failure = null);
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
          if (access['room'] != data['room'] ||
              (operator && access['room'] != selectedRoom)) {
            throw StateError('La llamada cambió. Vuelve a abrir el caso SOS.');
          }
          selectedRoom = access['room'] as String;
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
          joinedRoom = access['room'] as String;
          failure = null;
          roomChanged();
        } finally {
          joining = false;
        }
      } else if (data['state'] == 'waiting_assignment') {
        setState(() {
          failure = null;
          message = 'Buscando otro operador disponible para tu mismo SOS…';
        });
      } else if (data['state'] == 'waiting') {
        setState(() {
          failure = null;
          message = callback
              ? 'Llamando al ciudadano…'
              : 'Buscando operador · puedes cancelar';
        });
      }
    } catch (e) {
      if (!mounted || finished) return;
      if (e is WorkflowFailure && !e.temporary) {
        verificationDeadline?.cancel();
        finished = true;
        poll?.cancel();
        await closeCallResources([() => room.disconnect()]);
        joined = false;
        showFailure(e);
      } else {
        setState(() => failure = 'Reconectando con el servidor…');
        verificationDeadline ??= Timer(const Duration(seconds: 60), () async {
          verificationDeadline = null;
          if (!mounted || finished) return;
          await closeCallResources([() => room.disconnect()]);
          if (!mounted || finished) return;
          joined = false;
          showFailure(
            StateError(
              'No se pudo verificar la llamada durante un minuto. Reintentando conexión.',
            ),
          );
        });
      }
    } finally {
      checking = false;
    }
  }

  Future<bool> finish() async {
    verificationDeadline?.cancel();
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
          await WorkflowClient.request(
            'POST',
            '$path/end',
            body: {'room': selectedRoom ?? joinedRoom},
          );
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
    verificationDeadline?.cancel();
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
