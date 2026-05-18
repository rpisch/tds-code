import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLECounterManager()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("ESP32 BLE Counter")
                    .font(.title2.weight(.semibold))

                Text(bleManager.connectionStateText)
                    .font(.subheadline)
                    .foregroundStyle(bleManager.isConnected ? .green : .secondary)
            }

            Text(bleManager.latestValueText)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()

            VStack(spacing: 12) {
                Button(bleManager.isConnected ? "Connected" : (bleManager.isScanning ? "Scanning..." : "Scan and Connect")) {
                    bleManager.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bleManager.isScanning || bleManager.isConnected)

                Button("Disconnect") {
                    bleManager.disconnect()
                }
                .buttonStyle(.bordered)
                .disabled(!bleManager.isConnected)
            }

            Text(bleManager.debugMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .onAppear {
            bleManager.startScanning()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
