/// Tipos de ítems en la cola offline persistente.
enum OutboxItemType {
  heartbeat('heartbeat'),
  gpsTrack('gps_track'),
  visitaSync('visita_sync');

  const OutboxItemType(this.value);
  final String value;

  static OutboxItemType? fromValue(String? raw) {
    if (raw == null) return null;
    for (final t in OutboxItemType.values) {
      if (t.value == raw) return t;
    }
    return null;
  }
}
