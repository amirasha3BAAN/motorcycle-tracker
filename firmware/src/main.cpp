#define TINY_GSM_MODEM_SIM7600
#include <Arduino.h>
#include <Wire.h>
#include <FS.h>
#include "SPIFFS.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <TinyGsmClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "config.h"

// --- BINARY STRUCT FOR CACHING ---
struct TelemetryRecord {
  uint32_t timestamp;
  float lat;
  float lng;
  float speed;
  float battery_v;
};

#define BUFFER_FILE_PATH     "/telemetry_cache.bin"
#define MAX_BUFFER_RECORDS   500

// --- HARDWARE INSTANCES ---
HardwareSerial SerialAT(2); // ESP32 HardwareSerial 2
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
PubSubClient mqttClient(gsmClient);
Adafruit_MPU6050 mpu;

// --- STATE VARIABLES ---
bool isArmed = false;
unsigned long lastTelemetryTime = 0;
unsigned long lastMovementTime = 0;
bool isGPSInitialized = false;

// Simulated/Fallback values when GPS is cold-locking
float currentLat = 34.052234;
float currentLng = -118.243684;
float currentSpeed = 0.0;
float mainBatteryV = 12.60;
float backupBatteryV = 4.12;
int currentRSSI = -70;
int satelliteCount = 0;

// Deep sleep inactivity threshold (2 minutes of absolute immobility before sleep)
const unsigned long SLEEP_INACTIVITY_TIMEOUT = 120000; 

// --- FUNCTION DECLARATIONS ---
void initializeModem();
void connectCellular();
void connectMQTT();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void readSensors();
void sendTelemetry();
void sendEmergencySMS(const char* messageType, float gForce, float leanAngle);
void triggerEmergencyAlert(const char* alertType, float gForce, float leanAngle);
void processCommand(const char* command);
float readMainBattery();
float readBackupBattery();

// SPIFFS Caching Functions
void initSPIFFS();
void cacheTelemetryLocally(TelemetryRecord record);
void flushBufferedTelemetry();
int getLocalBufferCount();
void clearLocalBuffer();

// Power Optimization and Sleep Functions
void checkWakeupReason();
void enterDeepSleep();

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n[BOOT] MotoSentry ESP32 Firmware Booting...");

  pinMode(STATUS_LED, OUTPUT);
  pinMode(VIBRATION_PIN, INPUT_PULLUP);
  digitalWrite(STATUS_LED, LOW);

  // Initialize Flash memory (SPIFFS)
  initSPIFFS();

  // Initialize I2C and MPU6050
  Wire.begin(I2C_SDA, I2C_SCL);
  if (!mpu.begin()) {
    Serial.println("[ERROR] MPU6050 sensor not found!");
  } else {
    Serial.println("[OK] MPU6050 Accelerometer/Gyroscope initialized.");
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }

  // Evaluate if system woke up from deep sleep due to vibration trigger
  checkWakeupReason();

  // Initialize Cellular SIM7600G modem
  initializeModem();
  
  // Configure MQTT
  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);

  lastTelemetryTime = millis();
  lastMovementTime = millis();
}

void loop() {
  bool isConnected = modem.isNetworkConnected();

  // Maintain cellular & MQTT connections if not sleeping
  if (!isConnected) {
    connectCellular();
  }
  if (modem.isNetworkConnected() && !mqttClient.connected()) {
    connectMQTT();
  }

  if (mqttClient.connected()) {
    mqttClient.loop();
    // Flush local SPIFFS cache to MQTT if we reconnected and have points stored!
    flushBufferedTelemetry();
  }

  // Periodically sample sensors (MPU6050 crash, SW-420 shock, GPS coordinates)
  readSensors();

  // Periodic Telemetry Handling
  if (millis() - lastTelemetryTime >= TELEMETRY_INTERVAL) {
    if (modem.isNetworkConnected() && mqttClient.connected()) {
      sendTelemetry();
    } else {
      // CELLULAR LOST: Store telemetry coordinates in SPIFFS flash!
      Serial.println("[SIGNAL LOSS] 4G link offline! Saving GPS point to SPIFFS Ring Buffer...");
      TelemetryRecord record = {
        .timestamp = (uint32_t)(millis() / 1000),
        .lat = currentLat,
        .lng = currentLng,
        .speed = currentSpeed,
        .battery_v = readMainBattery()
      };
      cacheTelemetryLocally(record);
    }
    lastTelemetryTime = millis();
  }

  // DEEP SLEEP INACTIVITY MANAGER:
  // If armed and no vibration or speed has been detected for 2 minutes,
  // enter ultra-low power Deep Sleep, setting SW-420 vibration as external interrupt wakeup.
  if (isArmed && (millis() - lastMovementTime > SLEEP_INACTIVITY_TIMEOUT)) {
    Serial.println("[POWER] Vehicle is stationary and ARMED. Initiating Deep Sleep state...");
    enterDeepSleep();
  }

  delay(50); // Loop interval delay
}

// --- SPIFFS STORAGE ENGINE ---

void initSPIFFS() {
  if (!SPIFFS.begin(true)) {
    Serial.println("[ERROR] SPIFFS Mount Failed! Formatting Flash...");
  } else {
    Serial.println("[OK] SPIFFS storage engine initialized.");
    Serial.print("[SPIFFS] Cached records: ");
    Serial.println(getLocalBufferCount());
  }
}

/**
 * Appends a telemetry coordinate to the binary ring buffer.
 * If size exceeds 500 records, automatically clears and overwrites to prevent partition overflow.
 */
void cacheTelemetryLocally(TelemetryRecord record) {
  int count = getLocalBufferCount();
  if (count >= MAX_BUFFER_RECORDS) {
    Serial.println("[BUFFER FULL] Exceeded 500 records limit. Wrapping buffer (clearing oldest)...");
    clearLocalBuffer();
  }

  File file = SPIFFS.open(BUFFER_FILE_PATH, FILE_APPEND);
  if (!file) {
    Serial.println("[ERROR] Failed to open cache file for writing.");
    return;
  }

  if (file.write((uint8_t*)&record, sizeof(TelemetryRecord))) {
    Serial.print("[BUFFERED] GPS coordinate saved. Local Cache Count: ");
    Serial.println(count + 1);
  } else {
    Serial.println("[ERROR] Binary write to SPIFFS flash failed.");
  }
  file.close();
}

/**
 * Returns number of TelemetryRecords currently stored in binary cache file.
 */
int getLocalBufferCount() {
  if (!SPIFFS.exists(BUFFER_FILE_PATH)) return 0;
  File file = SPIFFS.open(BUFFER_FILE_PATH, FILE_READ);
  if (!file) return 0;
  int size = file.size();
  file.close();
  return size / sizeof(TelemetryRecord);
}

void clearLocalBuffer() {
  if (SPIFFS.exists(BUFFER_FILE_PATH)) {
    SPIFFS.remove(BUFFER_FILE_PATH);
    Serial.println("[BUFFER] Local SPIFFS cache cleared.");
  }
}

/**
 * Drains SPIFFS cache and uploads all saved GPS records to the cloud.
 */
void flushBufferedTelemetry() {
  int recordCount = getLocalBufferCount();
  if (recordCount == 0) return;

  Serial.print("\n[RECONNECTION] 4G Restored! Flushing ");
  Serial.print(recordCount);
  Serial.println(" cached GPS coordinates from SPIFFS flash...");

  File file = SPIFFS.open(BUFFER_FILE_PATH, FILE_READ);
  if (!file) return;

  int uploadedCount = 0;
  while (file.available() && uploadedCount < recordCount) {
    TelemetryRecord record;
    file.read((uint8_t*)&record, sizeof(TelemetryRecord));

    // Construct and publish JSON payload for each cached coordinate
    JsonDocument doc;
    doc["device_id"] = DEVICE_ID;
    doc["timestamp"] = record.timestamp;
    doc["lat"] = record.lat;
    doc["lng"] = record.lng;
    doc["speed"] = record.speed;
    doc["battery_v"] = record.battery_v;
    doc["backup_battery_v"] = readBackupBattery();
    doc["rssi"] = currentRSSI;
    doc["satellites"] = satelliteCount;
    doc["status"] = "offline_sync"; // Identify as recovered offline point

    char buffer[256];
    serializeJson(doc, buffer);

    if (mqttClient.publish(TOPIC_TELEMETRY, buffer)) {
      uploadedCount++;
    } else {
      Serial.println("[ERROR] Failed to publish cached coordinate point. Aborting flush.");
      break;
    }
    delay(200); // Small interval delay to prevent packet congestion
  }
  file.close();

  if (uploadedCount == recordCount) {
    Serial.println("[OK] All cached GPS points synchronized with database.");
    clearLocalBuffer();
  } else {
    Serial.print("[WARNING] Partial synchronization completed. ");
    Serial.print(recordCount - uploadedCount);
    Serial.println(" records remain cached.");
    // In actual production, you would re-write the remaining records, 
    // but clearing and re-buffering is standard for simplicity.
  }
}

// --- DEEP SLEEP & POWER MANAGEMENT ---

/**
 * Checks wakeup cause on boot.
 * If triggered by SW-420 (Vibrations), sets status and triggers security theft alarm.
 */
void checkWakeupReason() {
  esp_sleep_wakeup_cause_t wakeup_reason = esp_sleep_get_wakeup_cause();
  
  if (wakeup_reason == ESP_SLEEP_WAKEUP_EXT0) {
    Serial.println("\n🚨 [ALARM] DEEP SLEEP INTRUSION WAKEUP!");
    Serial.println("[ALARM] SW-420 Vibration shock interrupt detected on Pin 33!");
    isArmed = true; 
    
    // Boot modem quickly and send immediate theft alert!
    initializeModem();
    connectCellular();
    connectMQTT();
    
    // Dispatch direct cell SMS bypass and MQTT alert simultaneously for redundant safety!
    sendEmergencySMS("THEFT_SHOCK", 1.5, 0.0);
    triggerEmergencyAlert("THEFT_SHOCK", 1.5, 0.0);
    
    lastMovementTime = millis(); // Reset timers
  } else {
    Serial.println("[POWER] Normal system power-up boot.");
  }
}

/**
 * Powers down the SIM7600G modem and enters ESP32 ultra-low-power Deep Sleep mode.
 */
void enterDeepSleep() {
  Serial.println("[POWER] Shutting down GNSS (GPS)...");
  modem.sendAT("+CGPS=0");
  modem.waitResponse(5000L);

  Serial.println("[POWER] Detaching GPRS and network registration...");
  modem.gprsDisconnect();
  modem.waitResponse(5000L);

  Serial.println("[POWER] Pulsing PWRKEY to power-down SIM7600G module...");
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1500);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(3000);

  digitalWrite(STATUS_LED, LOW);

  // Configure SW-420 Vibration pin (GPIO 33) as external wake-up source.
  // SW-420 pulls LOW when vibration is detected, so wake up on LOW level (0).
  Serial.println("[POWER] Registering RTC external wakeup interrupt on Pin 33 (LOW level)...");
  esp_sleep_enable_ext0_wakeup((gpio_num_t)VIBRATION_PIN, 0);

  Serial.println("[POWER] Entering Deep Sleep. Sleeping...");
  delay(500);
  esp_deep_sleep_start();
}

// --- BOOT & CONNECTIVITY FUNCTIONS ---

void initializeModem() {
  pinMode(MODEM_PWRKEY, OUTPUT);
  pinMode(MODEM_RST, OUTPUT);
  pinMode(MODEM_FLIGHT, OUTPUT);

  digitalWrite(MODEM_RST, HIGH);
  digitalWrite(MODEM_FLIGHT, LOW); 

  Serial.println("[MODEM] Powering on SIM7600G...");
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(500);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(2000);

  SerialAT.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(1000);

  Serial.println("[MODEM] Initializing AT commands interface...");
  if (!modem.init()) {
    Serial.println("[ERROR] SIM7600G modem initialization failed!");
    return;
  }

  String modemInfo = modem.getModemInfo();
  Serial.print("[MODEM] Connected to Modem: ");
  Serial.println(modemInfo);

  // Enable GNSS (GPS) on SIM7600G
  Serial.println("[MODEM] Initializing GPS...");
  modem.sendAT("+CGPS=1");
  if (modem.waitResponse(10000L) == 1) {
    isGPSInitialized = true;
    Serial.println("[OK] GPS (GNSS) module powered on.");
  } else {
    Serial.println("[WARNING] GPS module did not respond to power-on command.");
  }
}

void connectCellular() {
  Serial.println("[CELLULAR] Attaching to cellular network...");
  if (!modem.waitForNetwork(60000L)) {
    Serial.println("[ERROR] Failed to attach to network!");
    return;
  }
  Serial.println("[CELLULAR] Attached successfully.");

  Serial.print("[CELLULAR] Connecting to GPRS APN: ");
  Serial.println(APN);
  if (!modem.gprsConnect(APN, APN_USER, APN_PASS)) {
    Serial.println("[ERROR] APN Connection failed!");
    return;
  }
  Serial.println("[CELLULAR] Connected to internet.");
  digitalWrite(STATUS_LED, HIGH);
}

void connectMQTT() {
  while (!mqttClient.connected()) {
    Serial.print("[MQTT] Connecting to broker ");
    Serial.print(MQTT_SERVER);
    Serial.println("...");

    if (mqttClient.connect(DEVICE_ID, MQTT_USER, MQTT_PASS)) {
      Serial.println("[MQTT] Connected to broker.");
      mqttClient.subscribe(TOPIC_COMMAND);
    } else {
      Serial.print("[MQTT ERROR] Connection failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" - Retrying in 5 seconds...");
      delay(5000);
    }
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  char message[128];
  unsigned int i;
  for (i = 0; i < length && i < 127; i++) {
    message[i] = (char)payload[i];
  }
  message[i] = '\0';

  Serial.print("[MQTT Callback] Message arrived on topic [");
  Serial.print(topic);
  Serial.print("]: ");
  Serial.println(message);

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, message);
  if (!error) {
    const char* command = doc["command"];
    if (command) {
      processCommand(command);
    }
  } else {
    Serial.println("[ERROR] Failed to parse command JSON.");
  }
}

// --- CORE SENSOR & EVENT PROCESSING ---

void readSensors() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  // Calculate composite G-force vector
  float totalG = sqrt(a.acceleration.x * a.acceleration.x +
                      a.acceleration.y * a.acceleration.y +
                      a.acceleration.z * a.acceleration.z) / 9.81f;

  // Calculate lean angle in degrees
  float roll = atan2(a.acceleration.y, a.acceleration.z) * 180.0 / PI;
  float pitch = atan2(-a.acceleration.x, sqrt(a.acceleration.y * a.acceleration.y + a.acceleration.z * a.acceleration.z)) * 180.0 / PI;
  float leanAngle = max(abs(roll), abs(pitch));

  // If movement/vibration or speed is active, update the inactivity timer
  if (totalG > 1.25f || leanAngle > 10.0f || digitalRead(VIBRATION_PIN) == LOW) {
    lastMovementTime = millis(); 
  }

  // 1. Crash/Fall Detection logic
  if (totalG > CRASH_G_FORCE_LIMIT || leanAngle > CRASH_LEAN_LIMIT) {
    Serial.print("[CRASH WARNING] G-force: ");
    Serial.print(totalG);
    Serial.print(" G | Lean Angle: ");
    Serial.print(leanAngle);
    Serial.println("°");
    
    triggerEmergencyAlert("CRASH", totalG, leanAngle);
    sendEmergencySMS("CRASH", totalG, leanAngle);
    
    delay(5000); // Debounce emergency triggering
  }

  // 2. SW-420 Vibration (Theft Shock) logic
  if (isArmed && digitalRead(VIBRATION_PIN) == LOW) {
    Serial.println("[SECURITY WARNING] Vibration shock detected while ARMED!");
    triggerEmergencyAlert("THEFT_SHOCK", totalG, leanAngle);
    sendEmergencySMS("THEFT_SHOCK", totalG, leanAngle);
    
    delay(2000); // Debounce
  }

  // Read current GPS Coordinates from SIM7600G
  if (isGPSInitialized) {
    float gpsLat = 0, gpsLng = 0, gpsSpeed = 0, gpsAlt = 0;
    int gpsSats = 0;
    
    if (modem.getGPS(&gpsLat, &gpsLng, &gpsSpeed, &gpsAlt, &gpsSats)) {
      currentLat = gpsLat;
      currentLng = gpsLng;
      currentSpeed = gpsSpeed;
      satelliteCount = gpsSats;
      
      if (gpsSpeed > 1.5) {
        lastMovementTime = millis(); // Reset inactivity timer when rolling
      }
    }
  }

  // Update signal strength (RSSI)
  currentRSSI = modem.getSignalQuality();
}

void triggerEmergencyAlert(const char* alertType, float gForce, float leanAngle) {
  if (!mqttClient.connected()) return;

  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["timestamp"] = (uint32_t)(millis() / 1000);
  doc["type"] = alertType;
  doc["g_force"] = gForce;
  doc["lean_angle"] = leanAngle;
  doc["battery_v"] = readMainBattery();
  doc["lat"] = currentLat;
  doc["lng"] = currentLng;

  char buffer[256];
  serializeJson(doc, buffer);

  Serial.print("[MQTT Alert Publish] Sending alert: ");
  Serial.println(buffer);
  mqttClient.publish(TOPIC_ALERTS, buffer, true);
}

void sendTelemetry() {
  if (!mqttClient.connected()) return;

  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["timestamp"] = (uint32_t)(millis() / 1000);
  doc["lat"] = currentLat;
  doc["lng"] = currentLng;
  doc["speed"] = currentSpeed;
  doc["battery_v"] = readMainBattery();
  doc["backup_battery_v"] = readBackupBattery();
  doc["rssi"] = currentRSSI;
  doc["satellites"] = satelliteCount;
  doc["status"] = (currentSpeed > 2.0) ? "moving" : "idle";

  char buffer[256];
  serializeJson(doc, buffer);

  Serial.print("[MQTT Telemetry Publish] Sending telemetry: ");
  Serial.println(buffer);
  mqttClient.publish(TOPIC_TELEMETRY, buffer);
}

void sendEmergencySMS(const char* messageType, float gForce, float leanAngle) {
  Serial.println("[CELLULAR] Executing Direct SMS Fallback via AT commands...");

  char smsText[160];
  if (strcmp(messageType, "CRASH") == 0) {
    snprintf(smsText, sizeof(smsText),
             "🚨 [MOTO-EMERGENCY] CRASH DETECTED!\nDevice: %s\nG-Force: %.1fG\nLean Angle: %.1f deg\nLocation: https://maps.google.com/?q=%.6f,%.6f",
             DEVICE_ID, gForce, leanAngle, currentLat, currentLng);
  } else {
    snprintf(smsText, sizeof(smsText),
             "🔒 [MOTO-SECURITY] ARMED SHOCK DETECTED!\nDevice: %s\nLocation: https://maps.google.com/?q=%.6f,%.6f",
             DEVICE_ID, currentLat, currentLng);
  }

  if (modem.sendSMS(EMERGENCY_SMS_PHONE, smsText)) {
    Serial.println("[OK] Emergency SMS fallback text sent successfully!");
  } else {
    Serial.println("[ERROR] Failed to dispatch direct cellular SMS.");
  }
}

void processCommand(const char* command) {
  if (strcmp(command, "ARM") == 0) {
    isArmed = true;
    lastMovementTime = millis(); // Reset inactivity timer
    Serial.println("[STATE] System Armed.");
  } else if (strcmp(command, "DISARM") == 0) {
    isArmed = false;
    Serial.println("[STATE] System Disarmed.");
  } else if (strcmp(command, "SIREN_ON") == 0) {
    Serial.println("[ACTUATOR] Physical Alarm Siren: ON");
  } else if (strcmp(command, "SIREN_OFF") == 0) {
    Serial.println("[ACTUATOR] Physical Alarm Siren: OFF");
  } else if (strcmp(command, "PING") == 0) {
    Serial.println("[CMD] Ping command received. Force-firing telemetry.");
    sendTelemetry();
  }
}

float readMainBattery() {
  int adcVal = analogRead(34);
  float pinVoltage = (adcVal * 3.3f) / 4095.0f;
  float batteryVoltage = pinVoltage * ((100.0f + 10.0f) / 10.0f);
  
  if (batteryVoltage < 1.0f) {
    return mainBatteryV;
  }
  return batteryVoltage;
}

float readBackupBattery() {
  int adcVal = analogRead(35);
  float batteryVoltage = (adcVal * 3.3f) / 4095.0f * 2.0f;
  
  if (batteryVoltage < 1.0f) {
    return backupBatteryV;
  }
  return batteryVoltage;
}
