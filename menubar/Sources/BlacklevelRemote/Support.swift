import Foundation
import Security

/// Stores the pre-shared key in the login keychain.
enum Keychain {
    private static let service = "io.github.itsonlyjames.blacklevel.remote"
    /// Where the key lived when the app was called BraviaBar; moved to `service` on first read.
    private static let legacyService = "local.hijackingtv.braviabar"
    private static let account = "psk"

    static func readPSK() -> String? {
        if let psk = read(service: service) { return psk }
        guard let psk = read(service: legacyService) else { return nil }
        savePSK(psk)
        return psk
    }

    private static func read(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func savePSK(_ psk: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !psk.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(psk.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// Finds BRAVIA TVs with an SSDP search for Sony's ScalarWebAPI service.
enum Discovery {
    static func findTVs(timeout: TimeInterval = 3) async -> [String] {
        await Task.detached { search(timeout: timeout) }.value
    }

    private static func search(timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n" +
            "ST: urn:schemas-sony-com:service:ScalarWebAPI:1\r\n\r\n"
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &addr.sin_addr)
        let bytes = Array(message.utf8)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var found: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard n > 0 else { continue }
            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN))
            let host = String(cString: ip)
            if !found.contains(host) { found.append(host) }
        }
        return found
    }

    /// Looks up the TV's MAC address in the Mac's ARP cache (needed for Wake-on-LAN).
    static func macAddress(for host: String) -> String? {
        guard let output = Shell.run("/usr/sbin/arp", ["-n", host]) else { return nil }
        let pattern = #"at ([0-9a-fA-F]{1,2}(:[0-9a-fA-F]{1,2}){5})"#
        guard let range = output.range(of: pattern, options: .regularExpression) else { return nil }
        let mac = output[range].dropFirst(3)
        return mac.split(separator: ":").map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":")
    }
}

/// Fallback remote keys over ADB, for when no PSK is set but ADB debugging is on.
enum ADB {
    static let path: String? = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static let keycodes: [String: Int] = [
        "Up": 19, "Down": 20, "Left": 21, "Right": 22, "Confirm": 23,
        "Return": 4, "Home": 3, "Play": 126, "Pause": 127, "Stop": 86,
        "Rewind": 89, "Forward": 90, "Prev": 88, "Next": 87,
        "VolumeUp": 24, "VolumeDown": 25, "Mute": 164, "Input": 178, "Options": 82,
    ]

    static func sendKey(_ name: String, host: String) async throws {
        guard let path, let code = keycodes[name] else { throw BraviaError.transport("No ADB key for \(name)") }
        let serial = "\(host):5555"
        try await Task.detached {
            _ = Shell.run(path, ["connect", serial])
            guard Shell.run(path, ["-s", serial, "shell", "input", "keyevent", String(code)]) != nil else {
                throw BraviaError.transport("ADB couldn't reach the TV")
            }
        }.value
    }

    static func screenshot(host: String) async throws -> Data {
        guard let path else { throw BraviaError.transport("adb isn't installed") }
        let serial = "\(host):5555"
        return try await Task.detached {
            _ = Shell.run(path, ["connect", serial])
            guard let data = Shell.runData(path, ["-s", serial, "exec-out", "screencap", "-p"]), !data.isEmpty else {
                throw BraviaError.transport("ADB couldn't reach the TV")
            }
            return data
        }.value
    }
}

enum Shell {
    /// Runs a command and returns stdout as raw bytes, or nil if it exited non-zero.
    static func runData(_ path: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Runs a command and returns stdout, or nil if it exited non-zero.
    static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension String {
    /// The TV sends some names HTML-escaped ("Timers &amp; Clock").
    var htmlDecoded: String {
        guard contains("&") else { return self }
        return [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")]
            .reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
