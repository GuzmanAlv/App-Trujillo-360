/// No representa autenticación ni autorización de producción.
enum DemoProfile {
  neighbor1('neighbor-1', 'Vecino 1'),
  neighbor2('neighbor-2', 'Vecino 2'),
  neighbor3('neighbor-3', 'Vecino 3'),
  neighbor4('neighbor-4', 'Vecino 4'),
  administrator('demo-admin', 'Administrador de prueba');

  const DemoProfile(this.id, this.label);
  final String id, label;
  bool get isAdmin => this == administrator;
}
