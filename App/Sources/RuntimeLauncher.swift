import Foundation

@MainActor
final class RuntimeLauncher: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var availableMemoryMB: Int = 0

    var runtimeLinked: Bool { bb_runtime_available() != 0 }

    /// The recompiled game library made from the player's own game (scripts/mac/build_recomp_ios.sh).
    static var recompLibraryPath: String? {
        let path = Bundle.main.bundlePath + "/Frameworks/librecomp.dylib"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    static var moltenVKPath: String? {
        let path = Bundle.main.bundlePath + "/Frameworks/libMoltenVK.dylib"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func refreshMemory() {
        availableMemoryMB = Int(bb_available_memory() / (1024 * 1024))
    }

    func launch(config: Config, game: URL) {
        guard runtimeLinked else {
            state = .failed("The game runtime is not part of this build (see docs/STATUS.md).")
            return
        }
        let data = GameStore.supportDir
        do {
            try FileManager.default.createDirectory(at: data.appendingPathComponent("user"), withIntermediateDirectories: true)
            try config.bbportINI().write(to: data.appendingPathComponent("bbport.ini"), atomically: true, encoding: .utf8)
        } catch {
            state = .failed("Could not write settings: \(error.localizedDescription)")
            return
        }
        var env = config.environment(gameDir: game, dataDir: data)
        if let lib = Self.recompLibraryPath { env["BB_RECOMP_LIB"] = lib }
        if let vk = Self.moltenVKPath { env["SDL_VULKAN_LIBRARY"] = vk }
        env["BB_JIT"] = "0"   // iPadOS makes no executable memory: recompiled code + interpreter
        for (key, value) in env { setenv(key, value, 1) }

        let bundle = Bundle.main.bundlePath
        let pythonHome = bundle + "/python"
        let stdlib = Self.stdlibPath(pythonHome: pythonHome)
        let scripts = bundle + "/bbpy/runtime/scripts"
        let gamePath = game.path
        let dataPath = data.path
        let fps = config.frameCap.rawValue
        let logPath = data.appendingPathComponent("runtime.log").path

        state = .preparing
        // Preparing the game image takes a while: off the main thread. The runtime itself must
        // then run on the main thread, which pumps the game window's events.
        let thread = Thread { [weak self] in
            var err = [CChar](repeating: 0, count: 1024)
            let errLen = err.count
            let rc = bb_runtime_prepare(pythonHome, stdlib, scripts, gamePath, dataPath, fps, logPath, &err, errLen)
            let message = String(cString: err)
            Task { @MainActor in
                guard let self else { return }
                if rc != 0 { self.state = .failed(message); return }
                self.state = .running
                var runErr = [CChar](repeating: 0, count: 256)
                let runLen = runErr.count
                let code = bb_runtime_run(&runErr, runLen)
                self.finished(code: code, message: String(cString: runErr))
            }
        }
        thread.name = "bb-prepare"
        thread.stackSize = 16 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func finished(code: Int32, message: String) {
        state = code == 0 ? .idle : .failed(message.isEmpty ? "The runtime stopped (code \(code))." : message)
    }

    /// `<bundle>/python/lib/python3.x`, whichever minor version the support package carries.
    nonisolated private static func stdlibPath(pythonHome: String) -> String {
        let lib = pythonHome + "/lib"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: lib)) ?? []
        let version = names.filter { $0.hasPrefix("python3.") }.sorted().last ?? "python3.13"
        return lib + "/" + version
    }
}
