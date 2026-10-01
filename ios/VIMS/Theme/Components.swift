import SwiftUI

// MARK: - Flow layout (wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Section label (.lbl)

struct SectionLabel: View {
    let text: String
    var top: CGFloat = 20
    var body: some View {
        Text(text.uppercased())
            .font(VFont.mono(10.5))
            .tracking(1.26)
            .foregroundStyle(VC.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, top)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

struct HintText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VFont.ui(13))
            .foregroundStyle(VC.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: EdgeInsets = EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(VC.line, lineWidth: 1))
    }
}

extension View {
    func vCard(_ padding: EdgeInsets = EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16), radius: CGFloat = 14) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
    func vCard(all: CGFloat, radius: CGFloat = 14) -> some View {
        modifier(CardModifier(padding: EdgeInsets(top: all, leading: all, bottom: all, trailing: all), radius: radius))
    }
}

// MARK: - Buttons (.btn primary / ghost / signal)

enum VButtonKind { case primary, ghost, signal, danger }

struct VButtonStyle: ButtonStyle {
    var kind: VButtonKind = .primary
    var minHeight: CGFloat = 52
    var fullWidth = true
    /// Overrides the text color (e.g. the red "Cancel subscription" ghost button).
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(VFont.ui(15, .semibold))
            .labelStyle(VLabelStyle())
            .foregroundStyle(fg)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(bg(pressed))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(kind == .ghost ? VC.line : .clear, lineWidth: 1))
            .shadow(color: kind == .primary ? VC.brand.opacity(0.45) : .clear, radius: 11, x: 0, y: 8)
            .contentShape(Rectangle())
    }

    private var fg: Color {
        if let tint { return tint }
        switch kind {
        case .primary, .danger: return .white
        case .ghost: return VC.ink
        case .signal: return Color(hex: 0x3A2A05)
        }
    }
    private func bg(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? VC.brandDeep : VC.brand
        case .ghost: return pressed ? VC.paper2 : VC.paper
        case .signal: return pressed ? VC.signalDeep : VC.signal
        case .danger: return pressed ? Color(hex: 0xB04438) : VC.c1
        }
    }
}

struct VLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon
            configuration.title
        }
    }
}

extension ButtonStyle where Self == VButtonStyle {
    static var vPrimary: VButtonStyle { VButtonStyle(kind: .primary) }
    static var vGhost: VButtonStyle { VButtonStyle(kind: .ghost) }
    static var vSignal: VButtonStyle { VButtonStyle(kind: .signal) }
}

/// Plain tap feedback for row-like buttons.
struct PressableStyle: ButtonStyle {
    var pressedColor: Color = VC.paper2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedColor : .clear)
            .contentShape(Rectangle())
    }
}

// MARK: - Chips

struct ChipView: View {
    let label: String
    let on: Bool
    var body: some View {
        Text(label)
            .font(VFont.ui(13.5, .medium))
            .foregroundStyle(on ? .white : VC.ink2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .frame(minHeight: 40)
            .background(on ? VC.brand : VC.paper)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
    }
}

struct ChipButton: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { ChipView(label: label, on: on) }
            .buttonStyle(ChipPressStyle())
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Single-select (tap again to deselect unless `required`) or multi-select chip group.
struct ChipGroup: View {
    let options: [String]
    @Binding var selection: [String]
    var single = true
    var required = false

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                ChipButton(label: opt, on: selection.contains(opt)) { tap(opt) }
            }
        }
    }

    private func tap(_ opt: String) {
        if single {
            if selection.contains(opt) {
                if !required { selection = [] }
            } else {
                selection = [opt]
            }
        } else {
            if let i = selection.firstIndex(of: opt) { selection.remove(at: i) } else { selection.append(opt) }
        }
    }
}

/// Convenience single-select bound to an optional String.
struct SingleChipGroup: View {
    let options: [String]
    @Binding var value: String?
    var required = false
    var body: some View {
        ChipGroup(options: options,
                  selection: Binding(get: { value.map { [$0] } ?? [] }, set: { value = $0.first }),
                  single: true, required: required)
    }
}

// MARK: - Segmented grid (.seg, 3 columns)

struct SegGrid: View {
    let options: [String]
    @Binding var value: String?
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(options, id: \.self) { o in
                let on = value == o
                Button {
                    value = on ? nil : o
                } label: {
                    Text(o)
                        .font(VFont.ui(12, .semibold))
                        .foregroundStyle(on ? .white : VC.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(on ? VC.brand : VC.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
                }
                .buttonStyle(ChipPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Status pills

enum PillKind { case done, prog, queued, new }

struct Pill: View {
    let kind: PillKind
    let text: String
    var dot = true
    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(fg).frame(width: 6, height: 6) }
            Text(text).font(VFont.mono(10.5, .semibold))
        }
        .foregroundStyle(fg)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(bg)
        .clipShape(Capsule())
    }
    private var fg: Color {
        switch kind {
        case .done: return VC.doneText
        case .prog: return VC.brandDeep
        case .queued: return VC.signalDeep
        case .new: return VC.ink3
        }
    }
    private var bg: Color {
        switch kind {
        case .done: return VC.c3bg
        case .prog: return VC.brand.opacity(0.13)
        case .queued: return VC.c2bg
        case .new: return VC.paper3
        }
    }
}

// MARK: - List row (.row)

struct LeadIcon: View {
    let symbol: String      // prototype icon name
    var body: some View {
        ProtoIcon(symbol, size: 22)
            .foregroundStyle(VC.brand)
            .frame(width: 44, height: 44)
            .background(VC.paper3)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct Chevron: View {
    var body: some View {
        ProtoIcon("chevron-right", size: 18).foregroundStyle(VC.chevron)
    }
}

struct RowView<Lead: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At large text sizes the status pill moves under the text so titles aren't truncated.
        let stacked = typeSize >= .xxLarge
        HStack(spacing: 13) {
            lead()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VFont.ui(15, .semibold)).foregroundStyle(VC.ink).lineLimit(stacked ? 3 : 1)
                if let subtitle { Text(subtitle).font(VFont.ui(12.5, .medium)).foregroundStyle(VC.ink2).lineLimit(stacked ? 4 : 2) }
                if stacked { trailing().padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked { trailing() }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
    }
}

/// Settings-style navigation row with an icon lead and chevron.
struct NavRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            RowView(title: title, subtitle: subtitle) { LeadIcon(symbol: symbol) } trailing: { Chevron() }
        }
        .buttonStyle(ChipPressStyle())
        .padding(.bottom, 10)
    }
}

// MARK: - Counter row (.counter)

struct CounterRow: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...12
    var body: some View {
        HStack {
            Text(label).font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
            Spacer()
            HStack(spacing: 16) {
                stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                    .accessibilityLabel("Decrease \(label)")
                Text("\(value)").font(VFont.mono(16, .semibold)).foregroundStyle(VC.ink).frame(minWidth: 20)
                stepButton("plus", enabled: value < range.upperBound) { value += 1 }
                    .accessibilityLabel("Increase \(label)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .frame(minHeight: 54)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 9)
    }

    private func stepButton(_ sym: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: { if enabled { act() } }) {
            Text(sym == "minus" ? "−" : "+").font(.system(size: 22, weight: .regular))
                .foregroundStyle(VC.brand)
                .frame(width: 44, height: 44)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VC.line, lineWidth: 1.5))
        }
        .buttonStyle(ChipPressStyle())
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - Text fields (.field / input.txt)
// Every field: no leading space and never two spaces in a row (docs/validation-rules.md), plus the
// field-kind filter/formatter while typing. Errors come from a FormErrors (keyed by fieldID) or `error`.

struct FieldBox<Content: View>: View {
    var focused: Bool
    var minHeight: CGFloat = 48
    var error: Bool = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .font(VFont.ui(15))
            .foregroundStyle(VC.ink)
            .tint(VC.brand)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(error ? VC.c1 : (focused ? VC.brand : VC.line), lineWidth: focused || error ? 2 : 1))
    }
}

struct FieldError: View {
    let text: String
    var body: some View {
        Text(text).font(VFont.ui(12.5)).foregroundStyle(VC.c1)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Error: \(text)")
    }
}

/// Binding that applies the always-on space rule + the kind filter (for non-TextField uses).
func filteredBinding(_ text: Binding<String>, kind: FieldKind?, fieldID: String?, errors: FormErrors?) -> Binding<String> {
    Binding(get: { text.wrappedValue }, set: { new in
        let v = kind?.filter(new) ?? Validator.collapseSpaces(new)
        text.wrappedValue = v
        if let fieldID, let errors { errors.revalidate(fieldID, v) }
    })
}

/// Text input that filters/formats while typing. It edits a local copy so a rejected keystroke is
/// removed from the field too (a transforming Binding alone leaves it on screen when the value
/// doesn't change), then publishes the filtered value and re-validates the field.
struct FilteredField: View {
    @Binding var text: String
    var kind: FieldKind? = nil
    var fieldID: String? = nil
    var errors: FormErrors? = nil
    var prompt: Text? = nil
    var secure = false
    var axis: Axis = .horizontal
    @State private var raw = ""
    @State private var loaded = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $raw, prompt: prompt)
            } else {
                TextField("", text: $raw, prompt: prompt, axis: axis)
            }
        }
        .onAppear { if !loaded { raw = text; loaded = true } }
        .onChange(of: raw) { _, new in
            let f = kind?.filter(new) ?? Validator.collapseSpaces(new)
            if f != new { raw = f; return }
            if text != f { text = f }
            if let fieldID, let errors { errors.revalidate(fieldID, f) }
        }
        .onChange(of: text) { _, new in if new != raw { raw = new } }
    }
}

struct VTextField: View {
    var label: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: Caps = .sentences
    var mono = false
    var error: String? = nil
    var bottom: CGFloat = 13
    var kind: FieldKind? = nil
    var fieldID: String? = nil
    var errors: FormErrors? = nil
    var trailing: String? = nil
    /// Mandatory field (same as its `.req` validation rule) → red " *" after the label.
    var required = false
    @State private var focused = false

    private var shownError: String? { error ?? fieldID.flatMap { errors?[$0] } }
    private var noAutocorrect: Bool {
        keyboard == .emailAddress || mono || keyboard == .URL || kind == .email || kind == .url || kind == .joinCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label { FieldLabel(text: label, required: required) }
            FieldBox(focused: focused, error: shownError != nil) {
                HStack(spacing: 8) {
                    FilteredTextField(text: $text, kind: kind, fieldID: fieldID, errors: errors, placeholder: placeholder,
                                      font: mono ? VFont.uMono(15, .medium) : VFont.uUI(15),
                                      keyboard: keyboard, contentType: contentType,
                                      caps: kind == .email || kind == .url ? .never : capitalization,
                                      autocorrect: !noAutocorrect, accessibilityLabel: label ?? placeholder,
                                      onFocus: { focused = $0 })
                    if let trailing, !trailing.isEmpty {
                        Text(trailing).font(VFont.mono(11, .semibold)).foregroundStyle(VC.brandDeep)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(VC.brand.opacity(0.1)).clipShape(Capsule())
                    }
                }
            }
            if let shownError { FieldError(text: shownError) }
        }
        .padding(.bottom, bottom)
        .id(fieldID ?? label ?? placeholder)
    }
}

/// The one form-field label style (prototype `.field > label`: IBM Plex Sans semibold, ink-2).
/// Required fields get a trailing " *" in c1 red; the label text itself is unchanged.
struct FieldLabel: View {
    let text: String
    var required = false
    var body: some View {
        Group {
            if required {
                Text("\(text)\(Text(" *").foregroundStyle(VC.c1))")
            } else {
                Text(text)
            }
        }
        .font(VFont.ui(13, .semibold)).foregroundStyle(VC.ink2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(required ? "\(text), required" : text)
    }
}

/// "* Required" hint shown at the top of longer forms.
struct RequiredHint: View {
    var body: some View {
        Text("\(Text("*").foregroundStyle(VC.c1)) Required")
            .font(VFont.ui(12)).foregroundStyle(VC.ink3)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, 6)
            .accessibilityLabel("Fields marked with an asterisk are required")
    }
}

struct VSecureField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = ""
    var allowReveal = true
    var contentType: UITextContentType = .password
    var error: String? = nil
    var fieldID: String? = nil
    var errors: FormErrors? = nil
    var required = false
    @State private var reveal = false
    @State private var focused = false

    private var shownError: String? { error ?? fieldID.flatMap { errors?[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label, required: required)
            FieldBox(focused: focused, error: shownError != nil) {
                HStack(spacing: 6) {
                    FilteredTextField(text: $text, kind: .password, fieldID: fieldID, errors: errors, placeholder: placeholder,
                                      secure: !reveal, contentType: contentType, caps: .never, autocorrect: false,
                                      accessibilityLabel: label, onFocus: { focused = $0 })
                    if allowReveal {
                        Button { reveal.toggle() } label: {
                            ProtoIcon("show-password", size: 20)
                                .foregroundStyle(reveal ? VC.brand : VC.ink3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -10)
                        .padding(.trailing, -10)
                        .accessibilityLabel(reveal ? "Hide password" : "Show password")
                    }
                }
            }
            if let shownError { FieldError(text: shownError) }
        }
        .padding(.bottom, 13)
        .id(fieldID ?? label)
    }
}

struct VTextArea: View {
    var label: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 84
    var maxLength: Int? = nil
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label { FieldLabel(text: label) }
            FieldBox(focused: focused, minHeight: minHeight) {
                FilteredField(text: $text, kind: maxLength.map { .plain(max: $0) },
                              prompt: Text(placeholder).foregroundStyle(VC.placeholder), axis: .vertical)
                    .lineLimit(3...12)
                    .lineSpacing(3)
                    .focused($focused)
                    .frame(minHeight: minHeight - 24, alignment: .topLeading)
            }
        }
        .padding(.bottom, 13)
    }
}

// MARK: - Banner (.banner)

struct Banner: View {
    var symbol: String = "you-re-offline"
    var tint: Color = VC.signalDeep
    var background: Color = VC.c2bg
    var border: Color = Color(hex: 0xF0DCAE)
    var textColor: Color = Color(hex: 0x7A5A10)
    let text: AttributedString
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ProtoIcon(symbol, size: 19).foregroundStyle(tint).padding(.top, 1)
            Text(text).font(VFont.ui(12.5)).foregroundStyle(textColor).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(border, lineWidth: 1))
    }
}

/// Markdown-ish helper: **bold** segments become bold.
func md(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

// MARK: - Success screen (.success)

struct SuccessBlock<Buttons: View>: View {
    let title: String
    let message: AttributedString
    @ViewBuilder var buttons: () -> Buttons
    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(VC.c3bg).frame(width: 96, height: 96)
                .overlay(ProtoIcon("link-my-account", size: 46, lineWidth: 2.2).foregroundStyle(VC.pass))
                .padding(.bottom, 20)
            Text(title).font(VFont.display(22, .bold)).foregroundStyle(VC.ink).padding(.bottom, 8)
            Text(message).font(VFont.ui(14)).foregroundStyle(VC.ink3).multilineTextAlignment(.center)
                .lineSpacing(3).frame(maxWidth: 300).padding(.bottom, 22)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) { buttons() }
        }
        .padding(.top, 40).padding(.horizontal, 10).padding(.bottom, 20)
    }
}

// MARK: - Dashed add box (.addsec)

struct DashedBox<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content() }
            .padding(14)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(VC.brand, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.bottom, 14)
    }
}

struct SmallField: View {
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default
    var kind: FieldKind? = nil
    var fieldID: String? = nil
    var errors: FormErrors? = nil
    var onSubmit: (() -> Void)? = nil
    /// Placeholder-only field: a required one shows a red "*" inside its trailing edge.
    var required = false
    var body: some View {
        let err = fieldID.flatMap { errors?[$0] }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                FilteredTextField(text: $text, kind: kind, fieldID: fieldID, errors: errors, placeholder: placeholder,
                                  font: VFont.uUI(14), keyboard: keyboard,
                                  caps: keyboard == .emailAddress || kind == .email ? .never : .sentences,
                                  autocorrect: !(keyboard == .emailAddress || kind == .email),
                                  accessibilityLabel: required ? "\(placeholder), required" : placeholder, onSubmit: onSubmit)
                if required {
                    Text("*").font(VFont.ui(15, .semibold)).foregroundStyle(VC.c1).accessibilityHidden(true)
                }
            }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(err != nil ? VC.c1 : VC.line, lineWidth: err != nil ? 2 : 1))
            if let err { FieldError(text: err) }
        }
        .id(fieldID ?? placeholder)
    }
}

// MARK: - Toggle (prototype switch)

struct VToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().tint(VC.brand)
    }
}
