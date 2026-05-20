import SwiftUI

struct ContentView: View {
    @ObservedObject var bleManager: BLECounterManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                valueDisplay
                controls
                status
                discoveredDevices
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

    private var status: some View {
        Text(bleManager.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var discoveredDevices: some View {
        Group {
            if !bleManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby BLE Devices")
                        .font(.headline)

                    ForEach(bleManager.discoveredDevices, id: \.self) { device in
                        Text(device)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(bleManager: BLECounterManager())
    }
}
