import AppKit
import SwiftUI

@MainActor
final class SessionListModel: ObservableObject {
    @Published private(set) var records: [SessionRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var status: String?
    @Published var selection: Set<String> = []

    @Published var searchText = "" { didSet { rebuild() } }
    @Published var provider: AgentProvider? { didSet { rebuild() } }
    @Published var sort: SessionSort = .recent { didSet { rebuild() } }

    @Published private(set) var visible: [SessionRecord] = []

    private let index = SessionIndex()
    private var statusTask: Task<Void, Never>?

    init() {
        records = index.load()
        rebuild()
        refresh()
    }

    var query: SessionQuery {
        SessionQuery(text: searchText, provider: provider, sort: sort)
    }

    var selectedRecords: [SessionRecord] {
        visible.filter { selection.contains($0.id) }
    }

    var totalBytes: Int { records.reduce(0) { $0 + $1.byteCount } }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let scanned = await index.scan()
            records = scanned
            selection = selection.filter { id in scanned.contains { $0.id == id } }
            rebuild()
            isScanning = false
        }
    }

    func toggle(_ record: SessionRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }

    func selectAllVisible() {
        selection = Set(visible.map(\.id))
    }

    func clearSelection() {
        selection.removeAll()
    }

    /// Copies one resume command per selected session, newest first.
    func copyResumeCommands() {
        let targets = selectedRecords
        guard !targets.isEmpty else { return }
        let text = targets.map(\.resumeCommand).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show(targets.count == 1 ? "Copied resume command" : "Copied \(targets.count) commands")
    }

    func deleteSelected(permanent: Bool = false) {
        let targets = selectedRecords
        guard !targets.isEmpty else { return }
        let outcome = SessionRemover.remove(targets, mode: permanent ? .permanent : .trash)
        let removed = Set(outcome.removed.map(\.id))
        records.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
        rebuild()

        if outcome.failed.isEmpty {
            let where_ = permanent ? "Deleted" : "Moved to Trash"
            show("\(where_) \(outcome.removed.count) · \(ByteFormat.short(outcome.reclaimedBytes)) freed")
        } else {
            show("\(outcome.failed.count) session(s) could not be removed")
        }
    }

    private func rebuild() {
        visible = query.apply(to: records)
    }

    private func show(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            status = nil
        }
    }
}
