import Foundation

enum PkgError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let m): return m }
    }
}

private final class ProgressBox {
    let callback: (UInt32, UInt32) -> Void
    init(_ callback: @escaping (UInt32, UInt32) -> Void) { self.callback = callback }
}

/// Extracts a PS4 .pkg through the extractor linked in BBPkg (see docs/STATUS.md: the
/// ps4-pkg-tool binary is a macOS command-line program and cannot be launched on iPadOS, so its
/// source has to be linked in as a library).
enum PkgImporter {
    static func extract(pkg: URL, to dest: URL, progress: @escaping (UInt32, UInt32) -> Void) async throws {
        let pkgPath = pkg.path
        let destPath = dest.path
        let box = ProgressBox(progress)
        let result: (Int32, String) = await Task.detached(priority: .userInitiated) {
            let pointer = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<ProgressBox>.fromOpaque(pointer).release() }
            var err = [CChar](repeating: 0, count: 512)
            let errLen = err.count
            let rc = bb_pkg_extract(pkgPath, destPath, { done, total, user in
                guard let user else { return }
                Unmanaged<ProgressBox>.fromOpaque(user).takeUnretainedValue().callback(done, total)
            }, pointer, &err, errLen)
            return (rc, String(cString: err))
        }.value
        if result.0 != 0 {
            throw PkgError.failed(result.1.isEmpty ? "Extraction failed (code \(result.0))." : result.1)
        }
    }
}
