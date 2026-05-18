import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Contexto del dispositivo para heartbeats (batería, red, versión, hardware).
class DeviceContextService {
  DeviceContextService({
    Battery? battery,
    DeviceInfoPlugin? deviceInfo,
  })  : _battery = battery ?? Battery(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final Battery _battery;
  final DeviceInfoPlugin _deviceInfo;

  PackageInfo? _packageInfo;
  String? _deviceLabel;

  Future<void> warmUp() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    _deviceLabel ??= await _resolveDeviceLabel();
  }

  Future<String> appVersion() async {
    await warmUp();
    final p = _packageInfo!;
    return '${p.version}+${p.buildNumber}';
  }

  Future<String> deviceLabel() async {
    await warmUp();
    return _deviceLabel ?? 'desconocido';
  }

  Future<int?> batteryLevelPercent() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  Future<String> connectionLabel() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return 'none';
      return results.map((e) => e.name).join(',');
    } catch (_) {
      return 'unknown';
    }
  }

  Future<Map<String, dynamic>> snapshot() async {
    await warmUp();
    return {
      'app_version': await appVersion(),
      'dispositivo': await deviceLabel(),
      'bateria': await batteryLevelPercent(),
      'conexion': await connectionLabel(),
    };
  }

  Future<String> _resolveDeviceLabel() async {
    try {
      if (Platform.isAndroid) {
        final a = await _deviceInfo.androidInfo;
        return '${a.manufacturer} ${a.model} (Android ${a.version.release})';
      }
      if (Platform.isIOS) {
        final i = await _deviceInfo.iosInfo;
        return '${i.name} ${i.model} (iOS ${i.systemVersion})';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }
}
