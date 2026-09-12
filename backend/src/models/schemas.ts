export interface TelemetryPayload {
  device_id: string;
  timestamp: number;
  lat: number;
  lng: number;
  speed: number;          // Speed in km/h
  battery_v: number;      // Main 12V motorcycle battery voltage
  backup_battery_v: number; // Backup internal LiPo battery voltage
  rssi: number;             // 4G LTE signal strength in dBm
  satellites: number;       // GPS satellites locked
  status: 'moving' | 'idle' | 'parked';
}

export interface AlertPayload {
  device_id: string;
  timestamp: number;
  type: 'CRASH' | 'THEFT_SHOCK';
  g_force: number;        // Peak accelerometer vector (G)
  lean_angle: number;     // Estimated pitch/roll angle (degrees)
  battery_v: number;
  lat: number;
  lng: number;
}

export interface CommandPayload {
  device_id: string;
  command: 'ARM' | 'DISARM' | 'PING' | 'SIREN_ON' | 'SIREN_OFF';
  timestamp: number;
}
