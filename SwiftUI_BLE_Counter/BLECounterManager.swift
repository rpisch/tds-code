import Combine
import CoreBluetooth
import Foundation
import UserNotifications

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
    private let warningThreshold = 20
    private let notificationCenter = UNUserNotificationCenter.current()
    private let centralManagerRestoreIdentifier = "com.tds.blecounter.central"

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?
    private var pendingScanRequest = false
    private var discoveredDeviceIDs = Set<UUID>()
    private var wasAboveWarningThreshold = false

    var latestValueText: String {
        guard let latestValue else {
            return "--"
        }

        return "\(latestValue) ppm"
    }

    override init() {
        super.init()
        configureWarningNotifications()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: centralManagerRestoreIdentifier]
        )
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
            withServices: [serviceUUID],
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

    private func discoverCounterService(on peripheral: CBPeripheral) {
        if let services = peripheral.services, !services.isEmpty {
            let counterServices = services.filter { $0.uuid == serviceUUID }

            guard !counterServices.isEmpty else {
                peripheral.discoverServices([serviceUUID])
                return
            }

            for service in counterServices {
                discoverCounterCharacteristic(on: peripheral, service: service)
            }
        } else {
            peripheral.discoverServices([serviceUUID])
        }
    }

    private func discoverCounterCharacteristic(on peripheral: CBPeripheral, service: CBService) {
        if let characteristics = service.characteristics, !characteristics.isEmpty {
            let counterCharacteristics = characteristics.filter { $0.uuid == counterCharacteristicUUID }

            guard !counterCharacteristics.isEmpty else {
                peripheral.discoverCharacteristics([counterCharacteristicUUID], for: service)
                return
            }

            for characteristic in counterCharacteristics {
                activateCounterCharacteristic(characteristic, on: peripheral)
            }
        } else {
            peripheral.discoverCharacteristics([counterCharacteristicUUID], for: service)
        }
    }

    private func activateCounterCharacteristic(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        connectionStateText = "Subscribed"
        statusMessage = "Counter characteristic found. Waiting for values..."

        if characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }

        if characteristic.properties.contains(.notify), !characteristic.isNotifying {
            peripheral.setNotifyValue(true, for: characteristic)
        }
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

    private func configureWarningNotifications() {
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func handleWarningNotification(for value: Int) {
        let isAboveWarningThreshold = value > warningThreshold
        defer {
            wasAboveWarningThreshold = isAboveWarningThreshold
        }

        guard isAboveWarningThreshold && !wasAboveWarningThreshold else {
            return
        }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.scheduleWarningNotification(for: value)
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        self.scheduleWarningNotification(for: value)
                    }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func scheduleWarningNotification(for value: Int) {
        let content = UNMutableNotificationContent()
        content.title = "TDS Alert: Filter Change Needed"
        content.body = "\(value) ppm detected"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "esp32-value-warning-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }
}

extension BLECounterManager: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []

        guard let peripheral = restoredPeripherals.first else {
            connectionStateText = "Bluetooth restored"
            statusMessage = "Bluetooth state was restored, but no ESP32 peripheral was available."
            return
        }

        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = peripheral.state == .connected
        connectionStateText = "Bluetooth restored"
        statusMessage = "Restored ESP32 Bluetooth state. Waiting for updates..."

        switch peripheral.state {
        case .connected:
            discoverCounterService(on: peripheral)
        case .connecting:
            statusMessage = "Restored pending ESP32 connection."
        default:
            central.connect(peripheral, options: nil)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if connectedPeripheral == nil && !isScanning {
                connectionStateText = "Bluetooth ready"
                statusMessage = "Bluetooth is ready. Tap Scan and Connect."
            }

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
        discoverCounterService(on: peripheral)
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

        for service in services where service.uuid == serviceUUID {
            discoverCounterCharacteristic(on: peripheral, service: service)
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
            activateCounterCharacteristic(characteristic, on: peripheral)
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
        handleWarningNotification(for: value)
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

extension BLECounterManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
