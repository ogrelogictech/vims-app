import SwiftUI
import MessageUI
import UIKit
import UniformTypeIdentifiers

/// Everything needed to email a finished report. To = client (+ agent, unless the inspection's step-1
/// "Send the report to the real estate agent" is off — v1.4, e.g. New Hampshire); CC = the signed-in inspector's own
/// email (data v1.3 `support.ccInspector`, an archive copy). No Bcc (client Oct 30, data v1.13): the phone's mail app
/// shows a Bcc line to the sender, so the master-admin report-quality copy (`PlatformSettings.activeReportBcc`) is not
/// put on the device compose; the VIMS server sends it separately (TODO(backend) in `make`). `bcc` stays in the draft
/// (always empty) so `-mailSelfTest` can show it.
struct ReportMailDraft: Equatable {
    var to: [String]
    var cc: [String] = []
    var bcc: [String]
    var subject: String
    var body: String
    var attachmentURL: URL
    var attachmentName: String
    /// More files after the main one, each under its own file name (the agreement email's state documents).
    var extraAttachments: [URL] = []

    static func validEmails(_ list: [String]) -> [String] {
        list.map { Validator.trimmed($0) }.filter { Validator.error(for: $0, rule: .req(.email, "Email")) == nil }
    }

    /// - Parameter ccInspector: the signed-in user's email when `support.ccInspector` is on (nil = no CC).
    static func make(_ insp: Inspection, company: CompanyProfile, platform: PlatformSettings, pdf: URL,
                     ccInspector: String? = nil) -> ReportMailDraft {
        let to = validEmails([insp.field("Client email")] + (insp.sendsReportToAgent ? [insp.field("Real estate agent email")] : []))
        let cc = validEmails([ccInspector ?? ""]).filter { me in !to.contains { $0.caseInsensitiveCompare(me) == .orderedSame } }
        let client = insp.clientName.split(separator: " ").first.map(String.init) ?? ""
        let date = Fmt.parse(insp.field("Date"), "yyyy-MM-dd").map { Fmt.date($0, "MMMM d, yyyy") } ?? ""
        var body = "Hi\(client.isEmpty ? "" : " \(client)"),\n\n"
        body += "Your inspection report for \(insp.address.isEmpty ? insp.addressLine1 : insp.displayAddress)"
        body += date.isEmpty ? " is attached.\n\n" : " (inspected \(date)) is attached.\n\n"
        body += "Please read it carefully and let us know if you have any questions.\n"
        if !company.reviewURL.isEmpty { body += "\nIf you have a moment, we'd appreciate a review: \(company.reviewURL)\n" }
        body += "\nThank you,\n\(company.inspectorName.isEmpty ? company.name : company.inspectorName)\n\(company.name)"
        if !company.phone.isEmpty { body += "\n\(company.phone)" }
        // TODO(backend): when a report is emailed, the VIMS server sends the report-quality copy to
        // `platform.activeReportBcc` itself (POST the inspection id + report to the server's report-mail endpoint).
        // Never added to this compose (client Oct 30); until the server send exists, no quality copy is sent.
        return ReportMailDraft(
            to: to,
            cc: cc,
            bcc: [],
            subject: "Inspection report — \(insp.addressLine1)",
            body: body,
            attachmentURL: pdf,
            attachmentName: "Inspection Report - \(insp.addressLine1).pdf")
    }

    /// A state document (stateRules docs, e.g. the Oregon CCB consumer notice) sent to the client with the
    /// inspection agreement: To = client email (when valid), the PDF attached. No CC/BCC.
    static func stateDocument(_ doc: StateDocDef, pdf: URL, insp: Inspection, company: CompanyProfile, sender: String) -> ReportMailDraft {
        let first = insp.clientName.split(separator: " ").first.map(String.init) ?? ""
        var body = "Hi\(first.isEmpty ? "" : " \(first)"),\n\n"
        body += "Attached is the \(doc.name), provided with your inspection agreement"
        body += insp.address.isEmpty ? ".\n" : " for \(insp.displayAddress).\n"
        body += "\nThank you,\n\(sender.isEmpty ? company.name : sender)\n\(company.name)"
        if !company.phone.isEmpty { body += "\n\(company.phone)" }
        return ReportMailDraft(to: validEmails([insp.field("Client email")]), bcc: [], subject: doc.name, body: body,
                               attachmentURL: pdf, attachmentName: pdf.lastPathComponent)
    }

    /// Client Oct 30 (3), data v1.15 `agreementPrefill.emailButton`: the inspection agreement to the client. To = the
    /// client email (empty when none — the inspector can type it), no CC / BCC. `attachment` = the filled agreement PDF,
    /// or the company's own uploaded agreement unchanged; `docs` = the state's required documents (stateRules docs), each
    /// attached under its bundled file name, as the state-document draft does.
    static func agreement(_ fill: AgreementFill, attachment: URL, attachmentName: String, docs: [StateDocDef],
                          stateName: String?, company: CompanyProfile, sender: String) -> ReportMailDraft {
        let found = docs.compactMap { d in d.bundleURL.map { (d, $0) } }
        return ReportMailDraft(
            to: validEmails([fill.clientEmail]),
            bcc: [],
            subject: fill.street.isEmpty ? "Inspection Agreement" : "Inspection Agreement \u{2013} \(fill.street)",
            body: agreementBody(fill, docTitles: found.map(\.0.name), stateName: stateName, company: company, sender: sender),
            attachmentURL: attachment,
            attachmentName: attachmentName,
            extraAttachments: found.map(\.1))
    }

    /// The agreement email's text (spec `emailButton.body` + `_bodyNote`).
    static func agreementBody(_ fill: AgreementFill, docTitles: [String], stateName: String?, company: CompanyProfile, sender: String) -> String {
        let first = fill.clientName.split(separator: " ").first.map(String.init) ?? ""
        var body = first.isEmpty ? "Hello,\n\n" : "Hi \(first),\n\n"
        body += "Attached is the inspection agreement for the inspection"
        if !fill.fullAddress.isEmpty { body += " at \(fill.fullAddress)" }
        if !fill.dateTime.isEmpty { body += " on \(fill.dateTime)" }
        body += ". Please read it, sign it and send it back to me before the inspection.\n"
        if !docTitles.isEmpty {
            body += "\nAlso attached: \(docTitles.joined(separator: ", ")), which \(stateName ?? fill.stateCode) requires with the agreement.\n"
        }
        let name = sender.trimmingCharacters(in: .whitespaces)
        body += "\nThank you,\n\(name.isEmpty ? company.name : name)\n\(company.name)"
        if !company.phone.isEmpty { body += "\n\(company.phone)" }
        return body
    }

    /// Every attached file, in order (the share-sheet fallback shares the same ones).
    var attachmentURLs: [URL] { [attachmentURL] + extraAttachments }

    static func mimeType(_ fileName: String) -> String {
        UTType(filenameExtension: (fileName as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Applies the draft to a mail composer (split out so the configuration is checkable).
    func configure(_ vc: MFMailComposeViewController) {
        vc.setToRecipients(to)
        if !cc.isEmpty { vc.setCcRecipients(cc) }
        if !bcc.isEmpty { vc.setBccRecipients(bcc) }     // always empty (client Oct 30): no Bcc line in the compose
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            vc.addAttachmentData(data, mimeType: Self.mimeType(attachmentName), fileName: attachmentName)
        }
        for url in extraAttachments {
            if let data = try? Data(contentsOf: url) {
                vc.addAttachmentData(data, mimeType: Self.mimeType(url.lastPathComponent), fileName: url.lastPathComponent)
            }
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let draft: ReportMailDraft
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        draft.configure(vc)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}

// Share-sheet fallback when Mail isn't set up: ShareSheet.present (Views/Shell/Adaptive.swift), which gives the
// iPad popover its anchor.
