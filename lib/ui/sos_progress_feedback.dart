import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/active_call.dart';

/// Foreground progress cues are separate from incoming SOS and call alarms.
class SosProgressFeedback extends StatefulWidget {
  const SosProgressFeedback({
    super.key,
    required this.mode,
    required this.child,
  });
  final String? mode;
  final Widget child;
  @override
  State<SosProgressFeedback> createState() => _SosProgressFeedbackState();
}

class _SosProgressFeedbackState extends State<SosProgressFeedback>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('trujillo360/proximity');
  static final owners = <Object, String>{};
  final owner = Object();
  Timer? lease;
  bool foreground = true;
  Future<void> signal() async {
    final mode = foreground && ActiveCall.id.value == null ? widget.mode : null;
    if (mode == null) {
      owners.remove(owner);
    } else {
      owners[owner] = mode;
    }
    try {
      await channel.invokeMethod<void>('sosProgressSignal', {
        'mode': owners.values.contains('operator')
            ? 'operator'
            : owners.values.contains('citizen')
            ? 'citizen'
            : 'none',
      });
    } catch (_) {
      /* Map status remains available without device feedback. */
    }
  }

  void update() {
    lease?.cancel();
    unawaited(signal());
    if (foreground && widget.mode != null && ActiveCall.id.value == null) {
      lease = Timer.periodic(const Duration(seconds: 8), (_) => signal());
    }
  }

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    ActiveCall.id.addListener(update);
    update();
  }

  @override
  void didUpdateWidget(covariant SosProgressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    update();
  }

  @override
  void dispose() {
    foreground = false;
    lease?.cancel();
    ActiveCall.id.removeListener(update);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(signal());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
