import SwiftUI
import UIKit
import Observation

enum Caps { case never, words, sentences, characters
    var uiKit: UITextAutocapitalizationType {
        switch self { case .never: return .none; case .words: return .words; case .sentences: return .sentences; case .characters: return .allCharacters }
    }
}

/// Return / Next focus chain for a form of `VTextField`s: setting `target` to a field id moves the keyboard there
/// (the field clears it once focused). Non-text stops (the wizard's State picker) watch it too.
@MainActor
@Observable
final class FocusChain {
    var target: String?
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
    /// Return key label; nil = Done when `onSubmit` is set, else the default.
    var returnKey: UIReturnKeyType? = nil
    /// A form's focus chain asks this field to take the keyboard (see `FocusChain`); `onFocusTaken` clears the request.
    var focusRequested = false
    var onFocusTaken: (() -> Void)? = nil

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
        tf.clearButtonMode = secure ? .never : .whileEditing
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
        if focusRequested {
            let taken = onFocusTaken
            DispatchQueue.main.async {
                if tf.window != nil, !tf.isFirstResponder { tf.becomeFirstResponder() }
                taken?()
            }
        }
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
        tf.returnKeyType = returnKey ?? (onSubmit == nil ? .default : .done)
        tf.accessibilityLabel = accessibilityLabel ?? placeholder
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FilteredTextField
        init(_ p: FilteredTextField) { parent = p }

        private func filter(_ s: String) -> String { parent.kind?.filter(s) ?? Validator.collapseSpaces(s) }

        private func publish(_ v: String) {
            if parent.text != v { parent.text = v }
            if let id = parent.fieldID, let errors = parent.errors {
                errors.revalidate(id, v)
                errors.liveLimit(id, v, kind: parent.kind)    // "Enter a number up to <max>" while typing
            }
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

        func textFieldDidBeginEditing(_ tf: UITextField) {
            parent.onFocus?(true)
            TextSelection.collapseIfAllSelected(tf)
        }
        func textFieldDidEndEditing(_ tf: UITextField) {
            parent.onFocus?(false)
        }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if let s = parent.onSubmit { s() } else { tf.resignFirstResponder() }
            return true
        }
    }
}

/// docs/validation-rules.md "Text selection": focusing a field never auto-selects its existing text — the caret goes
/// where the user tapped, or to the end. UIKit can hand a field focus with its whole text selected (programmatic focus /
/// Return-key chains, select-all restored from a previous edit, hardware-keyboard tabbing); right after focus, a
/// selection that covers the entire text is collapsed to a caret at the end. Installed app-wide for UITextField and
/// UITextView (SwiftUI TextField / TextEditor use them too) by `TextSelection.install()` at launch.
@MainActor
enum TextSelection {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { if let tf = n.object as? UITextField { collapseIfAllSelected(tf) } }
        }
        nc.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { if let tv = n.object as? UITextView { collapseIfAllSelected(tv) } }
        }
    }

    /// Now and once more on the next run-loop turn (UIKit may apply its selection after the begin-editing callback).
    static func collapseIfAllSelected(_ input: UITextInput & UIResponder) {
        collapse(input)
        DispatchQueue.main.async { collapse(input) }
    }

    private static func collapse(_ input: UITextInput & UIResponder) {
        guard input.isFirstResponder, let sel = input.selectedTextRange, !sel.isEmpty else { return }
        let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        guard let all, input.compare(sel.start, to: all.start) == .orderedSame,
              input.compare(sel.end, to: all.end) == .orderedSame else { return }
        let end = input.endOfDocument
        input.selectedTextRange = input.textRange(from: end, to: end)
    }
}
