import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/sos_alarm.dart';

class SosIncomingAttention extends StatefulWidget {
  const SosIncomingAttention({
    super.key,
    required this.active,
    required this.builder,
    this.enableSound = true,
    this.glowColor = const Color(0xffff0028),
    this.enableGlow = true,
  });
  final bool active, enableSound;
  final Color glowColor;
  final bool enableGlow;
  final Widget Function(bool muted, VoidCallback toggleMute) builder;
  @override
  State<SosIncomingAttention> createState() => _SosIncomingAttentionState();
}

class _SosIncomingAttentionState extends State<SosIncomingAttention>
    with SingleTickerProviderStateMixin {
  final alarmOwner = Object();
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? lease;
  bool muted = false;
  bool signalOwned = false;
  Future<void> signal(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final target = enabled && widget.enableSound;
    if (!target && !signalOwned) return;
    signalOwned = target;
    await SosAlarm.update(alarmOwner, target);
  }

  void update() {
    lease?.cancel();
    lease = null;
    final active = widget.active && !muted && widget.enableSound;
    unawaited(signal(active));
    if (active) {
      lease = Timer.periodic(const Duration(seconds: 8), (_) => signal(true));
    }
    if (widget.enableGlow &&
        widget.active &&
        !MediaQuery.disableAnimationsOf(context)) {
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
    if (old.active != widget.active ||
        old.enableSound != widget.enableSound ||
        old.enableGlow != widget.enableGlow ||
        old.glowColor != widget.glowColor) {
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

  void toggleMute() {
    setState(() => muted = !muted);
    update();
  }

  @override
  Widget build(BuildContext context) => !widget.enableGlow
      ? widget.builder(muted, toggleMute)
      : Stack(
          fit: StackFit.expand,
          children: [
            widget.builder(muted, toggleMute),
            if (widget.enableGlow && widget.active)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final red = widget.glowColor.withValues(
                        alpha: .28 + animation.value * .42,
                      );
                      return Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 52,
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
                            height: 52,
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
                            width: 52,
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
                            width: 52,
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
