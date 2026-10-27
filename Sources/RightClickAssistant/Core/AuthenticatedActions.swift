import Foundation
import Security
import Darwin

public enum AuthenticatedActionValidation {
    public static func decode(_ data: Data, now: Date = Date()) throws -> SharedActionEvent {
        guard data.count <= 262_144 else { throw CocoaError(.fileReadTooLarge) }
        let event = try JSONDecoder().decode(SharedActionEvent.self, from: data)
        guard event.schemaVersion == 2, UUID(uuidString: event.id) != nil,
              abs(now.timeIntervalSince1970 - event.createdAt) <= 60,
              !event.paths.isEmpty, event.paths.count <= 1024,
              event.paths.allSatisfy({ $0.hasPrefix("/") && !$0.utf8.contains(0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return event
    }
}

public enum ActionPeerIdentity {
    public static func requirement(for bundle: URL) throws -> SecRequirement {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { throw CocoaError(.executableNotLoadable) }
        return requirement
    }

    /// Use the kernel audit token, including the PID generation, to avoid PID reuse races.
    static func verify(socket: Int32, requirement: SecRequirement) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(socket, &uid, &gid) == 0, uid == getuid() else { return false }
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout.size(ofValue: token))
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              length == MemoryLayout.size(ofValue: token) else { return false }
        let data = withUnsafeBytes(of: token) { Data($0) }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: data] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let code else { return false }
        let valid = SecCodeCheckValidity(code, [], requirement)
        return valid == errSecSuccess
    }

    public static var endpointURL: URL {
        SharedStorageManager.shared.sharedContainerURL.appendingPathComponent("actions.sock")
    }
}

private enum ActionSocket {
    static func address(_ url: URL) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(url.path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw CocoaError(.fileWriteInvalidFileName) }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    static func configure(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var enabled: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }
    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }
}

/// Disk files never authorize actions. Both peers authenticate the live process behind the socket.
public final class AuthenticatedActionServer: @unchecked Sendable {
    private var source: DispatchSourceRead?
    private let requirement: SecRequirement
    private let requestQueue = DispatchQueue(label: "guyue.authenticated-actions")
    private var seenRequests: Set<String> = []
    private var requestOrder: [String] = []
    private let handler: @Sendable (SharedActionEvent) -> Bool

    public init(
        trustedClientBundle: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/RightClickAssistantExtension.appex"),
        handler: @escaping @Sendable (SharedActionEvent) -> Bool = { event in
            ActionDispatcher.shared.submit(
                actionId: event.actionId,
                targetURLs: event.paths.map { URL(fileURLWithPath: $0) },
                invocationKind: event.invocationKind,
                completion: { _ in }
            ) == .accepted
        }
    ) throws {
        self.handler = handler
        requirement = try ActionPeerIdentity.requirement(for: trustedClientBundle)
    }

    public func start(endpointURL: URL = ActionPeerIdentity.endpointURL) throws {
        guard source == nil else { return }
        var address = try ActionSocket.address(endpointURL)
        var attributes = stat()
        if lstat(endpointURL.path, &attributes) == 0 {
            guard attributes.st_mode & S_IFMT == S_IFSOCK else { throw CocoaError(.fileWriteFileExists) }
            guard unlink(endpointURL.path) == 0 else { throw POSIXError(.EACCES) }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        ActionSocket.configure(fd)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(endpointURL.path, 0o600) == 0, listen(fd, 16) == 0 else {
            close(fd); throw POSIXError(.EIO)
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            while let self {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                ActionSocket.configure(client)
                _ = fcntl(client, F_SETFL, 0)
                // Do not let an unauthenticated process occupy a payload reader.
                guard ActionPeerIdentity.verify(socket: client, requirement: self.requirement) else { close(client); continue }
                DispatchQueue.global(qos: .userInitiated).async { self.receive(client) }
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    public func stop() { source?.cancel(); source = nil }
    deinit { stop() }

    private func receive(_ fd: Int32) {
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            if count == 0 {
                guard let event = try? AuthenticatedActionValidation.decode(data) else { return }
                let accepted = requestQueue.sync { () -> Bool in
                    guard seenRequests.insert(event.id).inserted else { return false }
                    requestOrder.append(event.id)
                    if requestOrder.count > 4096 { seenRequests.remove(requestOrder.removeFirst()) }
                    return handler(event)
                }
                _ = ActionSocket.write(Data([accepted ? 1 : 0]), to: fd)
                return
            }
            guard count > 0, data.count + count <= 262_144 else { return }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}

public enum AuthenticatedActionClient {
    public static func send(
        actionId: String, paths: [String], invocationKind: ActionInvocationKind,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let event = SharedActionEvent(id: UUID().uuidString, createdAt: Date().timeIntervalSince1970,
                                     actionId: actionId, paths: paths, invocationKind: invocationKind)
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        DispatchQueue.global(qos: .userInitiated).async {
            completion((try? send(event: event, hostBundle: host, endpointURL: ActionPeerIdentity.endpointURL)) ?? false)
        }
    }

    /// Synchronous transport also used by the regression runner; never call on the UI thread.
    public static func send(event: SharedActionEvent, hostBundle: URL, endpointURL: URL) throws -> Bool {
        let requirement = try ActionPeerIdentity.requirement(for: hostBundle)
        let payload = try JSONEncoder().encode(event)
        _ = try AuthenticatedActionValidation.decode(payload)
        var address = try ActionSocket.address(endpointURL)
        // The host may still be starting. Retry connect only, never a submitted action.
        for attempt in 0..<20 {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return false }
            ActionSocket.configure(fd)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            if connected != 0 {
                close(fd)
                if attempt < 19 { Thread.sleep(forTimeInterval: 0.25) }
                continue
            }
            defer { close(fd) }
            guard ActionPeerIdentity.verify(socket: fd, requirement: requirement), ActionSocket.write(payload, to: fd) else { return false }
            shutdown(fd, SHUT_WR)
            var response: UInt8 = 0
            return recv(fd, &response, 1, 0) == 1 && response == 1
        }
        return false
    }
}
