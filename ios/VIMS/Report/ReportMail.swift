import SwiftUI
import MessageUI
import UIKit

/// Everything needed to email a finished report. BCC is the VIMS platform owner's report-quality
/// copy (PlatformSettings.activeReportBcc) and is never shown in the app UI.
struct ReportMailDraft: Equatable {
    var to: [String]
    var bcc: [String]
    var subject: String
    var body: String
    var attachmentURL: URL
    var attachmentName: String

    static func make(_ insp: Inspection, company: CompanyProfile, platform: PlatformSettings, pdf: URL) -> ReportMailDraft {
        let to = [insp.field("Client email"), insp.field("Real estate agent email")]
            .map { Validator.trimmed($0) }
            .filter { Validator.error(for: $0, rule: .req(.email, "Email")) == nil }
        let client = insp.clientName.split(separator: " ").first.map(String.init) ?? ""
        let date = Fmt.parse(insp.field("Date"), "yyyy-MM-dd").map { Fmt.date($0, "MMMM d, yyyy") } ?? ""
        var body = "Hi\(client.isEmpty ? "" : " \(client)"),\n\n"
        body += "Your inspection report for \(insp.address.isEmpty ? insp.addressLine1 : insp.address)"
        body += date.isEmpty ? " is attached.\n\n" : " (inspected \(date)) is attached.\n\n"
        body += "Please read it carefully and let us know if you have any questions.\n"
        if !company.reviewURL.isEmpty { body += "\nIf you have a moment, we'd appreciate a review: \(company.reviewURL)\n" }
        body += "\nThank you,\n\(company.inspectorName.isEmpty ? company.name : company.inspectorName)\n\(company.name)"
        if !company.phone.isEmpty { body += "\n\(company.phone)" }
        return ReportMailDraft(
            to: to,
            bcc: platform.activeReportBcc.map { [$0] } ?? [],
            subject: "Inspection report — \(insp.addressLine1)",
            body: body,
            attachmentURL: pdf,
            attachmentName: "Inspection Report - \(insp.addressLine1).pdf")
    }

    /// Applies the draft to a mail composer (split out so the configuration is checkable).
    func configure(_ vc: MFMailComposeViewController) {
        vc.setToRecipients(to)
        vc.setBccRecipients(bcc)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            vc.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentName)
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

/// Share-sheet fallback when Mail isn't set up. The share sheet can't carry a BCC.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
