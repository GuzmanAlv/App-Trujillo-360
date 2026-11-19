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
              builder: (context, child) {
                final red = Colors.red.withValues(
                  alpha: .12 + animation.value * .24,
                );
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [red, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [red, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      width: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [red, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, red],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
    ],
  );
}
