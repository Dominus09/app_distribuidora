import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/telemetry/operational_status_snapshot.dart';
import 'operational_status_card.dart';

/// Tarjeta operacional aislada: solo este subtree se reconstruye al actualizar estado.
class OperationalStatusListener extends StatelessWidget {
  const OperationalStatusListener({
    super.key,
    required this.snapshotListenable,
  });

  final ValueListenable<OperationalStatusSnapshot?> snapshotListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OperationalStatusSnapshot?>(
      valueListenable: snapshotListenable,
      builder: (context, snap, _) {
        return OperationalStatusCard(
          snapshot: snap,
          isLoading: snap == null,
        );
      },
    );
  }
}
