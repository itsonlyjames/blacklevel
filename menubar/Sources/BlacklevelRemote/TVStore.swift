import AppKit
import Foundation

struct Source: Identifiable, Hashable {
    let uri: String
    let title: String
    let connected: Bool
    var id: String { uri }
}

struct TVApp: Identifiable, Hashable {
    let uri: String
    let title: String
    var id: String { uri }
}

/// One picture or speaker setting as the TV describes it: either a list of choices or a numeric range.
struct TVSetting: Identifiable, Hashable {
    let target: String
    var current: String
    let choices: [String]
    let range: ClosedRange<Double>?
    let step: Double
    var id: String { target }

    var title: String {
        // "colorTemperature" -> "Color Temperature"
        target.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    init?(_ dict: [String: Any]) {
        guard let target = dict["target"] as? String, dict["isAvailable"] as? Bool ?? true else { return nil }
        self.target = target
        current = "\(dict["currentValue"] ?? "")"
        var candidates = dict["candidate"] as? [[String: Any]] ?? []
        if candidates.isEmpty { candidates = Self.knownCandidates[target] ?? [] }
        if let first = candidates.first, let min = Self.number(first["min"]), let max = Self.number(first["max"]), max > min {
            range = min...max
            step = Self.number(first["step"]) ?? 1
            choices = []
        } else {
            range = nil
            step = 1
            choices = candidates.filter { $0["isAvailable"] as? Bool ?? true }.compactMap { $0["value"].map { "\($0)" } }
        }
        if range == nil && choices.isEmpty { return nil }
    }

    /// The A80J returns speaker settings without candidates, so these fill in Sony's documented values.
    private static let knownCandidates: [String: [[String: Any]]] = [
        "tvPosition": [["value": "tableTop"], ["value": "wallMount"]],
        "subwooferLevel": [["min": 0, "max": 24, "step": 1]],
        "subwooferFreq": [["min": 0, "max": 30, "step": 1]],
        "subwooferPhase": [["value": "normal"], ["value": "reverse"]],
        "subwooferPower": [["value": "on"], ["value": "off"]],
    ]

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

@MainActor
final class TVStore: ObservableObject {
    @Published var host: String { didSet { UserDefaults.standard.set(host, forKey: "host"); client.host = host } }
    @Published var mac: String { didSet { UserDefaults.standard.set(mac, forKey: "mac") } }
    @Published var useADBFallback: Bool { didSet { UserDefaults.standard.set(useADBFallback, forKey: "adb") } }

    @Published var model = "BRAVIA"
    @Published var power: String?          // "active" / "standby" / nil when unreachable
    @Published var authorized: Bool?       // nil until we've tried an authenticated call
    @Published var nowPlaying: String?
    @Published var volume: Double = 0
    @Published var maxVolume: Double = 100
    @Published var muted = false
    @Published var sources: [Source] = []
    @Published var apps: [TVApp] = []
    @Published var remoteCodes: [String: String] = [:]
    @Published var pictureSettings: [TVSetting] = []
    @Published var soundSettings: [TVSetting] = []
    @Published var methods: [String: [String: [String]]] = [:]   // service -> method -> versions
    @Published var message: String?
    @Published var screenshot: NSImage?

    let client: BraviaClient
    private var poller: Timer?

    init() {
        let defaults = UserDefaults.standard
        // Carry settings over from when the app was called BraviaBar (a different bundle ID, so different defaults).
        if defaults.string(forKey: "host") == nil, let legacy = UserDefaults(suiteName: "local.hijackingtv.braviabar") {
            for key in ["host", "mac", "adb"] { if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) } }
        }
        host = defaults.string(forKey: "host") ?? ""
        mac = defaults.string(forKey: "mac") ?? ""
        useADBFallback = defaults.object(forKey: "adb") as? Bool ?? true
        client = BraviaClient(host: defaults.string(forKey: "host") ?? "", psk: Keychain.readPSK())
    }

    var isOn: Bool { power == "active" }
    var hasPSK: Bool { !(client.psk ?? "").isEmpty }
    var adbAvailable: Bool { ADB.path != nil }
    func supports(_ service: String, _ method: String) -> Bool { methods[service]?[method] != nil }

    func setPSK(_ psk: String) {
        Keychain.savePSK(psk)
        client.psk = psk
        set(\.authorized, nil)
        set(\.apps, [])
        Task { await refresh() }
    }

    /// Assigns only when the value changed, so polls that find nothing new don't re-render the menu.
    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<TVStore, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func startPolling() {
        poller?.invalidate()
        poller = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLive() }
        }
        Task { await refresh() }
    }

    func stopPolling() {
        poller?.invalidate()
        poller = nil
    }

    // MARK: Loading

    /// Runs on every menu open. The menu shows the last known state straight away; independent reads run
    /// concurrently, and one-time data (model, method list, remote codes, key check, app list) is cached.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        // First run: no address yet, so use the first TV that answers an SSDP search.
        if host.isEmpty, let found = await Discovery.findTVs().first { host = found }
        if model == "BRAVIA" { await loadModel() }
        await refreshLive()
        guard power != nil else { return }
        if mac.isEmpty, authorized != true { detectMAC() }

        async let methodsLoaded: () = methods.isEmpty ? loadMethodTypes() : ()
        async let authChecked: () = authorized == true ? () : checkAuthorization()
        async let codesLoaded: () = remoteCodes.isEmpty ? loadRemoteCodes() : ()
        async let sourcesLoaded: () = loadSources()
        async let settingsLoaded: () = loadSettings()
        _ = await (methodsLoaded, authChecked, codesLoaded, sourcesLoaded, settingsLoaded)
        if authorized == true, apps.isEmpty { await loadApps() }
    }

    private var refreshing = false
    /// True while the volume slider is being dragged, so polls don't yank it back.
    var volumeEditing = false

    /// Re-checks the key even when an earlier check passed (Settings → Test Connection).
    func verifyKey() async {
        set(\.authorized, nil)
        await checkAuthorization()
    }

    /// getSystemInformation is PSK-only, so it tells us whether the key works (and gives the MAC for Wake-on-LAN).
    /// A success is cached; a later 403 from any action clears it again.
    private func checkAuthorization() async {
        guard hasPSK else { set(\.authorized, false); return }
        do {
            let info = try await client.call("system", "getSystemInformation").first as? [String: Any]
            set(\.authorized, true)
            if let found = info?["macAddr"] as? String, !found.isEmpty { set(\.mac, found) }
        } catch BraviaError.needsAuth {
            set(\.authorized, false)
        } catch {}
    }

    private func loadModel() async {
        if let info = try? await client.call("system", "getInterfaceInformation").first as? [String: Any],
           let name = info["modelName"] as? String {
            set(\.model, name)
        }
    }

    /// The cheap, frequently-changing state: power, volume, what's playing. Polled every 5 s while the menu is open.
    func refreshLive() async {
        do {
            let status = try await client.call("system", "getPowerStatus").first as? [String: Any]
            set(\.power, status?["status"] as? String)
            if message == "Can't reach the TV at \(host)" { set(\.message, nil) }
        } catch {
            set(\.power, nil)
            set(\.message, error.localizedDescription)
            return
        }
        guard isOn else { set(\.nowPlaying, nil); return }

        async let volumeLoaded: () = loadVolume()
        async let playingLoaded: () = loadNowPlaying()
        _ = await (volumeLoaded, playingLoaded)
    }

    private func loadVolume() async {
        guard let speakers = try? await client.call("audio", "getVolumeInformation").first as? [[String: Any]],
              let speaker = speakers.first(where: { $0["target"] as? String == "speaker" }) ?? speakers.first else { return }
        if !volumeEditing, let value = (speaker["volume"] as? NSNumber)?.doubleValue { set(\.volume, value) }
        if let value = (speaker["maxVolume"] as? NSNumber)?.doubleValue { set(\.maxVolume, value) }
        if let value = speaker["mute"] as? Bool { set(\.muted, value) }
    }

    private func loadNowPlaying() async {
        guard authorized == true else { set(\.nowPlaying, nil); return }
        do {
            let info = try await client.call("avContent", "getPlayingContentInfo").first as? [String: Any]
            let title = (info?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            set(\.nowPlaying, title ?? info?["source"] as? String)
        } catch {
            // Sony returns "Illegal State" while an app (not an input or channel) is on screen; it doesn't say which.
            set(\.nowPlaying, nil)
        }
    }

    private func loadMethodTypes() async {
        var all: [String: [String: [String]]] = [:]
        await withTaskGroup(of: (String, [Any]?).self) { group in
            for service in ["system", "avContent", "audio", "appControl", "video", "videoScreen"] {
                group.addTask { [client] in (service, try? await client.call(service, "getMethodTypes", params: [""])) }
            }
            for await (service, rows) in group {
                for case let row as [Any] in rows ?? [] where row.count >= 4 {
                    if let name = row[0] as? String, let version = row[3] as? String {
                        all[service, default: [:]][name, default: []].append(version)
                    }
                }
            }
        }
        set(\.methods, all)
    }

    private func loadSources() async {
        guard let rows = try? await client.call("avContent", "getCurrentExternalInputsStatus").first as? [[String: Any]] else { return }
        set(\.sources, rows.compactMap { row in
            guard let uri = row["uri"] as? String else { return nil }
            let label = (row["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Source(uri: uri, title: label ?? row["title"] as? String ?? uri,
                          connected: row["connection"] as? Bool ?? true)
        })
    }

    private func loadApps() async {
        guard let rows = try? await client.call("appControl", "getApplicationList").first as? [[String: Any]] else { return }
        set(\.apps, rows.compactMap { row in
            guard let uri = row["uri"] as? String, let title = row["title"] as? String else { return nil }
            return TVApp(uri: uri, title: title)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    private func loadRemoteCodes() async {
        guard let result = try? await client.call("system", "getRemoteControllerInfo"), result.count > 1,
              let rows = result[1] as? [[String: Any]] else { return }
        var codes: [String: String] = [:]
        for row in rows {
            if let name = row["name"] as? String, let value = row["value"] as? String { codes[name] = value }
        }
        set(\.remoteCodes, codes)
    }

    private func loadSettings() async {
        async let picture = try? client.call("video", "getPictureQualitySettings", params: [["target": ""]])
        async let sound = try? client.call("audio", "getSpeakerSettings", params: [["target": ""]])
        if let rows = await picture?.first as? [[String: Any]] { set(\.pictureSettings, rows.compactMap(TVSetting.init)) }
        if let rows = await sound?.first as? [[String: Any]] { set(\.soundSettings, rows.compactMap(TVSetting.init)) }
    }

    // MARK: Actions

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                self.set(\.message, nil)
            } catch BraviaError.needsAuth {
                self.set(\.authorized, false)
                self.set(\.message, BraviaError.needsAuth.localizedDescription)
            } catch {
                self.set(\.message, error.localizedDescription)
            }
        }
    }

    func togglePower() {
        if power == nil || !isOn, !mac.isEmpty {
            try? BraviaClient.wake(mac: mac, host: host)
        }
        let target = !isOn
        perform {
            try await self.client.call("system", "setPowerStatus", params: [["status": target]])
            try await Task.sleep(for: .seconds(2))
            await self.refresh()
        }
    }

    func setVolume(_ value: Double) {
        perform { try await self.client.call("audio", "setAudioVolume", params: [["target": "speaker", "volume": String(Int(value.rounded()))]]) }
    }

    func toggleMute() {
        let target = !muted
        muted = target
        perform { try await self.client.call("audio", "setAudioMute", params: [["status": target]]) }
    }

    func play(_ source: Source) {
        perform {
            try await self.client.call("avContent", "setPlayContent", params: [["uri": source.uri]])
            await self.refreshLive()
        }
    }

    func launch(_ app: TVApp) {
        perform { try await self.client.call("appControl", "setActiveApp", params: [["uri": app.uri]]) }
    }

    /// Presses a remote key: IRCC with a PSK, otherwise ADB if enabled.
    func press(_ key: String) {
        perform {
            if let code = self.remoteCodes[key], self.authorized == true {
                try await self.client.sendIRCC(code)
            } else if self.useADBFallback, ADB.path != nil {
                try await ADB.sendKey(key, host: self.host)
            } else {
                throw BraviaError.needsAuth
            }
        }
    }

    func apply(_ setting: TVSetting, value: String, picture: Bool) {
        let method = picture ? "setPictureQualitySettings" : "setSpeakerSettings"
        let service = picture ? "video" : "audio"
        perform {
            try await self.client.call(service, method, params: [["settings": [["target": setting.target, "value": value]]]])
            await self.loadSettings()
        }
    }

    func sendText(_ text: String) {
        let versions = methods["appControl"]?["setTextForm"] ?? ["1.0"]
        let params: [Any] = versions.contains("1.0") ? [text] : [["text": text]]
        let version = versions.contains("1.0") ? "1.0" : versions.sorted().last ?? "1.1"
        perform { try await self.client.call("appControl", "setTextForm", params: params, version: version) }
    }

    /// The A80J lists getScreenshot but answers "Unsupported Operation", so ADB is tried after the REST API.
    var canScreenshot: Bool { (authorized == true && supports("system", "getScreenshot")) || adbAvailable }

    func takeScreenshot() {
        let version = methods["system"]?["getScreenshot"]?.sorted().last ?? "1.0"
        perform {
            var image: NSImage?
            if self.authorized == true, self.supports("system", "getScreenshot"),
               let result = try? await self.client.call("system", "getScreenshot", version: version) {
                image = try await Self.image(from: result)
            }
            if image == nil, self.adbAvailable {
                image = NSImage(data: try await ADB.screenshot(host: self.host))
            }
            guard let image else { throw BraviaError.transport("The TV couldn't take a screenshot") }
            self.screenshot = image
            let url = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BRAVIA \(Date().formatted(.iso8601)).png".replacingOccurrences(of: ":", with: "."))
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// getScreenshot isn't documented; accept a URL or base64 image anywhere in the result.
    private static func image(from result: [Any]) async throws -> NSImage? {
        var strings: [String] = []
        func collect(_ value: Any) {
            if let s = value as? String { strings.append(s) }
            if let a = value as? [Any] { a.forEach(collect) }
            if let d = value as? [String: Any] { d.values.forEach(collect) }
        }
        result.forEach(collect)
        for s in strings {
            if s.hasPrefix("http"), let url = URL(string: s) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) { return image }
            }
            if let data = Data(base64Encoded: s), let image = NSImage(data: data) { return image }
        }
        return nil
    }

    func detectMAC() {
        let host = host
        Task.detached {
            _ = Shell.run("/sbin/ping", ["-c", "1", "-t", "1", host])
            let found = Discovery.macAddress(for: host)
            await MainActor.run { if let found { self.mac = found } }
        }
    }
}
