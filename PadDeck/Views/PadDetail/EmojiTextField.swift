#if os(macOS)
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

            if text.isEmpty {
                emoji.wrappedValue = ""
                return
            }

            // Find the last character that is a real emoji (not digits, #, * etc.)
            let lastEmoji = text.last.flatMap { char -> String? in
                let scalars = char.unicodeScalars
                let isRealEmoji = scalars.contains { scalar in
                    scalar.properties.isEmoji &&
                    scalar.properties.isEmojiPresentation
                } || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)
                return isRealEmoji ? String(char) : nil
            }

            if let single = lastEmoji {
                emoji.wrappedValue = single
                field.stringValue = single
            } else {
                field.stringValue = emoji.wrappedValue
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

#else
import SwiftUI
import UIKit

/// A single-emoji text field for iOS. The emoji keyboard appears naturally on tap.
struct EmojiTextField: UIViewRepresentable {
    @Binding var emoji: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.text = emoji
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 24)
        field.placeholder = "+"
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor(white: 0.15, alpha: 1)
        field.textColor = .white
        // Hint iOS to show the emoji keyboard
        field.textContentType = .name
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != emoji {
            uiView.text = emoji
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(emoji: $emoji)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var emoji: Binding<String>

        init(emoji: Binding<String>) {
            self.emoji = emoji
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                emoji.wrappedValue = ""
                return true
            }

            // Accept only real emoji characters
            if let char = string.last {
                let scalars = char.unicodeScalars
                let isRealEmoji = scalars.contains { scalar in
                    scalar.properties.isEmoji &&
                    scalar.properties.isEmojiPresentation
                } || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)

                if isRealEmoji {
                    emoji.wrappedValue = String(char)
                    textField.text = String(char)
                }
            }
            return false
        }
    }
}
#endif
