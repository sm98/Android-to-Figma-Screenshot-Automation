import Foundation
import Security
import CryptoKit

struct TLSIdentity {
    let secIdentity: SecIdentity
    let certificateDER: Data
    let fingerprintSHA256Hex: String
}

enum TLSIdentityError: Error {
    case opensslFailed(String)
    case importFailed
    case keychainWriteFailed(OSStatus)
}

/// Generates (once) or loads a self-signed TLS identity used to secure the local server.
/// There is no CA involved: clients pin `fingerprintSHA256Hex` instead of trusting a chain.
///
/// The key pair and certificate are produced by shelling out to the system's `/usr/bin/openssl`
/// (LibreSSL, ships with macOS) rather than hand-rolling X.509 DER encoding in Swift. The
/// resulting PKCS#12 blob is stored in the login Keychain so the identity survives app restarts.
final class TLSIdentityStore {
    static let shared = TLSIdentityStore()

    private let keychainService = "com.screenshotsync.tls-identity"
    private let keychainAccount = "server-identity-p12"
    private let p12Password = "screenshotsync-local"

    func loadOrCreateIdentity() throws -> TLSIdentity {
        if let existing = readP12FromKeychain(), let identity = try? importIdentity(from: existing) {
            return identity
        }
        let generated = try generateP12ViaOpenSSL()
        try saveP12ToKeychain(generated)
        return try importIdentity(from: generated)
    }

    private func generateP12ViaOpenSSL() throws -> Data {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let keyURL = tmpDir.appendingPathComponent("key.pem")
        let certURL = tmpDir.appendingPathComponent("cert.pem")
        let p12URL = tmpDir.appendingPathComponent("identity.p12")

        try run("/usr/bin/openssl", [
            "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", keyURL.path, "-out", certURL.path,
            "-days", "3650", "-nodes", "-subj", "/CN=ScreenshotSync"
        ])

        try run("/usr/bin/openssl", [
            "pkcs12", "-export",
            "-inkey", keyURL.path, "-in", certURL.path,
            "-out", p12URL.path,
            "-passout", "pass:\(p12Password)"
        ])

        return try Data(contentsOf: p12URL)
    }

    private func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "unknown openssl error"
            throw TLSIdentityError.opensslFailed(msg)
        }
    }

    private func importIdentity(from p12Data: Data) throws -> TLSIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: p12Password]
        var rawItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let firstItem = items.first,
              let identityRef = firstItem[kSecImportItemIdentity as String] else {
            throw TLSIdentityError.importFailed
        }
        let secIdentity = identityRef as! SecIdentity // swiftlint:disable:this force_cast

        var certRef: SecCertificate?
        SecIdentityCopyCertificate(secIdentity, &certRef)
        guard let cert = certRef else { throw TLSIdentityError.importFailed }
        let certData = SecCertificateCopyData(cert) as Data
        let digest = SHA256.hash(data: certData)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()

        return TLSIdentity(secIdentity: secIdentity, certificateDER: certData, fingerprintSHA256Hex: fingerprint)
    }

    private func readP12FromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func saveP12ToKeychain(_ data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TLSIdentityError.keychainWriteFailed(status)
        }
    }
}
