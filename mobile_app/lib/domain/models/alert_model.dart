class AlertModel {
  final String deviceId;
  final int timestamp;
  final String type; // "CRASH" or "THEFT_SHOCK"
  final double gForce;
  final double leanAngle;
  final double batteryV;
  final double lat;
  final double lng;
  final int? serverTimestamp;

  AlertModel({
    required this.deviceId,
    required this.timestamp,
    required this.type,
    required this.gForce,
    required this.leanAngle,
    required this.batteryV,
    required this.lat,
    required this.lng,
    this.serverTimestamp,
  });

  factory AlertModel.fromMap(Map<dynamic, dynamic> map) {
    return AlertModel(
      deviceId: map['device_id'] ?? 'Unknown',
      timestamp: map['timestamp'] ?? 0,
      type: map['type'] ?? 'UNKNOWN',
      gForce: (map['g_force'] as num?)?.toDouble() ?? 0.0,
      leanAngle: (map['lean_angle'] as num?)?.toDouble() ?? 0.0,
      batteryV: (map['battery_v'] as num?)?.toDouble() ?? 0.0,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      serverTimestamp: map['server_timestamp'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp,
      'type': type,
      'g_force': gForce,
      'lean_angle': leanAngle,
      'battery_v': batteryV,
      'lat': lat,
      'lng': lng,
      'server_timestamp': serverTimestamp,
    };
  }
}
