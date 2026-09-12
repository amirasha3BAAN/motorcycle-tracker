import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/motorcycle_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _lastPosition;
  bool _showGeofenceConfigPanel = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MotorcycleProvider>(context);
    final telemetry = provider.currentTelemetry;

    // Default coordinate if no telemetry is loaded yet
    final LatLng vehicleLatLng = telemetry != null
        ? LatLng(telemetry.lat, telemetry.lng)
        : const LatLng(34.052234, -118.243684);

    // If coordinate has changed, move the map camera to center on the vehicle
    if (telemetry != null && _lastPosition != vehicleLatLng) {
      _lastPosition = vehicleLatLng;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(vehicleLatLng, 16.5);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap Widget using flutter_map (100% Free, Cardless, No API Keys required!)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: vehicleLatLng,
              initialZoom: 16.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // OpenStreetMap Dark/Standard tile layer
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.amirasha3BAAN.motorcycle_tracker',
              ),

              // Geofencing perimeter circle representation
              if (provider.geofenceEnabled)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(provider.geofenceLat, provider.geofenceLng),
                      radius: provider.geofenceRadiusMeters,
                      useRadiusInMeter: true,
                      color: provider.isArmed ? Colors.red.withOpacity(0.12) : Colors.amber.withOpacity(0.08),
                      borderColor: provider.isArmed ? Colors.red.withOpacity(0.6) : Colors.amber.withOpacity(0.5),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // Markers Layer (Motorcycle and Geofence Center Pin)
              MarkerLayer(
                markers: [
                  // Motorcycle marker
                  Marker(
                    point: vehicleLatLng,
                    width: 45.0,
                    height: 45.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: provider.isArmed ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: provider.isArmed ? Colors.redAccent : Colors.cyanAccent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.motorcycle,
                        color: provider.isArmed ? Colors.redAccent : Colors.cyanAccent,
                        size: 24.0,
                      ),
                    ),
                  ),

                  // Geofence Center Pin Marker (shown when geofence is enabled)
                  if (provider.geofenceEnabled)
                    Marker(
                      point: LatLng(provider.geofenceLat, provider.geofenceLng),
                      width: 40.0,
                      height: 40.0,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                        size: 36.0,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Custom floating overlays for styling
          _buildFloatingHeader(provider),
          _buildFloatingSettingsButton(),
          _buildFloatingMapHUD(provider),

          // Slide-up Geofence configuration sheet
          if (_showGeofenceConfigPanel) _buildGeofenceConfigPanel(provider),
        ],
      ),
    );
  }

  Widget _buildFloatingHeader(MotorcycleProvider provider) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 72, // Space for settings toggle button
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: provider.isArmed ? Colors.redAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                provider.isArmed ? Icons.lock : Icons.lock_open,
                color: provider.isArmed ? Colors.redAccent : Colors.greenAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.isArmed ? 'GEOFENCE SENTRY: ARMED' : 'SENTRY SLEEP / BYPASS',
                    style: TextStyle(
                      color: provider.isArmed ? Colors.redAccent : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.geofenceEnabled
                        ? 'Geofence Active: ${provider.geofenceRadiusMeters.toInt()}m'
                        : 'Geofence Disabled',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingSettingsButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.redAccent,
        elevation: 4,
        onPressed: () {
          setState(() {
            _showGeofenceConfigPanel = !_showGeofenceConfigPanel;
          });
        },
        child: Icon(_showGeofenceConfigPanel ? Icons.close : Icons.tune),
      ),
    );
  }

  Widget _buildFloatingMapHUD(MotorcycleProvider provider) {
    final telemetry = provider.currentTelemetry;
    if (telemetry == null || _showGeofenceConfigPanel) return const SizedBox.shrink();

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildHudStat('SPEED', '${telemetry.speed.toStringAsFixed(1)}', 'km/h'),
            const VerticalDivider(color: Colors.white12, width: 20, thickness: 1),
            _buildHudStat('SATELLITES', '${telemetry.satellites}', 'fixed'),
            const VerticalDivider(color: Colors.white12, width: 20, thickness: 1),
            _buildHudStat('ARMED GEOFENCE', provider.isArmed && provider.geofenceEnabled ? '${provider.geofenceRadiusMeters.toInt()}m' : 'OFF', provider.isArmed ? 'radius' : 'bypass'),
          ],
        ),
      ),
    );
  }

  Widget _buildHudStat(String label, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
            Text(
              unit,
              style: const TextStyle(color: Colors.grey, fontSize: 9),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildGeofenceConfigPanel(MotorcycleProvider provider) {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'GEOFENCE BOUNDARY RADAR',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8),
                    ),
                  ],
                ),
                Switch(
                  value: provider.geofenceEnabled,
                  onChanged: (val) {
                    provider.updateGeofence(
                      provider.geofenceLat,
                      provider.geofenceLng,
                      provider.geofenceRadiusMeters,
                      val,
                    );
                  },
                  activeColor: Colors.amber,
                )
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Define a security perimeter. If the bike exits this radius while system is armed, an emergency alarms is triggered.',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Perimeter Radius:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text('${provider.geofenceRadiusMeters.toInt()} meters', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            Slider(
              value: provider.geofenceRadiusMeters,
              min: 50.0,
              max: 800.0,
              divisions: 15,
              activeColor: Colors.amberAccent,
              inactiveColor: Colors.white12,
              onChanged: provider.geofenceEnabled
                  ? (value) {
                      provider.updateGeofence(
                        provider.geofenceLat,
                        provider.geofenceLng,
                        value,
                        provider.geofenceEnabled,
                      );
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: provider.geofenceEnabled ? Colors.white10 : Colors.white.withOpacity(0.05),
                foregroundColor: provider.geofenceEnabled ? Colors.white : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.gps_fixed, size: 16),
              label: const Text('LOCK PERIMETER TO VEHICLE POSITION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: provider.geofenceEnabled
                  ? () async {
                      await provider.setGeofenceToCurrentPosition();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🔒 Geofence perimeter anchored to current vehicle position.'),
                          backgroundColor: Colors.amber,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
