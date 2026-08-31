@testable import GhosttyTerminal
import Testing

// Hardware keys must not race a composition input method: while a CJK input
// mode is active, printable presses open (or extend) the IME's preedit, and
// the terminal only sees the committed text. These tests pin the routing
// decisions that keep pinyin keystrokes out of the shell.
struct TerminalIMECompositionTests {
    @Test
    func `composition languages are detected by primary language prefix`() {
        #expect(TerminalIMEComposition.languageUsesComposition("zh-Hans"))
        #expect(TerminalIMEComposition.languageUsesComposition("zh-Hant"))
        #expect(TerminalIMEComposition.languageUsesComposition("ja-JP"))
        #expect(TerminalIMEComposition.languageUsesComposition("ko-KR"))

        #expect(!TerminalIMEComposition.languageUsesComposition("en-US"))
        #expect(!TerminalIMEComposition.languageUsesComposition("de-DE"))
        #expect(!TerminalIMEComposition.languageUsesComposition("emoji"))
        #expect(!TerminalIMEComposition.languageUsesComposition("dictation"))
        #expect(!TerminalIMEComposition.languageUsesComposition(nil))
    }

    @Test
    func `marked text claims every key for the input method`() {
        for characters in ["n", " ", "\r", "\u{1B}", "1", "", "UIKeyInputUpArrow"] {
            #expect(TerminalIMEComposition.shouldDeferKey(
                characters: characters,
                hasMarkedText: true,
                inputModeUsesComposition: true
            ))
            // Marked text can outlive an input-mode switch mid-composition.
            #expect(TerminalIMEComposition.shouldDeferKey(
                characters: characters,
                hasMarkedText: true,
                inputModeUsesComposition: false
            ))
        }
    }

    @Test
    func `printable keys defer to an active composition input mode`() {
        for characters in ["n", "N", " ", "1", ";"] {
            #expect(TerminalIMEComposition.shouldDeferKey(
                characters: characters,
                hasMarkedText: false,
                inputModeUsesComposition: true
            ))
        }
    }

    @Test
    func `control and function keys keep driving the terminal`() {
        for characters in [
            "\r", // Return: must stay a real Enter key event
            "\t",
            "\u{1B}", // Escape
            "\u{7F}", // Delete
            "", // Backspace reports empty characters
            "UIKeyInputUpArrow",
            "\u{F700}", // AppKit-style function key scalar
        ] {
            #expect(!TerminalIMEComposition.shouldDeferKey(
                characters: characters,
                hasMarkedText: false,
                inputModeUsesComposition: true
            ))
        }
    }

    @Test
    func `function keys are encoded by key, printable ones by text`() {
        for characters in ["\u{7F}", "", "\r", "\t", "\u{1B}", "\u{F700}", "UIKeyInputUpArrow"] {
            #expect(TerminalIMEComposition.encodesByKey(characters: characters))
        }
        // A Korean IME commits the peeled-off jamo while the key is Backspace;
        // the jamo itself is text and the two must not be confused.
        for characters in ["n", " ", "ㅇ", "녀", "1"] {
            #expect(!TerminalIMEComposition.encodesByKey(characters: characters))
        }
    }

    @Test
    func `direct input modes never defer`() {
        for characters in ["n", " ", "\r", ""] {
            #expect(!TerminalIMEComposition.shouldDeferKey(
                characters: characters,
                hasMarkedText: false,
                inputModeUsesComposition: false
            ))
        }
    }
}
