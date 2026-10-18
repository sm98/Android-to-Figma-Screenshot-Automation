import Foundation

/// Matches the pairing QR JSON schema in PROTOCOL.md.
struct QRPayload: Codable {
    let v: Int
    let deviceId: String
    let deviceName: String
    let host: String
    let port: Int
    let certFingerprint: String
    let pairToken: String

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
