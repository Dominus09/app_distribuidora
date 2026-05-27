import 'dart:math' as math;

/// Cálculo de km en isolate (`compute`) para no bloquear el UI thread.
double computeKmFromTrackPoints(List<List<double>> points) {
  if (points.length < 2) return 0;
  const r = 6371000.0;
  var totalM = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final lat1 = a[0] * math.pi / 180;
    final lat2 = b[0] * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLon = (b[1] - a[1]) * math.pi / 180;
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    totalM += r * c;
  }
  return totalM / 1000;
}
