import Combine
import CoreBluetooth
import Foundation

final class BLECounterManager: NSObject, ObservableObject {
    @Published var latestValue: UInt8?
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionStateText = "Not started"
    @Published var debugMessage = "Open the ESP32 Serial Monitor for matching connection logs."

    private let deviceName = "ESP32-TDS-BLE"
    private let serviceUUID = CBUUID(string: "7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000")
    private let counterCharacteristicUUID = CBUUID(string: "7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000")

    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?

    var latestValueText: String {
        if let latestValue {
            return String(latestValue)
        }

        return "--"
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStateText = "Bluetooth unavailable"
            debugMessage = "Bluetooth state: \(centralManager.state.debugDescription)"
            return
        }

        latestValue = nil
        isScanning = true
        isConnected = false
        connectionStateText = "Scanning"
        debugMessage = "Looking for \(deviceName)..."

        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func disconnect() {
        guard let esp32Peripheral else {
            return
        }

        centralManager.cancelPeripheralConnection(esp32Peripheral)
    }
}

extension BLECounterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStateText = "Bluetooth ready"
            debugMessage = "Ready to scan for ESP32."
            startScanning()
        case .poweredOff:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth off"
            debugMessage = "Turn on Bluetooth on this iPhone."
        case .unauthorized:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth unauthorized"
            debugMessage = "Allow Bluetooth access for this app in Settings."
        case .unsupported:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth unsupported"
            debugMessage = "This device does not support Bluetooth LE central mode."
        case .resetting:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth resetting"
            debugMessage = "Bluetooth is resetting. Try again in a moment."
        case .unknown:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth unknown"
            debugMessage = "Waiting for Bluetooth state..."
        @unknown default:
            isScanning = false
            isConnected = false
            connectionStateText = "Bluetooth error"
            debugMessage = "Unknown Bluetooth state: \(central.state.rawValue)"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name
        let foundName = advertisedName ?? peripheralName ?? "unnamed peripheral"

        isScanning = false
        connectionStateText = "Connecting"
        debugMessage = "Found \(foundName), RSSI \(RSSI)."

        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStateText = "Connected"
        debugMessage = "Discovering ESP32 counter service..."
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        isScanning = false
        isConnected = false
        connectionStateText = "Disconnected"
        debugMessage = "Failed to connect: \(error?.localizedDescription ?? "No error details")."
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        isScanning = false
        isConnected = false
        esp32Peripheral = nil
        connectionStateText = "Disconnected"
        debugMessage = error?.localizedDescription ?? "Disconnected from ESP32."
    }
}

extension BLECounterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            debugMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else {
            debugMessage = "No services found."
            return
        }

        for service in services where service.uuid == serviceUUID {
            debugMessage = "Discovering counter characteristic..."
            peripheral.discoverCharacteristics([counterCharacteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            debugMessage = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else {
            debugMessage = "No characteristics found."
            return
        }

        for characteristic in characteristics where characteristic.uuid == counterCharacteristicUUID {
            debugMessage = "Subscribing to counter notifications..."
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            debugMessage = "Value update failed: \(error.localizedDescription)"
            return
        }

        guard characteristic.uuid == counterCharacteristicUUID else {
            return
        }

        guard let data = characteristic.value, let firstByte = data.first else {
            debugMessage = "Counter characteristic was empty."
            return
        }

        latestValue = firstByte
        connectionStateText = "Connected"
        debugMessage = "Received \(firstByte) from \(deviceName)."
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            debugMessage = "Notification setup failed: \(error.localizedDescription)"
            return
        }

        if characteristic.isNotifying {
            debugMessage = "Notification subscription is active."
        } else {
            debugMessage = "Notification subscription stopped."
        }
    }
}

private extension CBManagerState {
    var debugDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unknown future state \(rawValue)"
        }
    }
}
