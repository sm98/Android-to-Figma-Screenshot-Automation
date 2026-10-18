import Foundation
import Network
import Security

/// Minimal HTTP/1.1-over-TLS server built directly on Network.framework, with no external
/// server dependency. Each connection is treated as a single request/response (Connection: close)
/// which is all a LAN screenshot-upload client needs.
final class HTTPServer {
    typealias Handler = (HTTPRequest) -> HTTPResponse

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.screenshotsync.server")
    private var handlers: [String: Handler] = [:]
    private let maxBodySize = 25 * 1024 * 1024

    private(set) var port: UInt16 = 0
    var onStateChange: ((Bool) -> Void)?

    func route(_ path: String, handler: @escaping Handler) {
        handlers[path] = handler
    }

    /// - Parameters:
    ///   - bonjourName: advertised Bonjour instance name (shown in mDNS browsers), typically the Mac's device name.
    ///   - bonjourTXT: TXT record key/values advertised alongside the service; the Android app resolves this
    ///     Mac's current IP at send-time by browsing `_screenshotsync._tcp` and matching TXT `id` to the
    ///     `deviceId` it stored during pairing, rather than trusting a remembered IP.
    func start(
        identity: SecIdentity,
        preferredPort: UInt16 = 51828,
        bonjourName: String,
        bonjourTXT: [String: String]
    ) throws {
        guard let secIdentityRef = sec_identity_create(identity) else {
            throw NSError(domain: "HTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not bridge SecIdentity"])
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentityRef)
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false

        let requestedPort = NWEndpoint.Port(rawValue: preferredPort) ?? .any
        let listener = try NWListener(using: params, on: requestedPort)

        listener.service = NWListener.Service(
            name: bonjourName,
            type: "_screenshotsync._tcp",
            txtRecord: TXTRecordEncoder.encode(bonjourTXT)
        )

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue ?? 0
                self.onStateChange?(true)
            case .failed, .cancelled:
                self.onStateChange?(false)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                }
                if error != nil {
                    connection.cancel()
                    return
                }
                if let contentLength = HTTPRequestParser.peekContentLength(buffer), contentLength > self.maxBodySize {
                    self.send(response: HTTPResponse.json(413, ["status": "error", "message": "payload too large"]), on: connection)
                    return
                }
                if let request = HTTPRequestParser.tryParse(buffer) {
                    let response = self.route(for: request)
                    self.send(response: response, on: connection)
                    return
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                receiveMore()
            }
        }

        receiveMore()
    }

    private func route(for request: HTTPRequest) -> HTTPResponse {
        guard let handler = handlers[request.path] else {
            return HTTPResponse.json(404, ["status": "error", "message": "not found"])
        }
        return handler(request)
    }

    private func send(response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
