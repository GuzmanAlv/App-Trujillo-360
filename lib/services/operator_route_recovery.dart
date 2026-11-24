/// One restoration per assignment/login, without undoing a manual "Quitar ruta".
class OperatorRouteRecovery {
  String? _owner, _restored;
  void reset() {
    _owner = null;
    _restored = null;
  }

  String? recover(
    String owner,
    List<Map<String, dynamic>> rows,
    String? currentCase,
  ) {
    if (_owner != owner) {
      _owner = owner;
      _restored = null;
    }
    final active = rows.where(
      (r) =>
          r['can_track'] == true &&
          r['decision'] == 'confirmed' &&
          r['attention'] == 'en_route',
    );
    if (active.isEmpty) {
      _restored = null;
      return null;
    }
    final id = '${active.first['id']}';
    if (_restored == id) return null;
    _restored = id;
    return currentCase == id ? null : id;
  }
}
