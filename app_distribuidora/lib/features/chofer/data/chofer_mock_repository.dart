import 'package:flutter/foundation.dart';

import '../models/chofer_cliente.dart';
import '../models/chofer_entrega_estado.dart';
import '../models/tipo_incidencia_chofer.dart';
import 'chofer_mock_seed.dart';

/// Estado global mock del módulo chofer (sin HTTP). Reemplazar por repositorio API más adelante.
class ChoferMockRepository extends ChangeNotifier {
  ChoferMockRepository._() : _clientes = buildChoferMockClientesSeed();

  static final ChoferMockRepository instance = ChoferMockRepository._();

  List<ChoferCliente> _clientes;

  static const choferNombreDisplay = 'Claudio';
  static const rutaNombreHoy = 'Quellón';

  /// Ubicación simulada del chofer (mock mapa).
  static const simLat = -43.1155;
  static const simLng = -73.6152;

  List<ChoferCliente> get clientes => List<ChoferCliente>.unmodifiable(_clientes);

  int get total => _clientes.length;

  int get completados => _clientes
      .where((c) => c.estado != ChoferEntregaEstado.pendiente)
      .length;

  double get progreso01 => total == 0 ? 0.0 : completados / total;

  List<ChoferCliente> pendientesOrdenRuta() {
    final p = _clientes.where((c) => c.esPendiente).toList();
    p.sort((a, b) => a.ordenRuta.compareTo(b.ordenRuta));
    return p;
  }

  List<ChoferCliente> pendientesPorDistanciaMock() {
    final p = _clientes.where((c) => c.esPendiente).toList();
    p.sort((a, b) => a.distanciaMetrosMock.compareTo(b.distanciaMetrosMock));
    return p;
  }

  ChoferCliente? byId(String id) {
    for (final c in _clientes) {
      if (c.id == id) return c;
    }
    return null;
  }

  ChoferCliente? masCercanoPendiente() {
    final p = pendientesPorDistanciaMock();
    return p.isEmpty ? null : p.first;
  }

  void marcarEntregado(String id) {
    final i = _clientes.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _clientes = [..._clientes]..[i] = _clientes[i].conEstadoEntregado();
    notifyListeners();
  }

  void marcarIncidencia(
    String id, {
    required TipoIncidenciaChofer tipo,
    String? observacion,
  }) {
    final i = _clientes.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _clientes = [..._clientes]
      ..[i] = _clientes[i].conIncidencia(tipo: tipo, observacion: observacion);
    notifyListeners();
  }
}
