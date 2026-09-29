import SwiftUI
import UIKit

enum Caps { case never, words, sentences, characters
    var uiKit: UITextAutocapitalizationType {
        switch self { case .never: return .none; case .words: return .words; case .sentences: return .sentences; case .characters: return .allCharacters }
    }
}

/// Single-line text input that filters/formats every keystroke synchronously (UITextField delegate),
/// so formatted fields (phone, card, join code…) never drop characters however fast someone types.
struct FilteredTextField: UIViewRepresentable {
    @Binding var text: String
    var kind: FieldKind? = nil
    var fieldID: String? = nil
    var errors: FormErrors? = nil
    var placeholder: String = ""
    var font: UIFont = VFont.uUI(15)
    var textStyle: UIFont.TextStyle = .body
    var textColor: UIColor = UIColor(hex: 0x17222E)
    var placeholderColor: UIColor = UIColor(hex: 0xA7B4C2)
    var tint: UIColor = UIColor(hex: 0x2F5EC9)
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var caps: Caps = .sentences
    var autocorrect = true
    var accessibilityLabel: String? = nil
    var onFocus: ((Bool) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.adjustsFontForContentSizeCategory = true
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        configure(tf)
        tf.text = text
        return tf
    }

    /// Full proposed width, intrinsic (font) height — never stretch vertically.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let h = uiView.intrinsicContentSize.height
        return CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: h)
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        configure(tf)
        if tf.text != text { tf.text = text }
    }

    private func configure(_ tf: UITextField) {
        tf.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        tf.textColor = textColor
        tf.tintColor = tint
        tf.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor])
        tf.keyboardType = keyboard
        tf.textContentType = contentType
        tf.autocapitalizationType = caps.uiKit
        tf.autocorrectionType = autocorrect ? .default : .no
        tf.spellCheckingType = autocorrect ? .default : .no
        if tf.isSecureTextEntry != secure { tf.isSecureTextEntry = secure }
        tf.returnKeyType = onSubmit == nil ? .default : .done
        tf.accessibilityLabel = accessibilityLabel ?? placeholder
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FilteredTextField
        init(_ p: FilteredTextField) { parent = p }

        private func filter(_ s: String) -> String { parent.kind?.filter(s) ?? Validator.collapseSpaces(s) }

        private func publish(_ v: String) {
            if parent.text != v { parent.text = v }
            if let id = parent.fieldID, let errors = parent.errors { errors.revalidate(id, v) }
        }

        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = tf.text ?? ""
            guard let r = Range(range, in: current) else { return true }
            let proposed = current.replacingCharacters(in: r, with: string)
            let filtered = filter(proposed)
            if filtered == proposed { return true }          // UIKit applies it; .editingChanged publishes
            // Apply the filtered/formatted value ourselves and keep the caret sensible.
            let atEnd = range.location + range.length >= (current as NSString).length
            tf.text = filtered
            let caretOffset = atEnd ? (filtered as NSString).length
                : min((filtered as NSString).length, range.location + (string as NSString).length)
            if let pos = tf.position(from: tf.beginningOfDocument, offset: caretOffset) {
                tf.selectedTextRange = tf.textRange(from: pos, to: pos)
            }
            publish(filtered)
            return false
        }

        @objc func changed(_ tf: UITextField) {
            // Autocorrect / dictation / autofill paths bypass shouldChange; filter here too.
            let v = tf.text ?? ""
            let f = filter(v)
            if f != v { tf.text = f }
            publish(f)
        }

        func textFieldDidBeginEditing(_ tf: UITextField) { parent.onFocus?(true) }
        func textFieldDidEndEditing(_ tf: UITextField) {
            parent.onFocus?(false)
        }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if let s = parent.onSubmit { s() } else { tf.resignFirstResponder() }
            return true
        }
    }
}
