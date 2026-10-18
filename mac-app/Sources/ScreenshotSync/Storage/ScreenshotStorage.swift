import Foundation

enum ScreenshotStorageError: Error {
    case writeFailed
}

enum ScreenshotStorage {
    /// Also creates the folder if it doesn't exist yet — called both at app launch and on every
    /// save, so the folder is visible immediately rather than only appearing after the first upload.
    @discardableResult
    static func destinationFolder() -> URL {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let folder = desktopURL.appendingPathComponent("Mobile Screenshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Saves as `<DeviceName>_<yyyyMMdd_HHmmss>.<ext>`, suffixing with `_1`, `_2`, ... on collision.
    static func save(_ data: Data, deviceName: String, originalFilename: String) throws -> URL {
        let ext = (originalFilename as NSString).pathExtension.isEmpty
            ? "png"
            : (originalFilename as NSString).pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let safeDeviceName = deviceName.replacingOccurrences(of: " ", with: "-")

        let folder = destinationFolder()
        var filename = "\(safeDeviceName)_\(timestamp).\(ext)"
        var url = folder.appendingPathComponent(filename)
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path) {
            filename = "\(safeDeviceName)_\(timestamp)_\(suffix).\(ext)"
            url = folder.appendingPathComponent(filename)
            suffix += 1
        }

        do {
            try data.write(to: url)
        } catch {
            throw ScreenshotStorageError.writeFailed
        }
        return url
    }
}
