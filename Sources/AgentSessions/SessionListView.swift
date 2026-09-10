import AppKit
import SwiftUI

struct SessionListView: View {
    @ObservedObject var model: SessionListModel
    @State private var confirmingDelete = false
    @FocusState private var searchFocused: Bool

    private let rowLimit = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            filters
            Divider()
            list
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Agent Sessions").font(.headline)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
            } else {
                Button("Rescan", systemImage: "arrow.clockwise") { model.refresh() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Rescan transcripts")
            }
        }
    }

    private var summary: String {
        let total = model.records.count
        let shown = model.visible.count
        let size = ByteFormat.short(model.totalBytes)
        return shown == total ? "\(total) · \(size)" : "\(shown)/\(total) · \(size)"
    }

    private var filters: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search title, directory or id", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { model.searchText = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Picker("Provider", selection: $model.provider) {
                    Text("All").tag(AgentProvider?.none)
                    ForEach(AgentProvider.allCases) { provider in
                        Text(provider.displayName).tag(AgentProvider?.some(provider))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Sort", selection: $model.sort) {
                    ForEach(SessionSort.manual) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private var list: some View {
        Group {
            if model.visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(model.records.isEmpty ? "No transcripts found" : "Nothing matches that search")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.visible.prefix(rowLimit)) { record in
                            SessionRow(
                                record: record,
                                isSelected: model.selection.contains(record.id),
                                toggle: { model.toggle(record) }
                            )
                        }
                        if model.visible.count > rowLimit {
                            Text("\(model.visible.count - rowLimit) more — narrow the search to see them")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .frame(height: 340)
            }
        }
    }

    private var footer: some View {
        Group {
            if confirmingDelete {
                deleteConfirmation
            } else {
                actions
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let status = model.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else if model.selection.isEmpty {
                Text("Click rows to select")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.selection.count) selected")
                    .font(.caption.weight(.medium))
                Button("None") { model.clearSelection() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            Button("Copy resume") { model.copyResumeCommands() }
                .disabled(model.selection.isEmpty)
            Button("Trash", role: .destructive) { confirmingDelete = true }
                .disabled(model.selection.isEmpty)
            Menu {
                Button("Select all shown") { model.selectAllVisible() }
                Divider()
                Button("Quit Agent Sessions") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
    }

    /// The confirmation stays inside the popover. A sheet or `confirmationDialog`
    /// takes key focus away from the menu bar window, which closes it and tears down
    /// this view before the button's action ever runs, so the delete never happened.
    private var deleteConfirmation: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Move \(model.selection.count) session(s) to the Trash?")
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Cancel") { confirmingDelete = false }
            Button("Move to Trash", role: .destructive) {
                confirmingDelete = false
                model.deleteSelected()
            }
        }
        .help("Transcripts go to the Trash, so you can put them back.")
    }
}

private struct SessionRow: View {
    let record: SessionRecord
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 13))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Label(record.provider.displayName, systemImage: record.provider.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(record.directoryLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    HStack(spacing: 6) {
                        Text(Format.relative(record.updatedAt))
                        Text("·")
                        Text("\(record.messageCount) turns")
                        Text("·")
                        Text(ByteFormat.short(record.byteCount))
                        if record.isArchived {
                            Text("· archived").foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy resume command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.resumeCommand, forType: .string)
            }
            Button("Copy session id") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.sessionID, forType: .string)
            }
            Button("Show transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: record.transcriptPath)])
            }
        }
    }
}
