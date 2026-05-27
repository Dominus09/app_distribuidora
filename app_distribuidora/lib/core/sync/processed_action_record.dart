import '../session/operational_scope.dart';

/// Clave compuesta de idempotencia: vendedor + fecha + ruta + action_id.
class ProcessedActionRecord {
  const ProcessedActionRecord({
    required this.vendedorId,
    required this.fechaOperativa,
    required this.rutaId,
    required this.actionId,
  });

  final String vendedorId;
  final String fechaOperativa;
  final int rutaId;
  final String actionId;

  factory ProcessedActionRecord.fromScope(
    OperationalScope scope,
    String actionId,
  ) {
    return ProcessedActionRecord(
      vendedorId: scope.vendedorIdTrimmed,
      fechaOperativa: scope.fechaOperativa,
      rutaId: scope.rutaId != null && scope.rutaId! >= 1 ? scope.rutaId! : 0,
      actionId: actionId.trim(),
    );
  }

  factory ProcessedActionRecord.fromVisitaContext({
    required String vendedorId,
    required String fechaOperativa,
    required int? rutaId,
    required String actionId,
  }) {
    return ProcessedActionRecord(
      vendedorId: vendedorId.trim(),
      fechaOperativa: fechaOperativa,
      rutaId: rutaId != null && rutaId >= 1 ? rutaId : 0,
      actionId: actionId.trim(),
    );
  }

  /// Clave en memoria para Set lookup.
  String get memoryKey =>
      '$vendedorId|$fechaOperativa|$rutaId|$actionId';

  Map<String, Object> toDbRow({DateTime? confirmedAt}) {
    return {
      'vendedor_id': vendedorId,
      'fecha_operativa': fechaOperativa,
      'ruta_id': rutaId,
      'action_id': actionId,
      'confirmed_at':
          (confirmedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }
}
