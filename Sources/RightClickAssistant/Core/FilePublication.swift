import Foundation
import Darwin

/// Same-volume publication that atomically refuses every existing destination, including symlinks.
public enum FilePublication {
    public static func publish(_ source: URL, to destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renamex_np(from!, to!, UInt32(RENAME_EXCL))
            }
        }
        if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}
