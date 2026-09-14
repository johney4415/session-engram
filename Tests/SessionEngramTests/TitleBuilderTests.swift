import Foundation
import Testing
@testable import SessionEngram

@Test func skipsHarnessInjectedTurns() {
    #expect(TitleBuilder.isPersonWritten("<recommended_plugins>\nAirtable\n</recommended_plugins>") == false)
    #expect(TitleBuilder.isPersonWritten("Caveat: the messages below were generated…") == false)
    #expect(TitleBuilder.isPersonWritten("[Request interrupted by user]") == false)
    #expect(TitleBuilder.isPersonWritten("幫我看一下這個 PR") == true)
}

@Test func stripsLinksAndCollapsesWhitespace() {
    let raw = "https://github.com/acme/checkout-service/pull/1234\n\n幫我處理   這個 pr 的\tconflict"
    #expect(TitleBuilder.normalize(raw) == "幫我處理 這個 pr 的 conflict")
}

@Test func titlesASlashCommandByWhatWasTypedWithIt() {
    let raw = "<command-message>review-pr</command-message>\n"
        + "<command-name>/review-pr</command-name>\n"
        + "<command-args>16942</command-args>"
    // The number is the only thing that identifies this session, so it has to survive
    // into the title or no one can search for it.
    #expect(TitleBuilder.title(from: [raw]) == "/review-pr 16942")
}

@Test func keepsTheLinkAnArgumentCarries() {
    let raw = "<command-name>/cross-review-pr</command-name>\n"
        + "<command-args>https://github.com/acme/checkout-service/pull/1234</command-args>"
    // normalize() strips links out of ordinary prompts; here the link is the argument,
    // and dropping it would drop the pr number with it.
    #expect(TitleBuilder.title(from: [raw]) == "/cross-review-pr https://github.com/acme/checkout-service/pull/1234")
}

@Test func skipsACommandThatCarriesNothing() {
    // A bare command names the command, never the session.
    #expect(TitleBuilder.slashCommand("<command-name>/clear</command-name>") == nil)
    #expect(TitleBuilder.slashCommand("<command-name>/compact</command-name><command-args></command-args>") == nil)
    #expect(TitleBuilder.isPersonWritten("<command-name>/clear</command-name>") == false)
}

@Test func stillRejectsTheHarnessOwnTurns() {
    #expect(TitleBuilder.isPersonWritten("<task-notification>\n<task-id>b1</task-id>") == false)
    #expect(TitleBuilder.displayText("<system-reminder>x</system-reminder>") == nil)
}

@Test func picksFirstMeaningfulPrompt() {
    let title = TitleBuilder.title(from: [
        "<command-name>/clear</command-name>",
        "eixt",
        "幫我解 merge conflict",
    ])
    #expect(title == "幫我解 merge conflict")
}

@Test func returnsNilWhenNothingIsUsable() {
    #expect(TitleBuilder.title(from: ["exit", "ok", "<system-reminder>x</system-reminder>"]) == nil)
}

@Test func truncatesLongPrompts() {
    let long = String(repeating: "資料", count: 60)
    let title = TitleBuilder.truncate(long)
    #expect(title.count == TitleBuilder.maxLength + 1)
    #expect(title.hasSuffix("…"))
}

@Test func keepsPastedCodeAsALabel() {
    // Pasted tracebacks are still the best label available for that session.
    let title = TitleBuilder.title(from: ["In [1]: node.on_enter(cycle, audiences)"])
    #expect(title == "In [1]: node.on_enter(cycle, audiences)")
}
