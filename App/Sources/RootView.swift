import SwiftUI
import UniformTypeIdentifiers

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home", graphics = "Graphics", controls = "Controls", advanced = "Advanced", log = "Log"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .graphics: return "display"
        case .controls: return "gamecontroller"
        case .advanced: return "gearshape.2"
        case .log: return "doc.text"
        }
    }
}

/// The launcher's sidebar layout (Home, Graphics, Controls, Advanced), kept on purpose.
struct RootView: View {
    @State private var tab: Tab? = .home

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Bloodborne")
        } detail: {
            switch tab ?? .home {
            case .home: HomeView()
            case .graphics: GraphicsView()
            case .controls: ControlsView()
            case .advanced: AdvancedView()
            case .log: LogView()
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var games: GameStore
    @EnvironmentObject var launcher: RuntimeLauncher

    @State private var showPicker = false
    @State private var pickerRole: ImportRole = .base

    private var pkgType: UTType { UTType(filenameExtension: "pkg") ?? .data }

    var body: some View {
        Form {
            Section("Game files") {
                ForEach(ImportRole.allCases) { role in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(role.title).font(.headline)
                            Spacer()
                            Button("Choose folder or .pkg…") { pickerRole = role; showPicker = true }
                            if (role == .base ? games.base : games.update) != nil {
                                Button("Remove", role: .destructive) { games.clear(role) }
                            }
                        }
                        Text(role.hint).font(.footnote).foregroundStyle(.secondary)
                        if let url = (role == .base ? games.base : games.update) {
                            Text(url.lastPathComponent).font(.footnote.monospaced())
                        }
                    }
                }
                if let busy = games.busy {
                    VStack(alignment: .leading) {
                        Text(busy)
                        if let p = games.progress { ProgressView(value: p) } else { ProgressView() }
                    }
                }
                if let status = games.status {
                    Label(status.message, systemImage: status.isOK ? "checkmark.seal" : "exclamationmark.triangle")
                        .foregroundStyle(status.isOK ? .green : .orange)
                }
            }

            Section("Runtime") {
                Label(launcher.runtimeLinked ? "Game runtime: included" : "Game runtime: not in this build",
                      systemImage: launcher.runtimeLinked ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(launcher.runtimeLinked ? .green : .orange)
                Label(RuntimeLauncher.recompLibraryPath != nil ? "Recompiled game library: included" : "Recompiled game library: missing",
                      systemImage: RuntimeLauncher.recompLibraryPath != nil ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(RuntimeLauncher.recompLibraryPath != nil ? .green : .orange)
                if RuntimeLauncher.recompLibraryPath == nil {
                    Text("iPadOS cannot translate game code while it runs, so the game needs librecomp.dylib made from your own copy (scripts/mac/build_recomp_ios.sh) inside the app. Without it the game runs only in the very slow interpreter.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Summary") {
                LabeledContent("Resolution", value: settings.config.preset.title)
                LabeledContent("Renderer", value: settings.config.renderer.title)
                LabeledContent("Frame rate", value: settings.config.frameCap.title)
            }

            Section {
                Button {
                    if let folder = games.launchFolder { launcher.launch(config: settings.config, game: folder) }
                } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(games.launchFolder == nil || launcher.state == .running || launcher.state == .preparing)

                if launcher.state == .preparing { HStack { ProgressView(); Text("Preparing the game…") } }
                if case .failed(let message) = launcher.state {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Home")
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder, pkgType], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                let role = pickerRole
                Task { await games.importPicked(urls, role: role) }
            case .failure(let error):
                games.errorMessage = error.localizedDescription
            }
        }
        .alert("Import", isPresented: Binding(get: { games.errorMessage != nil },
                                              set: { if !$0 { games.errorMessage = nil } })) {
            Button("OK") { games.errorMessage = nil }
        } message: { Text(games.errorMessage ?? "") }
    }
}

struct GraphicsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Resolution") {
                Picker("Preset", selection: $settings.config.preset) {
                    ForEach(QualityPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Text("The whole game renders at this size. Changes apply at the next start.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Frame rate") {
                Picker("Limit", selection: $settings.config.frameCap) {
                    ForEach(FrameCap.allCases) { Text($0.title).tag($0) }
                }
                Toggle("FPS counter", isOn: $settings.config.showFPS)
            }
        }
        .navigationTitle("Graphics")
    }
}

struct ControlsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var controllers: [String] = []

    var body: some View {
        Form {
            Section("Connected controllers") {
                if controllers.isEmpty { Text("None. Connect a DualSense over Bluetooth.").foregroundStyle(.secondary) }
                ForEach(controllers, id: \.self) { Text($0) }
            }
            Section("DualSense") {
                Toggle("Haptics (rumble)", isOn: $settings.config.haptics)
                Toggle("Gyro aiming (moves the camera)", isOn: $settings.config.gyroAim)
                if settings.config.gyroAim {
                    HStack {
                        Text("Sensitivity")
                        Slider(value: $settings.config.gyroSensitivity, in: 10...120, step: 5)
                        Text("\(Int(settings.config.gyroSensitivity))").monospacedDigit()
                    }
                }
                Text("The touchpad works as in the Mac version: a click on the left or right half is the game's touchpad button.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Controls")
        .task { controllers = BBControllers.names() }
        .onReceive(NotificationCenter.default.publisher(for: .bbControllersChanged)) { _ in
            controllers = BBControllers.names()
        }
    }
}

struct AdvancedView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var launcher: RuntimeLauncher
    @State private var probe: String = ""
    @State private var probing = false

    var body: some View {
        Form {
            Section("Renderer") {
                Picker("Renderer", selection: $settings.config.renderer) {
                    ForEach(RendererChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Text("Metal draws directly and is usually faster. MoltenVK translates the game's Vulkan calls to Metal.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Memory and address space") {
                LabeledContent("Memory available to the app", value: launcher.availableMemoryMB > 0 ? "\(launcher.availableMemoryMB) MB" : "unknown")
                Button(probing ? "Probing…" : "Probe address space") {
                    probing = true
                    Task.detached {
                        let text = AddressProbe.run()
                        await MainActor.run { probe = text; probing = false; launcher.refreshMemory() }
                    }
                }
                .disabled(probing)
                if !probe.isEmpty { Text(probe).font(.footnote.monospaced()) }
                Text("Needs the increased-memory-limit entitlement in the signing profile to show more than the default limit.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Advanced")
        .onAppear { launcher.refreshMemory() }
    }
}

struct LogView: View {
    @State private var text = ""

    private func load() {
        let dir = GameStore.supportDir
        var out = ""
        for name in ["prepare.log", "runtime.log"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { continue }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            out += "== \(name)\n" + lines.suffix(150).joined(separator: "\n") + "\n"
        }
        text = out.isEmpty ? "Nothing logged yet." : out
    }

    var body: some View {
        ScrollView {
            Text(text).font(.footnote.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Log")
        .toolbar { Button("Reload", action: load) }
        .onAppear(perform: load)
    }
}
