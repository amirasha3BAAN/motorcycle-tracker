import express from 'express';
import { createServer } from 'http';
import * as dotenv from 'dotenv';
import cors from 'cors';
import { initializeMQTT, sendCommand } from './mqtt/listener';
import { saveTelemetry, saveAlert } from './services/dbService';
import { initializeWebSockets, getDatabase } from './config/firebase';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Create native HTTP server and attach Express
const server = createServer(app);

// Boot WebSockets on the same HTTP port
initializeWebSockets(server);

// Boot MQTT Listener
initializeMQTT();

/**
 * REST Endpoint to get the complete real-time status of a motorcycle
 */
app.get('/api/motorcycles/:deviceId/status', async (req, res) => {
  const { deviceId } = req.params;
  const db = getDatabase();

  try {
    const telemetrySnap = await db.ref(`motorcycles/${deviceId}/telemetry/current`).once('value');
    const alertSnap = await db.ref(`motorcycles/${deviceId}/alerts/latest`).once('value');
    const stateSnap = await db.ref(`motorcycles/${deviceId}/state`).once('value');
    const geofenceSnap = await db.ref(`motorcycles/${deviceId}/geofence`).once('value');

    // Default states if nodes do not exist yet
    const telemetry = telemetrySnap.exists() ? telemetrySnap.val() : null;
    const alert = alertSnap.exists() ? alertSnap.val() : null;
    const state = stateSnap.exists() ? stateSnap.val() : { armed: false };
    const geofence = geofenceSnap.exists() ? geofenceSnap.val() : {
      lat: 34.052234,
      lng: -118.243684,
      radius_meters: 150.0,
      enabled: true
    };

    return res.status(200).json({
      device_id: deviceId,
      telemetry,
      latest_alert: alert,
      state,
      geofence
    });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * REST Endpoint to retrieve historical telemetry for map trails/breadcrumbs
 */
app.get('/api/motorcycles/:deviceId/telemetry/history', async (req, res) => {
  const { deviceId } = req.params;
  const db = getDatabase();

  try {
    const historySnap = await db.ref(`motorcycles/${deviceId}/telemetry/history`).once('value');
    let historyList: any[] = [];

    if (historySnap.exists()) {
      const val = historySnap.val();
      // If it's stored as an object (standard push keys), convert to a sorted array
      if (typeof val === 'object') {
        historyList = Object.keys(val).map(key => val[key]);
      } else if (Array.isArray(val)) {
        historyList = val;
      }
    }

    return res.status(200).json({
      device_id: deviceId,
      history: historyList
    });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * REST Endpoint to update the armed state (e.g. from the Flutter App)
 */
app.post('/api/motorcycles/:deviceId/arm', async (req, res) => {
  const { deviceId } = req.params;
  const { armed } = req.body;

  if (typeof armed !== 'boolean') {
    return res.status(400).json({ error: 'Armed parameter must be a boolean.' });
  }

  const db = getDatabase();
  try {
    await db.ref(`motorcycles/${deviceId}/state`).update({ armed });
    return res.status(200).json({ message: `Armed status updated to ${armed}` });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * REST Endpoint to update the geofence config (e.g. from the Flutter App)
 */
app.post('/api/motorcycles/:deviceId/geofence', async (req, res) => {
  const { deviceId } = req.params;
  const { lat, lng, radius_meters, enabled } = req.body;

  const db = getDatabase();
  try {
    const currentGeofenceSnap = await db.ref(`motorcycles/${deviceId}/geofence`).once('value');
    const existing = currentGeofenceSnap.exists() ? currentGeofenceSnap.val() : {};

    const updated = {
      lat: typeof lat === 'number' ? lat : (existing.lat ?? 34.052234),
      lng: typeof lng === 'number' ? lng : (existing.lng ?? -118.243684),
      radius_meters: typeof radius_meters === 'number' ? radius_meters : (existing.radius_meters ?? 150.0),
      enabled: typeof enabled === 'boolean' ? enabled : (existing.enabled ?? true)
    };

    await db.ref(`motorcycles/${deviceId}/geofence`).set(updated);
    return res.status(200).json({
      message: 'Geofence configurations successfully updated.',
      geofence: updated
    });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * REST Endpoint to dispatch commands to ESP32 (e.g. ARM, DISARM, PING, SIREN_ON, SIREN_OFF)
 */
app.post('/api/motorcycles/:deviceId/command', async (req, res) => {
  const { deviceId } = req.params;
  const { command } = req.body;

  if (!command || !['ARM', 'DISARM', 'PING', 'SIREN_ON', 'SIREN_OFF'].includes(command)) {
    return res.status(400).json({
      error: 'Invalid or missing command. Must be ARM, DISARM, PING, SIREN_ON, or SIREN_OFF'
    });
  }

  try {
    await sendCommand(deviceId, command);

    // Also automatically align our local DB state for ARM / DISARM
    if (command === 'ARM' || command === 'DISARM') {
      const db = getDatabase();
      await db.ref(`motorcycles/${deviceId}/state`).update({ armed: command === 'ARM' });
    }

    return res.status(200).json({
      message: `Command "${command}" successfully dispatched to topic: moto/command/${deviceId}`
    });
  } catch (err) {
    return res.status(500).json({
      error: `Failed to dispatch command: ${(err as Error).message}`
    });
  }
});

/**
 * TEST/SIMULATOR ENDPOINT: Simulates a Telemetry message over HTTP.
 * Useful for validating the pipeline, geofencing, and database operations.
 */
app.post('/api/test/simulate-telemetry', async (req, res) => {
  const telemetryPayload = req.body;
  
  if (!telemetryPayload.device_id || typeof telemetryPayload.lat !== 'number' || typeof telemetryPayload.lng !== 'number') {
    return res.status(400).json({ error: 'Missing device_id, lat, or lng.' });
  }

  try {
    await saveTelemetry(telemetryPayload);
    return res.status(200).json({
      message: 'Telemetry simulated successfully.',
      data: telemetryPayload
    });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * TEST/SIMULATOR ENDPOINT: Simulates a Crash/Emergency Alert over HTTP.
 */
app.post('/api/test/simulate-alert', async (req, res) => {
  const alertPayload = req.body;
  
  if (!alertPayload.device_id || !alertPayload.type || typeof alertPayload.lat !== 'number') {
    return res.status(400).json({ error: 'Missing device_id, type, or lat/lng.' });
  }

  try {
    await saveAlert(alertPayload);
    return res.status(200).json({
      message: 'Alert simulated successfully and notification triggered.',
      data: alertPayload
    });
  } catch (err) {
    return res.status(500).json({ error: (err as Error).message });
  }
});

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    firebase_mode: 'LOCAL_STANDALONE_WS_AND_JSON'
  });
});

server.listen(port, () => {
  console.log(`[HTTP Server] Running on port ${port}`);
  console.log(`[HTTP Server] Health check: http://localhost:${port}/health`);
});
