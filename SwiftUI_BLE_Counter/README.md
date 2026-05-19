# SwiftUI BLE Counter

This folder contains the SwiftUI side of the ESP32 BLE counter test.

The current implementation is intentionally close to the working reference project:

- Create and retain one `CBCentralManager`.
- Wait for `centralManagerDidUpdateState`.
- Scan broadly with `scanForPeripherals(withServices: nil)`.
- Connect when the app sees `ESP32-TDS-BLE` or the matching service UUID.
- Discover all services and characteristics, then subscribe to the known counter characteristic.

## Files

- `BLECounterApp.swift`: SwiftUI app entry point.
- `ContentView.swift`: UI showing connection state, the latest value, and useful Bluetooth diagnostics.
- `BLECounterManager.swift`: CoreBluetooth scanner, connector, service discovery, notification subscription, and integer parsing.
- `Info.plist`: Bluetooth privacy strings.

## Xcode Setup

1. Create a new iOS App project in Xcode.
2. Choose SwiftUI for the interface and Swift for the language.
3. Replace the generated app entry file with `BLECounterApp.swift`, or keep the generated `@main` file and do not add `BLECounterApp.swift`.
4. Add `ContentView.swift` and `BLECounterManager.swift` to the app target.
5. Add `Privacy - Bluetooth Always Usage Description` / `NSBluetoothAlwaysUsageDescription` to the app target's actual Info settings. In newer Xcode projects, the generated target Info settings may be used instead of this standalone `Info.plist`.
6. Delete the old app from the iPhone after changing Bluetooth permission keys, then run again on a real iPhone. The iOS Simulator cannot test Bluetooth LE connections to an ESP32.

## BLE Contract

- Device name: `ESP32-TDS-BLE`
- Service UUID: `4FAFC201-1FB5-459E-8FCC-C5C9C331914B`
- Characteristic UUID: `BEB5483E-36E1-4688-B7F5-EA07361B26A8`
- Value format: 4-byte little-endian signed integer, `1...100`

The app also accepts the reference project's `BLE_DEVICE` name while scanning, which can help if you flash the original sample firmware for comparison.

## Debug Checklist

- `Info.plist Bluetooth key` must say `present`. If it says `missing`, the running app target does not contain `NSBluetoothAlwaysUsageDescription`.
- `Bluetooth authorization` should become `allowedAlways`. If it says `denied`, open iPhone Settings for the app and allow Bluetooth.
- `Bluetooth state` must become `poweredOn` before scanning can start.
- If the app scans and shows nearby BLE devices but not `ESP32-TDS-BLE`, confirm the ESP32 Serial Monitor says it is advertising.
- If no nearby BLE devices appear after 20 seconds, test with nRF Connect or LightBlue to confirm the iPhone can see BLE advertisements at all.
