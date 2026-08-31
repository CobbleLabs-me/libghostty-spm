//
//  TerminalIMEComposition.swift
//  libghostty-spm
//
//  Routing decisions for hardware keys while a composition-based input
//  method (Chinese, Japanese, Korean) is the active input mode. Pure logic,
//  kept platform-free so the macOS test suite can pin it.
//

import Foundation

enum TerminalIMEComposition {
    /// Whether the input mode identified by `primaryLanguage` composes text
    /// through marked-text preedit instead of inserting each keystroke
    /// directly. These are the modes where a raw hardware key must not reach
    /// the terminal: the input method turns key sequences into text.
    static func languageUsesComposition(_ primaryLanguage: String?) -> Bool {
        guard let primaryLanguage else { return false }
        let language = primaryLanguage.lowercased()
        return language.hasPrefix("zh")
            || language.hasPrefix("ja")
            || language.hasPrefix("ko")
    }

    /// Whether a hardware key press belongs to the input method rather than
    /// the terminal.
    ///
    /// With marked text on screen every key is the input method's — it moves
    /// the composition caret, picks candidates, commits, or cancels. Before
    /// composition starts, only presses that produce printable text can open
    /// one; control characters (Return, Tab, Escape…) and function keys keep
    /// driving the terminal even while a composition input mode is active.
    static func shouldDeferKey(
        characters: String?,
        hasMarkedText: Bool,
        inputModeUsesComposition: Bool
    ) -> Bool {
        if hasMarkedText { return true }
        guard inputModeUsesComposition else { return false }
        return !encodesByKey(characters: characters)
    }

    /// Whether the terminal core encodes this press by *key* rather than by
    /// its text: Backspace, Return, Tab, Escape, arrows, function keys.
    ///
    /// Text an input method commits on such a key must not ride on the key
    /// event. Ghostty drops any text attached to Backspace outright ("we
    /// modified IME") and lets the key's own sequence displace it on the
    /// others — the jamo a Korean IME peels off with Backspace would vanish
    /// and the syllable go with it.
    static func encodesByKey(characters: String?) -> Bool {
        guard
            let text = TerminalInputText.filteredFunctionKeyText(characters),
            !text.isEmpty
        else { return true }
        return text.unicodeScalars.contains {
            $0.value < 0x20 || $0.value == 0x7F
        }
    }
}
