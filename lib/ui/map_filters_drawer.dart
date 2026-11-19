import 'package:flutter/material.dart';
import 'report_style.dart';

class MapFiltersDrawer extends StatelessWidget {
  const MapFiltersDrawer({
    super.key,
    required this.categories,
    required this.selected,
    required this.historical,
    required this.hourBand,
    required this.onCategory,
    required this.onPeriod,
    required this.onHour,
    this.loading = false,
    this.error,
  });
  final List<String> categories;
  final String selected;
  final bool historical, loading;
  final int hourBand;
  final String? error;
  final ValueChanged<String> onCategory;
  final ValueChanged<bool> onPeriod;
  final ValueChanged<int> onHour;

  Widget section(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xff16826e)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xff687874)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget period(
    String title,
    String subtitle,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: active ? const Color(0xffe4f2ec) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active ? const Color(0xff16826e) : const Color(0xffe0e8e4),
          width: active ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          icon,
          color: active ? const Color(0xff087b65) : const Color(0xff65756f),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Icon(
          active ? Icons.radio_button_checked : Icons.radio_button_off,
          color: active ? const Color(0xff087b65) : const Color(0xffa5b1ac),
        ),
        onTap: onTap,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Drawer(
    width: 360,
    backgroundColor: const Color(0xfff5f8f6),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TRUJILLO 360',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontSize: 12,
                    color: Color(0xff087b65),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar filtros',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Filtros del mapa',
            style: TextStyle(
              fontSize: 26,
              letterSpacing: -.7,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Elige qué quieres ver en tu comunidad.',
            style: TextStyle(color: Color(0xff687874), fontSize: 13),
          ),
          section(
            Icons.schedule,
            'Periodo',
            'Consulta incidentes recientes o zonas históricas',
          ),
          period(
            'Recientes',
            'Incidentes de los últimos 7 días',
            Icons.update,
            !historical,
            () => onPeriod(false),
          ),
          period(
            'Historial',
            'Concentración de los últimos 90 días',
            Icons.history,
            historical,
            () => onPeriod(true),
          ),
          section(
            Icons.category_outlined,
            'Tipo de incidente',
            historical
                ? 'El historial reúne todas las categorías'
                : 'Selecciona una categoría para el mapa',
          ),
          if (!historical)
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              children: categories.map((category) {
                final style = ReportStyle.forCategory(category);
                final active = selected == category;
                final color = category == 'Todos'
                    ? const Color(0xff087b65)
                    : style.color;
                return Semantics(
                  button: true,
                  selected: active,
                  child: Material(
                    color: active ? color.withValues(alpha: .10) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: active ? color : const Color(0xffe0e8e4),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onCategory(category),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  category == 'Todos'
                                      ? Icons.grid_view_rounded
                                      : style.icon,
                                  size: 21,
                                  color: color,
                                ),
                                const Spacer(),
                                if (active)
                                  Icon(
                                    Icons.check_circle,
                                    color: color,
                                    size: 17,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              category,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: active ? color : const Color(0xff33453f),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.layers_outlined, color: Color(0xff16826e)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Todas las categorías incluidas',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            section(
              Icons.access_time_rounded,
              'Franja horaria',
              'Explora cómo cambian las zonas según la hora',
            ),
            DropdownButtonFormField<int>(
              initialValue: hourBand,
              key: ValueKey(hourBand),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xffe0e8e4)),
                ),
              ),
              items: const [
                DropdownMenuItem(value: -1, child: Text('Todas las horas')),
                DropdownMenuItem(value: 0, child: Text('Madrugada · 00–06 h')),
                DropdownMenuItem(value: 1, child: Text('Mañana · 06–12 h')),
                DropdownMenuItem(value: 2, child: Text('Tarde · 12–18 h')),
                DropdownMenuItem(value: 3, child: Text('Noche · 18–24 h')),
              ],
              onChanged: (hour) {
                if (hour != null) onHour(hour);
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Zonas aproximadas: amarillo 1–2 incidentes; rojo 3 o más. Sin color no significa seguro.',
              style: TextStyle(fontSize: 12, color: Color(0xff687874)),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff087b65),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver mapa'),
          ),
        ],
      ),
    ),
  );
}
