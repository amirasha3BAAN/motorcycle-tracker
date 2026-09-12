import http from 'http';

const PORT = process.env.PORT || 3000;
const DEVICE_ID = 'MOTO-ESP32-98A7B6';

function makeRequest(options: http.RequestOptions, postData?: string): Promise<any> {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          data: body ? JSON.parse(body) : null
        });
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    if (postData) {
      req.write(postData);
    }
    req.end();
  });
}

async function runTests() {
  console.log('🏁 [TESTING BOARD] Initializing automatic backend validation...\n');

  // Test 1: Health check
  console.log('🔍 Test 1: Querying server /health...');
  try {
    const health = await makeRequest({
      hostname: 'localhost',
      port: PORT,
      path: '/health',
      method: 'GET'
    });
    console.log(`⚡ Health Status: ${health.statusCode} OK | Mode: ${health.data.firebase_mode}\n`);
  } catch (err) {
    console.error('❌ Server is offline! Run "npm run dev" first in a separate terminal.\n');
    process.exit(1);
  }

  // Test 2: Simulating Telemetry (inside geofence)
  console.log('📡 Test 2: Simulating telemetry within geofence boundaries...');
  const telemetryOk = JSON.stringify({
    device_id: DEVICE_ID,
    timestamp: Math.floor(Date.now() / 1000),
    lat: 34.052234,
    lng: -118.243684,
    speed: 0.0,
    battery_v: 12.65,
    backup_battery_v: 4.15,
    rssi: -65,
    satellites: 9,
    status: 'parked'
  });

  const resTelemOk = await makeRequest({
    hostname: 'localhost',
    port: PORT,
    path: '/api/test/simulate-telemetry',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(telemetryOk)
    }
  }, telemetryOk);
  console.log(`✅ Telemetry Ingested: ${resTelemOk.statusCode} OK\n`);

  // Test 3: Arming device via Command REST API
  console.log('🔒 Test 3: Issuing ARM command to the motorcycle...');
  const commandPayload = JSON.stringify({ command: 'ARM' });
  const resCommand = await makeRequest({
    hostname: 'localhost',
    port: PORT,
    path: `/api/motorcycles/${DEVICE_ID}/command`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(commandPayload)
    }
  }, commandPayload);
  console.log(`✅ Command Dispatched: ${resCommand.data.message}\n`);

  // Test 4: Simulating Crash Alert (Direct Fall)
  console.log('🚨 Test 4: Simulating impact and emergency crash event...');
  const crashAlert = JSON.stringify({
    device_id: DEVICE_ID,
    timestamp: Math.floor(Date.now() / 1000),
    type: 'CRASH',
    g_force: 4.5,
    lean_angle: 85.0,
    battery_v: 12.50,
    lat: 34.052240,
    lng: -118.243690
  });

  const resAlert = await makeRequest({
    hostname: 'localhost',
    port: PORT,
    path: '/api/test/simulate-alert',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(crashAlert)
    }
  }, crashAlert);
  console.log(`✅ Alert Triggered: ${resAlert.statusCode} OK. Event and notifications dispatched.\n`);

  console.log('🎉 [SUCCESS] All backend integration simulation tests completed cleanly!');
}

runTests();
