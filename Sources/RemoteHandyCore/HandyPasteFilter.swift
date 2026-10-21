import Foundation

public enum PasteKeyEventKind {
    case down, up, modifiers
}

/// Pure key-pair policy. The macOS adapter supplies observed process/focus metadata.
public struct HandyPasteFilter {
    public private(set) var suppressedPasteCount = 0
    private var pendingVRelease = false
    private var pendingCommandRelease = false

    public init() {}

    public var isComplete: Bool {
        suppressedPasteCount > 0 && !pendingVRelease && !pendingCommandRelease
    }

    public mutating func shouldSuppress(
        kind: PasteKeyEventKind, key: Int64, command: Bool,
        sourcePID: Int64, handyPID: Int64?, targetMatches: Bool
    ) -> Bool {
        guard let handyPID, sourcePID == handyPID else { return false }
        // Always finish a swallowed key pair, even if focus changed in between.
        if kind == .up && key == 9 && pendingVRelease {
            pendingVRelease = false
            return true
        }
        if kind == .modifiers && (key == 55 || key == 54) {
            if !command && pendingCommandRelease {
                pendingCommandRelease = false
                return true
            }
            guard targetMatches else { return false }
            pendingCommandRelease = command
            return true
        }
        guard targetMatches else { return false }
        if kind == .down && key == 9 && command {
            pendingVRelease = true
            suppressedPasteCount += 1
            return true
        }
        return false
    }
}
