import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLECounterManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                valueDisplay
                controls
                debugSection
            }
            .padding()
        }
        .onAppear {
            bleManager.startScanning()
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
            Button(bleManager.isConnected ? "Connected" : (bleManager.isScanning ? "Scanning..." : "Scan and Connect")) {
                bleManager.startScanning()
            }
            .buttonStyle(.borderedProminent)
            .disabled(bleManager.isScanning || bleManager.isConnected)

            Button(bleManager.isScanning ? "Stop Scan" : "Disconnect") {
                bleManager.disconnect()
            }
            .buttonStyle(.bordered)
            .disabled(!bleManager.isConnected && !bleManager.isScanning)
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                Text(bleManager.debugMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !bleManager.discoveredDevices.isEmpty {
                Text("Nearby BLE Devices")
                    .font(.headline)

                ForEach(bleManager.discoveredDevices, id: \.self) { device in
                    Text(device)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
