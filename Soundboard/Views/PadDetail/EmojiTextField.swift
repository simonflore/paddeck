import AppKit
import SwiftUI

/// A single-emoji text field that opens the macOS character viewer on click.
struct EmojiTextField: NSViewRepresentable {
    @Binding var emoji: String

    func makeNSView(context: Context) -> EmojiNSTextField {
        let field = EmojiNSTextField()
        field.delegate = context.coordinator
        field.stringValue = emoji
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 24)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.placeholderString = "+"
        field.focusRingType = .exterior
        return field
    }

    func updateNSView(_ nsView: EmojiNSTextField, context: Context) {
        if nsView.stringValue != emoji {
            nsView.stringValue = emoji
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(emoji: $emoji)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var emoji: Binding<String>

        init(emoji: Binding<String>) {
            self.emoji = emoji
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let text = field.stringValue

            // Keep only the last character (emoji) entered
            if let last = text.last, last.unicodeScalars.allSatisfy({ $0.properties.isEmoji && $0.value > 0x23 }) {
                let single = String(last)
                emoji.wrappedValue = single
                field.stringValue = single
            } else if text.isEmpty {
                emoji.wrappedValue = ""
            } else {
                // Filter to emoji only
                let filtered = text.filter { char in
                    char.unicodeScalars.allSatisfy { $0.properties.isEmoji && $0.value > 0x23 }
                }
                if let last = filtered.last {
                    let single = String(last)
                    emoji.wrappedValue = single
                    field.stringValue = single
                } else {
                    field.stringValue = emoji.wrappedValue
                }
            }
        }
    }
}

/// Custom NSTextField that shows the emoji picker when it becomes first responder.
final class EmojiNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Open the macOS character/emoji viewer
            NSApp.orderFrontCharacterPalette(nil)
        }
        return result
    }
}
