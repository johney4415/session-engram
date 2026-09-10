import Foundation
import Testing
@testable import SessionEngram

private func record(
    _ id: String,
    provider: AgentProvider = .claude,
    title: String = "Session",
    cwd: String = "/Users/x/work",
    minutesAgo: Int = 0,
    bytes: Int = 1024,
    turns: Int = 1,
    archived: Bool = false
) -> SessionRecord {
    SessionRecord(
        provider: provider,
        sessionID: id,
        title: title,
        cwd: cwd,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(minutesAgo) * 60),
        messageCount: turns,
        byteCount: bytes,
        transcriptPath: "/tmp/\(provider.rawValue)-\(id)-\(minutesAgo).jsonl",
        auxiliaryPaths: [],
        isArchived: archived
    )
}

@Test func everySearchTermMustMatch() {
    let records = [
        record("a", title: "SQL export 數量與 preview 不符"),
        record("b", title: "SQL model placeholder"),
    ]
    var query = SessionQuery()
    query.text = "sql preview"
    #expect(query.apply(to: records).map(\.sessionID) == ["a"])
}

@Test func searchMatchesDirectoryAndID() {
    let records = [record("abc123", cwd: "/Users/x/work/checkout-service")]
    var query = SessionQuery()
    query.text = "checkout"
    #expect(query.apply(to: records).count == 1)
    query.text = "abc1"
    #expect(query.apply(to: records).count == 1)
}

@Test func filtersByProviderAndArchive() {
    let records = [
        record("a", provider: .claude),
        record("b", provider: .codex),
        record("c", provider: .codex, archived: true),
    ]
    var query = SessionQuery()
    query.provider = .codex
    #expect(query.apply(to: records).count == 2)
    query.includeArchived = false
    #expect(query.apply(to: records).map(\.sessionID) == ["b"])
}

@Test func sortsByRequestedOrder() {
    let records = [
        record("old", minutesAgo: 100, bytes: 900, turns: 9),
        record("new", minutesAgo: 1, bytes: 100, turns: 1),
    ]
    #expect(SessionSort.recent.sort(records).first?.sessionID == "new")
    #expect(SessionSort.oldest.sort(records).first?.sessionID == "old")
    #expect(SessionSort.largest.sort(records).first?.sessionID == "old")
    #expect(SessionSort.busiest.sort(records).first?.sessionID == "old")
}

@Test func resolvesIDsByPrefix() {
    let records = [record("1a2b3c4dab"), record("1a2bffff11"), record("bde677f1")]
    if case .found(let match) = SessionLookup.resolve("bde6", in: records) {
        #expect(match.sessionID == "bde677f1")
    } else {
        Issue.record("expected a single match")
    }
    if case .ambiguous(let matches) = SessionLookup.resolve("1a2b", in: records) {
        #expect(matches.count == 2)
    } else {
        Issue.record("expected an ambiguous match")
    }
    if case .notFound = SessionLookup.resolve("zzz", in: records) {} else {
        Issue.record("expected no match")
    }
}

@Test func exactIDWinsOverPrefix() {
    let records = [record("abc"), record("abcdef")]
    if case .found(let match) = SessionLookup.resolve("abc", in: records) {
        #expect(match.sessionID == "abc")
    } else {
        Issue.record("expected the exact id to win")
    }
}

@Test func buildsResumeCommandsPerProvider() {
    let claude = record("cafe", provider: .claude, cwd: "/Users/x/my work")
    #expect(claude.resumeCommand == "cd '/Users/x/my work' && claude --resume cafe")

    let codex = record("beef", provider: .codex, cwd: "/Users/x/work")
    #expect(codex.resumeCommand == "cd /Users/x/work && codex resume beef")

    let noCWD = record("beef", provider: .codex, cwd: "")
    #expect(noCWD.resumeCommand == "codex resume beef")
}

@Test func mergesSplitRolloutsIntoOneSession() {
    let first = record("thread", provider: .codex, title: "查詢台北公寓成交時間", minutesAgo: 60, bytes: 500, turns: 3)
    var second = record("thread", provider: .codex, title: TitleBuilder.fallback, minutesAgo: 5, bytes: 700, turns: 2)
    second.transcriptPath = "/tmp/codex-thread-resumed.jsonl"

    let merged = SessionMerger.merge([second, first])
    #expect(merged.count == 1)
    let session = try! #require(merged.first)
    #expect(session.title == "查詢台北公寓成交時間")
    #expect(session.byteCount == 1200)
    #expect(session.messageCount == 5)
    #expect(session.allPaths.count == 2)
    #expect(session.updatedAt == second.updatedAt)
}

@Test func keepsDistinctSessionsApart() {
    let records = [record("a"), record("b"), record("a", provider: .codex)]
    #expect(SessionMerger.merge(records).count == 3)
}
