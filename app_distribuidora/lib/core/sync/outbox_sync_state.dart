/// Estado explícito de una fila en la cola outbox (SQLite).
enum OutboxSyncState {
  pending,
  syncing,
  synced,
  failed,
  deadLetter,
}

extension OutboxSyncStateCodec on OutboxSyncState {
  String get dbValue => switch (this) {
        OutboxSyncState.pending => 'pending',
        OutboxSyncState.syncing => 'syncing',
        OutboxSyncState.synced => 'synced',
        OutboxSyncState.failed => 'failed',
        OutboxSyncState.deadLetter => 'dead_letter',
      };

  static OutboxSyncState fromDb(String? raw) {
    final n = raw?.trim().toLowerCase();
    return switch (n) {
      'syncing' => OutboxSyncState.syncing,
      'synced' => OutboxSyncState.synced,
      'failed' => OutboxSyncState.failed,
      'dead_letter' => OutboxSyncState.deadLetter,
      _ => OutboxSyncState.pending,
    };
  }

  bool get isTerminal =>
      this == OutboxSyncState.synced || this == OutboxSyncState.deadLetter;

  bool get isRetryable =>
      this == OutboxSyncState.pending || this == OutboxSyncState.failed;
}
