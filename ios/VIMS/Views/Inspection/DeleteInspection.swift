import SwiftUI

// Deleting an inspection to free device storage (client feedback, Oct 2026: a tester couldn't find a way to delete
// current or old inspections). Home rows have a visible ⋯ More options button with the same items as the row's
// long-press menu; inside an inspection, the Sections overview and Report ready screens have a red
// "Delete inspection" button. Every path asks the same confirmation, which offers "Save report first" when a
// report PDF exists. Only the signed-in inspector's own inspections are listed, so only the owner can delete.
// TODO(backend): once the VIMS server is live, reports are retained server-side (reports 3 years, agreements
// 5 years), so deleting on the device only frees space — see AppStore.deleteInspection.

extension View {
    /// The one "Delete this inspection?" confirmation. Attach it to the control that opens it so the iPad popover
    /// points at that control; `anchor` is where "Save report first"'s share sheet points on iPad.
    /// `leave`: deleting from inside the inspection returns to Home first.
    func deleteInspectionConfirmation(_ insp: Inspection, isPresented: Binding<Bool>, anchor: PopoverAnchor?, leave: Bool = false) -> some View {
        modifier(DeleteInspectionConfirmation(insp: insp, isPresented: isPresented, anchor: anchor, leave: leave))
    }
}

struct DeleteInspectionConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    let insp: Inspection
    @Binding var isPresented: Bool
    let anchor: PopoverAnchor?
    let leave: Bool

    func body(content: Content) -> some View {
        // Team QA Oct 22: a centered alert with a short title and message and explicit buttons (on iOS 26 the
        // confirmation dialog became a cramped popover with long text and no visible Cancel).
        content.alert("Delete this inspection?", isPresented: $isPresented) {
            if store.reportURL(insp.id) != nil {
                // Opens the share sheet (Save to Files, Mail, AirDrop…); the inspection is kept.
                Button("Save report first") { store.shareReport(insp.id, from: anchor, afterDismiss: true) }
            }
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteCopy.inspection(insp.addressLine1))
        }
    }

    private func delete() {
        let id = insp.id
        guard leave, !store.path.isEmpty else {
            withAnimation(.easeOut(duration: 0.25)) { store.deleteInspection(id) }
            store.toast("Inspection deleted")
            return
        }
        // From inside the inspection: back to Home, then delete once the pop has finished, so the screens
        // sliding away never render a missing inspection, and the row visibly leaves the list.
        store.goHome()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.easeOut(duration: 0.25)) { store.deleteInspection(id) }
            store.toast("Inspection deleted")
        }
    }
}

/// Short, clear wording for the delete / remove alerts (team QA Oct 22).
enum DeleteCopy {
    static func inspection(_ address: String) -> String {
        let a = address.trimmingCharacters(in: .whitespaces)
        return "This removes the checklist, photos and report for \(a.isEmpty ? "this inspection" : a) from this device. "
            + "Some states require keeping reports for 3–5 years."
    }
}

/// The items of a Home inspection row's ⋯ menu and its long-press menu.
struct InspectionMenuItems: View {
    @Environment(AppStore.self) private var store
    let insp: Inspection
    let anchor: PopoverAnchor
    let onDelete: () -> Void

    var body: some View {
        if store.reportURL(insp.id) != nil {
            Button { store.shareReport(insp.id, from: anchor, afterDismiss: true) } label: {
                IconLabel("Save or share report", icon: "upload-logo-png")
            }
        }
        Button(role: .destructive, action: onDelete) { IconLabel("Delete inspection", icon: "trash") }
    }
}

/// Home row's visible ⋯ More options button (44 pt), overlaid on the row's trailing edge.
struct InspectionMoreButton: View {
    let insp: Inspection
    let anchor: PopoverAnchor
    let onDelete: () -> Void

    var body: some View {
        Menu {
            InspectionMenuItems(insp: insp, anchor: anchor, onDelete: onDelete)
        } label: {
            ProtoIcon("more", size: 20)
                .foregroundStyle(VC.ink2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .popoverAnchor(anchor)
        .accessibilityLabel("More options for \(insp.addressLine1)")
    }
}
