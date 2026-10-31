import AppKit
import CryptoKit
import Foundation
import Security

/// Checks GitHub Releases for a newer Blacklevel Remote and installs it in place.
/// The one request that leaves the local network, so it can be switched off in Settings.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let page: URL
        let zip: URL
        let sums: URL?
    }

    static let shared = Updater()

    /// The newer release, once a check finds one.
    @Published private(set) var release: Release?
    @Published private(set) var checking = false
    @Published private(set) var installing = false
    /// What went wrong with the last check or install; "Up to date" after a check that found nothing.
    @Published private(set) var status: String?
    @Published var checkAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(checkAutomatically, forKey: "checkUpdates")
            schedule()
        }
    }

    static let releasesPage = URL(string: "https://github.com/itsonlyjames/blacklevel/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/itsonlyjames/blacklevel/releases/latest")!
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var timer: Timer?

    private init() {
        checkAutomatically = UserDefaults.standard.object(forKey: "checkUpdates") as? Bool ?? true
        schedule()
    }

    /// Once shortly after launch, then daily.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard checkAutomatically else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check() async {
        guard !checking, !installing else { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: Self.api, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                throw UpdateError("GitHub didn't answer as expected")
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = (json["assets"] as? [[String: Any]] ?? []).reduce(into: [String: URL]()) { all, asset in
                if let name = asset["name"] as? String, let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                    all[name] = url
                }
            }
            guard Self.isNewer(version, than: current) else { release = nil; status = "Up to date"; return }
            guard let zip = assets["BlacklevelRemote-\(version)-macOS.zip"] else {
                throw UpdateError("\(version) has no macOS download")
            }
            release = Release(version: version, page: page, zip: zip, sums: assets["SHA256SUMS.txt"])
            status = nil
        } catch {
            // Keeps any release already found: a failed background check shouldn't hide it.
            status = error.localizedDescription
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installing

    /// For `--update`: prints what happens and quits, unless the install relaunches the app.
    func installLatest() async {
        await check()
        while checking { try? await Task.sleep(for: .milliseconds(200)) } // the launch check may be the one running
        guard let release else { print(status ?? "No update"); exit(status == "Up to date" ? 0 : 1) }
        print("Installing \(release.version) over \(Bundle.main.bundleURL.path)")
        install()
        while installing { try? await Task.sleep(for: .milliseconds(200)) }
        print(status ?? "Opened the release page")
        exit(1)
    }

    /// Downloads the release, checks it, swaps it in for the running app and relaunches.
    /// Builds from source (not Developer ID signed) can't be checked, so they get the release page instead.
    func install() {
        guard let release, !installing else { return }
        let app = Bundle.main.bundleURL
        if app.path.contains("/AppTranslocation/") {
            status = "Move Blacklevel Remote to Applications first, then update"
            return
        }
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            status = "Can't write to \(app.deletingLastPathComponent().path)"
            return
        }
        guard let team = Self.teamID(of: app) else {
            NSWorkspace.shared.open(release.page)
            return
        }
        installing = true
        status = nil
        Task {
            do {
                let fresh = try await Self.download(release, team: team)
                try Self.relaunch(replacing: app, with: fresh)
                NSApp.terminate(nil)
            } catch {
                installing = false
                status = error.localizedDescription
            }
        }
    }

    private static func download(_ release: Release, team: String) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BlacklevelUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (downloaded, response) = try await URLSession.shared.download(from: release.zip)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed") }
        let zip = dir.appendingPathComponent(release.zip.lastPathComponent)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        if let sums = release.sums {
            let (data, _) = try await URLSession.shared.data(from: sums)
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n")
                .first { $0.hasSuffix(" \(zip.lastPathComponent)") }
            let expected = line?.split(separator: " ").first.map(String.init)
            let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw UpdateError("The download didn't match its checksum") }
        }

        guard Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) != nil else { throw UpdateError("Couldn't unpack the update") }
        let fresh = dir.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: fresh.path) else { throw UpdateError("The update has no app in it") }
        // Same developer, same app: anything else isn't ours.
        guard teamID(of: fresh) == team,
              Bundle(url: fresh)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("The update isn't signed by the same developer")
        }
        return fresh
    }

    /// The Developer ID team of a validly signed app, or nil (ad hoc, unsigned, broken).
    private static func teamID(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString, [], &requirement)
        guard SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess else { return nil }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Waits for this process to quit, swaps the bundles (putting the old one back if that fails) and opens the result.
    private static func relaunch(replacing app: URL, with fresh: URL) throws {
        let script = """
        while kill -0 "$0" 2>/dev/null; do sleep 0.2; done
        old="$1.old-$$"
        mv "$1" "$old" || exit 1
        if mv "$2" "$1"; then rm -rf "$old"; else mv "$old" "$1"; fi
        open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier), app.path, fresh.path]
        try process.run()
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
