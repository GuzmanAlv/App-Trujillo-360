import 'dart:async';
import 'package:flutter/material.dart';

/// A release, pointer cancellation or app interruption cancels the hold.
class HoldSosButton extends StatefulWidget {
  const HoldSosButton({super.key, required this.onComplete, this.busy = false});
  final VoidCallback onComplete;
  final bool busy;
  @override
  State<HoldSosButton> createState() => _HoldSosButtonState();
}

class _HoldSosButtonState extends State<HoldSosButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  Timer? hold;
  int? pointer;
  void cancel() {
    hold?.cancel();
    pointer = null;
    progress.reset();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant HoldSosButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy) cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    hold?.cancel();
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SOS. Mantén presionado tres segundos para solicitar una llamada.',
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (!widget.busy && pointer == null) {
          pointer = event.pointer;
          progress.forward(from: 0);
          hold = Timer(const Duration(seconds: 3), () {
            if (!mounted || widget.busy || pointer == null) return;
            cancel();
            widget.onComplete();
          });
        }
      },
      onPointerUp: (event) {
        if (pointer == event.pointer) cancel();
      },
      onPointerCancel: (event) {
        if (pointer == event.pointer) cancel();
      },
      onPointerMove: (event) {
        final size = context.size;
        if (pointer == event.pointer &&
            size != null &&
            !(Offset.zero & size).contains(event.localPosition)) {
          cancel();
        }
      },
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, _) => Material(
          color: const Color(0xffc62828),
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: progress.value > 0
                      ? CircularProgressIndicator(
                          value: progress.value,
                          color: Colors.white,
                        )
                      : const Icon(Icons.sos, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.busy ? 'Enviando…' : 'Mantén 3 s',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
