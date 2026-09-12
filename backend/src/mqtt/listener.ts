import * as mqtt from 'mqtt';
import * as dotenv from 'dotenv';
import { saveTelemetry, saveAlert } from '../services/dbService';
import { TelemetryPayload, AlertPayload, CommandPayload } from '../models/schemas';

dotenv.config();

const brokerUrl = process.env.MQTT_BROKER_URL || 'mqtt://broker.hivemq.com:1883';
const clientId = process.env.MQTT_CLIENT_ID || `motorcycle_backend_${Math.random().toString(16).substring(2, 10)}`;

let client: mqtt.MqttClient | null = null;

export function initializeMQTT(): mqtt.MqttClient {
  console.log(`[MQTT] Connecting to broker: ${brokerUrl}`);
  
  client = mqtt.connect(brokerUrl, {
    clientId,
    username: process.env.MQTT_USERNAME || undefined,
    password: process.env.MQTT_PASSWORD || undefined,
    clean: true,
    reconnectPeriod: 5000 // Retry every 5 seconds
  });

  client.on('connect', () => {
    console.log('[MQTT] Connected successfully to MQTT Broker.');

    // Subscribe to wildcard topics to support multiple motorcycles out-of-the-box
    const topics = ['moto/telemetry/+', 'moto/alerts/+'];
    client?.subscribe(topics, (err) => {
      if (err) {
        console.error('[MQTT] Subscription error:', err);
      } else {
        console.log(`[MQTT] Subscribed to topics: ${topics.join(', ')}`);
      }
    });
  });

  client.on('message', async (topic, message) => {
    const rawPayload = message.toString();
    console.log(`\n[MQTT Message Received] Topic: ${topic}`);
    console.log(`[MQTT Message Received] Raw Payload: ${rawPayload}`);

    try {
      const parsedData = JSON.parse(rawPayload);

      if (topic.startsWith('moto/telemetry/')) {
        const telemetry: TelemetryPayload = parsedData;
        
        // Basic schema verification
        if (!telemetry.device_id || typeof telemetry.lat !== 'number' || typeof telemetry.lng !== 'number') {
          throw new Error('Invalid telemetry schema: device_id, lat, or lng is missing/invalid.');
        }

        await saveTelemetry(telemetry);

      } else if (topic.startsWith('moto/alerts/')) {
        const alert: AlertPayload = parsedData;

        // Basic schema verification
        if (!alert.device_id || !alert.type || typeof alert.lat !== 'number' || typeof alert.lng !== 'number') {
          throw new Error('Invalid alert schema: device_id, type, lat, or lng is missing/invalid.');
        }

        await saveAlert(alert);
      } else {
        console.warn(`[MQTT] Unhandled topic: ${topic}`);
      }
    } catch (err) {
      console.error(`[MQTT Error] Failed to process message on topic "${topic}":`, (err as Error).message);
    }
  });

  client.on('error', (error) => {
    console.error('[MQTT Error] Broker error:', error);
  });

  client.on('offline', () => {
    console.warn('[MQTT] Client went offline.');
  });

  client.on('reconnect', () => {
    console.log('[MQTT] Reconnecting...');
  });

  return client;
}

/**
 * Publishes an action command down to the ESP32 firmware.
 */
export function sendCommand(deviceId: string, command: CommandPayload['command']): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!client || !client.connected) {
      return reject(new Error('MQTT client is not connected. Cannot dispatch command.'));
    }

    const topic = `moto/command/${deviceId}`;
    const payload: CommandPayload = {
      device_id: deviceId,
      command,
      timestamp: Math.floor(Date.now() / 1000)
    };

    const messageString = JSON.stringify(payload);
    console.log(`[MQTT Publish] Topic: ${topic} | Command: ${command}`);

    client.publish(topic, messageString, { qos: 1 }, (err) => {
      if (err) {
        console.error(`[MQTT Publish Error] Failed to publish to ${topic}:`, err);
        return reject(err);
      }
      resolve();
    });
  });
}
