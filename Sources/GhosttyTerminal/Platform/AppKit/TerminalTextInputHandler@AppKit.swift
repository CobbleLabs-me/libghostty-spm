//
//  TerminalTextInputHandler@AppKit.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//  Reference:
//  - ghostty-org/ghostty
//  - macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift
//  IME text accumulation intentionally follows Ghostty's AppKit flow:
//  marked/preedit text is passed through as-is, without extra app-specific
//  filtering, so composition behavior stays consistent with upstream.
//

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import GhosttyKit

    @MainActor
    final class TerminalTextInputHandler: NSObject {
        private weak var view: AppTerminalView?
        private var markedTextState = TerminalMarkedTextState()
        private var accumulatedTexts: [String]?

        // MARK: - IME pseudo-document
        //
        // Right after an input-source switch (e.g. ABC → 2-Set Korean), macOS
        // IMEs do not start with marked text. They commit each intermediate
        // state and *replace* it on the next key via `replacementRange`
        // (ㅇ → 아 → 안), exactly like they do against NSTextView. A client
        // that ignores `replacementRange` — and answers `selectedRange` /
        // `attributedSubstring` with nothing — never gets offered that mode,
        // so the first jamo is committed bare and lost from the syllable.
        //
        // We therefore keep a tiny document made of the text the IME has
        // committed since the last cursor-moving event, answer the protocol
        // from it, and honor a replacement by sending backspaces — the same
        // strategy iTerm2 uses (iTermKeyboardHandler -insertText:replacementRange:).
        private var committedDoc = ""
        /// Replacements the IME asked for, to be flushed as Delete key events
        /// *before* the committed text inside the current keyDown.
        private var pendingBackspaces = 0
        /// The pseudo-document is only valid while nothing else moved the
        /// cursor. Anything we cannot see (control keys, Enter, clicks,
        /// focus changes) invalidates it.
        func resetCommittedRun() {
            committedDoc = ""
        }

        private var docLength: Int { committedDoc.utf16.count }

        func takePendingBackspaces() -> Int {
            defer { pendingBackspaces = 0 }
            return pendingBackspaces
        }

        var hasMarkedText: Bool {
            markedTextState.hasMarkedText
        }

        init(view: AppTerminalView) {
            self.view = view
            super.init()
        }

        func startCollectingText() {
            accumulatedTexts = []
        }

        func finishCollectingText() -> [String]? {
            defer { accumulatedTexts = nil }
            guard let texts = accumulatedTexts, !texts.isEmpty else { return nil }
            return texts
        }

        // MARK: - Text Input

        func insertText(_ string: Any, replacementRange: NSRange = NSRange(location: NSNotFound, length: 0)) {
            guard NSApp.currentEvent != nil else { return }

            let text: String
            if let attrStr = string as? NSAttributedString {
                text = attrStr.string
            } else if let str = string as? String {
                text = str
            } else {
                return
            }

            unmarkText()

            // An IME replacement is honored only when it ends exactly at our
            // cursor (= end of the pseudo-document) — same guard as iTerm2's
            // `shouldBackspaceAt:`. Anything else degrades to a plain append,
            // which is the pre-fix behavior.
            if replacementRange.location != NSNotFound,
               replacementRange.length > 0,
               NSMaxRange(replacementRange) == docLength {
                pendingBackspaces += replacementRange.length
                let doc = NSMutableString(string: committedDoc)
                doc.replaceCharacters(in: replacementRange, with: text)
                committedDoc = doc as String
            } else {
                committedDoc += text
                // The IME only ever replaces text near the cursor. Do not let
                // the document grow without bound; resetting merely degrades
                // a replacement that lands at that exact moment to an append.
                if docLength > 256 { resetCommittedRun() }
            }

            if accumulatedTexts != nil {
                accumulatedTexts?.append(text)
            } else {
                // Out-of-keyDown commit (candidate window click, input-source
                // switch mid-composition). Send through the *key* path:
                // `sendText` is the paste path and gets wrapped in bracketed
                // paste markers when the app enabled mode 2004.
                flushPendingBackspaces()
                sendCommittedText(text)
            }
        }

        /// Emits queued replacements as Delete key presses. The core encodes
        /// them per the active keyboard protocol (legacy 0x7f or kitty CSI).
        func flushPendingBackspaces() {
            let count = takePendingBackspaces()
            guard count > 0, let surface = view?.surface else { return }
            for _ in 0 ..< count {
                var del = ghostty_input_key_s()
                del.keycode = 51 // kVK_Delete
                del.text = nil
                del.composing = false
                del.mods = GHOSTTY_MODS_NONE
                del.consumed_mods = GHOSTTY_MODS_NONE
                del.unshifted_codepoint = 0
                del.action = GHOSTTY_ACTION_PRESS
                surface.sendKeyEvent(del)
                del.action = GHOSTTY_ACTION_RELEASE
                surface.sendKeyEvent(del)
            }
        }

        /// Committed text as a key event (keycode 0), mirroring upstream
        /// Ghostty's `committedTextAction`.
        func sendCommittedText(_ text: String) {
            guard !text.isEmpty, let surface = view?.surface else { return }
            var input = ghostty_input_key_s()
            input.action = GHOSTTY_ACTION_PRESS
            input.keycode = 0
            input.composing = false
            input.mods = GHOSTTY_MODS_NONE
            input.consumed_mods = GHOSTTY_MODS_NONE
            input.unshifted_codepoint = 0
            text.withCString { ptr in
                input.text = ptr
                surface.sendKeyEvent(input)
            }
        }

        func setMarkedText(
            _ string: Any,
            selectedRange: NSRange
        ) {
            let text: String
            if let attrStr = string as? NSAttributedString {
                text = attrStr.string
            } else if let str = string as? String {
                text = str
            } else {
                return
            }

            markedTextState.setMarkedText(text, selectedRange: selectedRange)

            if accumulatedTexts == nil {
                syncPreedit()
            }
        }

        func unmarkText() {
            guard markedTextState.hasMarkedText else { return }
            markedTextState.clear()
            syncPreedit()
        }

        /// Ranges are offset by the pseudo-document: the IME anchors its
        /// replacement ranges on what we report here. Reporting an empty
        /// world (`{NSNotFound, 0}` with no document) is what pushed IMEs
        /// into the lossy commit-then-abandon mode after a source switch.
        func currentSelectedRange() -> NSRange {
            guard markedTextState.hasMarkedText else {
                return NSRange(location: docLength, length: 0)
            }
            let inner = markedTextState.currentSelectedRange
            return NSRange(location: docLength + inner.location, length: inner.length)
        }

        func markedRange() -> NSRange {
            guard markedTextState.hasMarkedText else {
                return NSRange(location: NSNotFound, length: 0)
            }
            let inner = markedTextState.markedRange
            return NSRange(location: docLength + inner.location, length: inner.length)
        }

        func attributedSubstring(
            forProposedRange range: NSRange,
            actualRange: NSRangePointer?
        ) -> NSAttributedString? {
            // Serve pseudo-document followed by any marked text, clamped.
            // The IME reads this to decide whether it can replace.
            let whole = committedDoc + (markedTextState.text ?? "") as NSString
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: whole.length))
            guard clamped.length > 0 else { return nil }
            actualRange?.pointee = clamped
            return NSAttributedString(string: whole.substring(with: clamped))
        }

        func syncPreedit(clearIfNeeded: Bool = true) {
            guard let text = markedTextState.text else {
                guard clearIfNeeded else { return }
                view?.surface?.preedit("")
                return
            }

            view?.surface?.preedit(text)
        }
    }
#endif
