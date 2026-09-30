import SwiftUI

// End User License Agreement: the text comes verbatim from shared/legal/eula.json (store.eula).

/// The agreement as rendered in the prototype (#s-eula renderEula): title, revised date, intro,
/// numbered section headings in brand-deep, paragraphs, footer — all inside one card.
struct EULABody: View {
    let doc: EULADocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doc.title)
                .font(VFont.display(17, .heavy)).foregroundStyle(VC.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            Text("Revised \(doc.revised)")
                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                .padding(.bottom, 12)
            ForEach(Array(doc.intro.enumerated()), id: \.offset) { _, p in paragraph(p) }
            ForEach(Array(doc.sections.enumerated()), id: \.offset) { i, section in
                Text(section.heading)
                    .font(VFont.display(14, .bold)).foregroundStyle(VC.brandDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16).padding(.bottom, 8)
                    .id("eula-sec-\(i + 1)")
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, p in paragraph(p) }
            }
            if let footer = doc.footer, !footer.isEmpty {
                Text(footer)
                    .font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14).padding(.bottom, 10)
                    .id("eula-footer")
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(VFont.ui(13)).foregroundStyle(VC.ink2)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }
}

/// Settings → Legal → End User License Agreement, and the link on Create account / Join.
struct EULAView: View {
    @Environment(AppStore.self) private var store
    @State private var jump = FormErrors()     // only used for the DEBUG -eulaSection jump
    var body: some View {
        Screen(title: "License agreement", actions: store.session == nil ? [] : [store.homeAction()], errors: jump) {
            EULABody(doc: store.eula)
        }
        #if DEBUG
        .task {
            // -eulaSection N|footer: scroll to that heading (review screenshots).
            guard let n = DebugLaunch.value("-eulaSection") else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            jump.scrollTarget = n == "footer" ? "eula-footer" : "eula-sec-\(n)"
        }
        #endif
    }
}

/// Full-screen gate shown at sign-in when the user hasn't accepted the current eula.json version.
struct EULAGateView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmSignOut = false

    var body: some View {
        let updated = store.currentUser?.eulaVersion != nil
        VStack(spacing: 0) {
            AppHeader(title: updated ? "Updated license agreement" : "License agreement",
                      subtitle: store.session == nil ? "Vision Inspection Management Solutions" : store.company.name,
                      leading: .none)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Draft copy (not in the prototype): explains why the screen appears.
                    Text(updated
                         ? "We've updated the VIMS End User License Agreement (revised \(store.eula.revised)). Please review it and tap I agree to keep using VIMS."
                         : "Please review the VIMS End User License Agreement (revised \(store.eula.revised)) and tap I agree to continue.")
                        .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 14)
                    EULABody(doc: store.eula)
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 20)
            }
            VStack(spacing: 4) {
                Button("I agree") { withAnimation(.easeOut(duration: 0.25)) { store.acceptEula() } }
                    .buttonStyle(.vPrimary)
                Button("Sign out") { confirmSignOut = true }
                    .font(VFont.ui(14, .semibold)).foregroundStyle(VC.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .signOutConfirmation(isPresented: $confirmSignOut)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            .background(VC.paper.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(VC.line).frame(height: 1) }
        }
        .background(VC.paper2.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

/// "I have read and agree to the VIMS End User License Agreement…" — required on Create account
/// and Join a company. The agreement name opens the viewer.
struct EULAAgreeCheckbox: View {
    @Environment(AppStore.self) private var store
    @Binding var agreed: Bool
    let errors: FormErrors
    static let fieldID = "eula"
    static let errorText = "Please accept the End User License Agreement to continue"

    var body: some View {
        let error = errors[Self.fieldID]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    agreed.toggle()
                    if agreed { errors.set(Self.fieldID, nil) }
                } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(agreed ? VC.brand : VC.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(error != nil ? VC.c1 : (agreed ? VC.brand : VC.ink3), lineWidth: error != nil ? 2 : 1.5))
                        .overlay { if agreed { ProtoIcon("check", size: 15, lineWidth: 3).foregroundStyle(.white) } }
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -11).padding(.top, -11)
                .accessibilityLabel("I have read and agree to the VIMS End User License Agreement, which governs the free trial and subscription.")
                .accessibilityValue(agreed ? "Checked" : "Not checked")
                .accessibilityAddTraits(.isToggle)

                Text(sentence)
                    .font(VFont.ui(13.5)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { _ in
                        store.push(.eula)
                        return .handled
                    })
                    .padding(.leading, -11)
            }
            if let error { FieldError(text: error).padding(.leading, 30) }
        }
        .id(Self.fieldID)
        .padding(.top, 4).padding(.bottom, 16)
    }

    private var sentence: AttributedString {
        var s = AttributedString("I have read and agree to the ")
        var link = AttributedString("VIMS End User License Agreement")
        link.link = URL(string: "vims://eula")
        link.foregroundColor = VC.brand
        link.font = VFont.ui(13.5, .semibold)
        s += link
        s += AttributedString(", which governs the free trial and subscription.")
        return s
    }
}
