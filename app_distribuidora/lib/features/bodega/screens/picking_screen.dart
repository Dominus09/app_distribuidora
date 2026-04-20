import 'dart:async';

import 'package:flutter/material.dart';

import '../data/bodega_mock_repository.dart';
import '../models/picking_producto_mock.dart';
import '../widgets/picking_filters.dart';
import '../widgets/picking_producto_card.dart';
import 'picking_resumen_screen.dart';

/// Picking operativo de un camión (mock).
class PickingScreen extends StatefulWidget {
  const PickingScreen({super.key, required this.camionId});

  final String camionId;

  @override
  State<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends State<PickingScreen> {
  final _repo = BodegaMockRepository.instance;
  final _busquedaCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _busqueda = '';
  String _tipo = 'Todos';
  FiltroEstadoPicking _estado = FiltroEstadoPicking.todos;
  bool _ordenPendPorTipo = true;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<PickingProductoMock> _filtrar(List<PickingProductoMock> src) {
    return src.where((p) {
      if (!p.coincideBusqueda(_busqueda)) return false;
      if (_tipo != 'Todos' && p.tipoProducto != _tipo) return false;
      switch (_estado) {
        case FiltroEstadoPicking.todos:
          return true;
        case FiltroEstadoPicking.pendientes:
          return !p.pickingLineaCompleta;
        case FiltroEstadoPicking.validados:
          return p.codigoValidado;
        case FiltroEstadoPicking.conError:
          return p.hayErrorCodigo;
      }
    }).toList();
  }

  List<PickingProductoMock> _ordenar(List<PickingProductoMock> filtrados) {
    final incompletos = filtrados.where((p) => !p.pickingLineaCompleta).toList();
    final completos = filtrados.where((p) => p.pickingLineaCompleta).toList();
    int cmpProd(PickingProductoMock a, PickingProductoMock b) {
      if (_ordenPendPorTipo) {
        final t = a.tipoProducto.compareTo(b.tipoProducto);
        if (t != 0) return t;
      }
      return a.nombreProducto.toLowerCase().compareTo(b.nombreProducto.toLowerCase());
    }

    incompletos.sort(cmpProd);
    completos.sort(cmpProd);
    return [...incompletos, ...completos];
  }

  Future<void> _dialogoEscanear(PickingProductoMock p) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.microtask(() async {
          await Future<void>.delayed(const Duration(milliseconds: 550));
          if (!ctx.mounted) return;
          Navigator.of(ctx).pop();
          if (!mounted) return;
          final v = _repo.validarCodigoProducto(
            widget.camionId,
            p.id,
            p.codigoBarras,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: v ? Colors.green.shade800 : Colors.red.shade800,
              content: Text(
                v ? 'Código correcto · ${p.nombreProducto}' : 'Código no coincide',
              ),
            ),
          );
        });
        return const AlertDialog(
          title: Text('Escanear código'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Acerca el lector al código (mock)…'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _ingresoManual(PickingProductoMock p) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ingresar código'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Código de barras',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Validar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final v = _repo.validarCodigoProducto(
        widget.camionId,
        p.id,
        ctrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: v ? Colors.green.shade800 : Colors.red.shade800,
          content: Text(v ? 'Validado · ${p.nombreProducto}' : 'Código incorrecto'),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final camion = _repo.camion(widget.camionId);
        final total = camion.productos.length;
        final hechos = _repo.contarLineasCompletas(widget.camionId);
        final lista = _ordenar(_filtrar(camion.productos));

        return Scaffold(
          appBar: AppBar(
            title: Text('Picking · ${camion.nombre}'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => PickingResumenScreen(camionId: widget.camionId),
                    ),
                  );
                },
                child: const Text('Resumen'),
              ),
            ],
          ),
          body: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Productos completados: $hechos / $total',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: total == 0 ? 0 : hechos / total,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 16),
              PickingFiltersBar(
                busquedaController: _busquedaCtrl,
                onBusquedaChanged: (v) => setState(() => _busqueda = v),
                tipoSeleccionado: _tipo,
                onTipoChanged: (t) => setState(() => _tipo = t),
                estadoFiltro: _estado,
                onEstadoFiltroChanged: (e) => setState(() => _estado = e),
                ordenPendientesPorTipo: _ordenPendPorTipo,
                onOrdenPendientesChanged: (v) => setState(() => _ordenPendPorTipo = v),
              ),
              const SizedBox(height: 16),
              for (final p in lista) ...[
                PickingProductoCard(
                  producto: p,
                  onEscanearCodigo: () => unawaited(_dialogoEscanear(p)),
                  onIngresarCodigo: () => unawaited(_ingresoManual(p)),
                  onCambiarCargaCajas: (n) {
                    _repo.setCargaRealCajas(widget.camionId, p.id, n);
                  },
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}
