import SwiftUI

// MARK: - 04 Home (inspections list)

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDelete: Inspection?
    @State private var menuOpen = false

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
               actions: [HeaderAction(symbol: "hdr-add", label: "New inspection") { store.push(.wizard(editing: nil)) }]) {
            if !store.subscription.active {
                Button { store.push(.subscribe) } label: {
                    HStack {
                        Text(md("**Free trial** · \(store.subscription.trialDaysLeft) days left")).font(VFont.ui(13.5))
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

            HStack(spacing: 10) {
                StatTile(value: "\(today.count)", label: "Inspections today")
                StatTile(value: "\(store.pendingSyncCount)", label: "Waiting to sync")
            }
            .padding(.bottom, 6)

            SectionLabel(text: "Today · \(Fmt.date(Date(), "EEE, MMM d"))")
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

            Button { store.push(.wizard(editing: nil)) } label: {
                IconLabel("New inspection", icon: "hdr-add")
            }
            .buttonStyle(.vPrimary)
            .padding(.top, 14)

            Button { store.push(.settings) } label: {
                IconLabel("Settings", icon: "settings-structure-rooms")
            }
            .buttonStyle(.vGhost)
            .padding(.top, 10)
        }
    }

    /// The delete confirmation hangs off its own row, so on iPad the popover points at that inspection.
    private func row(_ insp: Inspection, timeLead: Bool) -> some View {
        InspectionRow(insp: insp, timeLead: timeLead) { open(insp) }
            .contextMenu { deleteButton(insp) }
            .confirmationDialog("Delete this inspection?",
                                isPresented: Binding(get: { pendingDelete?.id == insp.id }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete inspection", role: .destructive) {
                    if let p = pendingDelete { store.deleteInspection(p.id); store.toast("Inspection deleted") }
                    pendingDelete = nil
                }
            } message: {
                Text("This removes \(insp.addressLine1), its photos, and its report from this device.")
            }
    }

    private func open(_ insp: Inspection) {
        store.push(.sections(insp.id))
    }

    @ViewBuilder
    private func deleteButton(_ insp: Inspection) -> some View {
        Button(role: .destructive) { pendingDelete = insp } label: { IconLabel("Delete inspection", icon: "trash") }
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
    let action: () -> Void

    var body: some View {
        let st = store.homeStatus(insp)
        Button(action: action) {
            RowView(title: insp.addressLine1, subtitle: subtitle(st)) {
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
        .padding(.bottom, 10)
        .accessibilityHint("Opens the inspection checklist")
    }

    private func subtitle(_ st: AppStore.HomeStatus) -> String {
        if timeLead {
            let city = insp.cityShort
            return [city.isEmpty ? nil : city, insp.structureShort].compactMap { $0 }.joined(separator: " · ")
        }
        let d = Fmt.date(insp.scheduled, "MMM d")
        switch st {
        case .done: return "\(d) · Report sent"
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
            VStack(spacing: 0) {
                Image("VimsLogo").resizable().scaledToFit().frame(width: 58, height: 58)
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VC.line, lineWidth: 1))
                    .padding(.bottom, 14)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(d)").font(VFont.display(22, .heavy))
                    Text("day\(s) left").font(VFont.ui(13, .bold))
                }
                .foregroundStyle(soon ? VC.c1 : VC.signalDeep)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(soon ? VC.c1bg : VC.c2bg)
                .clipShape(Capsule())
                .padding(.bottom, 12)
                Text(soon ? "Only \(d) day\(s) left in your free look" : "Your free look is counting down")
                    .font(VFont.display(19, .bold)).foregroundStyle(VC.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text(soon
                     ? "You have \(d) day\(s) left to sign up. Set up your subscription so access continues without interruption when the free look ends."
                     : "You are on the \(store.subscription.trialDays)-day free look — \(d) days left. Subscribe any time to keep access after it ends.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                Button("Set up subscription") {
                    withAnimation { store.showSplash = false }
                    store.push(.subscribe)
                }
                .buttonStyle(.vPrimary)
                Button("Continue to app") { withAnimation { store.showSplash = false } }
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
}
