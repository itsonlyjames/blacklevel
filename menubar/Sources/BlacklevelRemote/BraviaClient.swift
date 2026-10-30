import Foundation

enum BraviaError: LocalizedError {
    case needsAuth
    case api(Int, String)
    case badResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .needsAuth: return "Set a PSK in Settings"
        case .api(let code, let message): return "TV error \(code): \(message)"
        case .badResponse: return "Unexpected reply from the TV"
        case .transport(let message): return message
        }
    }
}

/// Talks to Sony's BRAVIA REST API (JSON-RPC over HTTP) and the IRCC SOAP endpoint.
final class BraviaClient {
    /// Set BRAVIA_TRACE=1 to print each call's duration.
    static let trace = ProcessInfo.processInfo.environment["BRAVIA_TRACE"] != nil

    var host: String
    var psk: String?
    private let session: URLSession

    init(host: String, psk: String?) {
        self.host = host
        self.psk = psk
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }

    @discardableResult
    func call(_ service: String, _ method: String, params: [Any] = [], version: String = "1.0") async throws -> [Any] {
        guard let url = URL(string: "http://\(host)/sony/\(service)") else { throw BraviaError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let psk, !psk.isEmpty { request.setValue(psk, forHTTPHeaderField: "X-Auth-PSK") }
        let body: [String: Any] = ["method": method, "id": Int.random(in: 1...9999), "params": params, "version": version]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let start = ContinuousClock.now
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw BraviaError.transport("Can't reach the TV at \(host)")
        }
        if Self.trace { print("  \(service).\(method): \(ContinuousClock.now - start)") }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BraviaError.badResponse
        }
        if let error = object["error"] as? [Any] {
            let code = error.first as? Int ?? -1
            if code == 403 || code == 401 { throw BraviaError.needsAuth }
            throw BraviaError.api(code, error.count > 1 ? "\(error[1])" : "")
        }
        return object["result"] as? [Any] ?? object["results"] as? [Any] ?? []
    }

    func sendIRCC(_ code: String) async throws {
        guard let url = URL(string: "http://\(host)/sony/IRCC") else { throw BraviaError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"", forHTTPHeaderField: "SOAPACTION")
        if let psk, !psk.isEmpty { request.setValue(psk, forHTTPHeaderField: "X-Auth-PSK") }
        request.httpBody = """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1"><IRCCCode>\(code)</IRCCCode></u:X_SendIRCC>\
        </s:Body></s:Envelope>
        """.data(using: .utf8)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw BraviaError.transport("Can't reach the TV at \(host)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 401 { throw BraviaError.needsAuth }
        if status != 200 { throw BraviaError.api(status, "IRCC rejected") }
    }

    /// Sends a Wake-on-LAN magic packet to the broadcast addresses of the TV's subnet.
    static func wake(mac: String, host: String) throws {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { throw BraviaError.transport("Invalid MAC address") }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }

        var targets = ["255.255.255.255"]
        let octets = host.split(separator: ".")
        if octets.count == 4 { targets.append(octets.prefix(3).joined(separator: ".") + ".255") }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw BraviaError.transport("Couldn't open a socket") }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(9).bigEndian
            inet_pton(AF_INET, target, &addr.sin_addr)
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
