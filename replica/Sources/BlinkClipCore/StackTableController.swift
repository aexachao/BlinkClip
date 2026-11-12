import AppKit

@MainActor
private final class StackTableView: NSTableView {
    // 0a0b2c: the Stack table permits window dragging independently of row selection.
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Recovered Stack table behavior. Presentation of an individual replica item is supplied by the UI.
@MainActor public final class StackTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    public let tableView: NSTableView
    public let scrollView: NSScrollView
    private var snippetInputs: [ClipboardRestoreItem] = [] { didSet { snippetsRevision &+= 1 } }
    // Value-only clients retain their existing API; the production table uses native inputs.
    public var snippets: [ClipboardItem] {
        get { snippetInputs.map { $0.resolvedItem() } }
        set { snippetInputs = newValue.map { ClipboardRestoreItem(item: $0) } }
    }
    public var snippetIDs: [UUID] { snippetInputs.map(\.id) }
    private var snippetsRevision: UInt = 0
    private var animatedInputsAwaitingRefresh: [ClipboardRestoreItem]?
    public var makeCell: ((ClipboardItem, Int) -> NSView)?
    public var makeNativeCell: ((ClipboardRestoreItem, Int) -> NSView)?
    public var removeSnippet: (([UUID], Int) -> Bool)?
    public var removeActionTitle = ""
    private var heightConstraint: NSLayoutConstraint?

    public override init() {
        tableView = StackTableView(frame: .init(x: 0, y: 0, width: 264, height: 44))
        scrollView = NSScrollView(frame: tableView.frame)
        super.init()
        let column = NSTableColumn(identifier: .init("snippet"))
        column.width = 264
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
    }

    /// Retain and reuse a height constraint on the enclosing scroll view.
    public func tableHeightConstraint() -> NSLayoutConstraint {
        if let heightConstraint { return heightConstraint }
        let constraint = tableView.enclosingScrollView!.heightAnchor.constraint(equalToConstant: tableView.rowHeight)
        heightConstraint = constraint
        return constraint
    }

    /// The animator commits its constant on a later run-loop turn.
    public func updateTableHeight() {
        let constraint = tableHeightConstraint()
        constraint.animator().constant = tableView.rowHeight * CGFloat(min(10, max(1, snippetInputs.count)))
        constraint.isActive = true
    }

    private func sameInputs(_ lhs: [ClipboardRestoreItem], _ rhs: [ClipboardRestoreItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { pair in
            if pair.0.hasNativeEntity || pair.1.hasNativeEntity {
                return pair.0.hasSameEntity(as: pair.1)
            }
            return pair.0.resolvedItem() == pair.1.resolvedItem()
        }
    }

    public func updateSnippets(_ values: [ClipboardItem]) {
        updateNativeSnippets(values.map { ClipboardRestoreItem(item: $0) })
    }

    public func updateNativeSnippets(_ values: [ClipboardRestoreItem]) {
        let preserveRemoval = animatedInputsAwaitingRefresh.map { sameInputs($0, values) } == true
            && sameInputs(snippetInputs, values)
        animatedInputsAwaitingRefresh = nil
        snippetInputs = values
        if !preserveRemoval { tableView.reloadData() }
        updateTableHeight()
    }

    public func didInsertSnippet(previousIDs: [UUID], updated: [ClipboardItem], at index: Int) {
        didInsertNativeSnippet(previousIDs: previousIDs, updated: updated.map { ClipboardRestoreItem(item: $0) }, at: index)
    }

    public func didInsertNativeSnippet(previousIDs: [UUID], updated: [ClipboardRestoreItem], at index: Int) {
        guard updated.count == previousIDs.count + 1, updated.indices.contains(index) else { return }
        var priorIDs = updated.map(\.id)
        priorIDs.remove(at: index)
        guard priorIDs == previousIDs else { return }
        if snippetIDs == previousIDs {
            snippetInputs = updated
            animatedInputsAwaitingRefresh = updated
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                updateTableHeight()
                tableView.insertRows(at: IndexSet(integer: index), withAnimation: .effectGap)
                if updated.count > 10 { tableView.scrollRowToVisible(index) }
            }
        } else {
            // The observed state may have reached the table before this notification.
            if !sameInputs(snippetInputs, updated) {
                snippetInputs = updated
                tableView.reloadData()
            }
            updateTableHeight()
            if updated.count > 10 { tableView.scrollRowToVisible(index) }
        }
    }

    public func didConsumeHead(previousIDs: [UUID], remaining: [ClipboardItem]) {
        didConsumeNativeHead(previousIDs: previousIDs, remaining: remaining.map { ClipboardRestoreItem(item: $0) })
    }

    public func didConsumeNativeHead(previousIDs: [UUID], remaining: [ClipboardRestoreItem]) {
        guard !previousIDs.isEmpty, Array(previousIDs.dropFirst()) == remaining.map(\.id) else { return }
        if snippetIDs == previousIDs {
            snippetInputs = remaining
            animatedInputsAwaitingRefresh = remaining
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                tableView.animator().removeRows(at: IndexSet(integer: 0), withAnimation: .slideUp)
                tableView.scrollRowToVisible(0)
                updateTableHeight()
            }
        } else {
            // A SwiftUI refresh may already have applied the model change.
            if !sameInputs(snippetInputs, remaining) {
                snippetInputs = remaining
                tableView.reloadData()
            }
            tableView.scrollRowToVisible(0)
            updateTableHeight()
        }
    }

    public func currentCount() -> Int { snippetInputs.count }
    public func shouldSelectRow(row: Int) -> Bool { false }

    public func tableView(_ tableView: NSTableView, rowActionsForRow row: Int,
                          edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing else { return [] }
        return [NSTableViewRowAction(style: .destructive, title: removeActionTitle) { [weak self] _, row in
            guard let self else { return }
            self.removeRow(at: row, expectedIDs: self.snippetIDs)
        }]
    }

    public func removeRow(at row: Int, expectedIDs: [UUID]) {
        guard snippetIDs == expectedIDs, snippetInputs.indices.contains(row),
              let removeSnippet else { return }
        let revision = snippetsRevision
        guard removeSnippet(expectedIDs, row), snippetsRevision == revision else { return }
        snippetInputs.remove(at: row)
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .slideUp)
        updateTableHeight()
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { currentCount() }
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { shouldSelectRow(row: row) }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard snippetInputs.indices.contains(row) else { return nil }
        let input = snippetInputs[row]
        if let makeNativeCell { return makeNativeCell(input, row) }
        return makeCell?(input.resolvedItem(), row)
    }
}
