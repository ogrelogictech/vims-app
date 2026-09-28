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

enum VButtonKind { case primary, ghost, signal }

struct VButtonStyle: ButtonStyle {
    var kind: VButtonKind = .primary
    var minHeight: CGFloat = 52
    var fullWidth = true

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
        switch kind {
        case .primary: return .white
        case .ghost: return VC.ink
        case .signal: return Color(hex: 0x3A2A05)
        }
    }
    private func bg(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? VC.brandDeep : VC.brand
        case .ghost: return pressed ? VC.paper2 : VC.paper
        case .signal: return pressed ? VC.signalDeep : VC.signal
        }
    }
}

struct VLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon.font(.system(size: 17, weight: .semibold))
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
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(VC.brand)
            .frame(width: 44, height: 44)
            .background(VC.paper3)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(VC.chevron)
    }
}

struct RowView<Lead: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 13) {
            lead()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VFont.ui(15, .semibold)).foregroundStyle(VC.ink).lineLimit(1)
                if let subtitle { Text(subtitle).font(VFont.ui(12.5, .medium)).foregroundStyle(VC.ink2).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
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
            Image(systemName: sym).font(.system(size: 16, weight: .semibold))
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

struct VTextField: View {
    var label: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences
    var mono = false
    var error: String? = nil
    var bottom: CGFloat = 13
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label { FieldLabel(text: label) }
            FieldBox(focused: focused, error: error != nil) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(VC.placeholder))
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(keyboard == .emailAddress || mono || keyboard == .URL)
                    .font(mono ? VFont.mono(15, .medium) : VFont.ui(15))
                    .focused($focused)
            }
            if let error { Text(error).font(VFont.ui(12)).foregroundStyle(VC.c1) }
        }
        .padding(.bottom, bottom)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).font(VFont.ui(12.5, .semibold)).foregroundStyle(VC.ink2)
    }
}

struct VSecureField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = ""
    var allowReveal = true
    var contentType: UITextContentType = .password
    var error: String? = nil
    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            FieldBox(focused: focused, error: error != nil) {
                HStack(spacing: 6) {
                    Group {
                        if reveal {
                            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(VC.placeholder))
                        } else {
                            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(VC.placeholder))
                        }
                    }
                    .textContentType(contentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    if allowReveal {
                        Button { reveal.toggle() } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye")
                                .font(.system(size: 17))
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
            if let error { Text(error).font(VFont.ui(12)).foregroundStyle(VC.c1) }
        }
        .padding(.bottom, 13)
    }
}

struct VTextArea: View {
    var label: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 84
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label { FieldLabel(text: label) }
            FieldBox(focused: focused, minHeight: minHeight) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(VC.placeholder), axis: .vertical)
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
    var symbol: String = "arrow.triangle.2.circlepath"
    var tint: Color = VC.signalDeep
    var background: Color = VC.c2bg
    var border: Color = Color(hex: 0xF0DCAE)
    var textColor: Color = Color(hex: 0x7A5A10)
    let text: AttributedString
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint).padding(.top, 1)
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
                .overlay(Image(systemName: "checkmark").font(.system(size: 40, weight: .semibold)).foregroundStyle(VC.pass))
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
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(VC.placeholder))
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .font(VFont.ui(14))
            .foregroundStyle(VC.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VC.line, lineWidth: 1))
    }
}

// MARK: - Toggle (prototype switch)

struct VToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().tint(VC.brand)
    }
}
