#ifndef CONFIG_H
#define CONFIG_H

// --- HARDWARE PIN MAPPING ---
// SIM7600G Hardware Serial Connections
#define MODEM_RX             26
#define MODEM_TX             27
#define MODEM_RST            5
#define MODEM_PWRKEY         4
#define MODEM_FLIGHT         25

// SW-420 Vibration Sensor
#define VIBRATION_PIN        33  // Must support external RTC interrupt (e.g., GPIO 33)

// MPU6050 I2C (ESP32 defaults)
#define I2C_SDA              21
#define I2C_SCL              22

// Status Indicator LED
#define STATUS_LED           2

// --- CELLULAR & SMS CONFIG ---
#define APN                  "internet"
#define APN_USER             ""
#define APN_PASS             ""
#define EMERGENCY_SMS_PHONE  "+1234567890"  // Owner's direct cell number

// --- MQTT CONFIG ---
#define MQTT_SERVER          "broker.hivemq.com"
#define MQTT_PORT            1883
#define MQTT_USER            ""
#define MQTT_PASS            ""
#define DEVICE_ID            "MOTO-ESP32-98A7B6"

// MQTT Topics
#define TOPIC_TELEMETRY      "moto/telemetry/MOTO-ESP32-98A7B6"
#define TOPIC_ALERTS         "moto/alerts/MOTO-ESP32-98A7B6"
#define TOPIC_COMMAND        "moto/command/MOTO-ESP32-98A7B6"

// --- SYSTEM THRESHOLDS ---
#define CRASH_G_FORCE_LIMIT  3.5f    // Accel G-force threshold for crash detection
#define CRASH_LEAN_LIMIT     65.0f   // Lean angle threshold (degrees) for fall detection
#define SHOCK_SENSITIVITY    500     // Vibration threshold
#define TELEMETRY_INTERVAL   10000   // Post telemetry every 10s (ms)

#endif // CONFIG_H
