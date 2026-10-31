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
        if CommandLine.arguments.contains("--window") {
            Task { @MainActor in DebugWindow.open() }
        }
        // `BlacklevelRemote --update` checks GitHub and installs a newer release if there is one (for testing the updater).
        if CommandLine.arguments.contains("--update") {
            Task { @MainActor in await Updater.shared.installLatest() }
        }
        _ = Updater.shared // starts the launch and daily update checks
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

// MARK: - Theme

/// The launcher's palette (launcher/app/assets/index.html), so the remote and the TV look like one thing.
enum Theme {
    static let bg = Color(red: 0.051, green: 0.043, blue: 0.035)
    static let tile = Color(red: 0.105, green: 0.094, blue: 0.082)
    static let tileHover = Color(red: 0.16, green: 0.145, blue: 0.125)
    static let ink = Color(red: 0.91, green: 0.886, blue: 0.83)
    static let dim = Color(red: 0.47, green: 0.445, blue: 0.41)
    static let line = Color.white.opacity(0.07)
    static let accent = Color(red: 0.91, green: 0.6, blue: 0.36)
    static let twoColumns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
}

/// Flat, square-cornered tile. Labels set their own size.
struct TileStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration, prominent: prominent) }

    private struct Tile: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(prominent ? Theme.accent : Theme.ink)
                .background(configuration.isPressed ? Theme.accent.opacity(0.3) : hovering ? Theme.tileHover : Theme.tile)
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.35)
                .onHover { hovering = $0 }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.dim)
    }
}

private struct Rule: View {
    var body: some View { Theme.line.frame(height: 1) }
}

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var store: TVStore
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let message = store.message {
                Text(message).font(.caption).foregroundStyle(Theme.accent)
            } else if store.authorized == false {
                Text("Set a pre-shared key in Settings to control the TV").font(.caption).foregroundStyle(Theme.dim)
            }
            if store.isOn, let issue = store.loadIssue {
                HStack(spacing: 8) {
                    Text(issue).font(.caption).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Retry", action: store.retryLoad)
                        .buttonStyle(TileStyle())
                        .font(.caption)
                        .frame(height: 22)
                }
            }

            if store.isOn || (!store.liveChecked && store.hasCachedState) {
                // The menu window can't grow past the screen, so the body scrolls once it's taller than that.
                ScrollView {
                    controls
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.never)
                .frame(height: min(contentHeight, maxScrollHeight))
                .onPreferenceChange(ContentHeightKey.self) { height in
                    // Whole points only, so sub-pixel layout passes don't keep resizing the window.
                    let rounded = height.rounded(.up)
                    if abs(rounded - contentHeight) >= 1 { contentHeight = rounded }
                }
            }

            Rule()
            if let release = updater.release { update(release) }
            footer
        }
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        // Clicking anywhere that isn't a control ends typing, like any Mac window. Buttons keep their clicks.
        .contentShape(Rectangle())
        .onTapGesture { endEditing() }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: MenuHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(MenuHeightKey.self) { height in
            let rounded = height.rounded(.up)
            if abs(rounded - menuHeight) >= 1 { menuHeight = rounded }
        }
        .background(WindowSizer(size: CGSize(width: 320, height: menuHeight)))
        // Top-aligned and filled, so a window that's briefly the wrong size shows dark, not a white band.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .environment(\.colorScheme, .dark)
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }

    @State private var contentHeight: CGFloat = 0
    @State private var menuHeight: CGFloat = 0
    /// Leaves room for the menu bar, header and footer; read when the menu opens, not on every render.
    @State private var maxScrollHeight: CGFloat = max((NSScreen.main?.visibleFrame.height ?? 800) - 200, 300)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VolumeRow()
            RemotePad()
            if !store.sources.isEmpty { InputsGrid() }
            if !store.apps.isEmpty { AppSearch() }
            SettingsGroup(title: "Picture", settings: store.pictureSettings, picture: true)
            SettingsGroup(title: "Sound", settings: store.soundSettings, picture: false)
            if store.authorized == true { TextSender() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.isOn ? Theme.accent : Theme.dim.opacity(0.5))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.model).font(.system(size: 13, weight: .semibold))
                Text(statusText).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            Button(action: store.togglePower) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(TileStyle(prominent: store.isOn))
            // The menu window gives its first control keyboard focus, so Space/Return right after opening
            // would turn the TV off. Keep power out of the focus chain.
            .focusable(false)
            // Until the first power check answers, a press can't know whether it should turn the TV on or off.
            .disabled(!store.liveChecked && !store.host.isEmpty)
            .help(store.isOn ? "Turn off" : "Turn on")
        }
    }

    private var statusText: String {
        switch store.power {
        case "active": return store.nowPlaying.map { "On · \($0)" } ?? "On"
        case "standby": return "Standby"
        case nil where !store.liveChecked && !store.host.isEmpty: return "Connecting…"
        case nil: return store.host.isEmpty ? "Looking for a TV…" : "Not connected · \(store.host)"
        default: return store.power ?? ""
        }
    }

    private func update(_ release: Updater.Release) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Version \(release.version) is available").font(.caption)
                if let status = updater.status {
                    Text(status).font(.caption).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button(action: updater.install) {
                Text(updater.installing ? "Updating…" : "Update").frame(width: 72, height: 24)
            }
            .buttonStyle(TileStyle(prominent: true))
            .disabled(updater.installing)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
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
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Theme.dim)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct MenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// MenuBarExtra's window grows with its content but doesn't reliably shrink (notably when the content changed
/// while the menu was closed, e.g. the TV went to standby), leaving a tall panel with the menu floating in it.
/// This pins the window to the menu's own size, keeping its top edge under the menu bar, and re-applies it
/// whenever the window opens or something else resizes it.
private struct WindowSizer: NSViewRepresentable {
    let size: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.size = size
        DispatchQueue.main.async { context.coordinator.attach() }
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var size: CGSize = .zero { didSet { apply() } }
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func attach() {
            guard let window = view?.window, window !== self.window else { return apply() }
            observers.forEach(NotificationCenter.default.removeObserver)
            self.window = window
            observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
            apply()
        }

        private func apply() {
            guard let window, size.height > 0 else { return }
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
            let frame = window.frame
            guard abs(frame.height - target.height) >= 1 || abs(frame.width - target.width) >= 1 else { return }
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - target.height, width: target.width, height: target.height),
                            display: true)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

// MARK: - Volume

/// Keeps the slider's drag value local, so dragging doesn't publish through the store (and redraw the whole menu)
/// on every tick, and polls don't move the knob under the pointer.
struct VolumeRow: View {
    @EnvironmentObject var store: TVStore
    @State private var value: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: store.toggleMute) {
                Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(store.muted ? Theme.accent : Theme.dim)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            Slider(value: $value, in: 0...max(store.maxVolume, 1)) { isEditing in
                editing = isEditing
                store.volumeEditing = isEditing
                if !isEditing { store.setVolume(value) }
            }
            .controlSize(.small)
            Text(store.liveChecked ? "\(Int(value.rounded()))" : "–")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .frame(width: 24, alignment: .trailing)
        }
        // Volume and mute are never cached; until the TV answers there's nothing true to show.
        .disabled(!store.liveChecked)
        .onAppear { value = store.volume }
        .onChange(of: store.volume) { _, new in if !editing { value = new } }
    }
}

/// Takes keyboard focus off whichever text field has it.
@MainActor func endEditing() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

// MARK: - Apps

/// A search field instead of the full list: the TV reports 40-odd apps, most of them Sony extras.
/// Return opens the first match.
struct AppSearch: View {
    @EnvironmentObject var store: TVStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [TVApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let matches = store.apps.filter { $0.title.localizedCaseInsensitiveContains(q) }
        // Names that start with the query first ("pl" → Plex before Google Play).
        return matches.filter { $0.title.lowercased().hasPrefix(q.lowercased()) }
            + matches.filter { !$0.title.lowercased().hasPrefix(q.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Apps")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                TextField("Search \(store.apps.count) apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { open(first) } }
                    .onExitCommand { searchFocused = false }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.tile)

            let shown = Array(results.prefix(6))
            if !shown.isEmpty {
                LazyVGrid(columns: Theme.twoColumns, spacing: 2) {
                    ForEach(shown) { app in
                        Button { open(app) } label: {
                            Text(app.title).lineLimit(1).padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(TileStyle())
                    }
                }
            } else if !query.isEmpty {
                Text("No app matches “\(query)”").font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private func open(_ app: TVApp) {
        store.launch(app)
        query = ""
        searchFocused = false
    }
}

// MARK: - Remote

struct RemotePad: View {
    @EnvironmentObject var store: TVStore
    private let size: CGFloat = 40

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
        HStack(alignment: .top, spacing: 0) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { Color.clear.frame(width: size, height: size); key("Up", "chevron.up"); Color.clear.frame(width: size, height: size) }
                GridRow { key("Left", "chevron.left"); key("Confirm", "circle.fill", prominent: true); key("Right", "chevron.right") }
                GridRow { Color.clear.frame(width: size, height: size); key("Down", "chevron.down"); Color.clear.frame(width: size, height: size) }
            }
            Spacer(minLength: 16)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { key("Return", "arrow.uturn.backward"); key("Home", "house"); moreKeys }
                GridRow {
                    key("Rewind", "backward.fill")
                    key(available.contains("Play") ? "Play" : "Pause", "playpause.fill")
                    key("Forward", "forward.fill")
                }
                GridRow { key("VolumeDown", "minus"); key("Mute", "speaker.slash"); key("VolumeUp", "plus") }
            }
        }
    }

    private func key(_ name: String, _ symbol: String, prominent: Bool = false) -> some View {
        Button { store.press(name) } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 7 : 12, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(TileStyle(prominent: prominent))
        .disabled(!available.contains(name))
        .help(name)
    }

    private var moreKeys: some View {
        Menu {
            ForEach(RemoteKeyGroups.sections) { section in
                let keys = section.keys.filter { available.contains($0.name) }
                if !keys.isEmpty {
                    Section(section.title) {
                        ForEach(keys) { key in Button(key.title) { store.press(key.name) } }
                    }
                }
            }
            let numbers = RemoteKeyGroups.numbers.filter { available.contains($0.name) }
            if !numbers.isEmpty {
                Menu("Numbers") {
                    ForEach(numbers) { key in Button(key.title) { store.press(key.name) } }
                }
            }
            let others = RemoteKeyGroups.others(in: available)
            if !others.isEmpty {
                Menu("Other keys") {
                    ForEach(others, id: \.self) { name in Button(RemoteKeyGroups.title(for: name)) { store.press(name) } }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .frame(width: size, height: size)
        }
        // A button-style menu draws its label as given, like the other tiles; .borderlessButton hosts it
        // in an AppKit pop-up button that ignores the frame and pushes the glyph off centre.
        .menuStyle(.button)
        .buttonStyle(TileStyle())
        .menuIndicator(.hidden)
        .help("All remote keys")
    }
}

/// The TV reports 152 IRCC keys; the "…" menu shows the useful ones grouped, tucks the rest into a submenu,
/// and never lists service, demo or pairing keys that can put the TV into odd states.
enum RemoteKeyGroups {
    struct Key: Identifiable {
        let name: String
        let title: String
        var id: String { name }
    }

    struct Group: Identifiable {
        let title: String
        let keys: [Key]
        var id: String { title }
    }

    static let sections: [Group] = [
        Group(title: "Menus", keys: [
            Key(name: "Options", title: "Options"),
            Key(name: "ActionMenu", title: "Action menu"),
            Key(name: "SyncMenu", title: "BRAVIA Sync menu"),
            Key(name: "Display", title: "Info"),
            Key(name: "GGuide", title: "Guide"),
            Key(name: "Help", title: "Help"),
        ]),
        Group(title: "Inputs", keys: [
            Key(name: "Input", title: "Input selector"),
            Key(name: "Hdmi1", title: "HDMI 1"),
            Key(name: "Hdmi2", title: "HDMI 2"),
            Key(name: "Hdmi3", title: "HDMI 3"),
            Key(name: "Hdmi4", title: "HDMI 4"),
        ]),
        Group(title: "Playback", keys: [
            Key(name: "Play", title: "Play"),
            Key(name: "Pause", title: "Pause"),
            Key(name: "Stop", title: "Stop"),
            Key(name: "Prev", title: "Previous"),
            Key(name: "Next", title: "Next"),
            Key(name: "SubTitle", title: "Subtitles"),
            Key(name: "Audio", title: "Audio track"),
        ]),
        Group(title: "Picture & sound", keys: [
            Key(name: "PictureMode", title: "Picture mode"),
            Key(name: "Wide", title: "Screen format"),
            Key(name: "PictureOff", title: "Picture off"),
            Key(name: "AudioOutput_Toggle", title: "Switch audio output"),
        ]),
        Group(title: "Colour buttons", keys: [
            Key(name: "Red", title: "Red"),
            Key(name: "Green", title: "Green"),
            Key(name: "Yellow", title: "Yellow"),
            Key(name: "Blue", title: "Blue"),
        ]),
        Group(title: "Apps", keys: [
            Key(name: "Netflix", title: "Netflix"),
            Key(name: "YouTube", title: "YouTube"),
            Key(name: "GooglePlay", title: "Google Play"),
        ]),
        Group(title: "Power", keys: [
            Key(name: "SleepTimer", title: "Sleep timer"),
        ]),
    ]

    static let numbers: [Key] = (1...9).map { Key(name: "Num\($0)", title: "\($0)") }
        + [Key(name: "Num0", title: "0"), Key(name: "Enter", title: "Enter")]

    /// Keys that change service, demo, pairing or shop state; they never appear in the menu.
    private static let hidden: Set<String> = [
        "DemoMode", "DemoSurround", "ShopRemoteControlForcedDynamic", "AutoParingRequest", "B2bCustomizeKey",
        "DARWINLOOP", "MicPressedFromPairedRC", "MicPressedFromUnpairedRC", "FlashPlus", "FlashMinus", "WakeUp",
        "PowerOff", "TvPower", "Sleep",
    ]

    /// Keys already on the pad, so they aren't repeated in "Other keys".
    private static let onPad: Set<String> = [
        "Up", "Down", "Left", "Right", "Confirm", "Return", "Home", "Rewind", "Forward", "PlayPause",
        "VolumeUp", "VolumeDown", "Mute", "CursorUp", "CursorDown", "CursorLeft", "CursorRight", "DpadCenter", "Exit",
    ]

    static func others(in available: Set<String>) -> [String] {
        let listed = Set(sections.flatMap(\.keys).map(\.name) + numbers.map(\.name))
        return available.subtracting(listed).subtracting(hidden).subtracting(onPad)
            .filter { !$0.hasPrefix("PartnerApp") }
            .sorted { title(for: $0).localizedCaseInsensitiveCompare(title(for: $1)) == .orderedAscending }
    }

    /// "ChannelUp" -> "Channel up", "Tv_Radio" -> "TV radio".
    static func title(for name: String) -> String {
        let spaced = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        let words = spaced.split(separator: " ").enumerated().map { index, word -> String in
            let upper = word.uppercased()
            if ["TV", "EPG", "BS", "CS", "PAP", "AD", "BSCS", "RGB", "3D", "STB", "ACS"].contains(upper) { return upper }
            return index == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
        }
        return words.joined(separator: " ")
    }
}

// MARK: - Inputs

struct InputsGrid: View {
    @EnvironmentObject var store: TVStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Inputs")
            LazyVGrid(columns: Theme.twoColumns, spacing: 2) {
                ForEach(store.sources) { source in
                    Button { store.play(source) } label: {
                        Text(source.title).lineLimit(1).padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(TileStyle(prominent: store.isPlaying(source)))
                    .opacity(source.connected ? 1 : 0.4)
                }
            }
        }
    }
}

// MARK: - Picture / sound

struct SettingsGroup: View {
    @EnvironmentObject var store: TVStore
    let title: String
    let settings: [TVSetting]
    let picture: Bool
    @State private var expanded = false

    var body: some View {
        if !settings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // No animated expand: the menu panel resizes to fit, and an animated height made it
                // resize on every frame. The section snaps open; only the chevron turns.
                Button { expanded.toggle() } label: {
                    HStack {
                        SectionLabel(text: title)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                            .animation(.easeOut(duration: 0.15), value: expanded)
                    }
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(spacing: 8) {
                        ForEach(settings) { setting in
                            SettingRow(setting: setting) { store.apply(setting, value: $0, picture: picture) }
                        }
                    }
                }
            }
        }
    }
}

struct SettingRow: View {
    let setting: TVSetting
    let onChange: (String) -> Void
    @State private var value: Double = 0

    var body: some View {
        // No pop-up menus here: they can close or misplace the menu bar panel. Choices are inline segments
        // (up to four) or a ‹ value › stepper that cycles through longer lists.
        if setting.range == nil, setting.choices.count > 2, setting.choices.count <= 4 {
            VStack(alignment: .leading, spacing: 6) {
                title
                Segments(choices: setting.choices, current: setting.current, onChange: onChange)
            }
        } else {
            HStack {
                title
                Spacer()
                if let range = setting.range {
                    Slider(value: $value, in: range, step: setting.step) { editing in
                        if !editing { onChange(String(Int(value))) }
                    }
                    .controlSize(.small)
                    .frame(width: 110)
                    Text("\(Int(value))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.dim).frame(width: 26, alignment: .trailing)
                } else if setting.choices.count <= 2 {
                    Segments(choices: setting.choices, current: setting.current, onChange: onChange).frame(width: 150)
                } else {
                    Cycler(choices: setting.choices, current: setting.current, onChange: onChange).frame(width: 150)
                }
            }
            .onAppear { value = Double(setting.current) ?? 0 }
            .onChange(of: setting.current) { _, new in value = Double(new) ?? value }
        }
    }

    private var title: some View {
        Text(setting.title).font(.system(size: 12)).lineLimit(1)
    }
}

/// A row of tiles, one per choice, with the current one in the accent colour.
private struct Segments: View {
    let choices: [String]
    let current: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { choice in
                Button { if choice != current { onChange(choice) } } label: {
                    Text(TVSetting.label(for: choice))
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(TileStyle(prominent: choice == current))
                .focusable(false)
            }
        }
    }
}

/// ‹ value › for lists too long for segments (picture mode has seven).
private struct Cycler: View {
    let choices: [String]
    let current: String
    let onChange: (String) -> Void

    private var index: Int { choices.firstIndex(of: current) ?? 0 }

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", by: -1)
            Text(TVSetting.label(for: current))
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Theme.tile)
            arrow("chevron.right", by: 1)
        }
    }

    private func arrow(_ symbol: String, by step: Int) -> some View {
        Button {
            guard !choices.isEmpty else { return }
            onChange(choices[(index + step + choices.count) % choices.count])
        } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 26, height: 26)
        }
        .buttonStyle(TileStyle())
        .focusable(false)
        .help(symbol == "chevron.left" ? "Previous" : "Next")
    }
}

// MARK: - Text

struct TextSender: View {
    @EnvironmentObject var store: TVStore
    @State private var text = ""

    var body: some View {
        if store.supports("appControl", "setTextForm") {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 11)).foregroundStyle(Theme.dim)
                TextField("Type into the TV's text box", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(send)
                    .onExitCommand(perform: endEditing)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.tile)
        }
    }

    private func send() {
        guard !text.isEmpty else { return }
        store.sendText(text)
        text = ""
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @EnvironmentObject var store: TVStore
    @ObservedObject private var updater = Updater.shared
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

            Section {
                Toggle("Check for updates daily", isOn: $updater.checkAutomatically)
                HStack {
                    if let release = updater.release {
                        Button(updater.installing ? "Updating…" : "Update to \(release.version)", action: updater.install)
                            .disabled(updater.installing)
                    } else {
                        Button(updater.checking ? "Checking…" : "Check Now") { Task { await updater.check() } }
                            .disabled(updater.checking)
                    }
                    if let status = updater.status { Text(status).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Version \(updater.current). Asks GitHub for the latest release, the only request that leaves your network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Debug window

/// `BlacklevelRemote --window` shows the menu in an ordinary window (a regular app, so UI tools can click it).
/// The window follows the view's preferred size the way the menu bar panel does.
@MainActor
enum DebugWindow {
    private static var window: NSWindow?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        let store = TVStore()
        let controller = NSHostingController(rootView: MenuView().environmentObject(store))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "Blacklevel Remote (debug)"
        window.styleMask = [.titled, .closable]
        window.setFrameTopLeftPoint(NSPoint(x: 200, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
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
