import Foundation

/// Hand-rolled DNS TXT record encoding: each entry is a length byte followed by "key=value" bytes.
/// Avoids depending on the newer NWTXTRecord API so this works across a wider macOS range.
enum TXTRecordEncoder {
    static func encode(_ pairs: [String: String]) -> Data {
        var data = Data()
        for (key, value) in pairs {
            let entryBytes = Array("\(key)=\(value)".utf8.prefix(255))
            data.append(UInt8(entryBytes.count))
            data.append(contentsOf: entryBytes)
        }
        return data
    }
}
