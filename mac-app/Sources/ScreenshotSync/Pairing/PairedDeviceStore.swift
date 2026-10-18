import Foundation
import Security

/// Keychain-backed list of paired Android devices. `add`/`remove` are safe to call from any
/// thread (the server's background queue calls them during /pair), but the `@Published devices`
/// mutation is always hopped to the main queue since SwiftUI observes it.
final class PairedDeviceStore: ObservableObject {
    static let shared = PairedDeviceStore()

    @Published private(set) var devices: [PairedDevice] = []

    private let service = "com.screenshotsync.paired-devices"
    private let account = "paired-devices-json"

    private init() {
        devices = Self.load(service: service, account: account)
    }

    func add(_ device: PairedDevice) {
        var current = Self.load(service: service, account: account)
        current.removeAll { $0.androidDeviceId == device.androidDeviceId }
        current.append(device)
        Self.save(current, service: service, account: account)
        DispatchQueue.main.async { self.devices = current }
    }

    func remove(androidDeviceId: String) {
        var current = Self.load(service: service, account: account)
        current.removeAll { $0.androidDeviceId == androidDeviceId }
        Self.save(current, service: service, account: account)
        DispatchQueue.main.async { self.devices = current }
    }

    /// Fresh read from Keychain (not the cached @Published array) so auth checks on the
    /// server's background queue always see the latest revocation state.
    func device(forBearerToken token: String) -> PairedDevice? {
        Self.load(service: service, account: account).first { $0.bearerToken == token }
    }

    private static func load(service: String, account: String) -> [PairedDevice] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }

    private static func save(_ devices: [PairedDevice], service: String, account: String) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
