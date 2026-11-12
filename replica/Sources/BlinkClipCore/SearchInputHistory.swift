import Foundation

@MainActor
public final class SearchInputHistory {
    public struct Snapshot: Equatable {
        public let nodes: [SearchQueryNode]
        public let selection: NSRange

        public init(nodes: [SearchQueryNode], selection: NSRange) {
            self.nodes = nodes
            self.selection = selection
        }
    }

    private var undo: [Snapshot] = []
    private var redo: [Snapshot] = []
    private var timer: Timer?
    private var pending: Snapshot?
    public private(set) var current: Snapshot
    private let interval: TimeInterval

    public init(nodes: [SearchQueryNode] = [], interval: TimeInterval) {
        current = Snapshot(nodes: nodes, selection: NSRange(location: 0, length: 0))
        self.interval = interval
    }

    deinit { timer?.invalidate() }

    public func appendSnapshot(_ snapshot: Snapshot, immediate: Bool) {
        guard snapshot != current else { return }
        if immediate {
            flushPendingSnapshot()
            undo.append(current)
            current = snapshot
        } else {
            if pending == nil { pending = current }
            current = snapshot
            schedulePendingFlush()
        }
        redo.removeAll()
    }

    public func flushPendingSnapshot() {
        timer?.invalidate()
        timer = nil
        if let pending { undo.append(pending) }
        pending = nil
    }

    public func schedulePendingFlush() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.flushPendingSnapshot() }
        }
    }

    public func undoSnapshot() -> Snapshot? {
        flushPendingSnapshot()
        guard let snapshot = undo.popLast() else { return nil }
        redo.append(current)
        current = snapshot
        return snapshot
    }

    public func redoSnapshot() -> Snapshot? {
        guard let snapshot = redo.popLast() else { return nil }
        undo.append(current)
        current = snapshot
        return snapshot
    }

    public func clearHistory() {
        undo.removeAll()
        redo.removeAll()
        timer?.invalidate()
        timer = nil
        pending = nil
    }
}
