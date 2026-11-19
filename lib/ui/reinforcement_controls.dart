import 'package:flutter/material.dart';
import '../services/reinforcements_store.dart';
import 'sos_status.dart';

class ReinforcementControls {
  static const orange = Color(0xffe97b14);
  static Widget icon({Color color = Colors.white}) => SizedBox(
    width: 28,
    height: 28,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 1,
          child: Container(
            width: 12,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          child: Icon(Icons.directions_car_filled, color: color, size: 27),
        ),
      ],
    ),
  );
  static Widget banner(Map<String, dynamic> row, VoidCallback onTap) =>
      Material(
        color: const Color(0xffffe5c8),
        borderRadius: BorderRadius.circular(15),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon(color: orange),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    '${row['name'] ?? 'Una patrulla'} solicita refuerzos',
                    style: const TextStyle(
                      color: Color(0xff8c4004),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: orange, size: 19),
              ],
            ),
          ),
        ),
      );
  static Future<void> showRequests(
    BuildContext context,
    ReinforcementsStore store,
    void Function(Map<String, dynamic>, bool) select,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .43,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Patrullas que necesitan apoyo',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: store.others.isEmpty
                      ? const Center(child: Text('No hay solicitudes activas.'))
                      : ListView.builder(
                          itemCount: store.others.length,
                          itemBuilder: (context, index) {
                            final row = store.others[index];
                            return ListTile(
                              leading: icon(color: orange),
                              title: Text(
                                '${row['name'] ?? 'Patrulla'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: const Text(
                                'Ver ubicación y ruta de apoyo',
                                style: TextStyle(fontSize: 12),
                              ),
                              trailing: const Icon(
                                Icons.directions,
                                color: orange,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                select(row, true);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget button(
    BuildContext context,
    ReinforcementsStore store,
    void Function(Map<String, dynamic>, bool) select,
  ) => SosSupportFrame(
    active: true,
    pulse: true,
    soft: true,
    glowColor: orange,
    margin: EdgeInsets.zero,
    child: Material(
      color: orange,
      elevation: 4,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => showRequests(context, store, select),
        child: Semantics(
          button: true,
          label: '${store.others.length} patrullas solicitan refuerzos',
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                icon(),
                Positioned(
                  top: 2,
                  right: 4,
                  child: Text(
                    '${store.others.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
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
