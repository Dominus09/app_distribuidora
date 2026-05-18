import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/field_log.dart';
import 'outbox_item_type.dart';

/// Registro en cola offline (heartbeats, GPS, respaldo de sync).
class OutboxRow {
  OutboxRow({
    required this.id,
    required this.itemType,
    required this.payloadJson,
    required this.createdAt,
    required this.retryCount,
    this.nextRetryAt,
    this.synced = false,
    this.syncConfirmedAt,
    this.idempotencyKey,
  });

  final int id;
  final OutboxItemType itemType;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextRetryAt;
  final bool synced;
  final DateTime? syncConfirmedAt;
  final String? idempotencyKey;

  Map<String, dynamic> get payload {
    try {
      final d = jsonDecode(payloadJson);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {};
  }
}

/// Punto GPS almacenado para tracking de km recorridos.
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

/// SQLite: cola outbox + puntos GPS + IDs de acción ya confirmados.
class OutboxDatabase {
  OutboxDatabase._();
  static final OutboxDatabase instance = OutboxDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'operational_telemetry.db');
    fieldLog('OutboxDB', 'abriendo $path');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            next_retry_at TEXT,
            synced INTEGER NOT NULL DEFAULT 0,
            sync_confirmed_at TEXT,
            idempotency_key TEXT UNIQUE
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_outbox_pending ON outbox(synced, next_retry_at)
        ''');
        await db.execute('''
          CREATE TABLE gps_track_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vendedor_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL,
            captured_at TEXT NOT NULL,
            uploaded INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_gps_vendedor_time ON gps_track_points(vendedor_id, captured_at)
        ''');
        await db.execute('''
          CREATE TABLE processed_action_ids (
            action_id TEXT PRIMARY KEY,
            confirmed_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE telemetry_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> enqueue({
    required OutboxItemType type,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      return await db.insert('outbox', {
        'item_type': type.value,
        'payload': jsonEncode(payload),
        'created_at': now,
        'retry_count': 0,
        'synced': 0,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      });
    } on DatabaseException catch (e) {
      if (idempotencyKey != null && e.isUniqueConstraintError()) {
        fieldLog('OutboxDB', 'duplicado idempotency=$idempotencyKey');
        return -1;
      }
      rethrow;
    }
  }

  Future<List<OutboxRow>> pendingItems({int limit = 50}) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'outbox',
      where: 'synced = 0 AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: [now],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_rowFromMap).toList();
  }

  Future<int> pendingCount() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM outbox WHERE synced = 0',
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> markSynced(int id, {DateTime? confirmedAt}) async {
    final db = await database;
    await db.update(
      'outbox',
      {
        'synced': 1,
        'sync_confirmed_at':
            (confirmedAt ?? DateTime.now()).toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> scheduleRetry(
    int id,
    int retryCount,
    DateTime nextRetryAt,
  ) async {
    final db = await database;
    await db.update(
      'outbox',
      {
        'retry_count': retryCount,
        'next_retry_at': nextRetryAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> purgeSyncedOlderThan(Duration maxAge) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(maxAge).toUtc().toIso8601String();
    await db.delete(
      'outbox',
      where: 'synced = 1 AND sync_confirmed_at < ?',
      whereArgs: [cutoff],
    );
  }

  Future<int> insertGpsPoint({
    required String vendedorId,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
    double? accuracyMeters,
  }) async {
    final db = await database;
    return db.insert('gps_track_points', {
      'vendedor_id': vendedorId,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'uploaded': 0,
    });
  }

  Future<GpsTrackPoint?> lastGpsPoint(String vendedorId) async {
    final db = await database;
    final rows = await db.query(
      'gps_track_points',
      where: 'vendedor_id = ?',
      whereArgs: [vendedorId],
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
    final db = await database;
    final rows = await db.query(
      'gps_track_points',
      where: 'vendedor_id = ? AND uploaded = 0',
      whereArgs: [vendedorId],
      orderBy: 'captured_at ASC',
      limit: limit,
    );
    return rows.map(_gpsFromMap).toList();
  }

  Future<void> markGpsPointsUploaded(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE gps_track_points SET uploaded = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// Distancia total en km entre puntos consecutivos del día.
  Future<double> kmRecorridosHoy(String vendedorId) async {
    final db = await database;
    final start = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).toUtc().toIso8601String();
    final rows = await db.query(
      'gps_track_points',
      where: 'vendedor_id = ? AND captured_at >= ?',
      whereArgs: [vendedorId, start],
      orderBy: 'captured_at ASC',
    );
    if (rows.length < 2) return 0;
    var totalM = 0.0;
    for (var i = 1; i < rows.length; i++) {
      final a = rows[i - 1];
      final b = rows[i];
      totalM += _haversineM(
        a['latitude']! as double,
        a['longitude']! as double,
        b['latitude']! as double,
        b['longitude']! as double,
      );
    }
    return totalM / 1000;
  }

  Future<void> rememberProcessedAction(String actionId) async {
    final db = await database;
    await db.insert(
      'processed_action_ids',
      {
        'action_id': actionId,
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isActionProcessed(String actionId) async {
    final db = await database;
    final rows = await db.query(
      'processed_action_ids',
      where: 'action_id = ?',
      whereArgs: [actionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> loadProcessedActionIds() async {
    final db = await database;
    final rows = await db.query('processed_action_ids');
    return rows.map((r) => r['action_id']! as String).toSet();
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'telemetry_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'telemetry_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  OutboxRow _rowFromMap(Map<String, Object?> m) {
    return OutboxRow(
      id: m['id']! as int,
      itemType: OutboxItemType.fromValue(m['item_type'] as String?) ??
          OutboxItemType.heartbeat,
      payloadJson: m['payload']! as String,
      createdAt: DateTime.parse(m['created_at']! as String).toLocal(),
      retryCount: m['retry_count']! as int,
      nextRetryAt: m['next_retry_at'] != null
          ? DateTime.parse(m['next_retry_at']! as String).toLocal()
          : null,
      synced: (m['synced'] as int? ?? 0) == 1,
      syncConfirmedAt: m['sync_confirmed_at'] != null
          ? DateTime.parse(m['sync_confirmed_at']! as String).toLocal()
          : null,
      idempotencyKey: m['idempotency_key'] as String?,
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

  static double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dLat = p2 - p1;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1) *
            math.cos(p2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}
