import 'package:flutter/material.dart';
import '../models/incident.dart';
import 'report_style.dart';

class ProximityAlertCard extends StatelessWidget {
  const ProximityAlertCard({
    super.key,
    required this.incident,
    required this.meters,
    required this.onOpen,
    required this.onDismiss,
  });
  final Incident incident;
  final int meters;
  final VoidCallback onOpen, onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = ReportStyle.forCategory(incident.type);
    final confirmed =
        !incident.needsReview &&
        incident.corroborationCount >= 3 &&
        ['corroborated', 'verified'].contains(incident.remoteStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportCategoryIcon(category: incident.type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ALERTA CERCANA',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff087f68),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    incident.type,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff172b26),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Cerrar alerta',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, color: Color(0xff63736c)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.near_me_rounded, size: 17, color: style.color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'A $meters m de ti · ${reportTime(incident.createdAt)}',
                style: const TextStyle(
                  color: Color(0xff344b42),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            confirmed
                ? 'Corroborado por la comunidad'
                : 'Pendiente de corroboración',
            style: TextStyle(
              color: style.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff087f68),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onOpen,
            icon: const Icon(Icons.map_outlined, size: 20),
            label: const Text('Ver ubicación'),
          ),
        ),
      ],
    );
  }
}
