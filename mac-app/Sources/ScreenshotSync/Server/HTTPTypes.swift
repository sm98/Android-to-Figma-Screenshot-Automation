import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String] // lowercased keys
    let body: Data
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String] = [:]
    var body: Data = Data()

    static func json(_ status: Int, _ object: [String: Any]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: data)
    }

    func serialize() -> Data {
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        allHeaders["Connection"] = "close"

        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        for (key, value) in allHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return ""
        }
    }
}

/// Parses a single HTTP/1.1 request from an accumulating buffer. Returns nil until the
/// full request (headers + declared Content-Length body) has arrived.
enum HTTPRequestParser {
    static func tryParse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEndRange.upperBound
        let availableBody = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard availableBody >= contentLength else {
            return nil // wait for more data
        }
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    /// Reads Content-Length as soon as headers are available, even if the body hasn't fully
    /// arrived yet — lets the server reject an oversized upload immediately instead of buffering it.
    static func peekContentLength(_ buffer: Data) -> Int? {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        for line in headerString.components(separatedBy: "\r\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "content-length" else { continue }
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            return Int(value)
        }
        return nil
    }
}
