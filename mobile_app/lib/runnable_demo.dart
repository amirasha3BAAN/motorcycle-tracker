import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const MotoSentryApp());
}

// --- CORE MODELS ---
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
  });
}

class AlertModel {
  final String deviceId;
  final int timestamp;
  final String type; // "CRASH" | "THEFT_SHOCK"
  final double gForce;
  final double leanAngle;
  final double batteryV;
  final double lat;
  final double lng;

  AlertModel({
    required this.deviceId,
    required this.timestamp,
    required this.type,
    required this.gForce,
    required this.leanAngle,
    required this.batteryV,
    required this.lat,
    required this.lng,
  });
}

// --- STATE MANAGEMENT INLINE ---
class MotorcycleState {
  final String deviceId = 'MOTO-ESP32-98A7B6';
  Telemetry? currentTelemetry;
  AlertModel? latestAlert;
  bool isArmed = false;
  bool isSimulationActive = false;

  // Geofence boundaries
  double geofenceLat = 34.052234;
  double geofenceLng = -118.243684;
  double geofenceRadiusMeters = 150.0;
  bool geofenceEnabled = true;

  double simLat = 34.052234;
  double simLng = -118.243684;
  double simAngle = 0.0;
  
  // Track past coordinates to render trails
  final List<Offset> breadcrumbs = [];

  MotorcycleState() {
    currentTelemetry = Telemetry(
      deviceId: deviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lat: simLat,
      lng: simLng,
      speed: 0.0,
      batteryV: 12.62,
      backupBatteryV: 4.15,
      rssi: -65,
      satellites: 9,
      status: 'parked',
    );
  }
}

// --- MAIN FLUTTER CORE APPLICATION ---
class MotoSentryApp extends StatelessWidget {
  const MotoSentryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoSentry Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.redAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.redAccent,
          secondary: Colors.amberAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final MotorcycleState _state = MotorcycleState();
  Timer? _simulationTimer;
  Timer? _radarSweepTimer;
  double _radarAngle = 0.0;

  @override
  void initState() {
    super.initState();
    // Start radar sweeps animation
    _radarSweepTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        _radarAngle = (_radarAngle + 0.03) % (2 * pi);
      });
    });
  }

  void _toggleSimulation() {
    setState(() {
      _state.isSimulationActive = !_state.isSimulationActive;
    });

    if (_state.isSimulationActive) {
      _simulationTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
        setState(() {
          _state.simAngle += 0.12;
          
          // Moves motorcycle in an expanding/contracting orbit
          double orbitRadius = 0.0012 + 0.0004 * sin(_state.simAngle * 0.4);
          _state.simLat = _state.geofenceLat + orbitRadius * cos(_state.simAngle);
          _state.simLng = _state.geofenceLng + orbitRadius * sin(_state.simAngle);

          _state.currentTelemetry = Telemetry(
            deviceId: _state.deviceId,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            lat: _state.simLat,
            lng: _state.simLng,
            speed: 38.5 + Random().nextDouble() * 12.0,
            batteryV: 12.45 - Random().nextDouble() * 0.08,
            backupBatteryV: 4.11,
            rssi: -62 - Random().nextInt(15),
            satellites: 9 + Random().nextInt(3),
            status: 'moving',
          );

          // Add tracking coordinate trails
          _state.breadcrumbs.add(Offset(_state.simLat, _state.simLng));
          if (_state.breadcrumbs.length > 30) {
            _state.breadcrumbs.removeAt(0);
          }

          // Evaluate dynamic geofencing
          if (_state.isArmed && _state.geofenceEnabled) {
            final distance = _calculateDistance(
              _state.simLat, _state.simLng, _state.geofenceLat, _state.geofenceLng
            );
            if (distance > _state.geofenceRadiusMeters && _state.latestAlert == null) {
              _state.latestAlert = AlertModel(
                deviceId: _state.deviceId,
                timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                type: 'THEFT_SHOCK',
                gForce: 1.0,
                leanAngle: 0.0,
                batteryV: _state.currentTelemetry!.batteryV,
                lat: _state.simLat,
                lng: _state.simLng,
              );
            }
          }
        });
      });
    } else {
      _simulationTimer?.cancel();
      setState(() {
        _state.currentTelemetry = Telemetry(
          deviceId: _state.deviceId,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          lat: _state.simLat,
          lng: _state.simLng,
          speed: 0.0,
          batteryV: 12.61,
          backupBatteryV: 4.14,
          rssi: -65,
          satellites: 8,
          status: 'parked',
        );
      });
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2.0) * sin(dLat / 2.0) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
        sin(dLon / 2.0) * sin(dLon / 2.0);
    final c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    return r * c;
  }

  void _triggerCrash() {
    setState(() {
      _state.latestAlert = AlertModel(
        deviceId: _state.deviceId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        type: 'CRASH',
        gForce: 4.62,
        leanAngle: 82.1,
        batteryV: 12.48,
        lat: _state.currentTelemetry!.lat,
        lng: _state.currentTelemetry!.lng,
      );
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _radarSweepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Screen 1: Virtual Map HUD
          MapHudScreen(
            state: _state,
            radarAngle: _radarAngle,
            onToggleSimulation: _toggleSimulation,
            onUpdateGeofence: (radius, enabled) {
              setState(() {
                _state.geofenceRadiusMeters = radius;
                _state.geofenceEnabled = enabled;
              });
            },
          ),
          // Screen 2: Telemetry Dashboard
          DashboardTab(
            state: _state,
            onToggleArm: () {
              setState(() {
                _state.isArmed = !_state.isArmed;
              });
            },
            onTriggerCrash: _triggerCrash,
            onToggleSimulation: _toggleSimulation,
            onDismissAlert: () {
              setState(() {
                _state.latestAlert = null;
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            activeIcon: Icon(Icons.radar),
            label: 'LIVE TRACKER',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize_outlined),
            activeIcon: Icon(Icons.dashboard_customize),
            label: 'DASHBOARD',
          ),
        ],
      ),
    );
  }
}

// --- SCREEN 1: RADAR MAP HUD SCREEN ---
class MapHudScreen extends StatefulWidget {
  final MotorcycleState state;
  final double radarAngle;
  final VoidCallback onToggleSimulation;
  final Function(double, bool) onUpdateGeofence;

  const MapHudScreen({
    Key? key,
    required this.state,
    required this.radarAngle,
    required this.onToggleSimulation,
    required this.onUpdateGeofence,
  }) : super(key: key);

  @override
  State<MapHudScreen> createState() => _MapHudScreenState();
}

class _MapHudScreenState extends State<MapHudScreen> {
  bool _showSliders = false;

  @override
  Widget build(BuildContext context) {
    final telemetry = widget.state.currentTelemetry!;
    final isArmed = widget.state.isArmed;

    return Stack(
      children: [
        // Vector GPS Radar Screen
        Positioned.fill(
          child: Container(
            color: const Color(0xFF0D0D0D),
            child: CustomPaint(
              painter: RadarPainter(
                state: widget.state,
                sweepAngle: widget.radarAngle,
              ),
            ),
          ),
        ),

        // Floating Header Banner
        Positioned(
          top: 48,
          left: 16,
          right: 72,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(
                  isArmed ? Icons.lock : Icons.lock_open,
                  color: isArmed ? Colors.redAccent : Colors.greenAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArmed ? 'GEOFENCE SHIELD: ARMED' : 'SENTRY INACTIVE',
                        style: TextStyle(
                          color: isArmed ? Colors.redAccent : Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        widget.state.geofenceEnabled
                            ? 'Sentry Perimeter: ${widget.state.geofenceRadiusMeters.toInt()}m'
                            : 'Geofence Guard Disabled',
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Floating Configurations Panel Trigger Button
        Positioned(
          top: 48,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: const Color(0xFF1E1E1E),
            foregroundColor: Colors.redAccent,
            onPressed: () {
              setState(() {
                _showSliders = !_showSliders;
              });
            },
            child: Icon(_showSliders ? Icons.close : Icons.tune),
          ),
        ),

        // Dynamic Bottom HUD Panel (Vehicle Telemetry Stats Overlay)
        if (!_showSliders)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildHudStat('SPEED', '${telemetry.speed.toStringAsFixed(1)}', 'km/h'),
                  _buildHudStat('SATELLITES', '${telemetry.satellites}', 'fixed'),
                  _buildHudStat('GEOFENCE', widget.state.isArmed && widget.state.geofenceEnabled ? '${widget.state.geofenceRadiusMeters.toInt()}m' : 'OFF', 'radius'),
                ],
              ),
            ),
          ),

        // Sliding Geofence Configurations Panel
        if (_showSliders)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TUNING CONFIGURATIONS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Switch(
                        value: widget.state.geofenceEnabled,
                        onChanged: (val) {
                          widget.onUpdateGeofence(widget.state.geofenceRadiusMeters, val);
                        },
                        activeColor: Colors.amberAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Guard Radius Limit:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text('${widget.state.geofenceRadiusMeters.toInt()}m', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: widget.state.geofenceRadiusMeters,
                    min: 50.0,
                    max: 400.0,
                    divisions: 14,
                    activeColor: Colors.amberAccent,
                    onChanged: widget.state.geofenceEnabled
                        ? (val) {
                            widget.onUpdateGeofence(val, widget.state.geofenceEnabled);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        _showSliders = false;
                      });
                    },
                    child: const Text('LOCK SETTINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          )
      ],
    );
  }

  Widget _buildHudStat(String label, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 9)),
          ],
        )
      ],
    );
  }
}

// --- CORE CUSTOM RADAR GRAPH VECTOR DRAWING ---
class RadarPainter extends CustomPainter {
  final MotorcycleState state;
  final double sweepAngle;

  RadarPainter({required this.state, required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 40);
    final maxRadius = min(size.width, size.height) * 0.42;

    // Background grids
    final gridPaint = Paint()
      ..color = const Color(0xFF00FF66).withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw grid rings
    canvas.drawCircle(center, maxRadius * 0.25, gridPaint);
    canvas.drawCircle(center, maxRadius * 0.50, gridPaint);
    canvas.drawCircle(center, maxRadius * 0.75, gridPaint);
    canvas.drawCircle(center, maxRadius, gridPaint);

    // Crosshairs
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), gridPaint);

    // Draw active Radar Sweep line
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFF00FF66).withOpacity(0.0),
          const Color(0xFF00FF66).withOpacity(0.35),
        ],
        stops: const [0.85, 1.0],
        transform: GradientRotation(sweepAngle - 0.3),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);

    // Draw Dynamic Geofence Boundary Circle
    if (state.geofenceEnabled) {
      final double mapGeofenceRadius = (state.geofenceRadiusMeters / 400.0) * maxRadius;
      final fencePaint = Paint()
        ..color = state.isArmed ? Colors.redAccent.withOpacity(0.4) : Colors.greenAccent.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final fenceFill = Paint()
        ..color = state.isArmed ? Colors.redAccent.withOpacity(0.06) : Colors.greenAccent.withOpacity(0.04)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, mapGeofenceRadius, fenceFill);
      canvas.drawCircle(center, mapGeofenceRadius, fencePaint);

      // Dash circles if ARMED
      if (state.isArmed) {
        final alertPaint = Paint()
          ..color = Colors.redAccent.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(center, mapGeofenceRadius + 6, alertPaint);
      }
    }

    // MAP VEHICLE COORDINATE TRANSLATION CALCULATIONS
    double getPixelX(double lng) {
      double diffLng = lng - state.geofenceLng;
      return center.dx + (diffLng / 0.0020) * maxRadius;
    }

    double getPixelY(double lat) {
      double diffLat = lat - state.geofenceLat;
      return center.dy - (diffLat / 0.0020) * maxRadius; 
    }

    // Render breadcrumbs (Trails)
    if (state.isSimulationActive && state.breadcrumbs.isNotEmpty) {
      final trailPaint = Paint()
        ..color = const Color(0xFF00FF66).withOpacity(0.35)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < state.breadcrumbs.length - 1; i++) {
        final p1 = Offset(getPixelX(state.breadcrumbs[i].dy), getPixelY(state.breadcrumbs[i].dx));
        final p2 = Offset(getPixelX(state.breadcrumbs[i + 1].dy), getPixelY(state.breadcrumbs[i + 1].dx));
        canvas.drawLine(p1, p2, trailPaint);
      }
    }

    // Plot Vehicle Target Dot
    final targetX = getPixelX(state.simLng);
    final targetY = getPixelY(state.simLat);
    final targetOffset = Offset(targetX, targetY);

    final targetCorePaint = Paint()
      ..color = state.isArmed ? Colors.redAccent : const Color(0xFF00FF66)
      ..style = PaintingStyle.fill;

    final targetPulsePaint = Paint()
      ..color = (state.isArmed ? Colors.redAccent : const Color(0xFF00FF66)).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    double ripple = (sin(sweepAngle * 8) + 1.0) * 8.0 + 8.0;
    canvas.drawCircle(targetOffset, ripple, targetPulsePaint);
    canvas.drawCircle(targetOffset, 6.0, targetCorePaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'MOTO_TGT',
        style: TextStyle(
          color: state.isArmed ? Colors.redAccent : const Color(0xFF00FF66),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withOpacity(0.6),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(targetX + 10, targetY - 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- SCREEN 2: SYSTEM TELEMETRY DASHBOARD TAB ---
class DashboardTab extends StatelessWidget {
  final MotorcycleState state;
  final VoidCallback onToggleArm;
  final VoidCallback onTriggerCrash;
  final VoidCallback onToggleSimulation;
  final VoidCallback onDismissAlert;

  const DashboardTab({
    Key? key,
    required this.state,
    required this.onToggleArm,
    required this.onTriggerCrash,
    required this.onToggleSimulation,
    required this.onDismissAlert,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final telemetry = state.currentTelemetry!;
    final isArmed = state.isArmed;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            if (state.latestAlert != null) ...[
              _buildAlertBanner(context),
              const SizedBox(height: 16),
            ],

            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isArmed ? Colors.redAccent.withOpacity(0.3) : Colors.white05,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isArmed ? 'SECURED & ARMED' : 'SYSTEM DISARMED',
                              style: TextStyle(
                                color: isArmed ? Colors.redAccent : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Sentry perimeter activates on arming',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                        Switch(
                          value: isArmed,
                          onChanged: (val) => onToggleArm(),
                          activeColor: Colors.redAccent,
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.volume_up, size: 18),
                            label: const Text('TRIGGER SIREN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔊 [COMMAND] Dispatching physical SIREN_ON to device...'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white30),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('FORCE PING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('📡 [COMMAND] Sending force ping command to device...'),
                                  backgroundColor: Colors.indigo,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'LIVE HARDWARE STATUS',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _buildStatCard('Main Battery', '${telemetry.batteryV.toStringAsFixed(2)} V', Icons.battery_charging_full, telemetry.batteryV > 12.0 ? Colors.green : Colors.amber, '12V Motorcycle Lead'),
                _buildStatCard('Backup Battery', '${telemetry.backupBatteryV.toStringAsFixed(2)} V', Icons.battery_saver, Colors.blue, 'Internal ESP32 LiPo'),
                _buildStatCard('Signal quality', '${telemetry.rssi} dBm', Icons.signal_cellular_alt, telemetry.rssi > -70 ? Colors.green : Colors.amber, telemetry.rssi > -70 ? 'Strong 4G LTE' : 'Weak Coverage'),
                _buildStatCard('GPS Satellites', '${telemetry.satellites} Fixed', Icons.satellite_alt, Colors.cyan, '3D Coordination Lock'),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white05),
              ),
              child: Row(
                children: [
                  Icon(
                    telemetry.status == 'moving' ? Icons.directions_bike : Icons.home,
                    color: telemetry.status == 'moving' ? Colors.greenAccent : Colors.orangeAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          telemetry.status == 'moving' ? 'Bike is Active/Moving' : 'Bike is Parked/Stationary',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          telemetry.status == 'moving' ? 'Speed: ${telemetry.speed.toStringAsFixed(1)} km/h' : 'Vibration sensor armed.',
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.bug_report, color: Colors.blueAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'DEMO EXPERIMENT CONSOLE',
                        style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                            side: const BorderSide(color: Colors.blueAccent),
                          ),
                          onPressed: onTriggerCrash,
                          child: const Text('MOCK CRASH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: state.isSimulationActive ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: onToggleSimulation,
                          child: Text(
                            state.isSimulationActive ? 'HALT RIDE' : 'START RIDE',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBanner(BuildContext context) {
    final alert = state.latestAlert!;
    final isCrash = alert.type == 'CRASH';

    return Card(
      color: isCrash ? Colors.red.shade900 : Colors.orange.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isCrash ? Icons.emergency_share : Icons.warning_amber,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCrash ? '🚨 SEVERE CRASH DETECTED!' : '🔒 VEHICLE SECURITY ALARM!',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCrash
                            ? 'Force: ${alert.gForce}G | Lean: ${alert.leanAngle}° | SMS sent.'
                            : 'Bike moved outside geofence boundary while armed!',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                )
              ],
            ),
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismissAlert,
                  child: const Text('DISMISS ALARM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, String caption) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(color: color.withOpacity(0.8), fontSize: 9)),
            ],
          )
        ],
      ),
    );
  }
}
