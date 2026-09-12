import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/models/telemetry_model.dart';
import '../domain/models/alert_model.dart';

class MotorcycleProvider with ChangeNotifier {
  final String _deviceId = 'MOTO-ESP32-98A7B6';
  
  // Update this to your live Render Backend URL when deploying (e.g. 'https://motorcycle-tracker-backend.onrender.com')
  final String _backendBaseUrl = 'https://motorcycle-tracker-backend.onrender.com'; 

  // Real-time states
  Telemetry? _currentTelemetry;
  AlertModel? _latestAlert;
  bool _isArmed = false;
  bool _isConnected = false; // Indicates if WebSocket is connected to the backend
  bool _isSimulationActive = false;

  // Dynamic Geofence Configurations
  double _geofenceLat = 34.052234;
  double _geofenceLng = -118.243684;
  double _geofenceRadiusMeters = 150.0;
  bool _geofenceEnabled = true;

  // WebSockets & HTTP
  WebSocketChannel? _channel;
  bool _isReconnecting = false;

  // Simulation timer
  Timer? _simulationTimer;
  double _simLat = 34.052234;
  double _simLng = -118.243684;
  double _simAngle = 0.0;

  // Getters
  String get deviceId => _deviceId;
  Telemetry? get currentTelemetry => _currentTelemetry;
  AlertModel? get latestAlert => _latestAlert;
  bool get isArmed => _isArmed;
  bool get isFirebaseConnected => _isConnected; // Map to the UI's connection indicator
  bool get isSimulationActive => _isSimulationActive;

  // Geofence Getters
  double get geofenceLat => _geofenceLat;
  double get geofenceLng => _geofenceLng;
  double get geofenceRadiusMeters => _geofenceRadiusMeters;
  bool get geofenceEnabled => _geofenceEnabled;

  MotorcycleProvider() {
    _loadInitialStatusAndConnect();
  }

  Future<void> _loadInitialStatusAndConnect() async {
    // 1. Fetch current status over HTTP GET REST API on startup
    await _fetchInitialStatus();
    
    // 2. Establish continuous WebSocket stream for live updates
    _connectWebSocket();
  }

  /// Fetches current status, armed state, and geofence config from backend
  Future<void> _fetchInitialStatus() async {
    try {
      print('[HTTP] Fetching initial motorcycle status from: $_backendBaseUrl');
      final response = await http.get(
        Uri.parse('$_backendBaseUrl/api/motorcycles/$_deviceId/status'),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['telemetry'] != null) {
          _currentTelemetry = Telemetry.fromMap(Map<String, dynamic>.from(data['telemetry']));
        } else {
          _loadMockInitialData();
        }

        if (data['latest_alert'] != null) {
          _latestAlert = AlertModel.fromMap(Map<String, dynamic>.from(data['latest_alert']));
        }

        if (data['state'] != null) {
          _isArmed = data['state']['armed'] == true;
        }

        if (data['geofence'] != null) {
          _geofenceLat = (data['geofence']['lat'] as num?)?.toDouble() ?? 34.052234;
          _geofenceLng = (data['geofence']['lng'] as num?)?.toDouble() ?? -118.243684;
          _geofenceRadiusMeters = (data['geofence']['radius_meters'] as num?)?.toDouble() ?? 150.0;
          _geofenceEnabled = data['geofence']['enabled'] ?? true;
        }
        
        notifyListeners();
        print('[HTTP Success] Completed initial status load from persistent server.');
      } else {
        print('[HTTP Warning] Server returned status ${response.statusCode}. Falling back to default mock data.');
        _loadMockInitialData();
      }
    } catch (e) {
      print('[HTTP Failure] Failed to load initial status ($e). Booting with default mock values.');
      _loadMockInitialData();
    }
  }

  /// Sets up continuous WebSocket connection for low-latency live telemetry updates
  void _connectWebSocket() {
    if (_isReconnecting) return;
    
    try {
      // Replace http:// or https:// with ws:// or wss:// respectively
      final wsUrl = _backendBaseUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws') + '/ws';
      print('[WebSocket] Connecting to real-time stream at: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _isReconnecting = false;
      notifyListeners();
      print('[WebSocket Connected] Live stream channel created.');

      _channel!.stream.listen(
        (message) {
          try {
            final payload = jsonDecode(message);
            final String path = payload['path'] ?? '';
            final data = payload['data'];

            if (path == 'motorcycles/$_deviceId/telemetry/current') {
              _currentTelemetry = Telemetry.fromMap(Map<String, dynamic>.from(data));
              notifyListeners();
            } else if (path == 'motorcycles/$_deviceId/alerts/latest') {
              if (data != null) {
                _latestAlert = AlertModel.fromMap(Map<String, dynamic>.from(data));
              } else {
                _latestAlert = null;
              }
              notifyListeners();
            } else if (path == 'motorcycles/$_deviceId/state') {
              if (data != null) {
                _isArmed = data['armed'] == true;
              }
              notifyListeners();
            } else if (path == 'motorcycles/$_deviceId/geofence') {
              if (data != null) {
                _geofenceLat = (data['lat'] as num?)?.toDouble() ?? 34.052234;
                _geofenceLng = (data['lng'] as num?)?.toDouble() ?? -118.243684;
                _geofenceRadiusMeters = (data['radius_meters'] as num?)?.toDouble() ?? 150.0;
                _geofenceEnabled = data['enabled'] ?? true;
              }
              notifyListeners();
            } else if (path == 'alerts/notifications') {
              print('[FCM Push Broadcast Received via WebSockets] Title: ${data['title']}, Body: ${data['body']}');
            }
          } catch (err) {
            print('[WebSocket Error] Failed to process incoming message: $err');
          }
        },
        onDone: () {
          print('[WebSocket Done] Connection closed. Attempting reconnect in 5s...');
          _handleDisconnect();
        },
        onError: (err) {
          print('[WebSocket Error] Connection error: $err. Reconnecting in 5s...');
          _handleDisconnect();
        },
        cancelOnError: true
      );
    } catch (e) {
      print('[WebSocket Error] Failed to connect: $e. Retrying in 5s...');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    notifyListeners();
    
    if (!_isReconnecting) {
      _isReconnecting = true;
      Timer(const Duration(seconds: 5), () {
        _isReconnecting = false;
        _connectWebSocket();
      });
    }
  }

  void _loadMockInitialData() {
    _currentTelemetry = Telemetry(
      deviceId: _deviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lat: _simLat,
      lng: _simLng,
      speed: 0.0,
      batteryV: 12.62,
      backupBatteryV: 4.15,
      rssi: -65,
      satellites: 9,
      status: 'parked',
    );
    _isArmed = false;
    notifyListeners();
  }

  /// Toggle motorcycle Armed state
  Future<void> toggleArmedState() async {
    final newArmedState = !_isArmed;
    _isArmed = newArmedState;
    notifyListeners();

    // Trigger state change immediately on server
    try {
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/api/motorcycles/$_deviceId/arm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'armed': newArmedState}),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        print('[HTTP Success] Local DB armed status updated.');
      } else {
        print('[HTTP Warning] Server rejected armed update: ${response.statusCode}');
      }
    } catch (e) {
      print('[HTTP Failure] Failed to update armed state in backend ($e). Operating optimistically.');
    }

    // Auto sync armed state down to ESP32 device via MQTT commands
    await sendRemoteCommand(newArmedState ? 'ARM' : 'DISARM');
  }

  /// Updates Geofence details dynamically on Backend REST API
  Future<void> updateGeofence(double lat, double lng, double radius, bool enabled) async {
    _geofenceLat = lat;
    _geofenceLng = lng;
    _geofenceRadiusMeters = radius;
    _geofenceEnabled = enabled;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/api/motorcycles/$_deviceId/geofence'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': lat,
          'lng': lng,
          'radius_meters': radius,
          'enabled': enabled,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        print('[HTTP Success] Geofence successfully updated on server.');
      } else {
        print('[HTTP Warning] Failed to update geofence on server: ${response.statusCode}');
      }
    } catch (e) {
      print('[HTTP Failure] Failed to update geofence on server ($e).');
    }
  }

  /// Anchors the geofence perimeter to the motorcycle's current live coordinate
  Future<void> setGeofenceToCurrentPosition() async {
    if (_currentTelemetry != null) {
      await updateGeofence(
        _currentTelemetry!.lat,
        _currentTelemetry!.lng,
        _geofenceRadiusMeters,
        _geofenceEnabled,
      );
    }
  }

  /// Remote command trigger over HTTP (dispatches request down to Node.js / MQTT broker)
  Future<bool> sendRemoteCommand(String command) async {
    print('[HTTP Request] Dispatching command "$command" to backend API...');
    try {
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/api/motorcycles/$_deviceId/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command}),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        print('[HTTP Success] Command successfully accepted by backend broker.');
        return true;
      } else {
        print('[HTTP Warning] Server rejected command with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[HTTP Failure] Backend offline ($e). Operating in sandbox simulation mode.');
      return false;
    }
  }

  /// Toggle Live Ride Simulation Mode
  void toggleSimulationMode() {
    _isSimulationActive = !_isSimulationActive;

    if (_isSimulationActive) {
      _simLat = _currentTelemetry?.lat ?? 34.052234;
      _simLng = _currentTelemetry?.lng ?? -118.243684;

      _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        // Move motorcycle in a small circle
        _simAngle += 0.05;
        _simLat += 0.0003 * cos(_simAngle);
        _simLng += 0.0003 * sin(_simAngle);

        _currentTelemetry = Telemetry(
          deviceId: _deviceId,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          lat: _simLat,
          lng: _simLng,
          speed: 42.5 + Random().nextDouble() * 5.0,
          batteryV: 12.50 - Random().nextDouble() * 0.1,
          backupBatteryV: 4.10,
          rssi: -60 - Random().nextInt(15),
          satellites: 10 + Random().nextInt(3),
          status: 'moving',
        );

        // Geofence breach simulation evaluation
        if (_isArmed && _geofenceEnabled) {
          final distance = _calculateDistance(_simLat, _simLng, _geofenceLat, _geofenceLng);
          if (distance > _geofenceRadiusMeters && _latestAlert == null) {
            print('[Sim Alert] Geofence breach simulated!');
            _latestAlert = AlertModel(
              deviceId: _deviceId,
              timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              type: 'THEFT_SHOCK',
              gForce: 1.0,
              leanAngle: 0.0,
              batteryV: _currentTelemetry!.batteryV,
              lat: _simLat,
              lng: _simLng,
            );
          }
        }
        notifyListeners();
      });
      print('[Simulation] Started simulated ride path.');
    } else {
      _simulationTimer?.cancel();
      _currentTelemetry = Telemetry(
        deviceId: _deviceId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        lat: _simLat,
        lng: _simLng,
        speed: 0.0,
        batteryV: 12.60,
        backupBatteryV: 4.14,
        rssi: -65,
        satellites: 8,
        status: 'parked',
      );
      notifyListeners();
      print('[Simulation] Stopped simulated ride path.');
    }
    notifyListeners();
  }

  /// Mathematical helper to compute distance in meters locally for simulation triggers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth's radius in meters
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2.0) * sin(dLat / 2.0) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
        sin(dLon / 2.0) * sin(dLon / 2.0);
    final c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    return r * c;
  }

  /// Simulates a crash event
  void simulateCrashEvent() {
    _latestAlert = AlertModel(
      deviceId: _deviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      type: 'CRASH',
      gForce: 4.62,
      leanAngle: 82.1,
      batteryV: 12.48,
      lat: _currentTelemetry?.lat ?? 34.052234,
      lng: _currentTelemetry?.lng ?? -118.243684,
    );
    notifyListeners();
  }

  /// Dismisses active alarm card
  void dismissAlert() {
    _latestAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _simulationTimer?.cancel();
    super.dispose();
  }
}
