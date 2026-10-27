import Foundation

// Optional integration check: compile and run while the updated installed host is running.
// Only a harmless new-file request in a fresh temporary directory is attempted.
@main
struct LegacyQueueProbe {
    static func main() throws {
        let manager = FileManager.default
        let id = UUID().uuidString
        let target = manager.temporaryDirectory.appendingPathComponent("rightclick-untrusted-\(id)")
        let queue = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let event = queue.appendingPathComponent("security-probe-\(id).json")
        try manager.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: event); try? manager.removeItem(at: target) }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2, "id": id, "createdAt": Date().timeIntervalSince1970,
            "actionId": "guyue.action.newfile.txt", "paths": [target.path], "invocationKind": "container"
        ])
        try data.write(to: event, options: .withoutOverwriting)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.triggerActionSignal"), object: nil, userInfo: nil, deliverImmediately: true
        )
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        guard try manager.contentsOfDirectory(atPath: target.path).isEmpty else {
            throw NSError(domain: "LegacyQueueProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Untrusted disk request was executed"])
        }
        print("PASS: installed host ignored forged disk request + distributed notification")
    }
}
