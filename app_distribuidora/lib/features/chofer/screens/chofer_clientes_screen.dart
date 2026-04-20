import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chofer_mock_repository.dart';
import '../models/chofer_cliente.dart';
import '../models/chofer_entrega_estado.dart';
import '../utils/chofer_launchers.dart';
import '../widgets/chofer_cliente_tile.dart';
import '../widgets/chofer_incidencia_sheet.dart';
import 'chofer_detalle_cliente_screen.dart';

enum _OrdenLista { ordenRuta, distancia }

/// Lista mock: pendientes primero; toggle orden ruta / distancia mock.
class ChoferClientesScreen extends StatefulWidget {
  const ChoferClientesScreen({super.key});

  @override
  State<ChoferClientesScreen> createState() => _ChoferClientesScreenState();
}

class _ChoferClientesScreenState extends State<ChoferClientesScreen> {
  _OrdenLista _orden = _OrdenLista.ordenRuta;

  List<ChoferCliente> _listaOrdenada(ChoferMockRepository r) {
    final pend = _orden == _OrdenLista.distancia
        ? r.pendientesPorDistanciaMock()
        : r.pendientesOrdenRuta();
    int prioridadCola(ChoferCliente x) =>
        x.estado == ChoferEntregaEstado.entregado ? 0 : 1;
    final rest = r.clientes.where((c) => !c.esPendiente).toList()
      ..sort((a, b) {
        final cmp = prioridadCola(a).compareTo(prioridadCola(b));
        if (cmp != 0) return cmp;
        return a.ordenRuta.compareTo(b.ordenRuta);
      });
    return [...pend, ...rest];
  }

  void _whatsappSnack(ChoferCliente c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${c.nombreFantasia} · ${c.estado.label}'),
        action: SnackBarAction(
          label: 'WhatsApp',
          onPressed: () {
            unawaited(
              launchWhatsAppReporteEntrega(
                telefono: c.telefono,
                nombreCliente: c.nombreFantasia,
                estadoLabel: c.estado.label,
                choferNombre: ChoferMockRepository.choferNombreDisplay,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ChoferMockRepository.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes del día'),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final items = _listaOrdenada(repo);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<_OrdenLista>(
                  segments: const [
                    ButtonSegment(
                      value: _OrdenLista.ordenRuta,
                      label: Text('Orden ruta'),
                      icon: Icon(Icons.format_list_numbered, size: 18),
                    ),
                    ButtonSegment(
                      value: _OrdenLista.distancia,
                      label: Text('Distancia'),
                      icon: Icon(Icons.straighten, size: 18),
                    ),
                  ],
                  selected: {_orden},
                  onSelectionChanged: (s) =>
                      setState(() => _orden = s.first),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ChoferClienteTile(
                      cliente: c,
                      onIr: () => unawaited(
                        launchGoogleMapsDirDestino(c.lat, c.lng),
                      ),
                      onEntregado: () {
                        repo.marcarEntregado(c.id);
                        _whatsappSnack(repo.byId(c.id)!);
                      },
                      onIncidencia: () {
                        showChoferIncidenciaSheet(
                          context,
                          onConfirmar: (tipo, obs, _) {
                            repo.marcarIncidencia(c.id, tipo: tipo, observacion: obs);
                            _whatsappSnack(repo.byId(c.id)!);
                          },
                        );
                      },
                      onAbrirDetalle: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ChoferDetalleClienteScreen(clienteId: c.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
