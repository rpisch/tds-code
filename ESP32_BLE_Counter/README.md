# ESP32 BLE Counter

This Arduino sketch turns an ESP32 into a BLE peripheral named `ESP32-TDS-BLE`.

It exposes one custom BLE service and one custom characteristic:

- Service UUID: `7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000`
- Counter characteristic UUID: `7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000`

The characteristic supports `read` and `notify`. Once per second, the ESP32 updates a binary integer value from `1` through `100`, then wraps back to `1`. The value is sent as a single unsigned byte because the test range fits in one byte.

The sketch explicitly advertises the custom service UUID and puts the device name in BLE scan response data. This makes the iPhone app able to find the ESP32 either by service UUID or by the `ESP32-TDS-BLE` name during debugging.

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
Service UUID: 7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000
Characteristic UUID: 7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000
Updated value: 1 (waiting for BLE connection)
```

When the iPhone connects, you should see:

```text
BLE central connected.
Notified value: 42
```

## Hardware Note

The original ESP32 supports Bluetooth LE. Some ESP32-family variants differ; for example, ESP32-S2 is Wi-Fi only and will not work for BLE. If your board is ESP32, ESP32-C3, ESP32-C6, ESP32-H2, ESP32-S3, or another BLE-capable module, check that the selected Arduino board package includes BLE support for that chip.
