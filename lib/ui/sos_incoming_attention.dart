import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SosIncomingAttention extends StatefulWidget {
  const SosIncomingAttention({
    super.key,
    required this.active,
    required this.builder,
  });
  final bool active;
  final Widget Function(bool muted, VoidCallback toggleMute) builder;
  @override
  State<SosIncomingAttention> createState() => _SosIncomingAttentionState();
}

class _SosIncomingAttentionState extends State<SosIncomingAttention>
    with SingleTickerProviderStateMixin {
  static const channel = MethodChannel('trujillo360/proximity');
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? lease;
  bool muted = false;
  Future<void> signal(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('sosIncomingAlarm', {
        'enabled': enabled,
      });
    } catch (_) {
      /* Visual alert remains usable. */
    }
  }

  void update() {
    lease?.cancel();
    lease = null;
    final active = widget.active && !muted;
    unawaited(signal(active));
    if (active) {
      lease = Timer.periodic(const Duration(seconds: 8), (_) => signal(true));
    }
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!animation.isAnimating) animation.repeat(reverse: true);
    } else {
      animation.stop();
      animation.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    update();
  }

  @override
  void didUpdateWidget(covariant SosIncomingAttention old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (!widget.active) muted = false;
      update();
    }
  }

  @override
  void dispose() {
    lease?.cancel();
    unawaited(signal(false));
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.builder(muted, () {
        setState(() => muted = !muted);
        update();
      }),
      if (widget.active)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.red.withValues(
                      alpha: .5 + animation.value * .4,
                    ),
                    width: 3 + animation.value * 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(
                        alpha: .16 + animation.value * .24,
                      ),
                      blurRadius: 18 + animation.value * 12,
                      spreadRadius: -8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
