import Testing
@testable import SessionEngram

@Suite("Terminal column arithmetic")
struct TextWidthTests {
    @Test func countsCJKCharactersAsTwoColumns() {
        #expect(TextWidth.of("abc") == 3)
        #expect(TextWidth.of("啟用工具") == 8)
        #expect(TextWidth.of("啟用 tool") == 9)
    }

    @Test func truncateFitsWithinTheGivenColumns() {
        #expect(TextWidth.truncate("abcdef", to: 6) == "abcdef")
        #expect(TextWidth.truncate("abcdef", to: 4) == "abc…")
        // A wide character that would straddle the limit is dropped whole.
        #expect(TextWidth.of(TextWidth.truncate("幫我啟用這個工具", to: 7)) <= 7)
    }

    @Test func padFillsShortTextAndClipsLongText() {
        #expect(TextWidth.pad("ab", to: 5) == "ab   ")
        #expect(TextWidth.of(TextWidth.pad("幫我啟用這個工具", to: 9)) == 9)
    }

    @Test func oneLineCollapsesPastedBlocks() {
        #expect(TextWidth.oneLine("first line\n  second\tthird ") == "first line second third")
    }
}
