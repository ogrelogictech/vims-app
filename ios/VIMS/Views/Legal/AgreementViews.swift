import SwiftUI
import QuickLook

// VIMS default inspection agreement (shared/legal/inspection-agreement.json, data v1.4) — prototype
// #s-agreementdoc (renderAgreement). Text is rendered verbatim; `{companyName}` → the signed-in company's name.

/// "Inspection agreement" screen. `stateCode == nil` (Company profile) lists every state's disclosure;
/// a code (wizard step 1) shows only that state's entry, or "No additional disclosures for <State>."
struct InspectionAgreementView: View {
    @Environment(AppStore.self) private var store
    let stateCode: String?
    @State private var quickLook: URL?
    @State private var jump = FormErrors()     // only used for the DEBUG -agreementScroll jump

    var body: some View {
        Screen(title: "Inspection agreement", subtitle: store.company.name, actions: [store.homeAction()], errors: jump) {
            if let doc = InspectionAgreement.bundled {
                content(doc)
            } else {
                Text("The VIMS inspection agreement couldn't be loaded.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vCard()
            }
        }
        .quickLookPreview($quickLook)
        #if DEBUG
        .task {
            // -agreementScroll disclosures: scroll to the state disclosures (review screenshots).
            guard DebugLaunch.value("-agreementScroll") != nil else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            jump.scrollTarget = "agreement-disclosures"
        }
        #endif
    }

    private func fill(_ t: String) -> String { InspectionAgreement.fill(t, company: store.company.name) }
    private func stateName(_ code: String) -> String { store.config.stateName(code) ?? code }

    @ViewBuilder
    private func content(_ doc: InspectionAgreement) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let own = store.company.agreementName, store.company.agreementFile != nil {
                ownNotice(own)
            }
            Text(fill(doc.title))
                .font(VFont.display(18, .heavy)).foregroundStyle(VC.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
            Text(doc.formLines.map(fill).joined(separator: "\n"))
                .font(VFont.mono(11.5)).foregroundStyle(VC.ink2)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(VC.line, lineWidth: 1))
                .padding(.bottom, 12)
            ForEach(Array(doc.body.enumerated()), id: \.offset) { _, b in block(b) }
            disclosures(doc)
            ForEach(Array(doc.closing.enumerated()), id: \.offset) { _, b in block(b) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
    }

    /// The company uses its own uploaded agreement: say so, and offer to open their file.
    private func ownNotice(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Your company uses its own agreement (") + Text(name).bold() + Text("). Below is the VIMS agreement for reference."))
                .font(VFont.ui(13)).foregroundStyle(VC.signalDeep).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let url = store.ownAgreementURL {
                Button { quickLook = url } label: { IconLabel("Open your agreement", icon: "file", iconSize: 16) }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44, fullWidth: false))
                    .font(VFont.ui(13.5, .semibold))
                    .accessibilityLabel("Open your agreement, \(name)")
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func disclosures(_ doc: InspectionAgreement) -> some View {
        let all = doc.disclosureStates
        let shown = stateCode.map { code in all.filter { $0 == code } } ?? all
        Text(doc.stateDisclosuresHeading)
            .font(VFont.display(14, .bold)).foregroundStyle(VC.brandDeep)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 14).padding(.bottom, 8)
            .id("agreement-disclosures")
        if let code = stateCode, shown.isEmpty {
            paragraph("No additional disclosures for \(stateName(code)).", color: VC.ink3)
        }
        ForEach(shown, id: \.self) { code in
            (Text("\(stateName(code)): ").font(VFont.ui(13, .bold)).foregroundColor(VC.ink)
             + Text(fill(doc.stateDisclosures[code] ?? "")))
                .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)
        }
        if let code = stateCode, !shown.isEmpty, shown.count < all.count {
            Text("Showing \(stateName(code)) only. The full agreement lists \(all.count) states.")
                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)
        }
    }

    @ViewBuilder
    private func block(_ b: InspectionAgreement.Block) -> some View {
        if b.isBullet {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}").font(VFont.ui(13)).foregroundStyle(VC.ink2)
                paragraph(fill(b.text), color: VC.ink2, bottom: 0)
            }
            .padding(.leading, 4).padding(.bottom, 9)
        } else {
            paragraph(fill(b.text), color: (b.lead ?? false) ? VC.ink : VC.ink2)   // lead → ink color (prototype)
        }
    }

    private func paragraph(_ text: String, color: Color, weight: VWeight = .regular, bottom: CGFloat = 9) -> some View {
        Text(text)
            .font(VFont.ui(13, weight)).foregroundStyle(color).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, bottom)
    }
}

/// Company profile → "Inspection agreement" card: VIMS agreement by default, or the company's own upload.
struct AgreementCard: View {
    @Environment(AppStore.self) private var store
    let upload: () -> Void

    var body: some View {
        let own = store.company.agreementFile != nil ? store.company.agreementName : nil
        HStack(spacing: 12) {
            LeadIcon(symbol: "no-agreement-uploaded")
            VStack(alignment: .leading, spacing: 2) {
                Text(own ?? "VIMS agreement").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                    .lineLimit(1).truncationMode(.middle)
                // "All 50 states · in use · View" / "Your agreement · in use · Use VIMS agreement": one line when it
                // fits, else the link drops under the status (a real button, so it's an easy tap target).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { status(own != nil); Text(" \u{00B7} ").font(VFont.ui(12)).foregroundStyle(VC.ink3); link(own != nil) }
                    VStack(alignment: .leading, spacing: 0) { status(own != nil); link(own != nil) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(own == nil ? "Upload your own" : "Replace") { upload() }
                .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44, fullWidth: false))
                .fixedSize()
        }
    }
}

extension AgreementCard {
    func status(_ own: Bool) -> some View {
        Text(own ? "Your agreement \u{00B7} in use" : "All 50 states \u{00B7} in use")
            .font(VFont.ui(12)).foregroundStyle(VC.ink3).fixedSize()
    }

    func link(_ own: Bool) -> some View {
        Button(own ? "Use VIMS agreement" : "View") {
            if own { store.useDefaultAgreement() } else { store.push(.agreement(state: nil)) }
        }
        .buttonStyle(InlineLinkStyle())
        .fixedSize()
        .accessibilityHint(own ? "Switches back to the VIMS agreement" : "Opens the VIMS agreement")
    }
}

/// Brand-colored inline text link with an enlarged hit area (prototype `<a style="color:var(--brand);font-weight:600">`).
struct InlineLinkStyle: ButtonStyle {
    var size: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VFont.ui(size, .semibold))
            .foregroundStyle(VC.brand.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: 28)
            .contentShape(Rectangle().inset(by: -8))
    }
}

/// Step-style checkbox row (22-pt box, 44-pt tall row), used by "Send the report to the real estate agent".
struct CheckboxRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? VC.brand : VC.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? VC.brand : VC.ink3, lineWidth: 1.5))
                    .overlay { if isOn { ProtoIcon("check", size: 15, lineWidth: 3).foregroundStyle(.white) } }
                    .frame(width: 22, height: 22)
                Text(label)
                    .font(VFont.ui(13.5)).foregroundStyle(VC.ink).lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
    }
}
