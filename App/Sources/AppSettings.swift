import Foundation

/// The three resolution presets. The runtime's `output_res` setting is the size the whole game
/// renders at when the upscaler is off (scripts/patches.py: scaled_sizes), so each preset is
/// simply one of the 16:9 outputs the runtime already lists.
enum QualityPreset: String, CaseIterable, Codable, Identifiable {
    case performance, balanced, quality
    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: return "Performance (540p)"
        case .balanced: return "Balanced (720p)"
        case .quality: return "Quality (1080p, slow)"
        }
    }
    var width: Int {
        switch self {
        case .performance: return 960
        case .balanced: return 1280
        case .quality: return 1920
        }
    }
    var height: Int {
        switch self {
        case .performance: return 540
        case .balanced: return 720
        case .quality: return 1080
        }
    }
    var outputRes: String { "\(width)x\(height)" }
}

enum RendererChoice: String, CaseIterable, Codable, Identifiable {
    case metal, moltenvk
    var id: String { rawValue }
    var title: String { self == .metal ? "Metal (native)" : "MoltenVK (Vulkan on Metal)" }
}

enum FrameCap: String, CaseIterable, Codable, Identifiable {
    case fps30 = "30", fps60 = "60", uncapped = "uncap"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fps30: return "30 FPS (the game's original rate)"
        case .fps60: return "60 FPS"
        case .uncapped: return "Uncapped"
        }
    }
}

struct Config: Codable, Equatable {
    var preset: QualityPreset = .balanced
    var renderer: RendererChoice = .metal
    var frameCap: FrameCap = .fps30
    var showFPS = false
    var haptics = true
    var gyroAim = false
    var gyroSensitivity = 40.0   // right-stick units per rad/s of controller rotation
}

final class AppSettings: ObservableObject {
    private static let key = "bb.config.v1"
    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let value = try? JSONDecoder().decode(Config.self, from: data) {
            config = value
        } else {
            config = Config()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension Config {
    /// bbport.ini lines the runtime reads (gpu/shim/bbport_settings.cpp, scripts/patches.py).
    func bbportINI() -> String {
        [
            "output_res=\(preset.outputRes)",
            "aspect_ratio=16:9",
            "upscaler=off",
            "live_resolution=0",     // a startup patch, not the live path that copies targets back
            "show_fps=\(showFPS ? 1 : 0)",
        ].joined(separator: "\n") + "\n"
    }

    /// Environment the runtime reads (run.sh's Darwin branch, translated).
    func environment(gameDir: URL, dataDir: URL) -> [String: String] {
        var env: [String: String] = [
            "BB_PREBUILT": "1",
            "BB_GAME_DIR": gameDir.path,
            "BB_DATA_DIR": dataDir.path,
            "BB_USER_DIR": dataDir.appendingPathComponent("user").path,
            "BB_GPU_USER_DIR": dataDir.appendingPathComponent("user").path,
            "BB_CONFIG": dataDir.appendingPathComponent("bbport.ini").path,
            "BB_METAL_FRAME": renderer == .metal ? "1" : "0",
            "BB_FPS": frameCap.rawValue,
            "BB_GUEST_IN_PLACE": "0",
            "BB_PREUPLOAD": "0",       // no extra GPU-side copies: unified memory is the scarce thing
            "MVK_CONFIG_LOG_LEVEL": "1",
            "BB_GYRO_AIM": gyroAim ? "1" : "0",
            "BB_GYRO_SENS": String(gyroSensitivity),
            "BB_HAPTICS": haptics ? "1" : "0",
        ]
        if renderer == .metal { env["BB_GFX_BACKEND"] = "metal" }
        switch frameCap {
        case .uncapped: env["BB_VBLANK_HZ"] = "480"
        default: env["BB_VBLANK_HZ"] = "60"
        }
        return env
    }
}
