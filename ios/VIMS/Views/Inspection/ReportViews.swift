import SwiftUI
import PDFKit
import MessageUI

// MARK: - 17 Summary

struct SummaryView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            Screen(title: "Summary", subtitle: insp.addressLine1,
                   actions: [HeaderAction(symbol: "hdr-sections", label: "Sections") { store.popToSections(inspectionID) }, store.homeAction()]) {
                HintText(text: "Every finding you flag lands here automatically, grouped by category. This drives the summary pages of the report.")
                    .padding(.top, 2).padding(.bottom, 14)
                // stateRules summaryDisclosure (Oklahoma): a permanent entry at the top of the summary.
                if let text = store.config.stateRule(insp.state)?.summaryDisclosure {
                    StateDisclosureCard(title: "\(store.config.stateName(insp.state) ?? insp.stateCode) disclosure", text: text)
                        .padding(.bottom, 12)
                }
                ForEach(store.config.findings.categories, id: \.id) { c in
                    SummaryCategoryCard(category: c, findings: insp.findings.filter { $0.category == c.id }) { f in
                        store.deleteFinding(inspectionID, findingID: f.id)
                        store.toast("Finding removed")
                    }
                }
                Button { store.push(.report(inspectionID)) } label: { IconLabel("Save and generate report", icon: "save-and-generate") }
                    .buttonStyle(.vPrimary)
                    .padding(.top, 14)
            }
        }
    }
}

struct SummaryCategoryCard: View {
    let category: FindingCategoryDef
    let findings: [Finding]
    let onDelete: (Finding) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Text("\(category.id)").font(VFont.display(16, .heavy)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(VC.category(category.id))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Category \(category.id)").font(VFont.ui(14.5, .bold)) + Text(" · \(category.label)").font(VFont.ui(14.5, .bold)))
                        .foregroundStyle(VC.ink)
                    Text(category.note).font(VFont.ui(12)).foregroundStyle(VC.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(findings.count)").font(VFont.mono(15, .semibold)).foregroundStyle(VC.ink)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .accessibilityElement(children: .combine)

            if findings.isEmpty {
                Text("No findings in this category.").font(VFont.ui(13)).foregroundStyle(VC.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15).padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(VC.line2).frame(height: 1) }
            }
            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(VC.category(category.id)).frame(width: 7, height: 7).padding(.top, 6)
                    (Text(f.section).font(VFont.ui(13.5, .bold)).foregroundColor(VC.ink) + Text(" — \(f.text)").font(VFont.ui(13.5)).foregroundColor(VC.ink2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(VC.line2).frame(height: 1) }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(role: .destructive) { onDelete(f) } label: { IconLabel("Remove finding", icon: "trash") }
                }
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 12)
    }
}

// MARK: - 18 Generate report (cover picker + contents)

struct ReportView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    @State private var coverStep = 1
    @State private var pageEstimate: Int?
    @State private var generating = false
    @State private var preview: PreviewDoc?

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            let cat = store.catalog
            let done = cat.sortedForReport(insp.leafSections.filter { insp.status[$0] == .done })
            Screen(title: "Generate report", subtitle: insp.addressLine1,
                   actions: [HeaderAction(symbol: "hdr-sections", label: "Sections") { store.popToSections(inspectionID) }, store.homeAction()]) {
                metaCard(insp)
                SectionLabel(text: "Report cover")
                CoverPicker(cover: Binding(get: { insp.cover }, set: { c in store.update(inspectionID) { $0.cover = c } }), step: $coverStep)

                SectionLabel(text: "Report pages")
                Text(Self.reportPages[store.catalog.reportLayout(for: insp.inspType)] ?? "")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .vCard(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

                SectionLabel(text: "Report contents · in checklist order")
                Text("Completed sections populate the report in the order they're numbered on your master checklist.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    if done.isEmpty {
                        Text("No sections completed yet").font(VFont.ui(14)).foregroundStyle(VC.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 12)
                    }
                    ForEach(Array(done.enumerated()), id: \.element) { i, n in
                        HStack {
                            Text(String(format: "%02d", cat.number(n))).font(VFont.mono(14, .semibold)).foregroundStyle(VC.brandDeep)
                                .frame(width: 30, alignment: .leading)
                            Text(n).font(VFont.ui(14)).foregroundStyle(VC.ink)
                            Spacer()
                            Pill(kind: .done, text: "Included")
                        }
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .overlay(alignment: .bottom) { if i < done.count - 1 { Rectangle().fill(VC.line2).frame(height: 1) } }
                    }
                }
                .padding(.vertical, 6)
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
                .padding(.bottom, 12)

                Button { Task { await previewFormat() } } label: { IconLabel("Preview report format", icon: "preview-report-format") }
                    .buttonStyle(.vGhost).padding(.top, -2)

                if !store.isOnline {
                    Banner(text: md("You're **offline**. The report generates on the device now; it uploads on the next sync."))
                        .padding(.top, 16)
                }
                Button { Task { await generate() } } label: {
                    if generating { ProgressView().tint(.white) } else { IconLabel("Generate PDF report", icon: "generate-pdf-report") }
                }
                .buttonStyle(.vPrimary)
                .disabled(generating)
                .padding(.top, 12)
            }
            .onAppear {
                if let s = DebugFlags.coverStep { coverStep = s; DebugFlags.coverStep = nil }
                Task { await estimate() }
            }
            .documentCover(item: $preview) { doc in PDFPreviewSheet(doc: doc) }
        }
    }

    /// Page structure per report layout (prototype copy for `reportLayouts`).
    static let reportPages: [ReportLayout: String] = [
        .standard: "Cover · Property information · Beginning notes · Checklist sections with their photos · Summary",
        .texas: "Cover · Inspector & property information (TREC REI 7-6) · Checklist (I / NI / NP / D) · Pictures · Summary",
        .fourPoint: "Cover · 4-Point checklist (Electrical, HVAC, Plumbing, Roof) · Pictures"
    ]

    private func metaCard(_ insp: Inspection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.catalog.reportLayout(for: insp.inspType) == .fourPoint ? "4-POINT INSPECTION REPORT" : "PROPERTY INSPECTION REPORT").font(VFont.mono(10.5)).tracking(1.4).foregroundStyle(Color(hex: 0xF2C869))
            Text(insp.addressLine1).font(VFont.display(20, .heavy)).foregroundStyle(.white).padding(.top, 9).padding(.bottom, 3)
            Text([insp.addressRest, insp.structure].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(VFont.ui(12.5)).foregroundStyle(Color(hex: 0xCFE2EB))
            HStack(spacing: 18) {
                stat(pageEstimate.map(String.init) ?? "—", "PAGES")
                stat("\(insp.findings.count)", "FINDINGS")
                stat("\(insp.photoCount)", "PHOTOS")
            }
            .padding(.top, 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [Color(hex: 0x274FB0), Color(hex: 0x101F45)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 2)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(VFont.display(17, .bold)).foregroundStyle(.white)
            Text(l).font(VFont.mono(10)).foregroundStyle(Color(hex: 0xA9C6D2))
        }
    }

    private func estimate() async {
        guard let data = store.reportData(inspectionID) else { return }
        let r = await Task.detached(priority: .utility) { ReportRenderer.render(data) }.value
        pageEstimate = r.pageCount
    }

    private func previewFormat() async {
        guard let data = store.reportData(inspectionID) else { return }
        let r = await Task.detached(priority: .userInitiated) { ReportRenderer.render(data) }.value
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VIMS-report-preview.pdf")
        try? r.pdf.write(to: url, options: .atomic)
        preview = PreviewDoc(url: url, title: "Report preview")
    }

    private func generate() async {
        generating = true
        let info = await store.generateReport(inspectionID)
        generating = false
        if info != nil { store.push(.reportReady(inspectionID)) } else { store.toast("Couldn't generate the report") }
    }
}

// MARK: Cover picker — Color → Theme → Style with live preview

struct CoverPicker: View {
    @Environment(AppStore.self) private var store
    @Binding var cover: CoverChoice
    @Binding var step: Int

    var body: some View {
        let covers = store.config.covers
        VStack(alignment: .leading, spacing: 0) {
            Button { step = 1 } label: {
                HStack(spacing: 13) {
                    CoverArt(cover: cover, size: CGSize(width: 78, height: 104), fontSize: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cover.label).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                        Text("Tap to change color, theme, or style").font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(13)
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
            }
            .buttonStyle(ChipPressStyle())
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    let label = ["1 · Color", "2 · Theme", "3 · Style"][i - 1]
                    Button { step = i } label: {
                        Text(label.uppercased()).font(VFont.mono(10)).tracking(0.6)
                            .foregroundStyle(i == step ? .white : (i < step ? VC.brandDeep : VC.ink3))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(i == step ? VC.hdr : (i < step ? VC.brand.opacity(0.14) : VC.paper3))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2).padding(.bottom, 14)

            switch step {
            case 1:
                HStack(spacing: 10) {
                    ForEach(covers.colors, id: \.name) { c in
                        let on = cover.color == c.name
                        Button { cover.color = c.name } label: {
                            VStack(spacing: 0) {
                                LinearGradient(colors: [Color(hexString: c.from), Color(hexString: c.to)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(height: 56)
                                Text(c.name).font(VFont.ui(12.5, .semibold)).foregroundStyle(on ? VC.brand : VC.ink2)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                            }
                            .background(VC.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 2))
                            .shadow(color: on ? VC.brand.opacity(0.15) : .clear, radius: 3)
                        }
                        .buttonStyle(ChipPressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Button("Next: theme") { step = 2 }.buttonStyle(.vPrimary).padding(.top, 12)
            case 2:
                SectionLabel(text: "Category", top: 2)
                optionGrid(store.config.coverCategoryOrder, selected: cover.category) { cat in
                    cover.category = cat
                    cover.option = covers.categories[cat]?.first ?? ""
                    if cat == "Solid" { cover.style = covers.solidStyle } else if cover.style == covers.solidStyle { cover.style = covers.styles.first ?? "Framed" }
                }
                let opts = covers.categories[cover.category] ?? []
                if !opts.isEmpty {
                    SectionLabel(text: "Image")
                    optionGrid(opts, selected: cover.option) { cover.option = $0 }
                }
                HStack(spacing: 10) {
                    Button("Back") { step = 1 }.buttonStyle(.vGhost)
                    Button("Next: style") { step = 3 }.buttonStyle(.vPrimary)
                }
                .padding(.top, 12)
            default:
                SectionLabel(text: "Style", top: 2)
                optionGrid(cover.category == "Solid" ? [covers.solidStyle] : covers.styles, selected: cover.style) { cover.style = $0 }
                Button("Back") { step = 2 }.buttonStyle(.vGhost).padding(.top, 12)
            }
        }
    }

    private func optionGrid(_ options: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(options, id: \.self) { o in
                let on = o == selected
                Button { pick(o) } label: {
                    HStack {
                        Text(o).font(VFont.ui(13.5, .semibold)).foregroundStyle(on ? VC.brandDeep : VC.ink2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if on { ProtoIcon("link-my-account", size: 16).foregroundStyle(VC.brand) }
                    }
                    .padding(.horizontal, 12).frame(minHeight: 46)
                    .background(on ? VC.brand.opacity(0.06) : VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
                }
                .buttonStyle(ChipPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct CoverArt: View {
    @Environment(AppStore.self) private var store
    let cover: CoverChoice
    let size: CGSize
    var fontSize: CGFloat = 11

    var body: some View {
        let c = store.config.covers.colors.first { $0.name == cover.color } ?? store.config.covers.colors[0]
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hexString: c.from), Color(hexString: c.to)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if cover.style == "Framed" {
                RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.7), lineWidth: 1.5).padding(7)
            } else if cover.style == "Shaded" {
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
            Text(cover.artLabel).font(VFont.display(fontSize, .bold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(8)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityLabel("Cover preview: \(cover.label)")
    }
}

// MARK: - 19 Report ready

struct ReportReadyView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    @State private var preview: PreviewDoc?
    @State private var mailDraft: MailDraftItem?
    @State private var emailAnchor = PopoverAnchor()
    private let canSendMail = MFMailComposeViewController.canSendMail()

    struct MailDraftItem: Identifiable { let id = UUID(); let draft: ReportMailDraft }

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            let pages = insp.report?.pageCount ?? 0
            Screen(title: "Report ready", subtitle: insp.addressLine1,
                   actions: [HeaderAction(symbol: "hdr-sections", label: "Sections") { store.popToSections(inspectionID) }, store.homeAction()]) {
                SuccessBlock(title: "Report generated",
                             message: AttributedString("\(pages)-page report for \(insp.addressLine1) is saved on this device " + (insp.needsSync ? "and queued to sync to the portal." : "and synced to the portal."))) {
                    if let url = store.reportURL(inspectionID) {
                        Button { preview = PreviewDoc(url: url, title: "\(insp.addressLine1) report") } label: {
                            IconLabel("Preview PDF", icon: "preview-report-format")
                        }
                        .buttonStyle(.vPrimary)
                        Button { emailReport(insp, url) } label: { IconLabel("Email to client", icon: "email-to-client") }
                            .buttonStyle(.vGhost)
                            .popoverAnchor(emailAnchor)
                        Text(mailNote)
                            .font(VFont.ui(12)).foregroundStyle(VC.ink3).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                    } else {
                        Text("The PDF file is missing — generate it again from the report screen.")
                            .font(VFont.ui(13)).foregroundStyle(VC.c1)
                    }
                    Button("Back to inspections") { store.goHome() }.buttonStyle(.vGhost)
                }
            }
            .documentCover(item: $preview) { doc in PDFPreviewSheet(doc: doc) }
            .task {
                guard DebugFlags.openPreview || DebugFlags.openShare, let url = store.reportURL(inspectionID) else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                if DebugFlags.openPreview { DebugFlags.openPreview = false; preview = PreviewDoc(url: url, title: "\(insp.addressLine1) report") }
                if DebugFlags.openShare { DebugFlags.openShare = false; emailReport(insp, url) }
            }
            .sheet(item: $mailDraft) { item in
                MailComposeView(draft: item.draft) { result in
                    mailDraft = nil
                    if result == .sent { store.toast("Report emailed") } else if result == .saved { store.toast("Saved to Drafts") }
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Under "Email to client": the inspector gets a copy (CC); without Mail, the share sheet is used instead.
    private var mailNote: String {
        let me = store.reportCcEmail
        // v1.4: the agent is left out when the inspection's "Send the report to the real estate agent" is off.
        let who = (store.inspection(inspectionID)?.sendsReportToAgent ?? true) ? "the client and agent" : "the client only"
        if canSendMail {
            return me.map { "The report is emailed to \(who), with a copy to you (\($0))." }
                ?? "The report is emailed to \(who)."
        }
        return "Mail isn't set up on this device, so the report opens in the share sheet. When reports are emailed through VIMS, "
            + "they go to \(who)"
            + (me.map { ", a copy goes to you (\($0))," } ?? "")
            + " and a blind copy is added for report-quality review."
    }

    /// Mail composer with the report attached, CC to the inspector and the platform BCC; share sheet when
    /// Mail isn't available. TODO(backend): the server-side send will always add the CC/BCC.
    private func emailReport(_ insp: Inspection, _ url: URL) {
        if canSendMail {
            mailDraft = MailDraftItem(draft: store.reportMailDraft(insp, pdf: url))
        } else {
            // Share a copy with a readable file name (the stored PDF is named by inspection id).
            let named = FileManager.default.temporaryDirectory.appendingPathComponent("Inspection Report - \(insp.addressLine1).pdf")
            try? FileManager.default.removeItem(at: named)
            let shared = (try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url
            ShareSheet.present([shared], from: emailAnchor)
        }
    }
}

// MARK: - PDF preview

struct PreviewDoc: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct PDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let doc: PreviewDoc

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    ProtoIcon("close", size: 19).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .accessibilityLabel("Close")
                Text(doc.title).font(VFont.display(16, .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                ShareLink(item: doc.url) {
                    ProtoIcon("upload-logo-png", size: 19).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .accessibilityLabel("Share PDF")
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(VC.hdr.ignoresSafeArea(edges: .top))   // full-screen cover on iPad: blue under the status bar
            PDFKitView(url: doc.url)
        }
        .background(Color(hex: 0x0C1119))
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = FitWidthPDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(hex: 0x0C1119)
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// Pages fit the view's width (re-fitted on rotation / iPad window resize) and pinch-zoom up to 5×.
final class FitWidthPDFView: PDFView {
    private var fittedWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard document != nil, bounds.width > 0, abs(bounds.width - fittedWidth) > 0.5 else { return }
        fittedWidth = bounds.width
        let fit = scaleFactorForSizeToFit
        guard fit > 0 else { return }
        minScaleFactor = fit
        maxScaleFactor = fit * 5
        scaleFactor = fit
    }
}
