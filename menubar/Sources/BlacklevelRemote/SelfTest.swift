import Combine
import Foundation

/// `BlacklevelRemote --selftest` checks each API the menu uses against the TV with the keychain PSK, printing one line per check.
/// Changes are restored straight away (volume and mute go back, settings are re-applied with their current values),
/// and nothing disruptive runs: no power, input switches to other sources, app launches or navigation keys.
enum SelfTest {
    static func run() async {
        let host = UserDefaults.standard.string(forKey: "host") ?? ""
        let client = BraviaClient(host: host, psk: Keychain.readPSK())
        print("PSK in keychain: \(client.psk.map { $0.isEmpty ? "empty" : "yes" } ?? "no")")

        await check("getSystemInformation (key accepted)") {
            let info = try await client.call("system", "getSystemInformation").first as? [String: Any]
            return "model \(info?["model"] ?? "?"), mac \(info?["macAddr"] ?? "?")"
        }
        await check("getPlayingContentInfo") {
            let info = try await client.call("avContent", "getPlayingContentInfo").first as? [String: Any]
            return "\(info?["title"] ?? info?["source"] ?? "nothing playing")"
        }
        await check("getApplicationList") {
            let apps = try await client.call("appControl", "getApplicationList").first as? [[String: Any]] ?? []
            return "\(apps.count) apps"
        }
        await check("getCurrentExternalInputsStatus") {
            let inputs = try await client.call("avContent", "getCurrentExternalInputsStatus").first as? [[String: Any]] ?? []
            return inputs.map { "\($0["label"] as? String ?? "") / \($0["title"] ?? "")" }.joined(separator: ", ")
        }
        await check("setPlayContent (re-select current input)") {
            let info = try await client.call("avContent", "getPlayingContentInfo").first as? [String: Any]
            guard let uri = info?["uri"] as? String, uri.hasPrefix("extInput") else { return "skipped: not on an HDMI input" }
            try await client.call("avContent", "setPlayContent", params: [["uri": uri]])
            return "ok \(uri)"
        }
        await check("setAudioVolume +1 and back") {
            let volumes = try await client.call("audio", "getVolumeInformation").first as? [[String: Any]] ?? []
            guard let speaker = volumes.first, let target = speaker["target"] as? String,
                  let volume = speaker["volume"] as? Int else { return "no volume info" }
            try await client.call("audio", "setAudioVolume", params: [["target": target, "volume": "\(volume + 1)"]])
            let after = (try await client.call("audio", "getVolumeInformation").first as? [[String: Any]])?.first?["volume"] as? Int
            try await client.call("audio", "setAudioVolume", params: [["target": target, "volume": "\(volume)"]])
            return "\(target): \(volume) → \(after.map(String.init) ?? "?") → \(volume)"
        }
        await check("setAudioMute toggle and back") {
            let speaker = (try await client.call("audio", "getVolumeInformation").first as? [[String: Any]])?.first
            let muted = speaker?["mute"] as? Bool ?? false
            try await client.call("audio", "setAudioMute", params: [["status": !muted]])
            try await client.call("audio", "setAudioMute", params: [["status": muted]])
            return "mute \(muted) → \(!muted) → \(muted)"
        }
        await check("setPictureQualitySettings (re-apply current)") {
            let settings = try await client.call("video", "getPictureQualitySettings", params: [["target": ""]]).first as? [[String: Any]] ?? []
            guard let setting = settings.first(where: { $0["target"] as? String == "brightness" }) ?? settings.first,
                  let target = setting["target"] as? String, let value = setting["currentValue"] else { return "no settings" }
            try await client.call("video", "setPictureQualitySettings", params: [["settings": [["target": target, "value": "\(value)"]]]])
            return "\(settings.count) settings; \(target)=\(value) re-applied"
        }
        await check("getSpeakerSettings") {
            let settings = try await client.call("audio", "getSpeakerSettings", params: [["target": ""]]).first as? [[String: Any]] ?? []
            return settings.map { "\($0["target"] ?? "?")=\($0["currentValue"] ?? "?")" }.joined(separator: ", ")
        }
        await check("setSpeakerSettings (re-apply current)") {
            let settings = try await client.call("audio", "getSpeakerSettings", params: [["target": ""]]).first as? [[String: Any]] ?? []
            var applied: [String] = []
            for setting in settings {
                guard let target = setting["target"] as? String, let value = setting["currentValue"] else { continue }
                try await client.call("audio", "setSpeakerSettings", params: [["settings": [["target": target, "value": "\(value)"]]]])
                applied.append(target)
            }
            return "re-applied \(applied.joined(separator: ", "))"
        }
        await check("ADB screenshot fallback") {
            let data = try await ADB.screenshot(host: host)
            return "\(data.count) bytes PNG"
        }
        await check("IRCC VolumeUp then VolumeDown") {
            let info = try await client.call("system", "getRemoteControllerInfo")
            let codes = (info.count > 1 ? info[1] : nil) as? [[String: String]] ?? []
            func code(_ name: String) -> String? { codes.first { $0["name"] == name }?["value"] }
            guard let up = code("VolumeUp"), let down = code("VolumeDown") else { return "codes missing" }
            try await client.sendIRCC(up)
            try await Task.sleep(for: .milliseconds(400))
            try await client.sendIRCC(down)
            return "\(codes.count) remote codes"
        }
        await check("getScreenshot") {
            let result = try await client.call("system", "getScreenshot", params: [[:] as [String: Any]])
            let first = result.first
            if let dict = first as? [String: Any] { return "keys: \(dict.keys.sorted().joined(separator: ","))" }
            return "type \(type(of: first as Any))"
        }
        await check("getPowerStatus") {
            let status = try await client.call("system", "getPowerStatus").first as? [String: Any]
            return "\(status?["status"] ?? "?") (power on/off not exercised)"
        }
        exit(0)
    }

    private static func check(_ name: String, _ body: () async throws -> String) async {
        do {
            print("PASS  \(name): \(try await body())")
        } catch BraviaError.api(7, _) {
            print("SKIP  \(name): Illegal State (an app, not an input, is on screen)")
        } catch {
            print("FAIL  \(name): \(error.localizedDescription)")
        }
    }
}

/// `BlacklevelRemote --timing` measures how long the menu's data loads take and how many state publishes they cause.
@MainActor
enum Timing {
    static func run() async {
        let store = TVStore()
        var publishes = 0
        let token = store.objectWillChange.sink { publishes += 1 }
        func measure(_ name: String, _ body: () async -> Void) async {
            publishes = 0
            let start = ContinuousClock.now
            await body()
            let ms = (ContinuousClock.now - start).components.attoseconds / 1_000_000_000_000_000
                + (ContinuousClock.now - start).components.seconds * 1000
            print(String(format: "%-28@ %5lld ms  %3d publishes", name as NSString, ms, publishes))
        }
        await measure("first open (cold refresh)") { await store.refresh() }
        await measure("second open (warm refresh)") { await store.refresh() }
        for i in 1...3 { await measure("poll \(i)") { await store.refreshLive() } }
        _ = token
        exit(0)
    }
}
