import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../session/operational_scope.dart';
import '../session/session_manager.dart';
import '../sync/outbox_sync_state.dart';
import '../sync/processed_action_record.dart';
import '../utils/field_log.dart';
import 'outbox_observability.dart';
import 'gps_km_calculator.dart';
import 'outbox_item_type.dart';

/// Registro en cola offline (heartbeats, GPS, respaldo de sync).
class OutboxRow {
  OutboxRow({
    required this.id,
    required this.vendedorId,
    required this.itemType,
    required this.payloadJson,
    required this.createdAt,
    required this.retryCount,
    this.fechaOperativa,
    this.rutaId,
    this.nextRetryAt,
    this.syncState = OutboxSyncState.pending,
    this.syncConfirmedAt,
    this.idempotencyKey,
    this.actionId,
    this.lastRetryAt,
    this.lastError,
    this.endpoint,
  });

  final int id;
  final String vendedorId;
  final OutboxItemType itemType;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final String? fechaOperativa;
  final int? rutaId;
  final DateTime? nextRetryAt;
  final OutboxSyncState syncState;
  final DateTime? syncConfirmedAt;
  final String? idempotencyKey;
  final String? actionId;
  final DateTime? lastRetryAt;
  final String? lastError;
  final String? endpoint;

  bool get synced => syncState == OutboxSyncState.synced;

  Map<String, dynamic> get payload {
    try {
      final d = jsonDecode(payloadJson);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {};
  }
}

class GpsTrackPoint {
  GpsTrackPoint({
    required this.id,
    required this.vendedorId,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
    this.uploaded = false,
  });

  final int id;
  final String vendedorId;
  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final double? accuracyMeters;
  final bool uploaded;
}

/// SQLite con aislamiento por [vendedor_id] en todas las tablas operacionales.
class OutboxDatabase {
  OutboxDatabase._();
  static final OutboxDatabase instance = OutboxDatabase._();

  static const _dbVersion = 4;
  static const _orphanVendedor = '__orphan__';

  Database? _db;

  String _requireVendedor(String? explicit) {
    final id = (explicit ?? SessionManager.instance.currentVendedorId)?.trim();
    if (id == null || id.isEmpty) {
      throw StateError('OutboxDatabase: sin vendedor_id activo');
    }
    return id;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'operational_telemetry.db');
    fieldLog('OutboxDB', 'abriendo $path v$_dbVersion');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vendedor_id TEXT NOT NULL,
        item_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        sync_confirmed_at TEXT,
        idempotency_key TEXT,
        fecha_operativa TEXT,
        ruta_id INTEGER,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        action_id TEXT,
        last_retry_at TEXT,
        last_error TEXT,
        endpoint TEXT,
        UNIQUE(vendedor_id, idempotency_key)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_outbox_vendedor_pending ON outbox(vendedor_id, sync_state, next_retry_at)',
    );
    await db.execute(
      'CREATE INDEX idx_outbox_scope ON outbox(vendedor_id, fecha_operativa, ruta_id)',
    );
    await db.execute('''
      CREATE TABLE gps_track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vendedor_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy_meters REAL,
        captured_at TEXT NOT NULL,
        uploaded INTEGER NOT NULL DEFAULT 0,
        fecha_operativa TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_gps_vendedor_time ON gps_track_points(vendedor_id, captured_at)',
    );
    await db.execute('''
      CREATE TABLE processed_actions (
        vendedor_id TEXT NOT NULL,
        fecha_operativa TEXT NOT NULL,
        ruta_id INTEGER NOT NULL,
        action_id TEXT NOT NULL,
        confirmed_at TEXT NOT NULL,
        PRIMARY KEY (vendedor_id, fecha_operativa, ruta_id, action_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE dead_letter_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vendedor_id TEXT NOT NULL,
        fecha_operativa TEXT,
        ruta_id INTEGER,
        action_id TEXT,
        item_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        endpoint TEXT,
        last_error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        dead_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_dead_letter_vendedor ON dead_letter_queue(vendedor_id, fecha_operativa)',
    );
    await db.execute('''
      CREATE TABLE telemetry_meta (
        vendedor_id TEXT NOT NULL,
        meta_key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY (vendedor_id, meta_key)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      fieldLog('OutboxDB', 'migración v1 → v2 (vendedor_id)');
      await db.execute('''
        CREATE TABLE outbox_v2 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          vendedor_id TEXT NOT NULL,
          item_type TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0,
          next_retry_at TEXT,
          synced INTEGER NOT NULL DEFAULT 0,
          sync_confirmed_at TEXT,
          idempotency_key TEXT,
          UNIQUE(vendedor_id, idempotency_key)
        )
      ''');
      final oldRows = await db.query('outbox');
      for (final row in oldRows) {
        var vid = _orphanVendedor;
        try {
          final payload = jsonDecode(row['payload']! as String);
          if (payload is Map) {
            final fromJson = payload['vendedor_id']?.toString().trim();
            if (fromJson != null && fromJson.isNotEmpty) vid = fromJson;
          }
        } catch (_) {}
        if (vid == _orphanVendedor) continue;
        await db.insert('outbox_v2', {
          'vendedor_id': vid,
          'item_type': row['item_type'],
          'payload': row['payload'],
          'created_at': row['created_at'],
          'retry_count': row['retry_count'],
          'next_retry_at': row['next_retry_at'],
          'synced': row['synced'],
          'sync_confirmed_at': row['sync_confirmed_at'],
          'idempotency_key': row['idempotency_key'],
        });
      }
      await db.execute('DROP TABLE outbox');
      await db.execute('ALTER TABLE outbox_v2 RENAME TO outbox');
      await db.execute(
        'CREATE INDEX idx_outbox_vendedor_pending ON outbox(vendedor_id, synced, next_retry_at)',
      );
      await db.execute('''
        CREATE TABLE processed_action_ids_v2 (
          vendedor_id TEXT NOT NULL,
          action_id TEXT NOT NULL,
          confirmed_at TEXT NOT NULL,
          PRIMARY KEY (vendedor_id, action_id)
        )
      ''');
      final active = SessionManager.instance.currentVendedorId?.trim();
      final legacyVid = (active != null && active.isNotEmpty)
          ? active
          : _orphanVendedor;
      await db.execute('''
        INSERT INTO processed_action_ids_v2 (vendedor_id, action_id, confirmed_at)
        SELECT ?, action_id, confirmed_at FROM processed_action_ids
      ''', [legacyVid]);
      await db.execute('DROP TABLE processed_action_ids');
      await db.execute(
        'ALTER TABLE processed_action_ids_v2 RENAME TO processed_action_ids',
      );
      await db.execute('''
        CREATE TABLE telemetry_meta_v2 (
          vendedor_id TEXT NOT NULL,
          meta_key TEXT NOT NULL,
          value TEXT NOT NULL,
          PRIMARY KEY (vendedor_id, meta_key)
        )
      ''');
      await db.execute('''
        INSERT INTO telemetry_meta_v2 (vendedor_id, meta_key, value)
        SELECT ?, key, value FROM telemetry_meta
      ''', [legacyVid]);
      await db.execute('DROP TABLE telemetry_meta');
      await db.execute(
        'ALTER TABLE telemetry_meta_v2 RENAME TO telemetry_meta',
      );
    }
    if (oldVersion < 3) {
      fieldLog('OutboxDB', 'migración v2 → v3 (fecha_operativa, ruta_id)');
      await db.execute(
        'ALTER TABLE outbox ADD COLUMN fecha_operativa TEXT',
      );
      await db.execute('ALTER TABLE outbox ADD COLUMN ruta_id INTEGER');
      await db.execute(
        'ALTER TABLE gps_track_points ADD COLUMN fecha_operativa TEXT',
      );
    }
    if (oldVersion < 4) {
      fieldLog('OutboxDB', 'migración v3 → v4 (sync_state, dead_letter, processed_actions)');
      await db.execute(
        "ALTER TABLE outbox ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'pending'",
      );
      await db.execute('ALTER TABLE outbox ADD COLUMN action_id TEXT');
      await db.execute('ALTER TABLE outbox ADD COLUMN last_retry_at TEXT');
      await db.execute('ALTER TABLE outbox ADD COLUMN last_error TEXT');
      await db.execute('ALTER TABLE outbox ADD COLUMN endpoint TEXT');
      await db.execute('''
        UPDATE outbox SET sync_state = CASE
          WHEN synced = 1 THEN 'synced'
          WHEN retry_count >= 12 THEN 'dead_letter'
          ELSE 'pending'
        END
      ''');
      await db.execute('''
        CREATE TABLE processed_actions (
          vendedor_id TEXT NOT NULL,
          fecha_operativa TEXT NOT NULL,
          ruta_id INTEGER NOT NULL,
          action_id TEXT NOT NULL,
          confirmed_at TEXT NOT NULL,
          PRIMARY KEY (vendedor_id, fecha_operativa, ruta_id, action_id)
        )
      ''');
      final legacyProcessed = await db.query('processed_action_ids');
      for (final row in legacyProcessed) {
        await db.insert(
          'processed_actions',
          {
            'vendedor_id': row['vendedor_id'],
            'fecha_operativa': '',
            'ruta_id': 0,
            'action_id': row['action_id'],
            'confirmed_at': row['confirmed_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await db.execute('DROP TABLE IF EXISTS processed_action_ids');
      await db.execute('''
        CREATE TABLE dead_letter_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          vendedor_id TEXT NOT NULL,
          fecha_operativa TEXT,
          ruta_id INTEGER,
          action_id TEXT,
          item_type TEXT NOT NULL,
          payload TEXT NOT NULL,
          endpoint TEXT,
          last_error TEXT,
          retry_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          dead_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_dead_letter_vendedor ON dead_letter_queue(vendedor_id, fecha_operativa)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outbox_scope ON outbox(vendedor_id, fecha_operativa, ruta_id)',
      );
    }
  }

  /// Filtro estricto por scope: con fecha activa NO incluye filas legacy sin fecha.
  void _appendScopeFilter(
    StringBuffer where,
    List<Object> args, {
    OperationalScope? scope,
    bool visitaRutaFilter = true,
  }) {
    final fecha = scope?.fechaOperativa;
    final rutaId = scope?.rutaId;
    if (fecha != null && fecha.isNotEmpty) {
      where.write(' AND fecha_operativa = ?');
      args.add(fecha);
    }
    if (visitaRutaFilter && rutaId != null && rutaId >= 1) {
      where.write(
        " AND (item_type != '${OutboxItemType.visitaSync.value}' OR ruta_id = ?)",
      );
      args.add(rutaId);
    }
  }

  Future<int> enqueue({
    required String vendedorId,
    required OutboxItemType type,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? fechaOperativa,
    int? rutaId,
    String? actionId,
    String? endpoint,
    String? source,
    String? stackSnippet,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final body = Map<String, dynamic>.from(payload)
      ..['vendedor_id'] = vid;
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    var insertId = -1;
    try {
      insertId = await db.insert('outbox', {
        'vendedor_id': vid,
        'item_type': type.value,
        'payload': jsonEncode(body),
        'created_at': now,
        'retry_count': 0,
        'synced': 0,
        'sync_state': OutboxSyncState.pending.dbValue,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        if (fechaOperativa != null) 'fecha_operativa': fechaOperativa,
        if (rutaId != null && rutaId >= 1) 'ruta_id': rutaId,
        if (actionId != null && actionId.isNotEmpty) 'action_id': actionId,
        if (endpoint != null) 'endpoint': endpoint,
      });
    } on DatabaseException catch (e) {
      if (idempotencyKey != null && e.isUniqueConstraintError()) {
        await db.update(
          'outbox',
          {
            'payload': jsonEncode(body),
            'sync_state': OutboxSyncState.pending.dbValue,
            'synced': 0,
          },
          where: 'vendedor_id = ? AND idempotency_key = ?',
          whereArgs: [vid, idempotencyKey],
        );
        fieldLog('OutboxDB', 'idempotency UPDATE v=$vid key=$idempotencyKey');
        insertId = -1;
      } else {
        rethrow;
      }
    }
    final pending = await pendingCount(
      vendedorId: vid,
      scope: fechaOperativa != null && rutaId != null
          ? OperationalScope(
              vendedorId: vid,
              fechaOperativa: fechaOperativa,
              rutaId: rutaId,
            )
          : fechaOperativa != null
              ? OperationalScope(
                  vendedorId: vid,
                  fechaOperativa: fechaOperativa,
                )
              : null,
    );
    OutboxObservability.instance.recordEnqueue(
      type: type,
      source: source ?? 'unknown',
      endpoint: endpoint,
      idempotencyKey: idempotencyKey,
      scope: fechaOperativa != null
          ? OperationalScope(
              vendedorId: vid,
              fechaOperativa: fechaOperativa,
              rutaId: rutaId,
            )
          : null,
      queueSizeAfter: pending,
      insertId: insertId,
      payloadSummary: OutboxObservability.summarizePayload(body),
      stackSnippet: stackSnippet,
    );
    return insertId;
  }

  Future<List<OutboxRow>> pendingItems({
    required String vendedorId,
    OperationalScope? scope,
    int limit = 50,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final where = StringBuffer(
      "vendedor_id = ? AND sync_state IN ('pending', 'failed', 'syncing') "
      'AND (next_retry_at IS NULL OR next_retry_at <= ?)',
    );
    final args = <Object>[vid, now];
    _appendScopeFilter(where, args, scope: scope, visitaRutaFilter: true);
    final rows = await db.query(
      'outbox',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_rowFromMap).toList();
  }

  Future<int> pendingCount({
    required String vendedorId,
    OperationalScope? scope,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final where = StringBuffer(
      "vendedor_id = ? AND sync_state IN ('pending', 'failed', 'syncing')",
    );
    final args = <Object>[vid];
    _appendScopeFilter(where, args, scope: scope, visitaRutaFilter: true);
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM outbox WHERE ${where.toString()}',
      args,
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Resumen diagnóstico: conteos por tipo y estado (scope estricto).
  Future<OutboxDiagnostics> loadDiagnostics({
    required String vendedorId,
    OperationalScope? scope,
    int stuckSampleLimit = 15,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;

    String scopeSql = '';
    final scopeArgs = <Object>[vid];
    if (scope?.fechaOperativa != null && scope!.fechaOperativa.isNotEmpty) {
      scopeSql = ' AND fecha_operativa = ?';
      scopeArgs.add(scope.fechaOperativa);
      if (scope.rutaId != null && scope.rutaId! >= 1) {
        scopeSql +=
            " AND (item_type != '${OutboxItemType.visitaSync.value}' OR ruta_id = ?)";
        scopeArgs.add(scope.rutaId!);
      }
    }

    final byTypeRows = await db.rawQuery('''
      SELECT item_type, sync_state, COUNT(*) AS c, MAX(retry_count) AS max_retry
      FROM outbox
      WHERE vendedor_id = ?$scopeSql
      GROUP BY item_type, sync_state
      ORDER BY c DESC
    ''', scopeArgs);

    final pending = await pendingCount(vendedorId: vid, scope: scope);

    final stuckRows = await db.rawQuery('''
      SELECT id, item_type, endpoint, retry_count, sync_state, last_error,
             fecha_operativa, ruta_id, action_id, created_at
      FROM outbox
      WHERE vendedor_id = ?$scopeSql
        AND sync_state IN ('pending', 'failed', 'syncing')
      ORDER BY retry_count DESC, created_at ASC
      LIMIT $stuckSampleLimit
    ''', scopeArgs);

    final legacyNullFecha = scope?.fechaOperativa != null
        ? Sqflite.firstIntValue(
              await db.rawQuery(
                '''SELECT COUNT(*) AS c FROM outbox
                   WHERE vendedor_id = ? AND fecha_operativa IS NULL
                     AND sync_state IN ('pending', 'failed', 'syncing')''',
                [vid],
              ),
            ) ??
            0
        : 0;

    final dead = await deadLetterCount(vendedorId: vid, scope: scope);

    return OutboxDiagnostics(
      pendingCount: pending,
      deadLetterCount: dead,
      legacyNullFechaPending: legacyNullFecha,
      byTypeAndState: byTypeRows
          .map(
            (r) => OutboxTypeStateCount(
              itemType: r['item_type']! as String,
              syncState: r['sync_state'] as String? ?? 'pending',
              count: r['c']! as int,
              maxRetry: r['max_retry'] as int? ?? 0,
            ),
          )
          .toList(),
      stuckSamples: stuckRows.map(OutboxStuckSample.fromRow).toList(),
    );
  }

  /// Elimina filas ya sincronizadas (no esperar 7 días).
  Future<int> purgeSyncedNow(String vendedorId) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    return db.delete(
      'outbox',
      where: "vendedor_id = ? AND sync_state = 'synced'",
      whereArgs: [vid],
    );
  }

  Future<void> markSynced(
    int id, {
    required String vendedorId,
    DateTime? confirmedAt,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final at = (confirmedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.update(
      'outbox',
      {
        'synced': 1,
        'sync_state': OutboxSyncState.synced.dbValue,
        'sync_confirmed_at': at,
        'last_error': null,
      },
      where: 'id = ? AND vendedor_id = ?',
      whereArgs: [id, vid],
    );
  }

  Future<void> markSyncing(int id, {required String vendedorId}) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    await db.update(
      'outbox',
      {'sync_state': OutboxSyncState.syncing.dbValue},
      where: 'id = ? AND vendedor_id = ?',
      whereArgs: [id, vid],
    );
  }

  Future<void> scheduleRetry(
    int id,
    String vendedorId,
    int retryCount,
    DateTime nextRetryAt, {
    String? lastError,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    await db.update(
      'outbox',
      {
        'retry_count': retryCount,
        'next_retry_at': nextRetryAt.toUtc().toIso8601String(),
        'last_retry_at': DateTime.now().toUtc().toIso8601String(),
        'sync_state': OutboxSyncState.failed.dbValue,
        if (lastError != null) 'last_error': lastError,
      },
      where: 'id = ? AND vendedor_id = ?',
      whereArgs: [id, vid],
    );
  }

  Future<void> resetStuckOutboxSyncing({
    required String vendedorId,
    OperationalScope? scope,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final where = StringBuffer(
      "vendedor_id = ? AND sync_state = 'syncing'",
    );
    final args = <Object>[vid];
    _appendScopeFilter(where, args, scope: scope, visitaRutaFilter: false);
    await db.update(
      'outbox',
      {'sync_state': OutboxSyncState.pending.dbValue},
      where: where.toString(),
      whereArgs: args,
    );
  }

  /// Mueve a dead letter ítems legacy sin `fecha_operativa` (fuera de scope).
  Future<int> archiveLegacyNullFechaPending(String vendedorId) async {
    final vid = _requireVendedor(vendedorId);
    final rows = await pendingItems(
      vendedorId: vid,
      scope: null,
      limit: 500,
    );
    var moved = 0;
    for (final row in rows) {
      if (row.fechaOperativa != null && row.fechaOperativa!.isNotEmpty) {
        continue;
      }
      await moveToDeadLetter(
        row,
        endpoint: row.endpoint ?? row.itemType.value,
        lastError: 'legacy sin fecha_operativa',
      );
      moved++;
    }
    return moved;
  }

  Future<void> moveToDeadLetter(
    OutboxRow row, {
    required String endpoint,
    required String lastError,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('dead_letter_queue', {
      'vendedor_id': row.vendedorId,
      'fecha_operativa': row.fechaOperativa,
      'ruta_id': row.rutaId,
      'action_id': row.actionId,
      'item_type': row.itemType.value,
      'payload': row.payloadJson,
      'endpoint': endpoint,
      'last_error': lastError,
      'retry_count': row.retryCount,
      'created_at': row.createdAt.toUtc().toIso8601String(),
      'dead_at': now,
    });
    await db.update(
      'outbox',
      {
        'sync_state': OutboxSyncState.deadLetter.dbValue,
        'synced': 1,
        'last_error': lastError,
        'endpoint': endpoint,
      },
      where: 'id = ? AND vendedor_id = ?',
      whereArgs: [row.id, row.vendedorId],
    );
  }

  Future<int> deadLetterCount({
    required String vendedorId,
    OperationalScope? scope,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final fecha = scope?.fechaOperativa;
    if (fecha != null && fecha.isNotEmpty) {
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM dead_letter_queue WHERE vendedor_id = ? '
        'AND (fecha_operativa IS NULL OR fecha_operativa = ?)',
        [vid, fecha],
      );
      return Sqflite.firstIntValue(r) ?? 0;
    }
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM dead_letter_queue WHERE vendedor_id = ?',
      [vid],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> purgeSyncedOlderThan(
    String vendedorId,
    Duration maxAge,
  ) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final cutoff =
        DateTime.now().subtract(maxAge).toUtc().toIso8601String();
    await db.delete(
      'outbox',
      where: 'vendedor_id = ? AND synced = 1 AND sync_confirmed_at < ?',
      whereArgs: [vid, cutoff],
    );
  }

  Future<int> insertGpsPoint({
    required String vendedorId,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
    double? accuracyMeters,
    String? fechaOperativa,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    return db.insert('gps_track_points', {
      'vendedor_id': vid,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'uploaded': 0,
      if (fechaOperativa != null) 'fecha_operativa': fechaOperativa,
    });
  }

  Future<GpsTrackPoint?> lastGpsPoint(String vendedorId) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final rows = await db.query(
      'gps_track_points',
      where: 'vendedor_id = ?',
      whereArgs: [vid],
      orderBy: 'captured_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _gpsFromMap(rows.first);
  }

  Future<List<GpsTrackPoint>> unuploadedGpsPoints({
    required String vendedorId,
    int limit = 100,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final rows = await db.query(
      'gps_track_points',
      where: 'vendedor_id = ? AND uploaded = 0',
      whereArgs: [vid],
      orderBy: 'captured_at ASC',
      limit: limit,
    );
    return rows.map(_gpsFromMap).toList();
  }

  Future<void> markGpsPointsUploaded(
    List<int> ids, {
    required String vendedorId,
  }) async {
    if (ids.isEmpty) return;
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE gps_track_points SET uploaded = 1 WHERE vendedor_id = ? AND id IN ($placeholders)',
      [vid, ...ids],
    );
  }

  Future<double> kmRecorridosHoy(
    String vendedorId, {
    String? fechaOperativa,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final fecha = fechaOperativa ?? OperationalScope.fechaFromDateTime(DateTime.now());
    final parsed = OperationalScope.parseFechaOperativa(fecha) ?? DateTime.now();
    final start = DateTime(parsed.year, parsed.month, parsed.day)
        .toUtc()
        .toIso8601String();
    final rows = await db.query(
      'gps_track_points',
      columns: ['latitude', 'longitude'],
      where:
          'vendedor_id = ? AND captured_at >= ? AND (fecha_operativa IS NULL OR fecha_operativa = ?)',
      whereArgs: [vid, start, fecha],
      orderBy: 'captured_at ASC',
    );
    if (rows.length < 2) return 0;

    final points = rows
        .map(
          (r) => <double>[
            r['latitude']! as double,
            r['longitude']! as double,
          ],
        )
        .toList(growable: false);

    if (points.length > 80) {
      return compute(computeKmFromTrackPoints, points);
    }
    return computeKmFromTrackPoints(points);
  }

  Future<void> rememberProcessedAction(ProcessedActionRecord record) async {
    final db = await database;
    await db.insert(
      'processed_actions',
      record.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isActionProcessed(ProcessedActionRecord record) async {
    final db = await database;
    final rows = await db.query(
      'processed_actions',
      where:
          'vendedor_id = ? AND fecha_operativa = ? AND ruta_id = ? AND action_id = ?',
      whereArgs: [
        record.vendedorId,
        record.fechaOperativa,
        record.rutaId,
        record.actionId,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> loadProcessedActionKeys({
    required String vendedorId,
    String? fechaOperativa,
    int? rutaId,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final where = StringBuffer('vendedor_id = ?');
    final args = <Object>[vid];
    if (fechaOperativa != null && fechaOperativa.isNotEmpty) {
      where.write(' AND fecha_operativa = ?');
      args.add(fechaOperativa);
    }
    if (rutaId != null && rutaId >= 1) {
      where.write(' AND ruta_id = ?');
      args.add(rutaId);
    }
    final rows = await db.query(
      'processed_actions',
      where: where.toString(),
      whereArgs: args,
    );
    return rows
        .map(
          (r) =>
              '${r['vendedor_id']}|${r['fecha_operativa']}|${r['ruta_id']}|${r['action_id']}',
        )
        .toSet();
  }

  @Deprecated('Use loadProcessedActionKeys')
  Future<Set<String>> loadProcessedActionIds(String vendedorId) async {
    return loadProcessedActionKeys(vendedorId: vendedorId);
  }

  Future<void> setMeta({
    required String vendedorId,
    required String key,
    required String value,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    await db.insert(
      'telemetry_meta',
      {'vendedor_id': vid, 'meta_key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta({
    required String vendedorId,
    required String key,
  }) async {
    final vid = _requireVendedor(vendedorId);
    final db = await database;
    final rows = await db.query(
      'telemetry_meta',
      where: 'vendedor_id = ? AND meta_key = ?',
      whereArgs: [vid, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  OutboxRow _rowFromMap(Map<String, Object?> m) {
    return OutboxRow(
      id: m['id']! as int,
      vendedorId: m['vendedor_id']! as String,
      itemType: OutboxItemType.fromValue(m['item_type'] as String?) ??
          OutboxItemType.heartbeat,
      payloadJson: m['payload']! as String,
      createdAt: DateTime.parse(m['created_at']! as String).toLocal(),
      retryCount: m['retry_count']! as int,
      fechaOperativa: m['fecha_operativa'] as String?,
      rutaId: m['ruta_id'] as int?,
      nextRetryAt: m['next_retry_at'] != null
          ? DateTime.parse(m['next_retry_at']! as String).toLocal()
          : null,
      syncState: m['sync_state'] != null
          ? OutboxSyncStateCodec.fromDb(m['sync_state'] as String?)
          : ((m['synced'] as int? ?? 0) == 1
              ? OutboxSyncState.synced
              : OutboxSyncState.pending),
      syncConfirmedAt: m['sync_confirmed_at'] != null
          ? DateTime.parse(m['sync_confirmed_at']! as String).toLocal()
          : null,
      idempotencyKey: m['idempotency_key'] as String?,
      actionId: m['action_id'] as String?,
      lastRetryAt: m['last_retry_at'] != null
          ? DateTime.parse(m['last_retry_at']! as String).toLocal()
          : null,
      lastError: m['last_error'] as String?,
      endpoint: m['endpoint'] as String?,
    );
  }

  GpsTrackPoint _gpsFromMap(Map<String, Object?> m) {
    return GpsTrackPoint(
      id: m['id']! as int,
      vendedorId: m['vendedor_id']! as String,
      latitude: m['latitude']! as double,
      longitude: m['longitude']! as double,
      capturedAt: DateTime.parse(m['captured_at']! as String).toLocal(),
      accuracyMeters: m['accuracy_meters'] as double?,
      uploaded: (m['uploaded'] as int? ?? 0) == 1,
    );
  }
}

/// Resumen de diagnóstico de la cola outbox.
class OutboxDiagnostics {
  const OutboxDiagnostics({
    required this.pendingCount,
    required this.deadLetterCount,
    required this.legacyNullFechaPending,
    required this.byTypeAndState,
    required this.stuckSamples,
  });

  final int pendingCount;
  final int deadLetterCount;
  final int legacyNullFechaPending;
  final List<OutboxTypeStateCount> byTypeAndState;
  final List<OutboxStuckSample> stuckSamples;

  Map<String, int> get countByItemType {
    final m = <String, int>{};
    for (final row in byTypeAndState) {
      m[row.itemType] = (m[row.itemType] ?? 0) + row.count;
    }
    return m;
  }

  /// Pendientes que afectan operación de visitas/georef (excluye telemetría secundaria).
  int get pendingOperacionalCount {
    const secondary = OutboxDiagnostics.tiposTelemetria;
    const activeStates = OutboxDiagnostics.estadosActivosCola;
    return byTypeAndState
        .where(
          (r) =>
              !secondary.contains(r.itemType) &&
              activeStates.contains(r.syncState),
        )
        .fold(0, (sum, r) => sum + r.count);
  }

  /// Heartbeat y gps_track pendientes de envío (no afectan estado «En línea»).
  int get pendingTelemetriaCount {
    const activeStates = OutboxDiagnostics.estadosActivosCola;
    return byTypeAndState
        .where(
          (r) =>
              OutboxDiagnostics.tiposTelemetria.contains(r.itemType) &&
              activeStates.contains(r.syncState),
        )
        .fold(0, (sum, r) => sum + r.count);
  }

  static const tiposTelemetria = {'heartbeat', 'gps_track'};
  static const estadosActivosCola = {'pending', 'failed', 'syncing'};
}

class OutboxTypeStateCount {
  const OutboxTypeStateCount({
    required this.itemType,
    required this.syncState,
    required this.count,
    required this.maxRetry,
  });

  final String itemType;
  final String syncState;
  final int count;
  final int maxRetry;
}

class OutboxStuckSample {
  const OutboxStuckSample({
    required this.id,
    required this.itemType,
    required this.endpoint,
    required this.retryCount,
    required this.syncState,
    required this.lastError,
    required this.fechaOperativa,
    required this.rutaId,
    required this.actionId,
    required this.createdAt,
  });

  final int id;
  final String itemType;
  final String? endpoint;
  final int retryCount;
  final String syncState;
  final String? lastError;
  final String? fechaOperativa;
  final int? rutaId;
  final String? actionId;
  final DateTime createdAt;

  factory OutboxStuckSample.fromRow(Map<String, Object?> r) {
    return OutboxStuckSample(
      id: r['id']! as int,
      itemType: r['item_type']! as String,
      endpoint: r['endpoint'] as String?,
      retryCount: r['retry_count']! as int,
      syncState: r['sync_state'] as String? ?? 'pending',
      lastError: r['last_error'] as String?,
      fechaOperativa: r['fecha_operativa'] as String?,
      rutaId: r['ruta_id'] as int?,
      actionId: r['action_id'] as String?,
      createdAt: DateTime.parse(r['created_at']! as String).toLocal(),
    );
  }
}
