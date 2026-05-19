import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLECounterManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                valueDisplay
                controls
                diagnostics
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("ESP32 BLE Counter")
                .font(.title2.weight(.semibold))

            Text(bleManager.connectionStateText)
                .font(.subheadline)
                .foregroundStyle(bleManager.isConnected ? .green : .secondary)
        }
    }

    private var valueDisplay: some View {
        Text(bleManager.latestValueText)
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .monospacedDigit()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(bleManager.isScanning ? "Scanning..." : "Scan and Connect") {
                bleManager.startScanning()
            }
            .buttonStyle(.borderedProminent)
            .disabled(bleManager.isScanning)

            Button("Disconnect") {
                bleManager.disconnect()
            }
            .buttonStyle(.bordered)
            .disabled(!bleManager.isConnected && !bleManager.isScanning)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bleManager.debugMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            Divider()

            Text(bleManager.bluetoothStateText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(bleManager.bluetoothAuthorizationText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(bleManager.infoPlistBluetoothKeyText)
                .font(.caption)
                .foregroundStyle(bleManager.infoPlistBluetoothKeyText.contains("missing") ? .red : .secondary)

            if !bleManager.discoveredDevices.isEmpty {
                Text("Nearby BLE Devices")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(bleManager.discoveredDevices, id: \.self) { device in
                    Text(device)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
