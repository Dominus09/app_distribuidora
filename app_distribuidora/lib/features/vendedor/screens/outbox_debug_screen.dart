import 'package:flutter/material.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/telemetry/outbox_database.dart';
import '../../../core/telemetry/outbox_observability.dart';
import '../../../core/telemetry/timer_registry.dart';
import '../../../core/telemetry/operational_telemetry_service.dart';
import '../../../core/telemetry/outbox_item_type.dart';
import '../../../core/telemetry/telemetry_config.dart';

/// Pantalla temporal de diagnóstico de la cola offline.
class OutboxDebugScreen extends StatefulWidget {
  const OutboxDebugScreen({
    super.key,
    required this.telemetry,
    required this.vendedorId,
    this.scope,
    this.serverClientes,
    this.cacheClientes,
  });

  final OperationalTelemetryService telemetry;
  final String vendedorId;
  final OperationalScope? scope;
  final int? serverClientes;
  final int? cacheClientes;

  @override
  State<OutboxDebugScreen> createState() => _OutboxDebugScreenState();
}

class _OutboxDebugScreenState extends State<OutboxDebugScreen> {
  OutboxDiagnostics? _diag;
  bool _loading = true;
  String? _lastAction;
  int _lastFlushSent = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final d = await widget.telemetry.loadOutboxDiagnostics();
    if (!mounted) return;
    setState(() {
      _diag = d;
      _loading = false;
    });
  }

  Map<String, int> _countBySyncState(OutboxDiagnostics d) {
    final m = <String, int>{};
    for (final row in d.byTypeAndState) {
      m[row.syncState] = (m[row.syncState] ?? 0) + row.count;
    }
    return m;
  }

  int _countForType(OutboxDiagnostics d, String type) {
    return d.byTypeAndState
        .where((r) => r.itemType == type)
        .fold(0, (sum, r) => sum + r.count);
  }

  @override
  Widget build(BuildContext context) {
    final d = _diag;
    final byState = d != null ? _countBySyncState(d) : <String, int>{};
    final obs = OutboxObservability.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug outbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('Scope operacional', [
                  Text('vendedor: ${widget.vendedorId}'),
                  Text('scope: ${widget.scope ?? "—"}'),
                  if (widget.serverClientes != null)
                    Text('clientes servidor: ${widget.serverClientes}'),
                  if (widget.cacheClientes != null)
                    Text('clientes caché: ${widget.cacheClientes}'),
                  Text(
                    'GET ruta: fecha=${widget.scope?.fechaOperativa ?? "—"} '
                    '&vendedor=${widget.vendedorId}',
                  ),
                ]),
                _section('Cola (scope estricto)', [
                  Text('pending (flushable): ${d?.pendingCount ?? 0}'),
                  Text('syncing: ${byState["syncing"] ?? 0}'),
                  Text('failed: ${byState["failed"] ?? 0}'),
                  Text('synced (en DB): ${byState["synced"] ?? 0}'),
                  Text('dead_letter tabla: ${d?.deadLetterCount ?? 0}'),
                  Text(
                    'legacy sin fecha (global): ${d?.legacyNullFechaPending ?? 0}',
                    style: TextStyle(
                      color: (d?.legacyNullFechaPending ?? 0) > 0
                          ? Colors.orange
                          : null,
                    ),
                  ),
                ]),
                _section('Por tipo (todos los estados)', [
                  _typeRow('heartbeat', _countForType(d!, OutboxItemType.heartbeat.value)),
                  _typeRow('gps_track', _countForType(d, OutboxItemType.gpsTrack.value)),
                  _typeRow('visita_sync', _countForType(d, OutboxItemType.visitaSync.value)),
                  _typeRow('georef_update', _countForType(d, OutboxItemType.georefUpdate.value)),
                ]),
                _section('Timers activos', [
                  if (TimerRegistry.instance.snapshot().isEmpty)
                    const Text('Ninguno registrado')
                  else
                    ...TimerRegistry.instance.snapshot().map(
                      (t) => Text(
                        '${t.name} (${t.owner}) '
                        '${t.detail ?? ""} '
                        'desde ${t.startedAt.toIso8601String().substring(11, 19)}',
                      ),
                    ),
                ]),
                _section('Métricas sesión (enqueue/flush)', [
                  Text(
                    'enqueue total: ${obs.enqueueTotals.entries.map((e) => "${e.key}:${e.value}").join(", ")}',
                  ),
                  Text(
                    'skip: ${obs.skipTotals.entries.map((e) => "${e.key}:${e.value}").join(", ")}',
                  ),
                  Text(
                    'rate/min: ${obs.ratesPerMinuteThisWindow.entries.map((e) => "${e.key}:${e.value}").join(", ")}',
                  ),
                  if (_lastFlushSent > 0)
                    Text('último flush: $_lastFlushSent enviados'),
                  if (_lastAction != null) Text(_lastAction!),
                ]),
                _section('Últimos enqueue (log)', [
                  if (obs.recentEnqueues.isEmpty)
                    const Text('Sin eventos aún')
                  else
                    ...obs.recentEnqueues.take(15).map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${e.at.toIso8601String().substring(11, 19)} '
                          '${e.skipped ? "SKIP" : "ENQ"} '
                          '${e.type} ← ${e.source}\n'
                          '${e.endpoint != null ? "ep=${e.endpoint} " : ""}'
                          '${e.payloadSummary ?? e.skipReason ?? ""}\n'
                          '${e.stackSnippet ?? ""}',
                          style: TextStyle(
                            fontSize: 11,
                            color: e.skipped ? Colors.orange : null,
                          ),
                        ),
                      ),
                    ),
                ]),
                _section('Stuck / alto retry', [
                  if (d.stuckSamples.isEmpty)
                    const Text('Sin muestras')
                  else
                    ...d.stuckSamples.map(
                      (s) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${s.id} ${s.itemType} retry=${s.retryCount} '
                                'state=${s.syncState}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text('endpoint: ${s.endpoint ?? "—"}'),
                              Text('fecha: ${s.fechaOperativa ?? "NULL"} ruta: ${s.rutaId ?? "—"}'),
                              Text('action_id: ${s.actionId ?? "—"}'),
                              if (s.lastError != null)
                                Text(
                                  'error: ${s.lastError}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        final n = await widget.telemetry.flushOutboxBackground();
                        setState(() {
                          _lastFlushSent = n;
                          _lastAction = 'Flush manual: $n ítems';
                        });
                        await _reload();
                      },
                      child: const Text('Flush ahora'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final n = await OutboxDatabase.instance.purgeSyncedNow(
                          widget.vendedorId,
                        );
                        setState(() => _lastAction = 'Purgados synced: $n');
                        await _reload();
                      },
                      child: const Text('Purgar synced'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await OutboxDatabase.instance.resetStuckOutboxSyncing(
                          vendedorId: widget.vendedorId,
                          scope: widget.scope,
                        );
                        setState(() => _lastAction = 'Reset syncing→pending');
                        await _reload();
                      },
                      child: const Text('Reset syncing'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final n = await OutboxDatabase.instance
                            .archiveLegacyNullFechaPending(widget.vendedorId);
                        setState(
                          () => _lastAction = 'Legacy→dead_letter: $n',
                        );
                        await _reload();
                      },
                      child: const Text('Archivar legacy NULL fecha'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Dead letter tras ${TelemetryConfig.maxRetryAttempts} reintentos. '
                  'Idempotencia heartbeat: 1 clave/minuto.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _typeRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: $count'),
    );
  }
}
