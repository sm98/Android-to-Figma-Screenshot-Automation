import Foundation

/// Tracks recently-accepted checksums so a client retrying an upload it thinks failed
/// doesn't produce a duplicate file or a duplicate Figma paste.
final class UploadDeduper {
    static let shared = UploadDeduper()

    private var seen: [String: Date] = [:]
    private let lock = NSLock()
    private let window: TimeInterval = 300

    /// Returns true (and does NOT record it again) if this checksum was already seen within the window.
    /// Otherwise records it now and returns false.
    func isDuplicate(checksum: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        prune()
        if let seenAt = seen[checksum], Date().timeIntervalSince(seenAt) < window {
            return true
        }
        seen[checksum] = Date()
        return false
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-window)
        seen = seen.filter { $0.value > cutoff }
    }
}
