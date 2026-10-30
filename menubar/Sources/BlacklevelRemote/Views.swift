import AppKit
import SwiftUI

@main
struct BlacklevelRemoteApp: App {
    @StateObject private var store = TVStore()

    init() {
        // `BlacklevelRemote --snapshot out.png` renders the live menu to a PNG and quits (for testing without clicking).
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in await Snapshot.render(to: path) }
        }
        if CommandLine.arguments.contains("--selftest") {
            Task { await SelfTest.run() }
        }
        if CommandLine.arguments.contains("--timing") {
            Task { await Timing.run() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(store)
        } label: {
            Image(systemName: store.isOn ? "tv.fill" : "tv")
        }
        .menuBarExtraStyle(.window)

        Window("Blacklevel Remote Settings", id: "settings") {
            SettingsView().environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var store: TVStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if store.authorized == false {
                Label("Set a PSK in Settings to control the TV", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if store.isOn {
                Divider()
                // The menu window can't grow past the screen, so the body scrolls once it's taller than that.
                ScrollView {
                    controls
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, maxScrollHeight))
                .onPreferenceChange(ContentHeightKey.self) { height in
                    // Whole points only, so sub-pixel layout passes don't keep resizing the window.
                    let rounded = height.rounded(.up)
                    if abs(rounded - contentHeight) >= 1 { contentHeight = rounded }
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }

    @State private var contentHeight: CGFloat = 0
    /// Leaves room for the menu bar, header and footer; read when the menu opens, not on every render.
    @State private var maxScrollHeight: CGFloat = max((NSScreen.main?.visibleFrame.height ?? 800) - 200, 300)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VolumeRow()
            RemotePad()
            if !store.sources.isEmpty { InputsGrid() }
            if !store.apps.isEmpty { AppsGroup() }
            SettingsGroup(title: "Picture", systemImage: "sparkles.tv", settings: store.pictureSettings, picture: true)
            SettingsGroup(title: "Sound", systemImage: "speaker.wave.2", settings: store.soundSettings, picture: false)
            if store.authorized == true { TextSender() }
        }
        .padding(.trailing, 2)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(store.isOn ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.model).font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: store.togglePower) {
                Image(systemName: "power")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(store.isOn ? .red : .green)
            }
            .buttonStyle(.borderless)
            // The menu window gives its first control keyboard focus, so Space/Return right after opening
            // would turn the TV off. Keep power out of the focus chain.
            .focusable(false)
            .help(store.isOn ? "Turn off" : "Turn on")
        }
    }

    private var statusText: String {
        switch store.power {
        case "active": return store.nowPlaying.map { "On · \($0)" } ?? "On"
        case "standby": return "Standby"
        case nil: return "Not connected · \(store.host)"
        default: return store.power ?? ""
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            if store.canScreenshot {
                Button { store.takeScreenshot() } label: { Image(systemName: "camera") }
                    .help("Screenshot to Pictures")
            }
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Volume

/// Keeps the slider's drag value local, so dragging doesn't publish through the store (and redraw the whole menu)
/// on every tick, and polls don't move the knob under the pointer.
struct VolumeRow: View {
    @EnvironmentObject var store: TVStore
    @State private var value: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: store.toggleMute) {
                Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            Slider(value: $value, in: 0...max(store.maxVolume, 1)) { isEditing in
                editing = isEditing
                store.volumeEditing = isEditing
                if !isEditing { store.setVolume(value) }
            }
            Text("\(Int(value.rounded()))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .onAppear { value = store.volume }
        .onChange(of: store.volume) { _, new in if !editing { value = new } }
    }
}

// MARK: - Apps

/// Same disclosure style as Picture and Sound, with apps as buttons like the inputs.
struct AppsGroup: View {
    @EnvironmentObject var store: TVStore

    var body: some View {
        DisclosureGroup {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(store.apps) { app in
                    Button { store.launch(app) } label: {
                        Text(app.title).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Apps", systemImage: "square.grid.2x2")
        }
    }
}

// MARK: - Remote

struct RemotePad: View {
    @EnvironmentObject var store: TVStore

    /// Keys the pad can send: IRCC names the TV reported, or the ADB fallback set.
    private var available: Set<String> {
        if store.authorized == true && !store.remoteCodes.isEmpty { return Set(store.remoteCodes.keys) }
        if store.useADBFallback && store.adbAvailable { return Set(ADB.keycodes.keys) }
        return []
    }

    var body: some View {
        if available.isEmpty { EmptyView() } else { pad }
    }

    private var pad: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 4) {
                key("Up", "chevron.up")
                HStack(spacing: 4) {
                    key("Left", "chevron.left")
                    key("Confirm", "circle.fill", prominent: true)
                    key("Right", "chevron.right")
                }
                key("Down", "chevron.down")
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    key("Return", "arrow.uturn.backward")
                    key("Home", "house")
                }
                HStack(spacing: 6) {
                    key("Rewind", "backward.fill")
                    key(available.contains("Play") ? "Play" : "Pause", "playpause.fill")
                    key("Forward", "forward.fill")
                }
                HStack(spacing: 6) {
                    key("VolumeDown", "speaker.minus")
                    key("VolumeUp", "speaker.plus")
                    moreKeys
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func key(_ name: String, _ symbol: String, prominent: Bool = false) -> some View {
        Button { store.press(name) } label: {
            Image(systemName: symbol)
                .font(prominent ? .system(size: 9) : .body)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.bordered)
        .disabled(!available.contains(name))
        .help(name)
    }

    private var moreKeys: some View {
        Menu {
            ForEach(available.sorted(), id: \.self) { name in
                Button(name) { store.press(name) }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .frame(width: 38)
        .help("All remote keys")
    }
}

// MARK: - Inputs

struct InputsGrid: View {
    @EnvironmentObject var store: TVStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inputs").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(store.sources) { source in
                    Button { store.play(source) } label: {
                        Text(source.title).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .opacity(source.connected ? 1 : 0.5)
                }
            }
        }
    }
}

// MARK: - Picture / sound

struct SettingsGroup: View {
    @EnvironmentObject var store: TVStore
    let title: String
    let systemImage: String
    let settings: [TVSetting]
    let picture: Bool

    var body: some View {
        if !settings.isEmpty {
            DisclosureGroup {
                VStack(spacing: 6) {
                    ForEach(settings) { setting in
                        SettingRow(setting: setting) { store.apply(setting, value: $0, picture: picture) }
                    }
                }
                .padding(.top, 4)
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

struct SettingRow: View {
    let setting: TVSetting
    let onChange: (String) -> Void
    @State private var value: Double = 0

    var body: some View {
        HStack {
            Text(setting.title).font(.callout).lineLimit(1)
            Spacer()
            if let range = setting.range {
                Slider(value: $value, in: range, step: setting.step) { editing in
                    if !editing { onChange(String(Int(value))) }
                }
                .frame(width: 120)
                Text("\(Int(value))").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
            } else {
                Picker("", selection: Binding(get: { setting.current }, set: onChange)) {
                    ForEach(setting.choices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
        .onAppear { value = Double(setting.current) ?? 0 }
        .onChange(of: setting.current) { _, new in value = Double(new) ?? value }
    }
}

// MARK: - Text

struct TextSender: View {
    @EnvironmentObject var store: TVStore
    @State private var text = ""

    var body: some View {
        if store.supports("appControl", "setTextForm") {
            HStack {
                TextField("Type into the TV's text box", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send).disabled(text.isEmpty)
            }
        }
    }

    private func send() {
        store.sendText(text)
        text = ""
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @EnvironmentObject var store: TVStore
    @State private var psk = Keychain.readPSK() ?? ""
    @State private var discovered: [String] = []
    @State private var searching = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("TV") {
                HStack {
                    TextField("Address", text: $store.host)
                    Button(searching ? "Searching…" : "Find") { find() }.disabled(searching)
                }
                if !discovered.isEmpty {
                    Picker("Found", selection: $store.host) {
                        ForEach(discovered, id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    TextField("MAC address (for Wake-on-LAN)", text: $store.mac)
                    Button("Detect") { store.detectMAC() }
                }
            }

            Section {
                SecureField("Pre-shared key", text: $psk)
                HStack {
                    Button("Save Key") { store.setPSK(psk) }
                    Button("Test Connection") { test() }
                    if let testResult { Text(testResult).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Pre-shared key")
            } footer: {
                Text("On the TV: Settings → Network & Internet → Home network → IP control. Set Authentication to “Normal and Pre-Shared Key”, then choose a Pre-Shared Key and enter the same one here. It's stored in your keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fallback") {
                Toggle("Use ADB for remote keys when no key is set", isOn: $store.useADBFallback)
                    .disabled(!store.adbAvailable)
                if !store.adbAvailable {
                    Text("adb isn't installed.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func find() {
        searching = true
        Task {
            discovered = await Discovery.findTVs()
            if store.host.isEmpty, let first = discovered.first { store.host = first }
            searching = false
            if discovered.isEmpty { testResult = "No TVs answered" }
        }
    }

    private func test() {
        testResult = "Testing…"
        Task {
            await store.refresh()
            await store.verifyKey()
            switch (store.power, store.authorized) {
            case (nil, _): testResult = "Can't reach the TV"
            case (_, true?): testResult = "Connected with key ✓"
            case (_, false?): testResult = "Reachable, key rejected or not set"
            default: testResult = "Reachable (TV in standby)"
            }
        }
    }
}

// MARK: - Snapshot

@MainActor
enum Snapshot {
    static func render(to path: String) async {
        let store = TVStore()
        await store.refresh()
        let view = MenuView().environmentObject(store).background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        hosting.frame.size = hosting.fittingSize
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }
}
