import SwiftUI

// MARK: - 10 Sections overview (grouped accordion)

struct SectionsOverviewView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    @State private var open: Set<String> = []
    @State private var didInit = false
    @State private var confirmDelete = false
    @State private var deleteAnchor = PopoverAnchor()
    var wide = WideLayout()

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            // A blank Planned Maintenance (v1.14 `notes`) section is optional: not counted until something is written.
            let leafs = store.progressSections(insp)
            let done = leafs.filter { insp.status[$0] == .done }.count
            let pct = leafs.isEmpty ? 0 : Int((Double(done) / Double(leafs.count) * 100).rounded())
            Screen(title: "Sections", subtitle: insp.addressLine1, actions: [store.homeAction()]) {
                if wide.isWide {
                    // iPad landscape: the checklist groups on the left; progress and the report actions beside them.
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 0) { groups(insp, top: 0) }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "Progress", top: 0)
                            progressCard(insp, done: done, total: leafs.count, pct: pct)
                            agreementRow(insp)
                            actions(insp)
                        }
                        .frame(width: 340)
                    }
                } else {
                    progressCard(insp, done: done, total: leafs.count, pct: pct)
                    agreementRow(insp)
                    groups(insp, top: 8)
                    actions(insp)
                }
            }
            .onAppear {
                if !didInit {
                    didInit = true
                    if let first = insp.groups.first(where: { $0.link == nil }) { open = [first.heading] }
                    #if DEBUG
                    if let g = DebugFlags.openGroup { DebugFlags.openGroup = nil; open = [g] }
                    #endif
                }
            }
        } else {
            Screen(title: "Sections") { Text("This inspection is no longer on this device.").font(VFont.ui(14)) }
        }
    }

    private func progressCard(_ insp: Inspection, done: Int, total: Int, pct: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(insp.addressLine1).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink).lineLimit(1)
                Spacer()
                Pill(kind: pct == 100 ? .done : pct == 0 ? .new : .prog, text: "\(pct)%")
            }
            .padding(.bottom, 9)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(VC.paper3)
                    Capsule().fill(LinearGradient(colors: [VC.brand, VC.brandBright], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(pct) / 100)
                }
            }
            .frame(height: 7)
            .accessibilityElement().accessibilityLabel("\(pct) percent complete")
            HStack(spacing: 14) {
                countText(done, "done", VC.ink)
                countText(total - done, "left", VC.ink)
                countText(insp.findings.count, "findings", VC.c1)
            }
            .padding(.top, 11)
        }
        .vCard(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .padding(.bottom, 12)
    }

    /// Client Oct 30 (3), data v1.15: "Inspection agreement" under the progress card (every inspection type, also after
    /// the report) → the agreement filled in from this saved inspection, with "Email inspection agreement".
    private func agreementRow(_ insp: Inspection) -> some View {
        let client = insp.clientName.trimmingCharacters(in: .whitespaces)
        let subtitle = client.isEmpty ? "Filled in \u{00B7} Email to client" : "Filled in for \(client) \u{00B7} Email to client"
        return Button {
            store.push(.agreement(state: insp.state, fill: store.agreementFill(insp)))
        } label: {
            HStack(spacing: 11) {
                ProtoIcon("file", size: 17).foregroundStyle(VC.brand)
                    .frame(width: 30, height: 30).background(VC.paper3)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inspection agreement").font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                    Text(subtitle).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProtoIcon("chevron-right", size: 18).foregroundStyle(VC.ink3)
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .accessibilityLabel("Inspection agreement, \(subtitle)")
        .accessibilityHint("Opens the agreement filled in for this inspection")
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func groups(_ insp: Inspection, top: CGFloat) -> some View {
        SectionLabel(text: "Checklist · tap a group", top: top)
        ForEach(insp.groups) { g in
            GroupAccordion(group: g, insp: insp, isOpen: open.contains(g.heading),
                           toggle: { withAnimation(.easeInOut(duration: 0.2)) { toggle(g.heading) } },
                           openLink: { link in openLink(link) },
                           openSection: { store.push(store.sectionRoute(inspectionID, $0)) })
        }
    }

    @ViewBuilder
    private func actions(_ insp: Inspection) -> some View {
        if insp.hasSummary {
            Button { store.push(.summary(inspectionID)) } label: { IconLabel("Review summary", icon: "review-summary-svg") }
                .buttonStyle(.vSignal).padding(.top, 8)
        }
        Button { store.push(.report(inspectionID)) } label: { IconLabel("Generate report", icon: "file") }
            .buttonStyle(.vPrimary).padding(.top, insp.hasSummary ? 10 : 8)
        // Red ghost button like Settings → Delete account; asks first, then returns to Home.
        Button { confirmDelete = true } label: { IconLabel("Delete inspection", icon: "trash") }
            .buttonStyle(VButtonStyle(kind: .ghost, tint: VC.c1))
            .popoverAnchor(deleteAnchor)
            .deleteInspectionConfirmation(insp, isPresented: $confirmDelete, anchor: deleteAnchor, leave: true)
            .padding(.top, 22)
    }

    private func countText(_ n: Int, _ label: String, _ color: Color) -> some View {
        (Text("\(n)").font(VFont.ui(12, .bold)).foregroundColor(color) + Text(" \(label)").font(VFont.ui(12)).foregroundColor(VC.ink3))
    }

    private func toggle(_ h: String) { if open.contains(h) { open.remove(h) } else { open.insert(h) } }

    private func openLink(_ link: String) {
        if link == "summary" { store.push(.summary(inspectionID)) } else { store.push(.wizard(editing: inspectionID)) }
    }
}

struct GroupAccordion: View {
    @Environment(AppStore.self) private var store
    let group: ChecklistGroup
    let insp: Inspection
    let isOpen: Bool
    let toggle: () -> Void
    let openLink: (String) -> Void
    let openSection: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let link = group.link {
                Button { openLink(link) } label: {
                    header(trailing: AnyView(ProtoIcon("chevron-right", size: 18).foregroundStyle(VC.ink3)))
                }
                .buttonStyle(PressableStyle())
            } else {
                let leafs = group.leafSections
                let counted = store.progressSections(insp, leafs)
                let done = counted.filter { insp.status[$0] == .done }.count
                Button(action: toggle) {
                    header(trailing: AnyView(HStack(spacing: 8) {
                        // Only blank optional notes sections (Planned Maintenance): "Optional" instead of "0/0".
                        Text(counted.isEmpty && !leafs.isEmpty ? "Optional" : "\(done)/\(counted.count)")
                            .font(VFont.mono(11)).foregroundStyle(VC.ink3)
                        ProtoIcon("chevron-down", size: 18).foregroundStyle(VC.ink3)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(isOpen ? "Collapse" : "Expand")
                if isOpen {
                    VStack(spacing: 0) {
                        Rectangle().fill(VC.line2).frame(height: 1)
                        if leafs.isEmpty {
                            Text("No sections in this group").font(VFont.ui(13)).foregroundStyle(VC.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                        }
                        ForEach(group.sections, id: \.self) { n in srow(n) }
                        if let sub = group.sub {
                            SubHead(text: sub.heading)
                            ForEach(sub.sections, id: \.self) { n in srow(n) }
                        }
                    }
                }
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private func header(trailing: AnyView) -> some View {
        HStack(spacing: 11) {
            ProtoIcon(group.icon ?? "info", size: 17).foregroundStyle(VC.brand)
                .frame(width: 30, height: 30).background(VC.paper3)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(group.heading).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func srow(_ n: String) -> some View {
        let st = insp.status[n] ?? .todo
        return Button { openSection(n) } label: {
            HStack(spacing: 12) {
                StatusDot(status: st, size: 9)
                Text(store.catalog(for: insp).title(n)).font(VFont.ui(14, .medium)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
                Pill(kind: st.pillKind, text: store.statusLabel(insp, n))
            }
            .padding(.leading, 18).padding(.trailing, 15).padding(.vertical, 12)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(VC.line2).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// One palette for every status in the app: Done = green, In progress = blue,
/// Queued = amber, Scheduled / Not started / Offline = gray — always with a text label.
extension SectionStatus {
    var label: String { self == .done ? "Done" : self == .prog ? "In progress" : "Not started" }
    var pillKind: PillKind { self == .done ? .done : self == .prog ? .prog : .new }
}

struct StatusDot: View {
    let status: SectionStatus
    var size: CGFloat = 9
    var body: some View {
        Circle()
            .fill(status == .done ? VC.pass : status == .prog ? VC.brand : VC.paper3)
            .overlay(Circle().stroke(status == .todo ? VC.ink3 : .clear, lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SubHead: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(VFont.mono(10, .semibold)).tracking(1.1).foregroundStyle(VC.brandDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18).padding(.trailing, 15).padding(.top, 12).padding(.bottom, 7)
            .background(VC.paper2)
            .overlay(alignment: .top) { Rectangle().fill(VC.line2).frame(height: 1) }
    }
}

// MARK: - Checklist drawer (slides in from the left inside an inspection)

struct SectionsDrawer: View {
    @Environment(AppStore.self) private var store
    let insp: Inspection
    let current: String
    @Binding var isOpen: Bool
    let openSection: (String) -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color(hex: 0x0A0F16, alpha: 0.5).ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityLabel("Close sections")
                    .accessibilityAddTraits(.isButton)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checklist sections").font(VFont.display(16, .bold)).foregroundStyle(.white)
                        Text(insp.addressLine1).font(VFont.ui(12)).foregroundStyle(VC.hdrSub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(VC.hdr.ignoresSafeArea(edges: .top))
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(insp.groups) { g in drawerGroup(g) }
                        }
                        .padding(10)
                    }
                }
                .frame(width: min(geo.size.width * 0.84, 340))
                .background(VC.paper2.ignoresSafeArea())
                .shadow(color: .black.opacity(0.4), radius: 20, x: 8)
                .transition(.move(edge: .leading))
            }
        }
        .onAppear {
            expanded = Set(insp.groups.filter { $0.leafSections.contains(current) }.map(\.heading))
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.24)) { isOpen = false } }

    @ViewBuilder
    private func drawerGroup(_ g: ChecklistGroup) -> some View {
        VStack(spacing: 0) {
            if let link = g.link {
                Button {
                    close()
                    store.push(link == "summary" ? .summary(insp.id) : .wizard(editing: insp.id))
                } label: {
                    dgh(g, trailing: AnyView(ProtoIcon("chevron-right", size: 16).foregroundStyle(VC.ink3)))
                }
                .buttonStyle(PressableStyle())
            } else {
                let isOpen = expanded.contains(g.heading)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { if isOpen { expanded.remove(g.heading) } else { expanded.insert(g.heading) } }
                } label: {
                    dgh(g, trailing: AnyView(HStack(spacing: 6) {
                        Text("\(g.leafSections.count)").font(VFont.mono(10)).foregroundStyle(VC.ink3)
                        ProtoIcon("chevron-down", size: 16).foregroundStyle(VC.ink3)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }))
                }
                .buttonStyle(PressableStyle())
                if isOpen {
                    Rectangle().fill(VC.line2).frame(height: 1)
                    ForEach(g.sections, id: \.self) { n in drow(n) }
                    if let sub = g.sub {
                        SubHead(text: sub.heading)
                        ForEach(sub.sections, id: \.self) { n in drow(n) }
                    }
                }
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
    }

    private func dgh(_ g: ChecklistGroup, trailing: AnyView) -> some View {
        HStack(spacing: 10) {
            ProtoIcon(g.icon ?? "info", size: 16).foregroundStyle(VC.brand)
                .frame(width: 26, height: 26).background(VC.paper3)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(g.heading).font(VFont.ui(13.5, .semibold)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func drow(_ n: String) -> some View {
        let on = n == current
        return Button {
            close()
            if !on { openSection(n) }
        } label: {
            HStack(spacing: 10) {
                let st = insp.status[n] ?? .todo
                StatusDot(status: st, size: 8)
                Text(store.catalog(for: insp).title(n)).font(VFont.ui(13.5, on ? .semibold : .regular)).foregroundStyle(on ? VC.brandDeep : VC.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Pill(kind: st.pillKind, text: store.statusLabel(insp, n))
            }
            .padding(.leading, 16).padding(.trailing, 13).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(on ? VC.brand.opacity(0.1) : .clear)
            .overlay(alignment: .top) { Rectangle().fill(VC.line2).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
