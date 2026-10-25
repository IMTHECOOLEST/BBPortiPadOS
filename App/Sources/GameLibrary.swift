import Foundation

/// Minimal PARAM.SFO reader (PSF: header 20 bytes, then 16-byte index entries).
struct ParamSFO {
    private(set) var values: [String: String] = [:]

    init?(data: Data) {
        let b = [UInt8](data)
        guard b.count >= 20, b[0] == 0, b[1] == 0x50, b[2] == 0x53, b[3] == 0x46 else { return nil }
        func u16(_ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
        let keyTable = u32(8), dataTable = u32(12), count = u32(16)
        guard count < 4096, 20 + count * 16 <= b.count else { return nil }
        for i in 0..<count {
            let e = 20 + i * 16
            let keyStart = keyTable + u16(e)
            let format = u16(e + 2)
            let length = u32(e + 4)
            let dataStart = dataTable + u32(e + 12)
            guard keyStart < b.count, dataStart + length <= b.count else { continue }
            var keyEnd = keyStart
            while keyEnd < b.count && b[keyEnd] != 0 { keyEnd += 1 }
            let key = String(decoding: b[keyStart..<keyEnd], as: UTF8.self)
            if format == 0x0404 && length >= 4 {
                values[key] = String(u32(dataStart))
            } else {
                var end = dataStart + length
                while end > dataStart && b[end - 1] == 0 { end -= 1 }
                values[key] = String(decoding: b[dataStart..<end], as: UTF8.self)
            }
        }
    }
}

enum GameCheck: Equatable {
    case ok(version: String)
    case missingEboot
    case missingParam
    case unreadableParam
    case wrongTitle(String)
    case wrongVersion(String)

    var isOK: Bool { if case .ok = self { return true } else { return false } }

    var message: String {
        switch self {
        case .ok(let v): return "Bloodborne (CUSA03173, EU Game of the Year) \(v)"
        case .missingEboot: return "No eboot.bin in this folder."
        case .missingParam: return "No sce_sys/param.sfo in this folder."
        case .unreadableParam: return "sce_sys/param.sfo could not be read."
        case .wrongTitle(let t): return "This is \(t), not CUSA03173 (the EU Game of the Year edition)."
        case .wrongVersion(let v): return "Version \(v) found; the 1.09 update is needed."
        }
    }
}

enum GameValidator {
    static let requiredTitleID = "CUSA03173"
    static let requiredVersionPrefix = "01.09"

    static func sfo(in folder: URL) -> ParamSFO? {
        let url = folder.appendingPathComponent("sce_sys/param.sfo")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ParamSFO(data: data)
    }

    /// `requireUpdate` is false for a base-game folder that is checked on its own.
    static func check(folder: URL, requireUpdate: Bool = true) -> GameCheck {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("eboot.bin").path) else { return .missingEboot }
        guard fm.fileExists(atPath: folder.appendingPathComponent("sce_sys/param.sfo").path) else { return .missingParam }
        guard let sfo = sfo(in: folder) else { return .unreadableParam }
        let title = sfo.values["TITLE_ID"] ?? "unknown"
        guard title == requiredTitleID else { return .wrongTitle(title) }
        let version = sfo.values["APP_VER"] ?? sfo.values["VERSION"] ?? "unknown"
        if requireUpdate && !version.hasPrefix(requiredVersionPrefix) { return .wrongVersion(version) }
        return .ok(version: version)
    }
}

/// A merged view of base game + update made of symlinks (the update wins), so nothing is copied
/// and the folders the player picked stay untouched. Mirrors what the runtime's mods.py does
/// with its merged view.
enum Overlay {
    static func build(base: URL, update: URL?, at dest: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) || (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try merge(base: base, update: update, into: dest)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    private static func merge(base: URL, update: URL?, into dest: URL) throws {
        let fm = FileManager.default
        let baseNames = Set((try? fm.contentsOfDirectory(atPath: base.path)) ?? [])
        let updateNames = update.map { Set((try? fm.contentsOfDirectory(atPath: $0.path)) ?? []) } ?? []
        for name in baseNames.union(updateNames) {
            let b = base.appendingPathComponent(name)
            let u = update?.appendingPathComponent(name)
            let d = dest.appendingPathComponent(name)
            let inBase = baseNames.contains(name)
            let inUpdate = updateNames.contains(name)
            if inBase, inUpdate, let u, isDirectory(b), isDirectory(u) {
                try fm.createDirectory(at: d, withIntermediateDirectories: false)
                try merge(base: b, update: u, into: d)
            } else if inUpdate, let u {
                try fm.createSymbolicLink(at: d, withDestinationURL: u)
            } else {
                try fm.createSymbolicLink(at: d, withDestinationURL: b)
            }
        }
    }
}
