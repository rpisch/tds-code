# ESP32 BLE Counter

This Arduino sketch turns an ESP32 into a BLE peripheral named `ESP32-TDS-BLE`.

It exposes one custom BLE service and one custom characteristic:

- Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Counter characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`

The characteristic supports `read`, `write`, and `notify`. Once per second, the ESP32 updates a binary integer value from `1` through `100`, then wraps back to `1`. The value is sent as a 4-byte little-endian signed integer.

This version follows the same simple shape as the working reference project: create a BLE server, create one custom service and characteristic, start the service, get advertising from the server, add the service UUID, enable scan response, and start advertising.

## Arduino Setup

1. Install the ESP32 Arduino board package in Arduino IDE.
2. Open `ESP32_BLE_Counter.ino`.
3. Select an ESP32 board that supports Bluetooth LE.
4. Upload the sketch.
5. Open Serial Monitor at `115200` baud to see connection and notification logs.

## Expected Serial Output

After reset, you should see:

```text
ESP32 BLE counter started.
Advertising as ESP32-TDS-BLE
Service UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b
Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8
Updated value: 1 (waiting for BLE connection)
```

When the iPhone connects, you should see:

```text
BLE central connected.
Notified value: 42
```

## Hardware Note

The original ESP32 supports Bluetooth LE. Some ESP32-family variants differ; for example, ESP32-S2 is Wi-Fi only and will not work for BLE. If your board is ESP32, ESP32-C3, ESP32-C6, ESP32-H2, ESP32-S3, or another BLE-capable module, check that the selected Arduino board package includes BLE support for that chip.
