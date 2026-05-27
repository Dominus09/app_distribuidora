import '../../features/vendedor/models/visita.dart';

/// Prioridad determinística de estado operativo (nunca degradar).
///
/// pending=0, visitado=1, incidencia=2, sin_compra (incidencia noCompra)=3
class VisitaReconciliation {
  VisitaReconciliation._();

  static int estadoPrioridad(Visita v) {
    switch (v.estado) {
      case VisitaEstado.pendiente:
        return 0;
      case VisitaEstado.visitado:
        return 1;
      case VisitaEstado.incidencia:
        if (v.tipoIncidencia == TipoIncidencia.noCompra) return 3;
        return 2;
    }
  }

  static bool localTieneProgresoOperativo(Visita l) {
    if (estadoPrioridad(l) > 0) return true;
    if (l.syncStatus != SyncStatus.synced) return true;
    if ((l.localActionId ?? '').isNotEmpty) return true;
    if (l.latVisita != null && l.lonVisita != null) return true;
    if (l.fechaHoraVisita != null) return true;
    return false;
  }

  /// Gana siempre el estado más avanzado; nunca visitado→pendiente.
  static Visita pickWinner(Visita a, Visita b) {
    final pa = estadoPrioridad(a);
    final pb = estadoPrioridad(b);
    if (pa > pb) return a;
    if (pb > pa) return b;
    return _prioridadSync(a) >= _prioridadSync(b) ? a : b;
  }

  static int _prioridadSync(Visita v) {
    var p = 0;
    switch (v.syncStatus) {
      case SyncStatus.pendingSync:
      case SyncStatus.syncing:
        p += 10;
      case SyncStatus.syncError:
        p += 5;
      case SyncStatus.deadLetter:
        p += 1;
      case SyncStatus.synced:
        p += 0;
    }
    if ((v.localActionId ?? '').isNotEmpty) p += 2;
    if (v.fechaHoraVisita != null) p += 1;
    return p;
  }

  static Visita mergeMaestro(Visita ganador, Visita maestro) {
    return ganador.copyWith(
      clienteNombre: maestro.clienteNombre,
      nombreFantasia: maestro.nombreFantasia,
      direccion: maestro.direccion,
      comuna: maestro.comuna,
      rutClean: maestro.rutClean,
      diaOperativo: maestro.diaOperativo,
      orden: maestro.orden,
      rutaId: maestro.rutaId ?? ganador.rutaId,
      latCliente: maestro.latCliente,
      lonCliente: maestro.lonCliente,
      clienteId: maestro.clienteId ?? ganador.clienteId,
    );
  }

  static Visita reconciliar({required Visita servidor, required Visita local}) {
    if (!localTieneProgresoOperativo(local)) return servidor;
    if (!localTieneProgresoOperativo(servidor)) {
      return mergeMaestro(local, servidor);
    }
    final winner = pickWinner(local, servidor);
    final maestro = winner == local ? servidor : local;
    return mergeMaestro(winner, maestro);
  }
}
