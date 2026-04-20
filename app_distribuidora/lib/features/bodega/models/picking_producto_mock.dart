/// Línea de picking (mock). Listo para mapear desde API sin cambiar la UI.
class PickingProductoMock {
  const PickingProductoMock({
    required this.id,
    required this.camionId,
    required this.tipoProducto,
    required this.nombreProducto,
    required this.variante,
    required this.cxc,
    required this.codigoBarras,
    required this.unidadesObjetivo,
    required this.cajasObjetivo,
    this.cargaRealCajas = 0,
    this.codigoValidado = false,
    this.hayErrorCodigo = false,
  });

  final String id;
  final String camionId;
  final String tipoProducto;
  final String nombreProducto;
  final String variante;
  /// Cantidad por caja (unidades).
  final int cxc;
  final String codigoBarras;
  final int unidadesObjetivo;
  final int cajasObjetivo;
  final int cargaRealCajas;
  final bool codigoValidado;
  final bool hayErrorCodigo;

  bool get esPendienteValidacion => !codigoValidado && !hayErrorCodigo;
  bool get tieneErrorCodigo => hayErrorCodigo;
  bool get cargaCompleta => cargaRealCajas >= cajasObjetivo && cajasObjetivo > 0;
  bool get pickingLineaCompleta => codigoValidado && cargaCompleta;

  int get cajasFaltantes => (cajasObjetivo - cargaRealCajas).clamp(0, cajasObjetivo);

  bool coincideBusqueda(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombreProducto.toLowerCase().contains(q) ||
        variante.toLowerCase().contains(q);
  }

  PickingProductoMock copyWith({
    int? cargaRealCajas,
    bool? codigoValidado,
    bool? hayErrorCodigo,
  }) {
    return PickingProductoMock(
      id: id,
      camionId: camionId,
      tipoProducto: tipoProducto,
      nombreProducto: nombreProducto,
      variante: variante,
      cxc: cxc,
      codigoBarras: codigoBarras,
      unidadesObjetivo: unidadesObjetivo,
      cajasObjetivo: cajasObjetivo,
      cargaRealCajas: cargaRealCajas ?? this.cargaRealCajas,
      codigoValidado: codigoValidado ?? this.codigoValidado,
      hayErrorCodigo: hayErrorCodigo ?? this.hayErrorCodigo,
    );
  }
}
