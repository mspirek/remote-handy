import Foundation
import Darwin

/// Advisory lock survives stale files and is released by the kernel after a crash.
public final class SingleInstanceLock {
    private var descriptor: Int32 = -1
    public init() {}
    public func acquire(at url: URL) throws -> Bool {
        if descriptor >= 0 { return true }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { return false }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
        return true
    }
    public func release() {
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }
    deinit { release() }
}
