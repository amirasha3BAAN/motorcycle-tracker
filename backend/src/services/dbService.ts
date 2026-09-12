import { getDatabase, sendPushNotification } from '../config/firebase';
import { TelemetryPayload, AlertPayload } from '../models/schemas';
import { isGeofenceBreached, GeofenceConfig } from './geofenceService';

/**
 * Persists live telemetry data.
 * Updates current status and appends to a light history node.
 */
export async function saveTelemetry(payload: TelemetryPayload): Promise<void> {
  const db = getDatabase();
  const deviceId = payload.device_id;

  // 1. Update the 'current' telemetry for real-time Flutter subscribers
  await db.ref(`motorcycles/${deviceId}/telemetry/current`).set({
    ...payload,
    server_timestamp: Date.now()
  });

  // 2. Also record in historical log for route tracing
  const historyRef = db.ref(`motorcycles/${deviceId}/telemetry/history`);
  await historyRef.push().set({
    lat: payload.lat,
    lng: payload.lng,
    speed: payload.speed,
    timestamp: payload.timestamp
  });

  console.log(`[DB] Telemetry stored for device ${deviceId}`);

  // 3. Perform geofencing validation
  await checkGeofence(payload);
}

/**
 * Saves emergency/crash alerts, updates latest alert state, and triggers an FCM push notification.
 */
export async function saveAlert(payload: AlertPayload): Promise<void> {
  const db = getDatabase();
  const deviceId = payload.device_id;

  // 1. Update the 'latest' alert node
  await db.ref(`motorcycles/${deviceId}/alerts/latest`).set({
    ...payload,
    server_timestamp: Date.now()
  });

  // 2. Push to alerts history
  await db.ref(`motorcycles/${deviceId}/alerts/history`).push().set(payload);

  console.log(`[DB] Alert persisted for device ${deviceId}: ${payload.type}`);

  // 3. Trigger immediate FCM Push Notification
  let title = '⚠️ EMERGENCY ALERT';
  let body = `Motorcycle ${deviceId} reported an alert.`;

  if (payload.type === 'CRASH') {
    title = '🚨 CRASH DETECTED';
    body = `A severe crash/fall was detected! Peak: ${payload.g_force}G, Lean: ${payload.lean_angle}°. Immediate action required!`;
  } else if (payload.type === 'THEFT_SHOCK') {
    title = '🔒 SECURITY ALERT: VIBRATION DETECTED';
    body = `Vibration detected on motorcycle ${deviceId} while armed. Check vehicle immediately!`;
  }

  await sendPushNotification({
    title,
    body,
    topic: `alerts_${deviceId}`
  });
}

/**
 * Internal helper to retrieve armed status and geofencing configuration,
 * validating against current telemetry coordinate.
 */
async function checkGeofence(telemetry: TelemetryPayload): Promise<void> {
  const db = getDatabase();
  const deviceId = telemetry.device_id;

  // Read armed state & geofence configuration
  const stateSnapshot = await db.ref(`motorcycles/${deviceId}/state`).once('value');
  const geofenceSnapshot = await db.ref(`motorcycles/${deviceId}/geofence`).once('value');

  if (!stateSnapshot.exists()) {
    // If state doesn't exist, initialize default state (unarmed)
    await db.ref(`motorcycles/${deviceId}/state`).set({ armed: false });
    return;
  }

  const state = stateSnapshot.val();
  const isArmed = state.armed === true;

  if (isArmed && geofenceSnapshot.exists()) {
    const config: GeofenceConfig = geofenceSnapshot.val();
    
    if (config.enabled && isGeofenceBreached(telemetry.lat, telemetry.lng, config)) {
      console.warn(`[GEOFENCE] BREACH DETECTED for device ${deviceId}!`);
      
      // Trigger a THEFT_SHOCK alert since motorcycle is moving away from geofence while armed
      const alertPayload: AlertPayload = {
        device_id: deviceId,
        timestamp: telemetry.timestamp,
        type: 'THEFT_SHOCK',
        g_force: 1.0, // GPS movement driven
        lean_angle: 0,
        battery_v: telemetry.battery_v,
        lat: telemetry.lat,
        lng: telemetry.lng
      };

      // To prevent constant alert flood, you'd typically rate-limit this. We will save it directly.
      await saveAlert(alertPayload);
    }
  }
}
