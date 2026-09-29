import SwiftUI

/// Home's left side-drawer menu (hamburger). Scrim tap or swipe left closes it.
struct HomeSideMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var isOpen: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.84, 340)
            ZStack(alignment: .leading) {
                Color(hex: 0x0A0F16, alpha: 0.5).ignoresSafeArea()
                    .opacity(Double(1 + min(0, drag) / width))
                    .onTapGesture { close() }
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
                panel
                    .frame(width: width)
                    .background(VC.paper2.ignoresSafeArea())
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 8)
                    .offset(x: min(0, drag))
                    .gesture(DragGesture(minimumDistance: 12)
                        .onChanged { drag = min(0, $0.translation.width) }
                        .onEnded { v in
                            if v.translation.width < -width * 0.3 || v.predictedEndTranslation.width < -width * 0.5 { close() }
                            else { withAnimation(.easeOut(duration: 0.2)) { drag = 0 } }
                        })
                    .transition(.move(edge: .leading))
                    .accessibilityAddTraits(.isModal)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: company logo (or initials), user name, email, company
            VStack(alignment: .leading, spacing: 10) {
                CompanyLogoBadge(size: 56, radius: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.session?.name ?? "").font(VFont.display(16, .bold)).foregroundStyle(.white)
                    Text(store.session?.email ?? "").font(VFont.ui(12)).foregroundStyle(VC.hdrSub).lineLimit(1)
                    Text(store.company.name).font(VFont.ui(12, .semibold)).foregroundStyle(VC.hdrSub).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(VC.hdr.ignoresSafeArea(edges: .top))

            ScrollView {
                VStack(spacing: 8) {
                    group {
                        item("hdr-home", "Inspections") { close() }
                        item("hdr-add", "New inspection") { go(.wizard(editing: nil)) }
                        item("settings-structure-rooms", "Settings") { go(.settings) }
                        item("company-profile-logo", "Company profile") { go(.company) }
                        item("how-vims-works", "How VIMS works") { go(.instructions) }
                        item("email-to-client", "Help & feedback", last: true) {
                            close()
                            let email = store.company.feedbackEmail
                            if let url = URL(string: "mailto:\(email)?subject=VIMS%20app%20feedback") { openURL(url) }
                        }
                    }
                    if store.isAdmin {
                        Text("ADMIN").font(VFont.mono(10, .semibold)).tracking(1.1).foregroundStyle(VC.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 8)
                        group {
                            item("manage-checklist-add", "Manage checklist") { go(.manageChecklist) }
                            item("plans-pricing-edit", "Plans & pricing") { go(.plans) }
                            item("inspector-accounts-inspector", "Inspectors", last: true) { go(.inspectors) }
                        }
                    }
                }
                .padding(10)
            }

            Button {
                close()
                store.signOut()
            } label: {
                IconLabel("Sign out", icon: "sign-out-sync")
            }
            .buttonStyle(.vGhost)
            .padding(.horizontal, 10).padding(.bottom, 12)
        }
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
    }

    private func item(_ icon: String, _ title: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProtoIcon(icon, size: 16).foregroundStyle(VC.brand)
                    .frame(width: 30, height: 30).background(VC.paper3)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProtoIcon("chevron-right", size: 16).foregroundStyle(VC.chevron)
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .frame(minHeight: 50)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(VC.line2).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) { isOpen = false }
        drag = 0
    }

    private func go(_ r: Route) {
        close()
        store.push(r)
    }
}
