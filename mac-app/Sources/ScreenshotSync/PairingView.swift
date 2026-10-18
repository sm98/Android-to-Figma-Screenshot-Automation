import SwiftUI

struct PairingView: View {
    @EnvironmentObject var serverController: ServerController
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: NSImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair New Device")
                .font(.headline)

            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                Text("Scan this from the Android app.\nExpires in 3 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView()
            }

            Button("Done") { dismiss() }
        }
        .padding(24)
        .frame(width: 280)
        .onAppear(perform: generate)
    }

    private func generate() {
        guard let fingerprint = serverController.certFingerprint,
              let host = LocalNetworkInfo.currentIPv4Address(),
              serverController.port != 0 else {
            errorMessage = "Server isn't ready yet — try again in a moment."
            return
        }

        let token = PairingManager.shared.generatePairingToken()
        let payload = QRPayload(
            v: 1,
            deviceId: PairingManager.shared.deviceId,
            deviceName: PairingManager.shared.deviceName,
            host: host,
            port: Int(serverController.port),
            certFingerprint: fingerprint,
            pairToken: token
        )

        guard let json = payload.jsonString() else {
            errorMessage = "Failed to build pairing payload."
            return
        }

        print("[ScreenshotSync] Pairing QR payload: \(json)")
        qrImage = QRCodeGenerator.image(for: json)
    }
}
