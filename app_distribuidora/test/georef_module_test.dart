import 'package:flutter_test/flutter_test.dart';

import 'package:app_distribuidora/core/coordenadas/coordenadas_efectivas.dart';
import 'package:app_distribuidora/core/telemetry/outbox_database.dart';
import 'package:app_distribuidora/features/vendedor/models/georef_estado.dart';
import 'package:app_distribuidora/features/vendedor/models/georef_origen.dart';
import 'package:app_distribuidora/features/vendedor/models/georef_pendiente.dart';
import 'package:app_distribuidora/features/vendedor/models/visita.dart';
import 'package:app_distribuidora/features/vendedor/services/address_geocoder.dart';
import 'package:app_distribuidora/features/vendedor/services/georef_local_store.dart';

void main() {
  group('CoordenadasEfectivas', () {
    test('prioriza lat_efectiva sobre lat réplica BSALE', () {
      final lat = CoordenadasEfectivas.latFromJson({
        'lat_efectiva': -33.45,
        'lat': -33.0,
      });
      expect(lat, -33.45);
    });

    test('usa lat_operacional si no hay efectiva explícita', () {
      final lat = CoordenadasEfectivas.latFromJson({
        'lat_operacional': -33.5,
        'lat': -33.0,
      });
      expect(lat, -33.5);
    });
  });

  group('GeorefLocalStore.mergeServidorConLocal', () {
    test('conserva captura local pendiente ante sync_rutero del servidor', () {
      const servidor = GeorefPendiente(
        rutaId: 10,
        clienteId: 'c1',
        clienteNombre: 'Cliente',
        direccion: 'Dir',
        latEfectiva: 0,
        lonEfectiva: 0,
        georefEstado: GeorefEstado.pendiente,
      );
      const local = GeorefPendiente(
        rutaId: 10,
        clienteId: 'c1',
        clienteNombre: 'Cliente',
        direccion: 'Dir',
        latEfectiva: -33.1,
        lonEfectiva: -70.6,
        georefEstado: GeorefEstado.capturada,
        localSyncStatus: GeorefSyncStatus.pendingSync,
        localActionId: 'uuid-1',
      );
      final merged = GeorefLocalStore.mergeServidorConLocal(
        servidor: [servidor],
        local: [local],
      );
      expect(merged.single.latEfectiva, -33.1);
      expect(merged.single.localSyncStatus, GeorefSyncStatus.pendingSync);
    });
  });

  group('Visita coordenadas efectivas', () {
    test('fromJson usa cadena COALESCE del backend', () {
      final v = Visita.fromJson({
        'id': '1',
        'cliente_nombre': 'A',
        'direccion': 'D',
        'orden_ruta': 1,
        'estado': 'pendiente',
        'lat_efectiva': -33.44,
        'lon_efectiva': -70.55,
        'lat': -33.0,
        'lon': -70.0,
      });
      expect(v.latEfectiva, -33.44);
      expect(v.lonEfectiva, -70.55);
    });

    test('error georreferencia se sincroniza como otros al backend', () {
      final v = Visita.fromJson({
        'id': '42',
        'ruta_id': 1,
        'cliente_id': 'c1',
        'cliente_nombre': 'A',
        'direccion': 'D',
        'orden_ruta': 1,
        'estado': 'incidencia',
        'tipo_incidencia': 'error georreferencia',
        'local_action_id': 'act-1',
        'sync_status': 'pending_sync',
      });
      final body = v.toJsonForApiCreate();
      expect(body['tipo_incidencia'], 'otros');
      expect(
        body['observacion'],
        'Error georreferencia: nueva ubicación capturada',
      );
    });
  });

  group('observacionErrorGeorefParaSync', () {
    test('prefija detalle del vendedor', () {
      expect(
        observacionErrorGeorefParaSync('Cliente movido de local'),
        'Error georreferencia: nueva ubicación capturada. Cliente movido de local',
      );
    });
  });

  group('GeorefPendiente', () {
    test('idempotency payload incluye vendedor y ruta', () {
      const item = GeorefPendiente(
        rutaId: 7,
        clienteId: 'c9',
        clienteNombre: 'X',
        direccion: 'Y',
        latEfectiva: 0,
        lonEfectiva: 0,
        georefEstado: GeorefEstado.pendiente,
        localActionId: 'act-1',
      );
      final body = item.toApiUpdatePayload(
        vendedorId: 'v3',
        lat: -33.1,
        lon: -70.6,
      );
      expect(body['vendedor_id'], 'v3');
      expect(body['ruta_id'], 7);
      expect(body['lat'], -33.1);
      expect(body['local_action_id'], 'act-1');
    });

    test('payload incluye georef_origen mapa_manual', () {
      const item = GeorefPendiente(
        rutaId: 1,
        clienteId: 'c1',
        clienteNombre: 'X',
        direccion: 'Y',
        latEfectiva: 0,
        lonEfectiva: 0,
        georefEstado: GeorefEstado.capturada,
        georefOrigen: GeorefOrigen.mapaManual,
        localActionId: 'act-2',
      );
      final body = item.toApiUpdatePayload(
        vendedorId: 'v3',
        lat: -33.2,
        lon: -70.7,
        origen: GeorefOrigen.mapaManual,
      );
      expect(body['georef_origen'], 'mapa_manual');
    });

    test('cliente aplicado y sincronizado no queda en merge local', () {
      const local = GeorefPendiente(
        rutaId: 10,
        clienteId: 'c1',
        clienteNombre: 'Cliente',
        direccion: 'Dir',
        latEfectiva: -33.1,
        lonEfectiva: -70.6,
        georefEstado: GeorefEstado.aplicada,
        localSyncStatus: GeorefSyncStatus.synced,
      );
      final merged = GeorefLocalStore.mergeServidorConLocal(
        servidor: const [],
        local: [local],
      );
      expect(merged, isEmpty);
    });
  });

  group('AddressGeocoder.buildSearchQueries', () {
    test('prioriza dirección completa con comuna y ciudad', () {
      final q = AddressGeocoder.buildSearchQueries(
        direccion: 'Av. Principal 100',
        comuna: 'Quillota',
        ciudad: 'Valparaíso',
      );
      expect(q.first, 'Av. Principal 100, Quillota, Valparaíso, Chile');
      expect(q, contains('Quillota, Valparaíso, Chile'));
      expect(q.last, 'Valparaíso, Chile');
    });
  });

  group('OutboxDiagnostics.pendingOperacionalCount', () {
    test('excluye heartbeat y gps_track de la cola operacional', () {
      const diag = OutboxDiagnostics(
        pendingCount: 3,
        deadLetterCount: 0,
        legacyNullFechaPending: 0,
        byTypeAndState: [
          OutboxTypeStateCount(
            itemType: 'gps_track',
            syncState: 'pending',
            count: 2,
            maxRetry: 0,
          ),
          OutboxTypeStateCount(
            itemType: 'visita_sync',
            syncState: 'pending',
            count: 1,
            maxRetry: 0,
          ),
        ],
        stuckSamples: [],
      );
      expect(diag.pendingOperacionalCount, 1);
      expect(diag.pendingCount, 3);
    });
  });
}
