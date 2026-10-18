import Foundation
import Combine
import CryptoKit

@MainActor
final class ServerController: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var lastError: String?
    @Published var certFingerprint: String?

    private let server = HTTPServer()

    func start() {
        do {
            let identity = try TLSIdentityStore.shared.loadOrCreateIdentity()
            certFingerprint = identity.fingerprintSHA256Hex
            print("[ScreenshotSync] TLS cert fingerprint: \(identity.fingerprintSHA256Hex)")

            AccessibilityOnboarding.promptIfNeeded()

            server.route("/pair", handler: Self.handlePair)
            server.route("/upload", handler: Self.handleUpload)

            server.onStateChange = { [weak self] running in
                Task { @MainActor in
                    self?.isRunning = running
                    self?.port = self?.server.port ?? 0
                }
            }

            try server.start(
                identity: identity.secIdentity,
                bonjourName: PairingManager.shared.deviceName,
                bonjourTXT: ["id": PairingManager.shared.deviceId, "v": "1"]
            )
        } catch {
            lastError = "\(error)"
            print("[ScreenshotSync] Failed to start server: \(error)")
        }
    }

    // Handlers run on the server's background queue, not the main actor — they only touch
    // PairingManager and PairedDeviceStore, which are both designed to be thread-safe.
    nonisolated private static func handlePair(_ request: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let token = json["pairToken"] as? String else {
            return HTTPResponse.json(400, ["status": "error", "message": "malformed request"])
        }
        guard PairingManager.shared.consumeToken(token) else {
            return HTTPResponse.json(401, ["status": "error", "message": "invalid or expired pairing token"])
        }

        let androidDeviceId = (json["androidDeviceId"] as? String) ?? UUID().uuidString
        let androidDeviceName = (json["androidDeviceName"] as? String) ?? "Android device"
        let bearerToken = PairingManager.randomToken()
        let device = PairedDevice(
            androidDeviceId: androidDeviceId,
            androidDeviceName: androidDeviceName,
            bearerToken: bearerToken,
            pairedAt: Date()
        )
        PairedDeviceStore.shared.add(device)
        print("[ScreenshotSync] Paired new device: \(androidDeviceName) (\(androidDeviceId))")

        return HTTPResponse.json(200, [
            "status": "ok",
            "deviceId": PairingManager.shared.deviceId,
            "bearerToken": bearerToken,
            "macDeviceName": PairingManager.shared.deviceName
        ])
    }

    nonisolated private static func handleUpload(_ request: HTTPRequest) -> HTTPResponse {
        guard let auth = request.headers["authorization"], auth.hasPrefix("Bearer "),
              let device = PairedDeviceStore.shared.device(forBearerToken: String(auth.dropFirst(7))) else {
            return HTTPResponse.json(401, ["status": "error", "message": "unauthorized"])
        }

        guard let expectedChecksum = request.headers["x-checksum-sha256"] else {
            return HTTPResponse.json(400, ["status": "error", "message": "missing X-Checksum-Sha256"])
        }
        let actualChecksum = SHA256.hash(data: request.body).map { String(format: "%02x", $0) }.joined()
        guard actualChecksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
            return HTTPResponse.json(400, ["status": "error", "message": "checksum mismatch"])
        }

        if UploadDeduper.shared.isDuplicate(checksum: actualChecksum) {
            print("[ScreenshotSync] Duplicate upload from \(device.androidDeviceName), ignoring")
            return HTTPResponse.json(200, ["status": "duplicate"])
        }

        let originalFilename = request.headers["x-filename"] ?? "screenshot.png"
        do {
            let savedURL = try ScreenshotStorage.save(
                request.body,
                deviceName: device.androidDeviceName,
                originalFilename: originalFilename
            )
            print("[ScreenshotSync] Saved screenshot from \(device.androidDeviceName) to \(savedURL.path)")

            var pastedToFigma = false
            if FigmaPasteController.isFigmaFrontmost() {
                pastedToFigma = FigmaPasteController.pasteImage(request.body)
            }

            return HTTPResponse.json(200, ["status": "ok", "pastedToFigma": pastedToFigma])
        } catch {
            print("[ScreenshotSync] Failed to save screenshot: \(error)")
            return HTTPResponse.json(500, ["status": "error", "message": "\(error)"])
        }
    }
}
