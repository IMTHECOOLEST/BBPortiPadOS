import Foundation
import GameController

extension Notification.Name {
    static let bbControllersChanged = Notification.Name("bb.controllers.changed")
}

enum BBControllers {
    private static var observing = false

    static func names() -> [String] {
        if !observing {
            observing = true
            for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    NotificationCenter.default.post(name: .bbControllersChanged, object: nil)
                }
            }
        }
        return GCController.controllers().map { $0.vendorName ?? "Controller" }
    }
}

enum AddressProbe {
    /// Reserves and releases address space and reports what the system allowed.
    static func run() -> String {
        var info = BBVAProbe()
        bb_probe_address_space(&info)
        func gib(_ v: UInt64) -> String { String(format: "%.1f GiB", Double(v) / 1_073_741_824.0) }
        return """
        reservable in 1 GiB blocks: \(gib(info.reserved_total))
        largest single block: \(gib(info.largest_block))
        highest address reserved: 0x\(String(info.highest_address, radix: 16))
        """
    }
}
