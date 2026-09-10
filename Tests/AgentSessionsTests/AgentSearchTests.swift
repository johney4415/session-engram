import Testing
@testable import AgentSessions

@Suite("Agent search replies")
struct AgentSearchTests {
    private let search = AgentSearch(agent: .claude, question: "the redis one")

    @Test func readsABareArrayOfIndexes() {
        #expect(search.indexes(in: "[12, 3, 40]") == [12, 3, 40])
    }

    @Test func liftsTheArrayOutOfProseAndFences() {
        let fenced = """
        Here are the ones worth reading:

        ```json
        [4, 9]
        ```
        """
        #expect(search.indexes(in: fenced) == [4, 9])
    }

    @Test func readsRankingWithReasons() {
        let reply = #"[{"index": 2, "why": "asks how big redis is"}, {"index": 7, "why": ""}]"#
        let ranked = search.ranking(in: reply)
        #expect(ranked?.count == 2)
        #expect(ranked?.first?.index == 2)
        #expect(ranked?.first?.why == "asks how big redis is")
        // A blank reason still leaves a usable label.
        #expect(ranked?.last?.why == "matched")
    }

    @Test func acceptsBareIndexesWhereObjectsWereAskedFor() {
        #expect(search.ranking(in: "[3, 1]")?.map(\.index) == [3, 1])
    }

    /// An empty array means the agent found nothing; anything unparseable means the
    /// reply could not be read. The caller treats those two very differently.
    @Test func separatesNothingFoundFromUnreadable() {
        #expect(search.indexes(in: "[]")?.isEmpty == true)
        #expect(search.indexes(in: "I could not find any matching sessions.") == nil)
        #expect(search.ranking(in: "sorry, nothing") == nil)
    }

    @Test func promptsCarryTheQuestionAndTheMarker() {
        let prompt = search.shortlistPrompt(for: [])
        #expect(prompt.hasPrefix(AgentSearch.marker))
        #expect(prompt.contains("the redis one"))
    }
}
