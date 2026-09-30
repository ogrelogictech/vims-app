import SwiftUI

struct HeaderAction: Identifiable {
    var id: String { symbol }
    let symbol: String
    let label: String
    let action: () -> Void
}

/// The prototype's blue app header (.apphdr): back/menu on the left, title + subtitle,
/// contextual actions on the right. Includes the offline/sync badge from the status bar.
struct AppHeader: View {
    enum Leading { case back, menu, none }

    @Environment(AppStore.self) private var store
    let title: String
    let subtitle: String
    var leading: Leading = .back
    var onLeading: (() -> Void)? = nil
    var actions: [HeaderAction] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                NetworkBadge()
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                switch leading {
                case .back:
                    HeaderButton(symbol: "hdr-back", label: "Back") { (onLeading ?? { store.back() })() }
                case .menu:
                    HeaderButton(symbol: "hdr-menu", label: "Menu") { onLeading?() }
                case .none:
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(VFont.display(17, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(VFont.ui(12))
                        .foregroundStyle(VC.hdrSub)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    ForEach(actions) { a in HeaderButton(symbol: a.symbol, label: a.label, action: a.action) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .background(VC.hdr.ignoresSafeArea(edges: .top))
    }
}

struct HeaderButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ProtoIcon(symbol, size: 20)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityLabel(label)
    }
}

struct NetworkBadge: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let n = store.pendingSyncCount
        let offline = !store.isOnline
        // Synced = green, queued = amber, Offline = gray (label always shown with the color).
        let text: String = store.syncing ? "Syncing…" : offline ? (n == 0 ? "Offline" : "Offline · \(n) queued") : (n == 0 ? "Synced" : "\(n) queued")
        let kind = offline ? 2 : (n > 0 && !store.syncing ? 1 : 0)
        HStack(spacing: 5) {
            Circle().frame(width: 6, height: 6)
            Text(text).font(VFont.mono(11))
        }
        .foregroundStyle(kind == 2 ? Color(hex: 0xE3E7ED) : kind == 1 ? Color(hex: 0xF2C869) : Color(hex: 0x7CE0AF))
        .padding(.horizontal, 9).padding(.vertical, 2)
        .background(kind == 2 ? Color.white.opacity(0.16) : kind == 1 ? VC.signal.opacity(0.22) : VC.pass.opacity(0.26))
        .clipShape(Capsule())
        .accessibilityLabel(text)
    }
}

/// Standard screen: header + scrolling content on paper-2.
struct Screen<Content: View>: View {
    @Environment(AppStore.self) private var store
    let title: String
    var subtitle: String? = nil
    var leading: AppHeader.Leading = .back
    var onLeading: (() -> Void)? = nil
    var actions: [HeaderAction] = []
    var scroll = true
    /// When set, the screen scrolls to the first field with an error after a submit.
    var errors: FormErrors? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: title, subtitle: subtitle ?? (store.session == nil ? "Vision Inspection Management Solutions" : store.company.name), leading: leading, onLeading: onLeading, actions: actions)
            if scroll {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) { content() }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 34)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: errors?.scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                        errors?.scrollTarget = nil
                    }
                }
            } else {
                content()
            }
        }
        .background(VC.paper2.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

extension AppStore {
    /// Standard contextual header actions (prototype setHeader()).
    func homeAction() -> HeaderAction { HeaderAction(symbol: "hdr-home", label: "Home") { [weak self] in self?.goHome() } }
}
