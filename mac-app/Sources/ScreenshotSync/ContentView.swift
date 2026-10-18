import SwiftUI
import ApplicationServices

struct ContentView: View {
    @EnvironmentObject var serverController: ServerController
    @ObservedObject private var pairedDeviceStore = PairedDeviceStore.shared
    @State private var showingPairing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot Sync")
                .font(.headline)

            HStack(spacing: 6) {
                Circle()
                    .fill(serverController.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Divider()

            if pairedDeviceStore.devices.isEmpty {
                Text("No paired devices yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pairedDeviceStore.devices) { device in
                        HStack {
                            Text(device.androidDeviceName)
                                .font(.caption)
                            Spacer()
                            Button {
                                pairedDeviceStore.remove(androidDeviceId: device.androidDeviceId)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button("Pair New Device…") {
                showingPairing = true
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: AXIsProcessTrusted() ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(AXIsProcessTrusted() ? .green : .orange)
                Text(AXIsProcessTrusted() ? "Figma auto-paste ready" : "Grant Accessibility access for Figma auto-paste")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280)
        .sheet(isPresented: $showingPairing) {
            PairingView()
                .environmentObject(serverController)
        }
    }

    private var statusText: String {
        if serverController.isRunning {
            return "Server running on port \(serverController.port)"
        } else if let error = serverController.lastError {
            return "Server error: \(error)"
        } else {
            return "Starting server…"
        }
    }
}
