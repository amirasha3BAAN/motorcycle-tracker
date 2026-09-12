class Telemetry {
  final String deviceId;
  final int timestamp;
  final double lat;
  final double lng;
  final double speed;
  final double batteryV;
  final double backupBatteryV;
  final int rssi;
  final int satellites;
  final String status;
  final int? serverTimestamp;

  Telemetry({
    required this.deviceId,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.batteryV,
    required this.backupBatteryV,
    required this.rssi,
    required this.satellites,
    required this.status,
    this.serverTimestamp,
  });

  factory Telemetry.fromMap(Map<dynamic, dynamic> map) {
    return Telemetry(
      deviceId: map['device_id'] ?? 'Unknown',
      timestamp: map['timestamp'] ?? 0,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      batteryV: (map['battery_v'] as num?)?.toDouble() ?? 0.0,
      backupBatteryV: (map['backup_battery_v'] as num?)?.toDouble() ?? 0.0,
      rssi: map['rssi'] ?? 0,
      satellites: map['satellites'] ?? 0,
      status: map['status'] ?? 'unknown',
      serverTimestamp: map['server_timestamp'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp,
      'lat': lat,
      'lng': lng,
      'speed': speed,
      'battery_v': batteryV,
      'backup_battery_v': backupBatteryV,
      'rssi': rssi,
      'satellites': satellites,
      'status': status,
      'server_timestamp': serverTimestamp,
    };
  }
}
