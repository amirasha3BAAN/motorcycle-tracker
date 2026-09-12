# Real-Time Motorcycle Tracking and Anti-Theft Emergency System

An expert IoT & Mobile Monorepo architecture using ESP32, SIM7600G (4G/GPS), MPU6050, SW-420, Flutter, Node.js (TypeScript), EMQX, and Firebase.

---

## 1. Monorepo Repository Structure

```text
E:\MotorCycle_APP\
├── README.md               # Main architecture & design documentation
├── firmware\               # ESP32 + SIM7600G platformio / C++ firmware
│   ├── src\
│   │   └── main.cpp        # Firmware main logic, RTOS tasks, MPU6050 sampling
│   ├── include\
│   │   └── config.h        # Pin mapping, AT commands, MQTT credentials
│   ├── platformio.ini      # Library dependencies & build targets
│   └── test\
├── backend\                # Node.js / TypeScript subscriber & REST API
│   ├── src\
│   │   ├── index.ts        # Entry point initializing MQTT & Express
│   │   ├── config\         # Firebase, database, & env configuration
│   │   ├── mqtt\
│   │   │   └── listener.ts # MQTT subscription and ingestion worker
│   │   ├── models\         # DB / telemetry schema types
│   │   └── services\       # Firebase Realtime DB and geofence calculation
│   ├── package.json
│   ├── tsconfig.json
│   └── .env.example
└── mobile_app\             # Flutter (Dart) mobile client
    ├── pubspec.yaml
    └── lib\
        ├── main.dart       # Core entrypoint (Provider + Firebase setup)
        ├── core\           # Network, themes, utility functions (Geofencing)
        │   └── geofence.dart
        ├── data\           # API & Firebase Realtime DB streams
        │   └── repositories\
        ├── domain\         # Models & business rules
        │   └── models\
        └── presentation\   # UI Layers (Google Maps SDK & Status Dashboards)
            ├── screens\
            │   ├── dashboard_screen.dart
            │   └── map_screen.dart
            └── widgets\
```

---

## 2. JSON Payload Schemas

### A. Live Telemetry (`moto/telemetry/<device_id>`)
Emitted periodically (e.g., every 10 seconds) during movement.
```json
{
  "device_id": "MOTO-ESP32-98A7B6",
  "timestamp": 1791888000,
  "lat": 34.052234,
  "lng": -118.243684,
  "speed": 45.2,          // Speed in km/h
  "battery_v": 12.62,      // Main 12V motorcycle battery voltage
  "backup_battery_v": 4.15, // Backup internal LiPo battery voltage
  "rssi": -65,             // 4G LTE signal strength in dBm
  "satellites": 9,         // GPS satellites locked
  "status": "moving"       // "moving" | "idle" | "parked"
}
```

### B. Crash/Emergency Alert (`moto/alerts/<device_id>`)
Emitted immediately upon crash or theft shock detection. Bypasses standard telemetry timers.
```json
{
  "device_id": "MOTO-ESP32-98A7B6",
  "timestamp": 1791888005,
  "type": "CRASH",        // "CRASH" (fall/impact) | "THEFT_SHOCK" (unauthorized move)
  "g_force": 4.25,        // Peak accelerometer vector (G)
  "lean_angle": 78.5,     // MPU6050 estimated pitch/roll tilt angle
  "battery_v": 12.55,
  "lat": 34.052240,
  "lng": -118.243690
}
```

### C. Device Command (`moto/command/<device_id>`)
Subscribed by ESP32 to receive remote control commands from mobile.
```json
{
  "device_id": "MOTO-ESP32-98A7B6",
  "command": "ARM",       // "ARM" | "DISARM" | "PING" | "SIREN_ON" | "SIREN_OFF"
  "timestamp": 1791888010
}
```

---

## 3. Initial Project Setup Commands

### Setup Backend:
```bash
cd backend
npm init -y
npm install typescript @types/node ts-node mqtt firebase-admin dotenv express @types/express --save
npx tsc --init
```

### Setup Mobile App (Flutter):
```bash
cd ..
flutter create --org com.motorcycle.tracker mobile_app
cd mobile_app
flutter pub add google_maps_flutter firebase_core firebase_auth firebase_database firebase_messaging provider
```
