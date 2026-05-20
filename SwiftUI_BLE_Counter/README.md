# SwiftUI BLE Counter

This folder contains the SwiftUI side of the ESP32 BLE counter test.

The current implementation is intentionally close to the working reference project:

- Create and retain one `CBCentralManager`.
- Give the central manager a restoration identifier so CoreBluetooth can restore BLE state after a background relaunch.
- Wait for `centralManagerDidUpdateState`.
- Scan for the advertised ESP32 service UUID.
- Connect when the app sees `ESP32-TDS-BLE` or the matching service UUID.
- Discover all services and characteristics, then subscribe to the known counter characteristic.
- Use `bluetooth-central` background mode so subscribed BLE updates can wake the app while the phone is locked.

## Files

- `BLECounterApp.swift`: SwiftUI app entry point that owns the BLE manager for app-lifetime restoration.
- `ContentView.swift`: UI showing connection state, the latest value, and nearby BLE devices while scanning.
- `BLECounterManager.swift`: CoreBluetooth scanner, connector, service discovery, notification subscription, integer parsing, and local warning notifications for values above `20`.
- `Info.plist`: Bluetooth privacy strings.

## Xcode Setup

1. Create a new iOS App project in Xcode.
2. Choose SwiftUI for the interface and Swift for the language.
3. Replace the generated app entry file with `BLECounterApp.swift`, or keep the generated `@main` file and do not add `BLECounterApp.swift`.
4. Add `ContentView.swift` and `BLECounterManager.swift` to the app target.
5. In **Signing & Capabilities**, add **Background Modes** and check **Uses Bluetooth LE accessories**. This maps to `UIBackgroundModes` / `bluetooth-central`.
6. Add `Privacy - Bluetooth Always Usage Description` / `NSBluetoothAlwaysUsageDescription` to the app target's actual Info settings. In newer Xcode projects, the generated target Info settings may be used instead of this standalone `Info.plist`.
7. If your Xcode target is not using this standalone `Info.plist`, add `Required background modes` with `App communicates using CoreBluetooth` / `bluetooth-central` in the target's Info settings.
8. Allow local notifications when the app asks. Values above `20` trigger a local warning notification.
9. Delete the old app from the iPhone after changing Bluetooth/background settings, then run again on a real iPhone. The iOS Simulator cannot test Bluetooth LE connections to an ESP32.

## BLE Contract

- Device name: `ESP32-TDS-BLE`
- Service UUID: `4FAFC201-1FB5-459E-8FCC-C5C9C331914B`
- Characteristic UUID: `BEB5483E-36E1-4688-B7F5-EA07361B26A8`
- Value format: 4-byte little-endian signed integer entered through the ESP32 Serial Monitor.
- Warning threshold: the iOS app sends a local notification when the received value crosses above `20`.

## Checklist

- If the app stays at `Bluetooth unknown`, recheck the Xcode Bluetooth capability and the Bluetooth usage description in the target's Info settings.
- If iOS denies permission, open iPhone Settings for the app and allow Bluetooth.
- If the app scans and shows nearby BLE devices but not `ESP32-TDS-BLE`, confirm the ESP32 Serial Monitor says it is advertising.
- If no nearby BLE devices appear after 20 seconds, test with nRF Connect or LightBlue to confirm the iPhone can see BLE advertisements at all.
- To test lock-screen alerts, connect to the ESP32, lock the phone, then enter a value above `20` in Serial Monitor.
- Do not force-quit the app before lock-screen testing. iOS may not relaunch a force-quit app for Bluetooth events.
