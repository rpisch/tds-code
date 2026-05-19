import Combine
import CoreBluetooth
import Foundation

final class BLECounterManager: NSObject, ObservableObject {
    @Published var latestValue: UInt8?
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionStateText = "Not started"
    @Published var debugMessage = "Open the ESP32 Serial Monitor for matching connection logs."
    @Published var discoveredDevices: [String] = []

    private let deviceName = "ESP32-TDS-BLE"
    private let serviceUUID = CBUUID(string: "7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000")
    private let counterCharacteristicUUID = CBUUID(string: "7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000")

    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?

    var latestValueText: String {
        if let latestValue {
            return String(latestValue)
        }

        return "--"
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard !isConnected else {
            debugMessage = "Already connected to ESP32."
            return
        }

        guard centralManager.state == .poweredOn else {
            connectionStateText = "Bluetooth unavailable"
            debugMessage = "Bluetooth state: \(centralManager.state.debugDescription)"
            return
        }

        centralManager.stopScan()
        scanTimeoutTimer?.invalidate()

        latestValue = nil
        isScanning = true
        isConnected = false
        connectionStateText = "Scanning"
        debugMessage = "Scanning for BLE devices. Waiting for \(deviceName)..."
        discoveredDevices = []

        // Scan broadly while debugging. Some ESP32 setups advertise the name before
        // iOS sees the custom service UUID, especially during early bring-up.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.handleScanTimeout()
        }
    }

    func disconnect() {
        guard let esp32Peripheral else {
            stopScanning()
            connectionStateText = "Disconnected"
            debugMessage = "No ESP32 connection is active."
            return
        }

        centralManager.cancelPeripheralConnection(esp32Peripheral)
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
        connectionStateText = "Not found"
        debugMessage = "Scan timed out after 15 seconds. Found \(discoveredDevices.count) BLE device(s), but not \(deviceName)."
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
            stopScanning()
            isConnected = false
            connectionStateText = "Bluetooth off"
            debugMessage = "Turn on Bluetooth on this iPhone."
        case .unauthorized:
            stopScanning()
            isConnected = false
            connectionStateText = "Bluetooth unauthorized"
            debugMessage = "Allow Bluetooth access for this app in Settings."
        case .unsupported:
            stopScanning()
            isConnected = false
            connectionStateText = "Bluetooth unsupported"
            debugMessage = "This device does not support Bluetooth LE central mode."
        case .resetting:
            stopScanning()
            isConnected = false
            connectionStateText = "Bluetooth resetting"
            debugMessage = "Bluetooth is resetting. Try again in a moment."
        case .unknown:
            stopScanning()
            isConnected = false
            connectionStateText = "Bluetooth unknown"
            debugMessage = "Waiting for Bluetooth state..."
        @unknown default:
            stopScanning()
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
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowServices = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceMatches = advertisedServices.contains(serviceUUID) || overflowServices.contains(serviceUUID)
        let nameMatches = advertisedName == deviceName || peripheralName == deviceName

        rememberDiscoveredDevice(name: foundName, rssi: RSSI, serviceMatches: serviceMatches)

        guard nameMatches || serviceMatches else {
            debugMessage = "Scanning... saw \(discoveredDevices.count) BLE device(s). Waiting for \(deviceName)."
            return
        }

        stopScanning()
        connectionStateText = "Connecting"
        debugMessage = "Found \(foundName), RSSI \(RSSI)."

        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
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
        stopScanning()
        isConnected = false
        connectionStateText = "Disconnected"
        debugMessage = "Failed to connect: \(error?.localizedDescription ?? "No error details")."
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stopScanning()
        isConnected = false
        esp32Peripheral = nil
        connectionStateText = "Disconnected"
        debugMessage = error?.localizedDescription ?? "Disconnected from ESP32."
    }

    private func rememberDiscoveredDevice(name: String, rssi: NSNumber, serviceMatches: Bool) {
        let marker = serviceMatches ? "service match" : "BLE"
        let summary = "\(name) | RSSI \(rssi) | \(marker)"

        discoveredDevices.removeAll { existing in
            existing.hasPrefix("\(name) |")
        }

        discoveredDevices.insert(summary, at: 0)

        if discoveredDevices.count > 8 {
            discoveredDevices.removeLast(discoveredDevices.count - 8)
        }
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
