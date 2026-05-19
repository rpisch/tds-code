import Combine
import CoreBluetooth
import Foundation

final class BLECounterManager: NSObject, ObservableObject {
    @Published var latestValue: Int?
    @Published var connectionStateText = "Starting Bluetooth"
    @Published var bluetoothStateText = "Bluetooth state: unknown"
    @Published var bluetoothAuthorizationText = "Bluetooth authorization: unknown"
    @Published var infoPlistBluetoothKeyText = "Info.plist Bluetooth key: unchecked"
    @Published var debugMessage = "Waiting for CoreBluetooth..."
    @Published var discoveredDevices: [String] = []
    @Published var isScanning = false
    @Published var isConnected = false

    private let deviceName = "ESP32-TDS-BLE"
    private let legacyReferenceDeviceName = "BLE_DEVICE"
    private let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    private let counterCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var counterCharacteristic: CBCharacteristic?
    private var pendingScanRequest = false
    private var scanTimeoutTimer: Timer?
    private var discoveredDeviceIDs = Set<UUID>()

    var latestValueText: String {
        guard let latestValue else {
            return "--"
        }

        return String(latestValue)
    }

    override init() {
        super.init()
        refreshRuntimeDiagnostics()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        refreshRuntimeDiagnostics()

        guard centralManager.state == .poweredOn else {
            pendingScanRequest = true
            connectionStateText = "Waiting for Bluetooth"
            debugMessage = "Scan requested, but CoreBluetooth is \(centralManager.state.debugDescription). Waiting for poweredOn."
            return
        }

        pendingScanRequest = false
        latestValue = nil
        discoveredDevices = []
        discoveredDeviceIDs = []
        isScanning = true
        isConnected = false
        connectionStateText = "Scanning"
        debugMessage = "Scanning for \(deviceName). Keep the ESP32 powered and advertising."

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
            debugMessage = "No ESP32 peripheral is connected."
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
        debugMessage = "Scan timed out. Saw \(discoveredDevices.count) BLE device(s), but not \(deviceName)."
    }

    private func refreshRuntimeDiagnostics() {
        bluetoothAuthorizationText = "Bluetooth authorization: \(CBManager.authorization.debugDescription)"

        if let message = Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String,
           !message.isEmpty {
            infoPlistBluetoothKeyText = "Info.plist Bluetooth key: present"
        } else {
            infoPlistBluetoothKeyText = "Info.plist Bluetooth key: missing NSBluetoothAlwaysUsageDescription"
        }
    }

    private func rememberDiscoveredDevice(_ peripheral: CBPeripheral, advertisedName: String?, rssi: NSNumber) {
        guard !discoveredDeviceIDs.contains(peripheral.identifier) else {
            return
        }

        discoveredDeviceIDs.insert(peripheral.identifier)
        let name = advertisedName ?? peripheral.name ?? "unnamed BLE device"
        let shortID = peripheral.identifier.uuidString.prefix(8)
        discoveredDevices.insert("\(name) | \(shortID) | RSSI \(rssi)", at: 0)

        if discoveredDevices.count > 12 {
            discoveredDevices.removeLast(discoveredDevices.count - 12)
        }
    }

    private func isTargetPeripheral(_ peripheral: CBPeripheral, advertisedName: String?, advertisedServices: [CBUUID]) -> Bool {
        let names = [advertisedName, peripheral.name].compactMap { $0 }
        let nameMatches = names.contains(deviceName) || names.contains(legacyReferenceDeviceName)
        let serviceMatches = advertisedServices.contains(serviceUUID)

        return nameMatches || serviceMatches
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
        refreshRuntimeDiagnostics()
        bluetoothStateText = "Bluetooth state: \(central.state.debugDescription)"

        switch central.state {
        case .poweredOn:
            connectionStateText = "Bluetooth ready"
            debugMessage = "Bluetooth is poweredOn. Tap Scan and Connect."

            if pendingScanRequest {
                startScanning()
            }
        case .poweredOff:
            stopScanning()
            connectionStateText = "Bluetooth off"
            debugMessage = "Turn on Bluetooth in iPhone Settings or Control Center."
        case .unauthorized:
            stopScanning()
            connectionStateText = "Bluetooth unauthorized"
            debugMessage = "Allow Bluetooth for this app in iPhone Settings."
        case .unsupported:
            stopScanning()
            connectionStateText = "Bluetooth unsupported"
            debugMessage = "This device does not support Bluetooth LE central mode."
        case .resetting:
            stopScanning()
            connectionStateText = "Bluetooth resetting"
            debugMessage = "Bluetooth is resetting. Try scanning again in a moment."
        case .unknown:
            connectionStateText = "Bluetooth unknown"
            debugMessage = "CoreBluetooth has not reported a usable state yet."
        @unknown default:
            stopScanning()
            connectionStateText = "Bluetooth error"
            debugMessage = "Unknown Bluetooth state: \(central.state.rawValue)."
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
            debugMessage = "Scanning... saw \(discoveredDevices.count) BLE device(s). Waiting for \(deviceName)."
            return
        }

        stopScanning()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        connectionStateText = "Connecting"
        debugMessage = "Found \(advertisedName ?? peripheral.name ?? deviceName). Connecting..."
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStateText = "Connected"
        debugMessage = "Connected. Discovering BLE services..."
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        connectionStateText = "Connection failed"
        debugMessage = error?.localizedDescription ?? "Failed to connect to ESP32."
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        counterCharacteristic = nil
        connectionStateText = "Disconnected"
        debugMessage = error?.localizedDescription ?? "Disconnected from ESP32."
    }
}

extension BLECounterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionStateText = "Service error"
            debugMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            connectionStateText = "No services"
            debugMessage = "Connected, but no BLE services were found."
            return
        }

        if services.contains(where: { $0.uuid == serviceUUID }) {
            debugMessage = "Counter service found. Discovering characteristics..."
        } else {
            let serviceList = services.map(\.uuid.uuidString).joined(separator: ", ")
            debugMessage = "Target service not found yet. Discovered: \(serviceList)"
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionStateText = "Characteristic error"
            debugMessage = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else {
            return
        }

        for characteristic in characteristics where characteristic.uuid == counterCharacteristicUUID {
            counterCharacteristic = characteristic
            connectionStateText = "Subscribed"
            debugMessage = "Counter characteristic found. Waiting for values..."

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
            debugMessage = "Value update failed: \(error.localizedDescription)"
            return
        }

        guard characteristic.uuid == counterCharacteristicUUID else {
            return
        }

        guard let data = characteristic.value, let value = integerValue(from: data) else {
            debugMessage = "Counter characteristic did not contain integer data."
            return
        }

        latestValue = value
        connectionStateText = "Receiving"
        debugMessage = "Received \(value) from ESP32."
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            debugMessage = "Notification setup failed: \(error.localizedDescription)"
            return
        }

        if characteristic.uuid == counterCharacteristicUUID, characteristic.isNotifying {
            debugMessage = "Notification subscription is active. Waiting for the next counter update."
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

private extension CBManagerAuthorization {
    var debugDescription: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .allowedAlways:
            return "allowedAlways"
        @unknown default:
            return "unknown future authorization \(rawValue)"
        }
    }
}
