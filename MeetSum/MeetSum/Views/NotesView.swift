//
//  NotesView.swift
//  MeetSum
//
//  Timestamped notes panel using NSTextView with live markdown formatting
//

import SwiftUI
import AppKit

struct NotesView: View {
    @Binding var text: String
    var isRecording: Bool
    var currentTimestamp: () -> String
    var onTextChange: (() -> Void)?

    @State private var markdownEnabled = true
    @State private var insertTimecodes: Bool = ModelSettings.insertTimecodeInNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with markdown toggle
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)

                Spacer()

                if isRecording {
                    Button(action: {
                        insertTimecodes.toggle()
                        ModelSettings.insertTimecodeInNotes = insertTimecodes
                    }) {
                        Image(systemName: insertTimecodes ? "clock.badge.checkmark" : "clock.badge.xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(insertTimecodes ? "Timecodes on: timestamps inserted on Enter" : "Timecodes off: plain newlines on Enter")
                }

                Button(action: { markdownEnabled.toggle() }) {
                    Image(systemName: markdownEnabled ? "textformat" : "textformat.alt")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(markdownEnabled ? "Disable markdown formatting" : "Enable markdown formatting")
            }

            TimestampedTextView(
                text: $text,
                isRecording: isRecording,
                markdownEnabled: markdownEnabled,
                currentTimestamp: currentTimestamp,
                onTextChange: onTextChange
            )
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }
}

// MARK: - NSViewRepresentable for NSTextView with timestamp injection and live markdown

struct TimestampedTextView: NSViewRepresentable {
    @Binding var text: String
    var isRecording: Bool
    var markdownEnabled: Bool
    var currentTimestamp: () -> String
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        if markdownEnabled {
            context.coordinator.applyMarkdownStyling(to: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self

        // Only update text if it changed externally (not from user typing)
        if textView.string != text && !context.coordinator.isUpdatingFromTextView {
            textView.string = text
            if markdownEnabled {
                context.coordinator.applyMarkdownStyling(to: textView)
            }
        }

        // Re-apply styling when markdown toggle changes
        if markdownEnabled != context.coordinator.lastMarkdownEnabled {
            context.coordinator.lastMarkdownEnabled = markdownEnabled
            if markdownEnabled {
                context.coordinator.applyMarkdownStyling(to: textView)
            } else {
                context.coordinator.clearMarkdownStyling(from: textView)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TimestampedTextView
        weak var textView: NSTextView?
        var isUpdatingFromTextView = false
        var lastMarkdownEnabled = true
        private var debounceWorkItem: DispatchWorkItem?
        private var stylingWorkItem: DispatchWorkItem?

        init(_ parent: TimestampedTextView) {
            self.parent = parent
            self.lastMarkdownEnabled = parent.markdownEnabled
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdatingFromTextView = true
            parent.text = textView.string
            isUpdatingFromTextView = false

            // Debounced markdown styling
            if parent.markdownEnabled {
                stylingWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, let textView = self.textView else { return }
                    self.applyMarkdownStyling(to: textView)
                }
                stylingWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
            }

            // Debounced auto-save
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.onTextChange?()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.isRecording && ModelSettings.insertTimecodeInNotes {
                    let timestamp = parent.currentTimestamp()
                    let insertion = "\n[\(timestamp)] "
                    textView.insertText(insertion, replacementRange: textView.selectedRange())
                    return true
                }
            }
            return false
        }

        // MARK: - Markdown Styling

        func applyMarkdownStyling(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let text = textStorage.string
            let baseFont = NSFont.systemFont(ofSize: 13)
            let baseColor = NSColor.labelColor

            textStorage.beginEditing()

            // Reset to base style
            textStorage.addAttribute(.font, value: baseFont, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)

            // Process line by line
            let nsString = text as NSString
            var lineStart = 0
            while lineStart < nsString.length {
                var lineEnd = 0
                var contentEnd = 0
                nsString.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: lineStart, length: 0))
                let lineRange = NSRange(location: lineStart, length: contentEnd - lineStart)
                let line = nsString.substring(with: lineRange)
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Headings
                if trimmed.hasPrefix("### ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .semibold), range: lineRange)
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: "### ")
                } else if trimmed.hasPrefix("## ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 16, weight: .semibold), range: lineRange)
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: "## ")
                } else if trimmed.hasPrefix("# ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 18, weight: .bold), range: lineRange)
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: "# ")
                }
                // Checklist items
                else if trimmed.hasPrefix("- [x] ") {
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: "- [x] ")
                    let prefixRange = syntaxRange(line: line, lineStart: lineStart, prefix: "- [x] ")
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: prefixRange)
                } else if trimmed.hasPrefix("- [ ] ") {
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: "- [ ] ")
                }
                // Bullet lists
                else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    applyMarkdownSyntaxDim(textStorage, line: line, lineStart: lineStart, prefix: String(trimmed.prefix(2)))
                }
                // Timestamps
                else if trimmed.hasPrefix("[") && trimmed.contains("] ") {
                    if let bracketEnd = line.range(of: "] ") {
                        let tsLength = line.distance(from: line.startIndex, to: bracketEnd.upperBound)
                        let tsRange = NSRange(location: lineStart, length: tsLength)
                        textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: tsRange)
                        textStorage.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), range: tsRange)
                    }
                }

                // Inline: bold
                applyInlinePattern(textStorage, in: text, lineRange: lineRange, delimiter: "**",
                                   attribute: .font, value: NSFont.systemFont(ofSize: 13, weight: .bold))

                // Inline: italic (single * not preceded/followed by *)
                applyItalicPattern(textStorage, in: text, lineRange: lineRange)

                // Inline: code
                applyInlinePattern(textStorage, in: text, lineRange: lineRange, delimiter: "`",
                                   attribute: .font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
                applyInlinePattern(textStorage, in: text, lineRange: lineRange, delimiter: "`",
                                   attribute: .backgroundColor, value: NSColor.quaternaryLabelColor)

                // Inline: strikethrough
                applyInlinePattern(textStorage, in: text, lineRange: lineRange, delimiter: "~~",
                                   attribute: .strikethroughStyle, value: NSUnderlineStyle.single.rawValue)

                lineStart = lineEnd
            }

            textStorage.endEditing()
        }

        func clearMarkdownStyling(from textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseFont = NSFont.systemFont(ofSize: 13)

            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: baseFont, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textStorage.removeAttribute(.backgroundColor, range: fullRange)
            textStorage.removeAttribute(.strikethroughStyle, range: fullRange)
            textStorage.endEditing()
        }

        // MARK: - Styling Helpers

        private func applyMarkdownSyntaxDim(_ textStorage: NSTextStorage, line: String, lineStart: Int, prefix: String) {
            let range = syntaxRange(line: line, lineStart: lineStart, prefix: prefix)
            textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        }

        private func syntaxRange(line: String, lineStart: Int, prefix: String) -> NSRange {
            // Find where prefix starts in the line (accounting for leading whitespace)
            let trimmedStart = line.count - line.drop(while: { $0 == " " || $0 == "\t" }).count
            return NSRange(location: lineStart + trimmedStart, length: prefix.count)
        }

        private func applyInlinePattern(_ textStorage: NSTextStorage, in text: String, lineRange: NSRange, delimiter: String, attribute: NSAttributedString.Key, value: Any) {
            let nsString = text as NSString
            let lineText = nsString.substring(with: lineRange)
            let delimLen = delimiter.count

            var searchStart = 0
            while searchStart < lineText.count {
                let openRange = (lineText as NSString).range(of: delimiter, options: [], range: NSRange(location: searchStart, length: lineText.count - searchStart))
                guard openRange.location != NSNotFound else { break }

                let afterOpen = openRange.location + openRange.length
                guard afterOpen < lineText.count else { break }

                let closeRange = (lineText as NSString).range(of: delimiter, options: [], range: NSRange(location: afterOpen, length: lineText.count - afterOpen))
                guard closeRange.location != NSNotFound else { break }

                // Apply attribute to content between delimiters (inclusive of delimiters)
                let matchStart = openRange.location
                let matchEnd = closeRange.location + closeRange.length
                let matchRange = NSRange(location: lineRange.location + matchStart, length: matchEnd - matchStart)
                textStorage.addAttribute(attribute, value: value, range: matchRange)

                // Dim the delimiter characters
                let openAbsolute = NSRange(location: lineRange.location + openRange.location, length: delimLen)
                let closeAbsolute = NSRange(location: lineRange.location + closeRange.location, length: delimLen)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openAbsolute)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeAbsolute)

                searchStart = matchEnd
            }
        }

        private func applyItalicPattern(_ textStorage: NSTextStorage, in text: String, lineRange: NSRange) {
            let nsString = text as NSString
            let lineText = nsString.substring(with: lineRange)

            var searchStart = 0
            while searchStart < lineText.count {
                // Find a single * not preceded or followed by another *
                let openRange = (lineText as NSString).range(of: "*", options: [], range: NSRange(location: searchStart, length: lineText.count - searchStart))
                guard openRange.location != NSNotFound else { break }

                // Skip if part of ** (bold)
                let before = openRange.location > 0 ? (lineText as NSString).substring(with: NSRange(location: openRange.location - 1, length: 1)) : ""
                let after = openRange.location + 1 < lineText.count ? (lineText as NSString).substring(with: NSRange(location: openRange.location + 1, length: 1)) : ""
                if before == "*" || after == "*" {
                    searchStart = openRange.location + 1
                    continue
                }

                let afterOpen = openRange.location + 1
                guard afterOpen < lineText.count else { break }

                // Find closing *
                var closeLocation: Int? = nil
                var pos = afterOpen
                while pos < lineText.count {
                    let charRange = NSRange(location: pos, length: 1)
                    let char = (lineText as NSString).substring(with: charRange)
                    if char == "*" {
                        let prevChar = pos > 0 ? (lineText as NSString).substring(with: NSRange(location: pos - 1, length: 1)) : ""
                        let nextChar = pos + 1 < lineText.count ? (lineText as NSString).substring(with: NSRange(location: pos + 1, length: 1)) : ""
                        if prevChar != "*" && nextChar != "*" {
                            closeLocation = pos
                            break
                        }
                    }
                    pos += 1
                }

                guard let closeLoc = closeLocation else {
                    searchStart = openRange.location + 1
                    continue
                }

                let matchRange = NSRange(location: lineRange.location + openRange.location, length: closeLoc - openRange.location + 1)
                let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: matchRange)

                // Dim delimiters
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: lineRange.location + openRange.location, length: 1))
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: lineRange.location + closeLoc, length: 1))

                searchStart = closeLoc + 1
            }
        }
    }
}
