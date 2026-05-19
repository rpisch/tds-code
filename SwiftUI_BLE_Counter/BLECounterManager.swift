import Combine
import CoreBluetooth
import Foundation

final class BLECounterManager: NSObject, ObservableObject {
    @Published var managerVersionText = "BLE manager v5 loaded"
    @Published var latestValue: UInt8?
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionStateText = "Not started"
    @Published var bluetoothStateText = "Bluetooth state: unknown"
    @Published var debugMessage = "Open the ESP32 Serial Monitor for matching connection logs."
    @Published var discoveredDevices: [String] = []
    @Published var scanButtonTapCount = 0
    @Published var centralManagerCreateCount = 0
    @Published var stateUpdateCallbackCount = 0

    private let deviceName = "ESP32-TDS-BLE"
    private let serviceUUID = CBUUID(string: "7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000")
    private let counterCharacteristicUUID = CBUUID(string: "7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000")

    private var centralManager: CBCentralManager?
    private var esp32Peripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?
    private var bluetoothStateWatchdogTimer: Timer?
    private var pendingScanAfterBluetoothPowersOn = false
    private var discoveredDeviceSummariesByID: [UUID: String] = [:]
    private var hasRecreatedUnknownCentralManager = false

    var latestValueText: String {
        if let latestValue {
            return String(latestValue)
        }

        return "--"
    }

    override init() {
        super.init()
    }

    func viewAppeared() {
        if centralManager == nil {
            createCentralManager(reason: "view appeared")
        }

        refreshBluetoothStateText()
        connectionStateText = "Ready"
        debugMessage = "View appeared. Tap Scan and Connect to start BLE scanning."
        scheduleBluetoothStateWatchdog()
    }

    func scanButtonTapped() {
        scanButtonTapCount += 1

        if centralManager == nil {
            createCentralManager(reason: "scan button tapped")
        }

        refreshBluetoothStateText()
        debugMessage = "Scan button tapped \(scanButtonTapCount) time(s). Bluetooth state: \(currentBluetoothState.debugDescription)."
        startScanning()
    }

    func stopScanOrDisconnectTapped() {
        if isScanning {
            stopScanning(clearPendingScan: true)
            connectionStateText = "Scan stopped"
            debugMessage = "Scan stopped by button."
            return
        }

        disconnect()
    }

    func recreateBluetoothManagerTapped() {
        hasRecreatedUnknownCentralManager = false
        createCentralManager(reason: "manual reset button")
        connectionStateText = "Bluetooth reset"
        debugMessage = "Recreated CoreBluetooth manager. Watch for state callbacks and then tap Scan and Connect."
        scheduleBluetoothStateWatchdog()
    }

    private var currentBluetoothState: CBManagerState {
        centralManager?.state ?? .unknown
    }

    private func createCentralManager(reason: String) {
        stopScanning(clearPendingScan: false)
        centralManager = nil
        centralManagerCreateCount += 1
        stateUpdateCallbackCount = 0
        bluetoothStateText = "Bluetooth state: creating manager"
        debugMessage = "Creating CoreBluetooth manager #\(centralManagerCreateCount) (\(reason))."

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    private func refreshBluetoothStateText() {
        bluetoothStateText = "Bluetooth state: \(currentBluetoothState.debugDescription)"
    }

    private func startScanning() {
        guard !isConnected else {
            debugMessage = "Already connected to ESP32."
            return
        }

        guard let centralManager else {
            createCentralManager(reason: "start scan without manager")
            pendingScanAfterBluetoothPowersOn = true
            connectionStateText = "Waiting for Bluetooth"
            return
        }

        guard centralManager.state == .poweredOn else {
            pendingScanAfterBluetoothPowersOn = true
            isScanning = false
            connectionStateText = "Waiting for Bluetooth"
            refreshBluetoothStateText()
            debugMessage = "Scan requested, but Bluetooth is \(centralManager.state.debugDescription). Waiting for CoreBluetooth to become poweredOn."
            scheduleBluetoothStateWatchdog()
            return
        }

        centralManager.stopScan()
        scanTimeoutTimer?.invalidate()

        latestValue = nil
        isScanning = true
        isConnected = false
        connectionStateText = "Scanning"
        bluetoothStateText = "Bluetooth state: poweredOn"
        debugMessage = "Scanning for BLE devices. Waiting for \(deviceName)..."
        pendingScanAfterBluetoothPowersOn = false
        discoveredDeviceSummariesByID = [:]
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

    private func disconnect() {
        guard let esp32Peripheral else {
            stopScanning(clearPendingScan: true)
            connectionStateText = "Disconnected"
            debugMessage = "No ESP32 connection is active."
            return
        }

        centralManager?.cancelPeripheralConnection(esp32Peripheral)
    }

    private func stopScanning(clearPendingScan: Bool = true) {
        centralManager?.stopScan()
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        isScanning = false
        if clearPendingScan {
            pendingScanAfterBluetoothPowersOn = false
        }
    }

    private func handleScanTimeout() {
        guard isScanning else {
            return
        }

        stopScanning(clearPendingScan: true)
        connectionStateText = "Not found"
        debugMessage = "Scan timed out after 15 seconds. Found \(discoveredDevices.count) BLE device(s), but not \(deviceName)."
    }

    private func scheduleBluetoothStateWatchdog() {
        bluetoothStateWatchdogTimer?.invalidate()

        bluetoothStateWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.handleBluetoothStateWatchdog()
        }
    }

    private func handleBluetoothStateWatchdog() {
        refreshBluetoothStateText()

        guard currentBluetoothState == .unknown else {
            return
        }

        if !hasRecreatedUnknownCentralManager {
            hasRecreatedUnknownCentralManager = true
            createCentralManager(reason: "state stuck unknown after 3 seconds")
            debugMessage = "Bluetooth stayed unknown for 3 seconds, so the app recreated the CoreBluetooth manager once."
            scheduleBluetoothStateWatchdog()
            return
        }

        connectionStateText = "Bluetooth stuck"
        debugMessage = "Bluetooth is still unknown. Check that the app target has NSBluetoothAlwaysUsageDescription, Bluetooth permission is allowed, and this is running on a real iPhone."
    }
}

extension BLECounterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateUpdateCallbackCount += 1
        bluetoothStateText = "Bluetooth state: \(central.state.debugDescription)"

        if central.state != .unknown {
            bluetoothStateWatchdogTimer?.invalidate()
        }

        switch central.state {
        case .poweredOn:
            connectionStateText = "Bluetooth ready"
            debugMessage = "CoreBluetooth is poweredOn. Ready to scan."

            if pendingScanAfterBluetoothPowersOn {
                debugMessage = "Bluetooth became poweredOn after a scan request. Starting scan now."
                startScanning()
            }
        case .poweredOff:
            stopScanning(clearPendingScan: true)
            isConnected = false
            connectionStateText = "Bluetooth off"
            debugMessage = "Turn on Bluetooth on this iPhone."
        case .unauthorized:
            stopScanning(clearPendingScan: true)
            isConnected = false
            connectionStateText = "Bluetooth unauthorized"
            debugMessage = "Allow Bluetooth access for this app in Settings."
        case .unsupported:
            stopScanning(clearPendingScan: true)
            isConnected = false
            connectionStateText = "Bluetooth unsupported"
            debugMessage = "This device does not support Bluetooth LE central mode."
        case .resetting:
            stopScanning(clearPendingScan: false)
            isConnected = false
            connectionStateText = "Bluetooth resetting"
            debugMessage = "Bluetooth is resetting. Try again in a moment."
            scheduleBluetoothStateWatchdog()
        case .unknown:
            stopScanning(clearPendingScan: false)
            isConnected = false
            connectionStateText = "Bluetooth unknown"
            debugMessage = "Waiting for Bluetooth state..."
            scheduleBluetoothStateWatchdog()
        @unknown default:
            stopScanning(clearPendingScan: true)
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

        rememberDiscoveredDevice(
            id: peripheral.identifier,
            name: foundName,
            rssi: RSSI,
            advertisedServices: advertisedServices,
            serviceMatches: serviceMatches
        )

        guard nameMatches || serviceMatches else {
            debugMessage = "Scanning... saw \(discoveredDevices.count) BLE device(s). Waiting for \(deviceName)."
            return
        }

        stopScanning(clearPendingScan: true)
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
        stopScanning(clearPendingScan: true)
        isConnected = false
        connectionStateText = "Disconnected"
        debugMessage = "Failed to connect: \(error?.localizedDescription ?? "No error details")."
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stopScanning(clearPendingScan: true)
        isConnected = false
        esp32Peripheral = nil
        connectionStateText = "Disconnected"
        debugMessage = error?.localizedDescription ?? "Disconnected from ESP32."
    }

    private func rememberDiscoveredDevice(
        id: UUID,
        name: String,
        rssi: NSNumber,
        advertisedServices: [CBUUID],
        serviceMatches: Bool
    ) {
        let marker = serviceMatches ? "service match" : "BLE"
        let shortID = id.uuidString.prefix(8)
        let services = advertisedServices.map(\.uuidString).joined(separator: ", ")
        let serviceText = services.isEmpty ? "no advertised services" : services
        let summary = "\(name) | \(shortID) | RSSI \(rssi) | \(marker) | \(serviceText)"

        discoveredDeviceSummariesByID[id] = summary
        discoveredDevices = Array(discoveredDeviceSummariesByID.values).sorted()
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
