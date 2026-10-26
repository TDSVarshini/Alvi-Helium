import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Bluetooth permissions the ring needs. Android 12+ asks for nearby devices;
/// older Android needs location to scan; iOS asks for Bluetooth.
Future<bool> ensureBluetoothPermissions() async {
  if (Platform.isIOS) {
    final s = await Permission.bluetooth.request();
    return s.isGranted || s.isLimited;
  }
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
  final ble = statuses[Permission.bluetoothScan]!.isGranted && statuses[Permission.bluetoothConnect]!.isGranted;
  // Pre-Android 12 devices report BLE permissions as granted and need location.
  return ble || statuses[Permission.locationWhenInUse]!.isGranted;
}

Future<bool> ensureLocationPermission() async {
  final s = await Permission.locationWhenInUse.request();
  return s.isGranted;
}
