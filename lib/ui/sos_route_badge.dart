import 'package:flutter/material.dart';
import '../services/sos_route_controller.dart';

/// Route information stays over the map instead of taking another full row.
class SosRouteBadge extends StatelessWidget {
  const SosRouteBadge({super.key, required this.route});
  final SosRouteController route;
  void details(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: route,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  route.isReinforcement ? 'Ruta de refuerzos' : 'Ruta al SOS',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  route.error ??
                      (route.loading
                          ? 'Calculando ruta…'
                          : '${(route.seconds / 60).ceil()} min · ${(route.meters / 1000).toStringAsFixed(1)} km · Tiempo estimado'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: route.loading ? null : route.recalculate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar ruta'),
                ),
                TextButton(
                  onPressed: () {
                    route.clear();
                    Navigator.pop(context);
                  },
                  child: const Text('Quitar ruta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: route,
    builder: (context, _) {
      if (route.caseId == null) return const SizedBox.shrink();
      final color = route.isReinforcement
          ? const Color(0xffe97b14)
          : const Color(0xff1769ce);
      return Semantics(
        button: true,
        label: 'Detalles de la ruta',
        child: InkWell(
          onTap: () => details(context),
          borderRadius: BorderRadius.circular(13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .18),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: route.loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        route.isReinforcement
                            ? Icons.local_police
                            : Icons.directions_car,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  route.loading
                      ? 'Calculando…'
                      : route.error != null
                      ? 'Ruta pendiente'
                      : '${(route.seconds / 60).ceil()} min · ${(route.meters / 1000).toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
