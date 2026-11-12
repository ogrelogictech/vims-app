import SwiftUI

// Client Nov 4, shared data v1.19 `wizard.fees`, mockup "Inspection Informaiton 5": wizard step 4 "Utilities, testing & fees".
// Each option is a chip with its $ box beside it, then the fees and the pre-filled agreement button. Amounts are optional
// and never block Build checklist; they appear only on the inspection agreement.

struct FeesStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var draft: Inspection
    let viewAgreement: () -> Void
    /// Width of the step's column, for telling whether a long chip fits beside its $ box.
    @State private var columnWidth: CGFloat = 0
    /// Holds "$ 99,999.99" with the field's clear button, at any Dynamic Type size.
    @ScaledMetric(relativeTo: .body) private var boxWidth: CGFloat = 132

    private static let pairGap: CGFloat = 10
    private static let columnGap: CGFloat = 18

    /// Two pairs per row on tablets, one per row on phones.
    private var twoColumns: Bool { sizeClass == .regular }

    var body: some View {
        let w = store.config.wizard
        let type = draft.inspType
        let locked = w.areasLocked(type)
        let note = WizardRules.areasLockedNote(type)
        VStack(alignment: .leading, spacing: 0) {
            if locked {
                AreasLockedNote(text: note).padding(.top, 2).padding(.bottom, 2).id("areasLocked")
            }
            SectionLabel(text: "Utility & systems", top: locked ? 16 : 2)
            options(w.utilityOptions, group: .utility, locked: locked, note: note)
            HintText(text: "Add any secondary testing for this inspection.").padding(.top, 20).padding(.bottom, 12)
            // Section keys stay stored ("Termite", "Septic"); the chips show the v1.8 titles.
            options(w.testOptions, group: .test, locked: false, note: nil)
            Rectangle().fill(VC.ink3).frame(height: 1.5).padding(.top, 20).padding(.bottom, 18)
                .accessibilityHidden(true)
            feeRows(wizard: w)
            agreementButton.padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
    }

    // MARK: Options

    /// The option rows in order. On tablets, an option whose chip can't sit beside its $ box in half the width takes a row
    /// of its own (Wood Destroying Organism Inspection, as in the mockup).
    private func rows(_ options: [String]) -> [[String]] {
        guard twoColumns else { return options.map { [$0] } }
        var out: [[String]] = []
        var row: [String] = []
        for o in options {
            if chipWidth(o) > pairRoom {
                if !row.isEmpty { out.append(row); row = [] }
                out.append([o])
                continue
            }
            row.append(o)
            if row.count == 2 { out.append(row); row = [] }
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    /// What's left for a chip beside its $ box in half the column.
    private var pairRoom: CGFloat { (columnWidth - Self.columnGap) / 2 - boxWidth - Self.pairGap }

    /// The chip's natural width: its text plus ChipView's padding.
    private func chipWidth(_ option: String) -> CGFloat {
        let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: VFont.uUI(13.5, .medium))
        return ceil((store.catalog.title(option) as NSString).size(withAttributes: [.font: font]).width) + 32
    }

    private func options(_ options: [String], group: Inspection.FeeGroup, locked: Bool, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows(options), id: \.self) { row in
                HStack(alignment: .top, spacing: Self.columnGap) {
                    ForEach(row, id: \.self) { o in
                        pair(o, group: group, locked: locked, note: note)
                    }
                    // A short last row keeps its pair the same width as the rows above; a long chip's row spans the column.
                    if twoColumns, row.count == 1, row.first.map({ chipWidth($0) <= pairRoom }) ?? false {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private func pair(_ option: String, group: Inspection.FeeGroup, locked: Bool, note: String?) -> some View {
        let title = store.catalog.title(option)
        let selected = draft.isSelected(option, in: group)
        return HStack(alignment: .center, spacing: Self.pairGap) {
            ChipButton(label: title, on: selected, disabled: locked, disabledHint: note) {
                draft.setFeeOption(option, in: group, selected: !selected)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if locked {
                // Locked: disabled, and no amount shown because it doesn't count (it comes back when another type unlocks it).
                FeeReadOnlyBox(text: "", label: "\(title) amount", disabled: true).frame(width: boxWidth)
            } else {
                FeeAmountBox(label: "\(title) amount", fieldID: "fee-\(option)", text: Binding(
                    get: { draft.fees?.amounts[option] ?? "" },
                    set: { draft.setFeeAmount($0, for: option, in: group) }))
                    .frame(width: boxWidth)
            }
        }
    }

    // MARK: Fees

    private func feeRows(wizard w: WizardDef) -> some View {
        let bundled = InspectionFees.text(draft.bundledFees(wizard: w))
        let total = InspectionFees.text(draft.totalFees(wizard: w))
        // Client Nov 13 (data v1.24 `wizard.fees.surcharge`, screen print): typed, optional, same limits as the other amounts,
        // on its own row right above Inspection Fee. Never locked by `areasLockedTypes`.
        let surcharge = feeRow("Out of service area surcharge") {
            FeeAmountBox(label: "Out of service area surcharge", fieldID: "fee-surcharge", text: Binding(
                get: { draft.fees?.surcharge ?? "" },
                set: { draft.setSurcharge($0) }))
        }
        let fee = feeRow("Inspection Fee") {
            FeeAmountBox(label: "Inspection Fee", fieldID: "fee-inspection", text: Binding(
                get: { draft.fees?.inspectionFee ?? "" },
                set: { draft.setInspectionFee($0) }))
        }
        let bundledRow = feeRow("Bundled Secondary Testing") { FeeReadOnlyBox(text: bundled, label: "Bundled Secondary Testing") }
        let totalRow = feeRow("Total Cost of Inspection", strong: true) { FeeReadOnlyBox(text: total, label: "Total Cost of Inspection", strong: true) }
        return VStack(alignment: .leading, spacing: 10) {
            if twoColumns {
                HStack(alignment: .center, spacing: Self.columnGap) {
                    surcharge
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
                HStack(alignment: .center, spacing: Self.columnGap) { fee; bundledRow }
                HStack(alignment: .center, spacing: Self.columnGap) {
                    totalRow
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            } else {
                surcharge; fee; bundledRow; totalRow
            }
        }
    }

    private func feeRow<Box: View>(_ label: String, strong: Bool = false, @ViewBuilder box: () -> Box) -> some View {
        HStack(alignment: .center, spacing: Self.pairGap) {
            Text(label)
                .font(VFont.ui(14, strong ? .bold : .semibold)).foregroundStyle(VC.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)     // the box beside it carries the same label
            box().frame(width: boxWidth)
        }
        .frame(maxWidth: .infinity)
    }

    private var agreementButton: some View {
        HStack(spacing: Self.columnGap) {
            Button(action: viewAgreement) {
                Text("View Pre-filled Inspection Agreement")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.vGhost)
            .accessibilityHint("Opens the agreement filled in from what's entered so far")
            if twoColumns { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
    }
}

/// A $ box: decimal keypad, up to 2 decimals, 0 to 99,999.99 (`InspectionFees.limits`, shown after a $). The keystroke filter
/// can't produce anything out of range, so these fields never hold an error and never block the step.
private struct FeeAmountBox: View {
    let label: String
    let fieldID: String
    @Binding var text: String
    @State private var focused = false

    var body: some View {
        FieldBox(focused: focused) {
            HStack(spacing: 5) {
                Text(verbatim: "$").foregroundStyle(VC.ink2).accessibilityHidden(true)
                FilteredTextField(text: $text, kind: .number(InspectionFees.limits), fieldID: fieldID, placeholder: "0.00",
                                  keyboard: .decimalPad, caps: .never, autocorrect: false,
                                  accessibilityLabel: "\(label) in dollars", onFocus: { focused = $0 })
            }
        }
        .id(fieldID)
    }
}

/// A computed amount, or a locked option's empty box.
private struct FeeReadOnlyBox: View {
    let text: String
    let label: String
    var strong = false
    var disabled = false

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "$").foregroundStyle(VC.ink2)
            Text(text)
                .font(VFont.ui(15, strong ? .bold : .medium)).foregroundStyle(VC.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(VFont.ui(15))
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(VC.paper2)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(VC.line, lineWidth: 1))
        .opacity(disabled ? 0.42 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(disabled ? "Locked" : "$\(text)")
    }
}

/// Client Nov 4 (`_timeOfWalkThroughAbout`): a time that starts empty, with no auto-fill, and can be cleared. A compact
/// DatePicker can't be empty, so the box shows "Not set" and a wheel opens on tap: a sheet on iPhone, a popover on iPad.
struct OptionalTimeField: View {
    let label: String
    @Binding var value: String
    /// Where the wheel starts while nothing is set (the inspection's Time).
    var suggested: String = ""
    @State private var picking = false
    @State private var wheel = Date()

    private static let format = "HH:mm"

    var body: some View {
        let shown = Fmt.parse(value, Self.format).map { Fmt.date($0, "h:mm a") }
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            FieldBox(focused: false) {
                HStack(spacing: 6) {
                    Button {
                        wheel = Fmt.parse(value, Self.format) ?? Fmt.parse(suggested, Self.format) ?? Date()
                        picking = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(shown ?? "Not set")
                                .foregroundStyle(shown == nil ? VC.placeholder : VC.ink)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if shown == nil { ProtoIcon("clock", size: 17).foregroundStyle(VC.ink3) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityValue(shown ?? "Not set")
                    .accessibilityHint("Opens a time picker")
                    if shown != nil {
                        OptionalFieldClear(label: "Clear \(label)") { value = "" }
                    }
                }
            }
            .popover(isPresented: $picking) { picker }
        }
    }

    private var picker: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { picking = false }
                    .font(VFont.ui(16)).foregroundStyle(VC.brand)
                    .frame(minWidth: 60, minHeight: 44, alignment: .leading)
                Spacer()
                Text(label).font(VFont.display(16, .bold)).foregroundStyle(VC.ink).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Button("Set") { value = Fmt.date(wheel, Self.format); picking = false }
                    .font(VFont.ui(16, .semibold)).foregroundStyle(VC.brand)
                    .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.top, 8)
            DatePicker(label, selection: $wheel, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .environment(\.locale, Fmt.locale)
                .padding(.bottom, 8)
        }
        .frame(minWidth: 320)
        .background(VC.paper)
        .presentationDetents([.height(300)])
    }
}
