import 'package:flutter/material.dart';

({String label, Color color, IconData icon}) sosStyle(Map<String, dynamic> d) {
  if (d['support_requested'] == true) {
    return (
      label: 'Apoyo solicitado',
      color: Colors.red.shade700,
      icon: Icons.campaign,
    );
  }
  if (d['decision'] == 'discarded') {
    return (
      label: 'Descartado',
      color: Colors.grey,
      icon: Icons.cancel_outlined,
    );
  }
  return switch (d['attention']) {
    'en_route' => (
      label: 'Unidad en camino',
      color: Colors.blue.shade700,
      icon: Icons.local_police,
    ),
    'on_scene' => (
      label: 'Unidad en la zona',
      color: Colors.purple.shade700,
      icon: Icons.location_on,
    ),
    'resolved' => (
      label: 'Resuelto',
      color: Colors.grey.shade700,
      icon: Icons.task_alt,
    ),
    _ =>
      d['decision'] == 'confirmed'
          ? (
              label: 'Confirmado',
              color: Colors.teal.shade700,
              icon: Icons.warning_rounded,
            )
          : (
              label: 'Pendiente',
              color: Colors.orange.shade800,
              icon: Icons.schedule,
            ),
  };
}

class SosStatusBadge extends StatelessWidget {
  const SosStatusBadge({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final s = sosStyle(data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: .10),
        border: Border.all(color: s.color.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, color: s.color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              s.label,
              style: TextStyle(
                color: s.color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SosSupportFrame extends StatefulWidget {
  const SosSupportFrame({
    super.key,
    required this.active,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });
  final bool active;
  final EdgeInsetsGeometry margin;
  final Widget child;
  @override
  State<SosSupportFrame> createState() => _SosSupportFrameState();
}

class _SosSupportFrameState extends State<SosSupportFrame>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  void update() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      animation.repeat(reverse: true);
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
  void didUpdateWidget(covariant SosSupportFrame old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) update();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, child) => Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: widget.active ? Border.all(color: Colors.red, width: 2) : null,
        boxShadow: widget.active
            ? [
                BoxShadow(
                  color: Colors.red.withValues(
                    alpha: .12 + animation.value * .18,
                  ),
                  blurRadius: 5 + animation.value * 10,
                ),
              ]
            : [],
      ),
      child: child,
    ),
    child: widget.child,
  );
}
