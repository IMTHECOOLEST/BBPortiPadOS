import Foundation

enum ImportRole: String, CaseIterable, Identifiable {
    case base, update
    var id: String { rawValue }
    var title: String { self == .base ? "Game (base)" : "Update (1.09)" }
    var hint: String {
        self == .base
            ? "The game's folder or its .pkg (CUSA03173, EU Game of the Year)."
            : "The 1.09 update's folder or .pkg. Skip it if your folder already has the update merged in."
    }
}

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var base: URL?
    @Published private(set) var update: URL?
    @Published private(set) var status: GameCheck?
    @Published private(set) var busy: String?
    @Published private(set) var progress: Double?
    @Published var errorMessage: String?

    /// Folders the picker returned stay open for as long as the app runs.
    private var openScopes: [URL] = []

    nonisolated static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("Bloodborne", isDirectory: true)
    }
    private static var gamesDir: URL { supportDir.appendingPathComponent("Games", isDirectory: true) }
    private static var mergedDir: URL { supportDir.appendingPathComponent("Merged", isDirectory: true) }

    /// The folder the runtime gets: base + update merged, or the base folder alone.
    var launchFolder: URL? {
        guard status?.isOK == true else { return nil }
        return update == nil ? base : Self.mergedDir
    }

    // MARK: - Restoring

    func restore() {
        for role in ImportRole.allCases {
            if let data = UserDefaults.standard.data(forKey: "bookmark.\(role.rawValue)") {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    if url.startAccessingSecurityScopedResource() { openScopes.append(url) }
                    set(role, url)
                }
            } else if let path = UserDefaults.standard.string(forKey: "path.\(role.rawValue)"),
                      FileManager.default.fileExists(atPath: path) {
                set(role, URL(fileURLWithPath: path))
            }
        }
        refresh()
    }

    // MARK: - Importing

    func importPicked(_ urls: [URL], role: ImportRole) async {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        if scoped { openScopes.append(url) }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            do {
                let data = try url.bookmarkData()
                UserDefaults.standard.set(data, forKey: "bookmark.\(role.rawValue)")
                UserDefaults.standard.removeObject(forKey: "path.\(role.rawValue)")
            } catch {
                errorMessage = "Could not remember this folder: \(error.localizedDescription)"
            }
            set(role, url)
        } else if url.pathExtension.lowercased() == "pkg" {
            await extract(pkg: url, role: role)
        } else {
            errorMessage = "Choose a game folder or a .pkg file."
        }
        refresh()
    }

    func clear(_ role: ImportRole) {
        UserDefaults.standard.removeObject(forKey: "bookmark.\(role.rawValue)")
        UserDefaults.standard.removeObject(forKey: "path.\(role.rawValue)")
        set(role, nil)
        refresh()
    }

    private func set(_ role: ImportRole, _ url: URL?) {
        if role == .base { base = url } else { update = url }
    }

    private func extract(pkg: URL, role: ImportRole) async {
        let dest = Self.gamesDir.appendingPathComponent(role.rawValue, isDirectory: true)
        busy = "Extracting \(pkg.lastPathComponent)…"
        progress = 0
        defer { busy = nil; progress = nil }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try await PkgImporter.extract(pkg: pkg, to: dest) { done, total in
                Task { @MainActor [weak self] in
                    self?.progress = total > 0 ? Double(done) / Double(total) : nil
                }
            }
            guard let root = Self.findGameRoot(in: dest) else {
                errorMessage = "The package was extracted, but no eboot.bin or sce_sys folder was found in it."
                return
            }
            UserDefaults.standard.set(root.path, forKey: "path.\(role.rawValue)")
            UserDefaults.standard.removeObject(forKey: "bookmark.\(role.rawValue)")
            set(role, root)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The folder (at most three levels down) that holds eboot.bin or sce_sys.
    nonisolated static func findGameRoot(in folder: URL, depth: Int = 0) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("eboot.bin").path) ||
            fm.fileExists(atPath: folder.appendingPathComponent("sce_sys").path) { return folder }
        guard depth < 3, let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }
        for name in names.sorted() {
            let child = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue,
               let found = findGameRoot(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Validation

    func refresh() {
        guard let base else { status = nil; return }
        if let update {
            do {
                try Overlay.build(base: base, update: update, at: Self.mergedDir)
                status = GameValidator.check(folder: Self.mergedDir)
            } catch {
                status = nil
                errorMessage = "Could not combine the game and the update: \(error.localizedDescription)"
            }
        } else {
            status = GameValidator.check(folder: base)
        }
    }
}
