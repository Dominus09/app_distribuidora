import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Versión de esquema del blob de visitas en SharedPreferences.
const int kVisitaCacheSchemaVersion = 2;

class CacheIntegrity {
  CacheIntegrity._();

  static String checksumForPayload(Map<String, dynamic> payload) {
    final canonical = jsonEncode(_sortMap(payload));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static bool verifyPayload(Map<String, dynamic> payload) {
    final expected = payload['checksum']?.toString();
    if (expected == null || expected.isEmpty) return true;
    final copy = Map<String, dynamic>.from(payload)..remove('checksum');
    return checksumForPayload(copy) == expected;
  }

  static Map<String, dynamic> wrapWithIntegrity(
    Map<String, dynamic> payload,
  ) {
    final body = Map<String, dynamic>.from(payload)
      ..['schema_version'] = kVisitaCacheSchemaVersion;
    return {
      ...body,
      'checksum': checksumForPayload(body),
    };
  }

  static dynamic _sortMap(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((e) => e.toString()).toList()..sort();
      return {
        for (final k in keys) k: _sortMap(value[k]),
      };
    }
    if (value is List) {
      return value.map(_sortMap).toList();
    }
    return value;
  }
}
