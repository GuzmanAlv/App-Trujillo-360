import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CallbackRing extends StatefulWidget {
  const CallbackRing({
    super.key,
    required this.active,
    required this.builder,
    this.ringId,
  });
  final String? ringId;
  final bool active;
  final Widget Function(bool, VoidCallback) builder;
  @override
  State<CallbackRing> createState() => _CallbackRingState();
}

class _CallbackRingState extends State<CallbackRing> {
  static const channel = MethodChannel('trujillo360/proximity');
  Timer? lease;
  bool muted = false;
  void update() {
    lease?.cancel();
    final enabled = widget.active && !muted;
    void signal() {
      unawaited(
        channel
            .invokeMethod('sosCallbackRing', {'enabled': enabled})
            .catchError((Object _) {}),
      );
    }

    signal();
    if (enabled) {
      lease = Timer.periodic(const Duration(seconds: 8), (_) => signal());
    }
  }

  @override
  void initState() {
    super.initState();
    update();
  }

  @override
  void didUpdateWidget(covariant CallbackRing old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.ringId != widget.ringId) {
      if (!widget.active || old.ringId != widget.ringId) muted = false;
      update();
    }
  }

  @override
  void dispose() {
    lease?.cancel();
    unawaited(
      channel
          .invokeMethod('sosCallbackRing', {'enabled': false})
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(muted, () {
    setState(() => muted = !muted);
    update();
  });
}
