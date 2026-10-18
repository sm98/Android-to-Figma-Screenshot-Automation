import Foundation
import Security

struct PendingPairing {
    let token: String
    let expiresAt: Date
}

/// Owns this Mac's stable identity plus the single in-flight pairing token (if any).
/// A pairing token is single-use and short-lived; consuming it clears it so it can't be replayed.
final class PairingManager {
    static let shared = PairingManager()

    let deviceId: String
    let deviceName: String

    private var pending: PendingPairing?
    private let lock = NSLock()

    private init() {
        deviceId = Self.loadOrCreateDeviceId()
        deviceName = Host.current().localizedName ?? "Mac"
    }

    func generatePairingToken(ttl: TimeInterval = 180) -> String {
        let token = Self.randomToken()
        lock.lock()
        pending = PendingPairing(token: token, expiresAt: Date().addingTimeInterval(ttl))
        lock.unlock()
        return token
    }

    /// Validates and consumes a pairing token. Returns false for unknown, expired, or already-used tokens.
    func consumeToken(_ token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current = pending, current.token == token, current.expiresAt > Date() else {
            return false
        }
        pending = nil
        return true
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func loadOrCreateDeviceId() -> String {
        let key = "macDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
