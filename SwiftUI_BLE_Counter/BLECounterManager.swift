import Combine
import CoreBluetooth
import Foundation

final class BLECounterManager: NSObject, ObservableObject {
    @Published var latestValue: Int?
    @Published var connectionStateText = "Starting Bluetooth"
    @Published var statusMessage = "Waiting for CoreBluetooth..."
    @Published var discoveredDevices: [String] = []
    @Published var isScanning = false
    @Published var isConnected = false

    private let deviceName = "ESP32-TDS-BLE"
    private let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    private let counterCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?
    private var pendingScanRequest = false
    private var discoveredDeviceIDs = Set<UUID>()

    var latestValueText: String {
        guard let latestValue else {
            return "--"
        }

        return String(latestValue)
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            pendingScanRequest = true
            connectionStateText = "Waiting for Bluetooth"
            statusMessage = "Bluetooth is \(centralManager.state.debugDescription). Waiting for poweredOn."
            return
        }

        pendingScanRequest = false
        latestValue = nil
        discoveredDevices = []
        discoveredDeviceIDs = []
        isConnected = false
        isScanning = true
        connectionStateText = "Scanning"
        statusMessage = "Scanning for \(deviceName)..."

        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.handleScanTimeout()
        }
    }

    func disconnect() {
        stopScanning()

        guard let connectedPeripheral else {
            isConnected = false
            connectionStateText = "Disconnected"
            statusMessage = "No ESP32 peripheral is connected."
            return
        }

        centralManager.cancelPeripheralConnection(connectedPeripheral)
    }

    private func stopScanning() {
        centralManager.stopScan()
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        isScanning = false
    }

    private func handleScanTimeout() {
        guard isScanning else {
            return
        }

        stopScanning()
        connectionStateText = "ESP32 not found"
        statusMessage = "Scan timed out. Saw \(discoveredDevices.count) BLE device(s), but not \(deviceName)."
    }

    private func rememberDiscoveredDevice(_ peripheral: CBPeripheral, advertisedName: String?, rssi: NSNumber) {
        guard !discoveredDeviceIDs.contains(peripheral.identifier) else {
            return
        }

        discoveredDeviceIDs.insert(peripheral.identifier)

        let name = advertisedName ?? peripheral.name ?? "unnamed BLE device"
        discoveredDevices.insert("\(name) | RSSI \(rssi)", at: 0)

        if discoveredDevices.count > 8 {
            discoveredDevices.removeLast(discoveredDevices.count - 8)
        }
    }

    private func isTargetPeripheral(_ peripheral: CBPeripheral, advertisedName: String?, advertisedServices: [CBUUID]) -> Bool {
        let names = [advertisedName, peripheral.name].compactMap { $0 }
        return names.contains(deviceName) || advertisedServices.contains(serviceUUID)
    }

    private func integerValue(from data: Data) -> Int? {
        if data.count >= MemoryLayout<Int32>.size {
            let bytes = Array(data.prefix(MemoryLayout<Int32>.size))
            let rawValue = UInt32(bytes[0]) |
                (UInt32(bytes[1]) << 8) |
                (UInt32(bytes[2]) << 16) |
                (UInt32(bytes[3]) << 24)
            return Int(Int32(bitPattern: rawValue))
        }

        if let firstByte = data.first {
            return Int(firstByte)
        }

        return nil
    }
}

extension BLECounterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStateText = "Bluetooth ready"
            statusMessage = "Bluetooth is ready. Tap Scan and Connect."

            if pendingScanRequest {
                startScanning()
            }
        case .poweredOff:
            stopScanning()
            connectionStateText = "Bluetooth off"
            statusMessage = "Turn on Bluetooth on the iPhone."
        case .unauthorized:
            stopScanning()
            connectionStateText = "Bluetooth unauthorized"
            statusMessage = "Allow Bluetooth access for this app in iPhone Settings."
        case .unsupported:
            stopScanning()
            connectionStateText = "Bluetooth unsupported"
            statusMessage = "This device does not support Bluetooth LE central mode."
        case .resetting:
            stopScanning()
            connectionStateText = "Bluetooth resetting"
            statusMessage = "Bluetooth is resetting. Try scanning again in a moment."
        case .unknown:
            connectionStateText = "Bluetooth unknown"
            statusMessage = "Waiting for CoreBluetooth to report its state."
        @unknown default:
            stopScanning()
            connectionStateText = "Bluetooth error"
            statusMessage = "Unknown Bluetooth state: \(central.state.rawValue)."
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

        rememberDiscoveredDevice(peripheral, advertisedName: advertisedName, rssi: RSSI)

        guard isTargetPeripheral(peripheral, advertisedName: advertisedName, advertisedServices: advertisedServices) else {
            statusMessage = "Scanning... saw \(discoveredDevices.count) BLE device(s). Waiting for \(deviceName)."
            return
        }

        stopScanning()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        connectionStateText = "Connecting"
        statusMessage = "Found \(advertisedName ?? peripheral.name ?? deviceName). Connecting..."
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStateText = "Connected"
        statusMessage = "Connected. Discovering BLE services..."
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        connectionStateText = "Connection failed"
        statusMessage = error?.localizedDescription ?? "Failed to connect to ESP32."
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        connectionStateText = "Disconnected"
        statusMessage = error?.localizedDescription ?? "Disconnected from ESP32."
    }
}

extension BLECounterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionStateText = "Service error"
            statusMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            connectionStateText = "No services"
            statusMessage = "Connected, but no BLE services were found."
            return
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionStateText = "Characteristic error"
            statusMessage = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else {
            return
        }

        for characteristic in characteristics where characteristic.uuid == counterCharacteristicUUID {
            connectionStateText = "Subscribed"
            statusMessage = "Counter characteristic found. Waiting for values..."

            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            statusMessage = "Value update failed: \(error.localizedDescription)"
            return
        }

        guard characteristic.uuid == counterCharacteristicUUID else {
            return
        }

        guard let data = characteristic.value, let value = integerValue(from: data) else {
            statusMessage = "Counter characteristic did not contain integer data."
            return
        }

        latestValue = value
        connectionStateText = "Receiving"
        statusMessage = "Received \(value) from ESP32."
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            statusMessage = "Notification setup failed: \(error.localizedDescription)"
            return
        }

        if characteristic.uuid == counterCharacteristicUUID, characteristic.isNotifying {
            statusMessage = "Notification subscription is active. Waiting for values..."
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
