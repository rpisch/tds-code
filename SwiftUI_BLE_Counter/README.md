# SwiftUI BLE Counter

This folder contains the SwiftUI side of the ESP32 BLE counter test.

## Files

- `BLECounterApp.swift`: SwiftUI app entry point.
- `ContentView.swift`: Minimal UI showing scanning/connection state and the latest received value.
- `BLECounterManager.swift`: CoreBluetooth scanner, connector, service discovery, notification subscription, and byte parsing.
- `Info.plist`: Bluetooth privacy strings.

## Xcode Setup

1. Create a new iOS App project in Xcode.
2. Choose SwiftUI for the interface and Swift for the language.
3. Replace the generated app entry file with `BLECounterApp.swift`, or keep the generated `@main` file and do not add `BLECounterApp.swift`.
4. Add `ContentView.swift` and `BLECounterManager.swift` to the app target.
5. Add the Bluetooth usage descriptions from `Info.plist` to your app target's actual Info settings. In newer Xcode projects, the generated target Info settings may be used instead of this standalone file.
6. Run on a real iPhone. The iOS Simulator cannot test Bluetooth LE connections to an ESP32.

## Phone Debug Checklist

- The top of the app should show `Debug UI v5`. If it does not, the phone is running an old build or Xcode is not using this `ContentView.swift`.
- The debug area should show `BLE manager v5 loaded`. If it does not, Xcode is not using this `BLECounterManager.swift`.
- `Managers created` should be at least `1`, and `State callbacks` should normally become at least `1` within a few seconds. If state stays `unknown`, use `Reset Bluetooth Manager` once.
- Pressing `Scan and Connect` should increment `Scan button taps`. If it does not, the button action is not connected to this manager instance.
- If the button tap count increments but Bluetooth says `unknown`, wait a few seconds or tap again. The manager now remembers the scan request until CoreBluetooth becomes `poweredOn`.
- If Bluetooth says `poweredOn` and the button changes to `Scanning...`, CoreBluetooth is scanning.
- If it says `Bluetooth unauthorized`, open iPhone Settings for the app and allow Bluetooth.
- If nearby BLE devices appear but not `ESP32-TDS-BLE`, the iPhone is scanning but the ESP32 is not advertising in a way the app can see.
- If no nearby BLE devices appear after 15 seconds, test with nRF Connect or LightBlue to confirm the phone can see BLE advertisements.
- The ESP32 should print `ESP32 BLE counter started.` and then `Updated value...` or `Notified value...` in Arduino Serial Monitor at `115200` baud.

## BLE Contract

- Device name: `ESP32-TDS-BLE`
- Service UUID: `7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000`
- Characteristic UUID: `7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000`
- Value format: one unsigned byte, `1...100`

The app scans for the service UUID, connects to the matching peripheral, reads the current value, subscribes to notifications, then displays each updated byte.
