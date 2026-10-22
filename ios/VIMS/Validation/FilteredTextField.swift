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
        let tf = CaretTextField()
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
        /// Whole-number field: a "." was typed at the end and discarded, so the digits typed right after it are the
        /// decimals and are discarded too ("2450" + "." + "5" stays "2450", never "24505"). Cleared by a delete or leaving.
        private var discardingDecimals = false
        init(_ p: FilteredTextField) { parent = p }

        /// Brief "Whole numbers only" under the field (cleared after a moment unless another error replaced it).
        private func wholeNumbersHint() {
            guard let id = parent.fieldID, let errors = parent.errors else { return }
            let msg = Validator.wholeNumbersOnly
            errors.map[id] = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if errors.map[id] == msg { errors.map[id] = nil } }
        }

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
            var range = range
            // Grouped numbers (sq ft / valuation): backspacing over a "," deletes the digit before it.
            if parent.kind?.isNumeric == true, string.isEmpty, range.length == 1, range.location > 0,
               (current as NSString).substring(with: range) == "," {
                range = NSRange(location: range.location - 1, length: 2)
            }
            // Whole-number fields (team QA Oct 22): a typed or pasted "." and everything after it is discarded.
            if case .number(let l)? = parent.kind, l.isInteger {
                let atEnd = range.location + range.length >= (current as NSString).length
                if string.isEmpty { discardingDecimals = false }
                else if string == "." || (string == "," && !l.grouping) {
                    discardingDecimals = atEnd
                    wholeNumbersHint()
                    return false
                } else if discardingDecimals, atEnd, string.allSatisfy(\.isNumber) {
                    wholeNumbersHint()
                    return false
                } else if string.contains(".") {
                    wholeNumbersHint()       // a pasted "2450.5" → "2450" (the filter stops at the ".")
                }
            }
            guard let r = Range(range, in: current) else { return true }
            let proposed = current.replacingCharacters(in: r, with: string)
            var filtered = filter(proposed)
            // Company code (QA Oct 14): typing the 3rd letter inserts the "-" (deleting it doesn't put it back).
            if parent.kind == .joinCode, !string.isEmpty, filtered.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil {
                filtered += "-"
            }
            if filtered == proposed { return true }          // UIKit applies it; .editingChanged publishes
            var caretOffset: Int
            if parent.kind?.isNumeric == true {
                // Numbers (QA Oct 22): a typed character the field can't take — a letter, a 2nd ".", a decimal past the
                // field's limit, a digit past its max length — is simply not accepted (nothing changes). Grouping commas
                // the formatter adds or moves don't count as a change; the caret keeps its place among the digits.
                let bare = { (x: String) in x.replacingOccurrences(of: ",", with: "") }
                if !string.isEmpty, (string as NSString).length <= 1, bare(filtered) != bare(proposed) { return false }
                let caretInProposed = min((proposed as NSString).length, range.location + (string as NSString).length)
                let digitsBefore = bare((proposed as NSString).substring(to: caretInProposed)).count
                // Filtered numbers are ASCII, so a character index is the UTF-16 offset.
                caretOffset = digitsBefore == 0 ? 0 : (filtered as NSString).length
                var seen = 0
                for (i, ch) in filtered.enumerated() where digitsBefore > 0 {
                    if ch != "," { seen += 1 }
                    if seen == digitsBefore { caretOffset = i + 1; break }
                }
            } else {
                let atEnd = range.location + range.length >= (current as NSString).length
                caretOffset = atEnd ? (filtered as NSString).length
                    : min((filtered as NSString).length, range.location + (string as NSString).length)
            }
            // Apply the filtered/formatted value ourselves and keep the caret sensible.
            tf.text = filtered
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
            discardingDecimals = false
            parent.onFocus?(false)
        }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if let s = parent.onSubmit { s() } else { tf.resignFirstResponder() }
            return true
        }
    }
}

/// The app's single-line field: a select-all that UIKit issues as part of giving it focus (keyboard Tab navigation,
/// programmatic focus) becomes a caret at the end. A Select All the user picks from the edit menu later still works.
final class CaretTextField: UITextField {
    private var focusedAt: Date?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { focusedAt = Date() }
        return ok
    }

    override func selectAll(_ sender: Any?) {
        if let t = focusedAt, Date().timeIntervalSince(t) < 0.5 {
            let end = endOfDocument
            selectedTextRange = textRange(from: end, to: end)
            return
        }
        super.selectAll(sender)
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

    /// Now, on the next run-loop turn and twice more shortly after: UIKit may apply its selection after the
    /// begin-editing callback (QA Oct 14: hardware-keyboard Tab / Return-chain focus and prefilled fields still came up
    /// selected). Only a selection covering the WHOLE text is collapsed, and only in this short focus window.
    static func collapseIfAllSelected(_ input: UITextInput & UIResponder) {
        collapse(input)
        DispatchQueue.main.async { collapse(input) }
        for delay in [0.12, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { collapse(input) }
        }
    }

    static func collapse(_ input: UITextInput & UIResponder) {
        guard input.isFirstResponder, let sel = input.selectedTextRange, !sel.isEmpty else { return }
        let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        guard let all, input.compare(sel.start, to: all.start) == .orderedSame,
              input.compare(sel.end, to: all.end) == .orderedSame else { return }
        let end = input.endOfDocument
        input.selectedTextRange = input.textRange(from: end, to: end)
    }
}

/// Team QA Oct 22 (docs/validation-rules.md): tapping anywhere outside the active field closes the keyboard, on every
/// screen. One tap recognizer per app window (installed at launch by `KeyboardDismiss.install()`); it never cancels or
/// delays touches and recognizes alongside everything else, so scrolling, buttons, chips and pickers work as before —
/// a button tapped with the keyboard up both acts and closes it. Taps inside a text field / text view (another field
/// takes focus as usual) and on the system edit menu, magnifier or keyboard are left alone.
@MainActor
enum KeyboardDismiss {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { if let w = n.object as? UIWindow { attach(to: w) } }
        }
    }

    static func attach(to window: UIWindow) {
        let name = NSStringFromClass(type(of: window))
        guard !name.contains("Keyboard"), !name.contains("TextEffects"),
              !(window.gestureRecognizers ?? []).contains(where: { $0 is KeyboardDismissTap }) else { return }
        window.addGestureRecognizer(KeyboardDismissTap())
    }
}

final class KeyboardDismissTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(tapped))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func tapped() {
        guard state == .ended else { return }
        view?.endEditing(true)
    }

    private static let systemParts = ["EditMenu", "Callout", "Magnifier", "TextSelection", "TextRange", "Keyboard", "InputView", "ContextMenu"]

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = view as? UIWindow, Self.editingView(in: window) != nil else { return false }
        var v = touch.view
        while let cur = v {
            if cur is UITextField || cur is UITextView || cur is UISearchBar { return false }
            let name = NSStringFromClass(type(of: cur))
            if Self.systemParts.contains(where: name.contains) { return false }
            v = cur.superview
        }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// The text field / text view in this window that has the keyboard, if any.
    private static func editingView(in root: UIView) -> UIView? {
        if root.isFirstResponder, root is UITextField || root is UITextView { return root }
        for sub in root.subviews { if let f = editingView(in: sub) { return f } }
        return nil
    }
}
