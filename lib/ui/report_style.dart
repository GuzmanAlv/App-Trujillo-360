import 'package:flutter/material.dart';

/// Shared visual identity for filters, forms, report cards and map labels.
class ReportStyle {
  const ReportStyle(this.color, this.icon);

  final Color color;
  final IconData icon;

  static ReportStyle forCategory(String category) => switch (category) {
    'Robo' => const ReportStyle(Color(0xffb45309), Icons.money_off_rounded),
    'Auxilio' => const ReportStyle(
      Color(0xff0369a1),
      Icons.health_and_safety_rounded,
    ),
    'Agresión' => const ReportStyle(
      Color(0xffbe123c),
      Icons.front_hand_rounded,
    ),
    'Riesgo' => const ReportStyle(Color(0xff7e22ce), Icons.warning_rounded),
    _ => const ReportStyle(Color(0xff087f68), Icons.layers_rounded),
  };
}

String reportTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class ReportCategoryIcon extends StatelessWidget {
  const ReportCategoryIcon({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final style = ReportStyle.forCategory(category);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(style.icon, color: style.color, size: 25),
    );
  }
}
