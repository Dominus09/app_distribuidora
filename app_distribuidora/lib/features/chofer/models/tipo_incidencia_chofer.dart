enum TipoIncidenciaChofer {
  clienteCerrado,
  noRecibe,
  sinStock,
  otros,
}

extension TipoIncidenciaChoferUi on TipoIncidenciaChofer {
  String get label => switch (this) {
        TipoIncidenciaChofer.clienteCerrado => 'Cliente cerrado',
        TipoIncidenciaChofer.noRecibe => 'No recibe',
        TipoIncidenciaChofer.sinStock => 'Sin stock',
        TipoIncidenciaChofer.otros => 'Otros',
      };
}
