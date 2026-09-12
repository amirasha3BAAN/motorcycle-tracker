import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/motorcycle_provider.dart';
import '../../domain/models/telemetry_model.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MotorcycleProvider>(context);
    final telemetry = provider.currentTelemetry;
    final isArmed = provider.isArmed;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'MOTO-SENTRY DASHBOARD',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(
              provider.isSimulationActive ? Icons.stop_circle : Icons.play_circle,
              color: provider.isSimulationActive ? Colors.red : Colors.green,
            ),
            tooltip: provider.isSimulationActive ? 'Stop Ride Demo' : 'Start Ride Demo',
            onPressed: provider.toggleSimulationMode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // System Alert Banner if alert is active
              if (provider.latestAlert != null) ...[
                _buildAlertBanner(context, provider),
                const SizedBox(height: 16),
              ],

              // Connection Status Header
              _buildConnectionHeader(provider),
              const SizedBox(height: 16),

              // Arm / Disarm Console Card
              _buildSecurityConsole(provider),
              const SizedBox(height: 16),

              // Primary Telemetry Parameters Grid
              const Text(
                'LIVE TELEMETRY STATUS',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0),
              ),
              const SizedBox(height: 8),
              if (telemetry != null) ...[
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _buildTelemetryCard(
                      title: 'Main Battery',
                      value: '${telemetry.batteryV.toStringAsFixed(2)} V',
                      icon: Icons.battery_charging_full,
                      color: telemetry.batteryV > 12.0 ? Colors.green : Colors.orange,
                      caption: telemetry.batteryV > 12.0 ? 'Optimal (12V SLA)' : 'Low Voltage Warning',
                    ),
                    _buildTelemetryCard(
                      title: 'Backup LiPo',
                      value: '${telemetry.backupBatteryV.toStringAsFixed(2)} V',
                      icon: Icons.battery_saver,
                      color: telemetry.backupBatteryV > 3.7 ? Colors.blue : Colors.red,
                      caption: 'Internal ESP32 Cell',
                    ),
                    _buildTelemetryCard(
                      title: 'Signal Strength',
                      value: '${telemetry.rssi} dBm',
                      icon: Icons.signal_cellular_alt,
                      color: _getRSSIColor(telemetry.rssi),
                      caption: _getRSSIDescription(telemetry.rssi),
                    ),
                    _buildTelemetryCard(
                      title: 'GPS Satellites',
                      value: '${telemetry.satellites} Locked',
                      icon: Icons.satellite_alt,
                      color: telemetry.satellites >= 6 ? Colors.indigoAccent : Colors.red,
                      caption: telemetry.satellites >= 6 ? '3D Precision Fix' : 'Searching / Cold Lock',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildMovementStatusCard(telemetry),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: Colors.redAccent),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Developer Actions Console
              _buildDeveloperActionsConsole(provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertBanner(BuildContext context, MotorcycleProvider provider) {
    final alert = provider.latestAlert!;
    final isCrash = alert.type == 'CRASH';

    return Card(
      color: isCrash ? Colors.red.shade900 : Colors.orange.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white30)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isCrash ? Icons.emergency_share : Icons.gpp_maybe,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCrash ? 'CRASH DETECTED!' : 'THEFT MOVE DETECTED!',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCrash
                            ? 'Impact Force: ${alert.gForce.toStringAsFixed(1)}G, Tilt: ${alert.leanAngle.toStringAsFixed(1)}°'
                            : 'Vehicle moved outside geofence boundary while armed.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: provider.dismissAlert,
                  child: const Text('DISMISS ALARM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionHeader(MotorcycleProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                provider.isFirebaseConnected ? Icons.cloud_done : Icons.cloud_off,
                color: provider.isFirebaseConnected ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.isFirebaseConnected ? 'Firebase Online' : 'Local Mock Sandbox',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'Device ID: ${provider.deviceId}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              )
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: provider.isSimulationActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              provider.isSimulationActive ? 'SIMULATOR ON' : 'LIVE MODEM',
              style: TextStyle(
                color: provider.isSimulationActive ? Colors.greenAccent : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSecurityConsole(MotorcycleProvider provider) {
    final isArmed = provider.isArmed;

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isArmed ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
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
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Geofence alarm triggers upon shock/movement',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                Switch(
                  value: isArmed,
                  onChanged: (val) => provider.toggleArmedState(),
                  activeColor: Colors.redAccent,
                  activeTrackColor: Colors.redAccent.withOpacity(0.3),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.white12,
                ),
              ],
            ),
            Divider(color: Colors.white.withOpacity(0.05), height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: const Text('TRIGGER SIREN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => provider.sendRemoteCommand('SIREN_ON'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('FORCE PING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => provider.sendRemoteCommand('PING'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: TextStyle(color: color.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMovementStatusCard(Telemetry telemetry) {
    final bool isMoving = telemetry.status == 'moving';
    final String timeStr = DateFormat('HH:mm:ss').format(
      DateTime.fromMillisecondsSinceEpoch(telemetry.timestamp * 1000),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMoving ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMoving ? Icons.directions_bike : Icons.home,
              color: isMoving ? Colors.greenAccent : Colors.orangeAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMoving ? 'Motorcycle is Moving' : 'Motorcycle is Idle/Parked',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  isMoving ? 'Current Speed: ${telemetry.speed.toStringAsFixed(1)} km/h' : 'Stationary GPS anchor active.',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'LAST UPDATE',
                style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDeveloperActionsConsole(MotorcycleProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'DEV DEMO SANDBOX CONTROLS',
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Use these triggers to simulate telemetry streams and hardware crashes in the emulator instantly.',
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    foregroundColor: Colors.blueAccent,
                    side: const BorderSide(color: Colors.blueAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: provider.simulateCrashEvent,
                  child: const Text('SIMULATE CRASH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: provider.isSimulationActive ? Colors.redAccent.withOpacity(0.1) : Colors.greenAccent.withOpacity(0.1),
                    foregroundColor: provider.isSimulationActive ? Colors.redAccent : Colors.greenAccent,
                    side: BorderSide(color: provider.isSimulationActive ? Colors.redAccent : Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: provider.toggleSimulationMode,
                  child: Text(
                    provider.isSimulationActive ? 'HALT RIDE DEMO' : 'START RIDE DEMO',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRSSIColor(int rssi) {
    if (rssi >= -65) return Colors.green;
    if (rssi >= -85) return Colors.amber;
    return Colors.red;
  }

  String _getRSSIDescription(int rssi) {
    if (rssi >= -65) return 'Excellent LTE (4G)';
    if (rssi >= -85) return 'Moderate Signal';
    return 'Weak / Edge Coverage';
  }
}
