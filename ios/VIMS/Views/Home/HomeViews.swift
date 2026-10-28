import SwiftUI

// MARK: - 04 Home (inspections list)

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDelete: Inspection?
    @State private var moreAnchors = PopoverAnchors()
    @State private var menuOpen = false
    var wide = WideLayout()

    var body: some View {
        ZStack {
            content
            if menuOpen {
                HomeSideMenu(isOpen: $menuOpen)
                    .zIndex(5)
            }
        }
        .onAppear { if DebugFlags.openMenu { DebugFlags.openMenu = false; menuOpen = true } }
    }

    @ViewBuilder private var content: some View {
        let cal = Calendar.current
        let today = store.inspections.filter { cal.isDateInToday($0.scheduled) }.sorted { $0.scheduled < $1.scheduled }
        let recent = store.inspections.filter { !cal.isDateInToday($0.scheduled) }.sorted { $0.scheduled > $1.scheduled }

        Screen(title: "Inspections",
               leading: .menu,
               onLeading: { withAnimation(.easeOut(duration: 0.24)) { menuOpen = true } },
               actions: [HeaderAction(symbol: "hdr-add", label: "New inspection") { store.startNewInspection() }]) {
            if store.isSubscriptionExempt && !store.subscription.active {
                // Client Oct 28: master admins never see a trial countdown or Subscribe.
                Text(md("**Master admin** · no subscription needed")).font(VFont.ui(13.5)).foregroundStyle(VC.brandDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .frame(minHeight: 48)
                    .background(VC.brand.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color(hex: 0xC9DEE6), lineWidth: 1))
                    .padding(.bottom, 14)
            } else if !store.subscription.active {
                Button { store.push(.subscribe) } label: {
                    HStack {
                        Text(md(store.subscription.trialEnded ? "**Free trial ended**" : "**Free trial** · \(store.subscription.trialDaysLeft) days left")).font(VFont.ui(13.5))
                        Spacer()
                        HStack(spacing: 3) {
                            Text("Subscribe").font(VFont.ui(13.5, .semibold))
                            ProtoIcon("inspections-today", size: 16)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .frame(minHeight: 48)
                    .background(LinearGradient(colors: [VC.brand, VC.brandBright], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(ChipPressStyle())
                .padding(.bottom, 14)
            }

            if wide.isWide {
                // iPad landscape: the inspection lists on the left, the counts and actions in a side column.
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) { lists(today: today, recent: recent) }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "At a glance", top: 0)
                        StatTile(value: "\(today.count)", label: "Inspections today")
                        secondTile
                        actionButtons.padding(.top, 4)
                    }
                    .frame(width: 320)
                }
            } else {
                HStack(spacing: 10) {
                    StatTile(value: "\(today.count)", label: "Inspections today")
                    secondTile
                }
                .padding(.bottom, 6)
                lists(today: today, recent: recent)
                actionButtons.padding(.top, 14)
            }
        }
    }

    @ViewBuilder
    private func lists(today: [Inspection], recent: [Inspection]) -> some View {
        SectionLabel(text: "Today · \(Fmt.date(Date(), "EEE, MMM d"))", top: wide.isWide ? 0 : 20)
        if store.inspections.isEmpty {
            VStack(spacing: 8) {
                ProtoIcon("harrison-blvd-aug", size: 28).foregroundStyle(VC.brand)
                Text("No inspections yet").font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                Text("Tap New inspection to set up your first one. Everything you add is saved on this device.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink3).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .vCard(all: 20)
            .padding(.bottom, 4)
        } else if today.isEmpty {
            Text("No inspections scheduled today.").font(VFont.ui(13)).foregroundStyle(VC.ink3).padding(.bottom, 10)
        }
        ForEach(today) { insp in row(insp, timeLead: true) }
        if !recent.isEmpty {
            SectionLabel(text: "Recent")
            ForEach(recent) { insp in row(insp, timeLead: false) }
        }
    }

    /// "Waiting to sync" only when sync is on (data v1.10 `features.sync`; Phase 1 doesn't sync) — else the
    /// inspections in progress.
    @ViewBuilder private var secondTile: some View {
        if store.syncEnabled {
            StatTile(value: "\(store.pendingSyncCount)", label: "Waiting to sync")
        } else {
            StatTile(value: "\(store.inspections.filter { store.homeStatus($0) == .prog }.count)", label: "In progress")
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { store.startNewInspection() } label: {
                IconLabel("New inspection", icon: "hdr-add")
            }
            .buttonStyle(.vPrimary)

            Button { store.push(.settings) } label: {
                IconLabel("Settings", icon: "settings-structure-rooms")
            }
            .buttonStyle(.vGhost)
        }
    }

    /// Each row has a visible ⋯ More options button (Save or share report · Delete inspection) with the same items on
    /// long-press. The delete confirmation hangs off that row's ⋯ button, so on iPad the popover points at it.
    private func row(_ insp: Inspection, timeLead: Bool) -> some View {
        let anchor = moreAnchors[insp.id.uuidString]
        let onDelete = { pendingDelete = insp }
        return InspectionRow(insp: insp, timeLead: timeLead, trailingInset: 31) { open(insp) }
            .contextMenu { InspectionMenuItems(insp: insp, anchor: anchor, onDelete: onDelete) }
            .overlay(alignment: .trailing) {
                InspectionMoreButton(insp: insp, anchor: anchor, onDelete: onDelete)
                    .deleteInspectionConfirmation(insp, isPresented: Binding(get: { pendingDelete?.id == insp.id },
                                                                             set: { if !$0 { pendingDelete = nil } }),
                                                  anchor: anchor)
                    .padding(.trailing, 2)
            }
            .padding(.bottom, 10)
    }

    private func open(_ insp: Inspection) {
        store.push(.sections(insp.id))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(VFont.display(24, .heavy)).foregroundStyle(VC.ink)
            Text(label).font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VC.line, lineWidth: 1))
    }
}

struct InspectionRow: View {
    @Environment(AppStore.self) private var store
    let insp: Inspection
    let timeLead: Bool
    /// Room on the right for Home's overlaid ⋯ More options button.
    var trailingInset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        let st = store.homeStatus(insp)
        Button(action: action) {
            RowView(title: insp.addressLine1, subtitle: subtitle(st), trailingInset: trailingInset) {
                if timeLead {
                    VStack(spacing: 1) {
                        Text(Fmt.date(insp.scheduled, "h:mm")).font(VFont.mono(15, .semibold)).foregroundStyle(VC.brandDeep)
                        Text(Fmt.date(insp.scheduled, "a")).font(VFont.mono(10, .semibold)).foregroundStyle(VC.ink2)
                    }
                    .frame(width: 50, height: 44)
                    .background(VC.paper3)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    LeadIcon(symbol: "harrison-blvd-aug")
                }
            } trailing: {
                switch st {
                case .done: Pill(kind: .done, text: "Done")
                case .queued: Pill(kind: .queued, text: "Queued")
                case .prog: Pill(kind: .prog, text: "In progress")
                case .scheduled: Pill(kind: .new, text: "Scheduled")
                }
            }
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityHint("Opens the inspection checklist")
    }

    private func subtitle(_ st: AppStore.HomeStatus) -> String {
        if timeLead {
            let city = insp.cityShort
            return [city.isEmpty ? nil : city, insp.structureShort].compactMap { $0 }.joined(separator: " · ")
        }
        let d = Fmt.date(insp.scheduled, "MMM d")
        switch st {
        case .done: return store.syncEnabled ? "\(d) · Report sent" : "\(d) · Report ready"
        case .queued: return "\(d) · Report ready to send"
        case .prog: return "\(d) · In progress"
        case .scheduled: return "\(d) · Scheduled"
        }
    }
}

// MARK: - 05 Free-look countdown splash

struct TrialSplashView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.subscription.trialDaysLeft
        let soon = d <= 10
        let s = d == 1 ? "" : "s"
        ZStack {
            Color(hex: 0x0A0F16, alpha: 0.72).ignoresSafeArea()
            // QA Oct 14: the card scrolls when it doesn't fit (small iPhones, large text, iPad landscape split view),
            // so its buttons are never cut off; it stays centered when it fits.
            GeometryReader { geo in
                ScrollView {
                    card(d: d, soon: soon, s: s)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func card(d: Int, soon: Bool, s: String) -> some View {
        let ended = store.subscription.trialEnded
        return VStack(spacing: 0) {
                Image("VimsLogo").resizable().scaledToFit().frame(width: 58, height: 58)
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VC.line, lineWidth: 1))
                    .padding(.bottom, 14)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if ended {
                        Text("Free trial ended").font(VFont.ui(13, .bold))
                    } else {
                        Text("\(d)").font(VFont.display(22, .heavy))
                        Text("day\(s) left").font(VFont.ui(13, .bold))
                    }
                }
                .foregroundStyle(soon ? VC.c1 : VC.signalDeep)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(soon ? VC.c1bg : VC.c2bg)
                .clipShape(Capsule())
                .padding(.bottom, 12)
                Text(ended ? "Your free trial has ended" : soon ? "Only \(d) day\(s) left in your free look" : "Your free look is counting down")
                    .font(VFont.display(19, .bold)).foregroundStyle(VC.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                Text(ended ? TrialEndedText.message(store)
                     : soon
                     ? "You have \(d) day\(s) left to sign up. Set up your subscription so access continues without interruption when the free look ends."
                     : "You are on the \(store.subscription.trialDays)-day free look — \(d) days left. Subscribe any time to keep access after it ends.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                Button(ended ? "Subscribe" : "Set up subscription") {
                    withAnimation { store.showSplash = false }
                    store.push(.subscribe)
                }
                .buttonStyle(.vPrimary)
                Button(ended ? "View my inspections" : "Continue to app") { withAnimation { store.showSplash = false } }
                    .buttonStyle(.vGhost)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 22).padding(.vertical, 26)
            .frame(maxWidth: Device.isPad ? 400 : 320)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 35, y: 30)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

/// Wording for the trial-ended prompt and splash (one free trial per device, `DeviceTrial`).
@MainActor
enum TrialEndedText {
    static func lead(_ store: AppStore) -> String {
        let sub = store.subscription
        return sub.deviceTrialUsed == true ? "This device has already used its \(sub.trialDays)-day free trial."
                                           : "Your \(sub.trialDays)-day free trial is over."
    }
    static let rest = "Subscribe to start new inspections. Your existing inspections stay available, and their reports can still be shared."
    static func message(_ store: AppStore) -> String { lead(store) + " " + rest }
}
