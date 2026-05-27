import 'package:flutter/foundation.dart';

import '../utils/field_log.dart';

/// Registro de timers/listeners activos (diagnóstico duplicados).
class TimerRegistry {
  TimerRegistry._();
  static final TimerRegistry instance = TimerRegistry._();

  final Map<String, _TimerEntry> _entries = {};

  void register({
    required String name,
    required String owner,
    String? detail,
  }) {
    _entries[name] = _TimerEntry(
      name: name,
      owner: owner,
      detail: detail,
      startedAt: DateTime.now(),
    );
    fieldLog(
      'TimerRegistry',
      '[TIMER][START] $name owner=$owner ${detail ?? ""}',
      force: kDebugMode,
    );
  }

  void unregister(String name) {
    _entries.remove(name);
    fieldLog(
      'TimerRegistry',
      '[TIMER][STOP] $name',
      force: kDebugMode,
    );
  }

  bool isActive(String name) => _entries.containsKey(name);

  List<TimerRegistryEntry> snapshot() {
    return _entries.values
        .map(
          (e) => TimerRegistryEntry(
            name: e.name,
            owner: e.owner,
            detail: e.detail,
            startedAt: e.startedAt,
          ),
        )
        .toList();
  }
}

class TimerRegistryEntry {
  const TimerRegistryEntry({
    required this.name,
    required this.owner,
    this.detail,
    required this.startedAt,
  });

  final String name;
  final String owner;
  final String? detail;
  final DateTime startedAt;
}

class _TimerEntry {
  _TimerEntry({
    required this.name,
    required this.owner,
    this.detail,
    required this.startedAt,
  });

  final String name;
  final String owner;
  final String? detail;
  final DateTime startedAt;
}
