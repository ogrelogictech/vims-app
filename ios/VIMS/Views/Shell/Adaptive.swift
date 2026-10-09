import SwiftUI
import UIKit
import LinkPresentation

// iPad support. The iPhone layout is the approved design and is left exactly as it is; on iPad (regular width)
// scrolling content sits in a centered readable column, big documents open full screen, dropdowns become
// popovers anchored to their field, and every UIKit share sheet gets a popover anchor (it crashes without one).

enum Device {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

enum PadLayout {
    /// Max width of a screen's scrolling content in regular width (iPad). Headers and bars stay full width.
    static let readableWidth: CGFloat = 740
    /// Narrower column for the sign-in / create-account / join forms.
    static let formWidth: CGFloat = 560
}

/// Centers the content in a `maxWidth` column in regular width; a no-op on iPhone (compact width).
/// The modifier never branches, so a size-class change (iPad multitasking) doesn't reset view state.
struct ReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var maxWidth: CGFloat = PadLayout.readableWidth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableColumn(_ maxWidth: CGFloat = PadLayout.readableWidth) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }

    /// iPad: page-sized sheet (iOS 18+; the iOS 17 form sheet otherwise). iPhone: unchanged.
    @ViewBuilder
    func padPageSheet() -> some View {
        if #available(iOS 18.0, *), Device.isPad {
            presentationSizing(.page)
        } else {
            self
        }
    }

    /// Big documents (PDF previews): full screen on iPad, the usual sheet on iPhone.
    func documentCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
        modifier(DocumentCover(item: item, cover: content))
    }
}

struct PickerPresentation<Picker: View>: ViewModifier {
    @Binding var isPresented: Bool
    let padSize: CGSize
    let picker: () -> Picker

    func body(content: Content) -> some View {
        if Device.isPad {
            content.popover(isPresented: $isPresented, arrowEdge: .top) {   // hangs below the field, like a dropdown
                picker()
                    // Ideal size; the popover shrinks it (never clips it) when there's less room next to the field.
                    .frame(width: padSize.width)
                    .frame(minHeight: 240, idealHeight: padSize.height, maxHeight: padSize.height)
                    .presentationCompactAdaptation(.popover)   // stays a popover in a narrow iPad window too
            }
        } else {
            content.sheet(isPresented: $isPresented, content: picker)
        }
    }
}

extension View {
    /// Pickers (e.g. the State list): iPad → a popover anchored to this field, `padSize` big; iPhone → the usual sheet.
    func pickerPresentation<Picker: View>(isPresented: Binding<Bool>, padSize: CGSize, @ViewBuilder picker: @escaping () -> Picker) -> some View {
        modifier(PickerPresentation(isPresented: isPresented, padSize: padSize, picker: picker))
    }
}

struct DocumentCover<Item: Identifiable, Cover: View>: ViewModifier {
    @Binding var item: Item?
    let cover: (Item) -> Cover

    func body(content: Content) -> some View {
        if Device.isPad {
            content.fullScreenCover(item: $item, content: cover)
        } else {
            content.sheet(item: $item, content: cover)
        }
    }
}

// MARK: - Share sheet with a popover anchor

/// Remembers the UIView behind a SwiftUI control so a UIKit popover (the share sheet on iPad) can point at it.
final class PopoverAnchor {
    weak var view: UIView?
}

/// One anchor per key, for a button repeated per row (e.g. each state document's "Send to client").
final class PopoverAnchors {
    private var map: [String: PopoverAnchor] = [:]
    subscript(_ key: String) -> PopoverAnchor {
        if let a = map[key] { return a }
        let a = PopoverAnchor()
        map[key] = a
        return a
    }
}

private struct PopoverAnchorView: UIViewRepresentable {
    let anchor: PopoverAnchor
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        anchor.view = v
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { anchor.view = v }
}

extension View {
    /// Marks this control as the place a share-sheet popover points to on iPad.
    func popoverAnchor(_ anchor: PopoverAnchor?) -> some View {
        background { if let anchor { PopoverAnchorView(anchor: anchor) } }
    }
}

enum ShareSheet {
    /// Presents UIActivityViewController over whatever is on screen. On iPad it's a popover pointing at
    /// `anchor` (or centered, arrowless, when there's no anchor) — never presented without a source, which crashes.
    /// On iPhone it's the usual bottom sheet.
    /// `title` labels a single shared file in the sheet's header (e.g. "Share agreement").
    @MainActor
    static func present(_ items: [Any], from anchor: PopoverAnchor?, title: String? = nil, completion: (() -> Void)? = nil) {
        guard let top = topViewController() else { return }
        let shared: [Any] = title.flatMap { t in (items.first as? URL).map { [TitledFile(url: $0, title: t)] } } ?? items
        let vc = UIActivityViewController(activityItems: shared, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in completion?() }
        if let pop = vc.popoverPresentationController {
            if let v = anchor?.view, v.window != nil {
                pop.sourceView = v
                pop.sourceRect = v.bounds
            } else {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
        }
        top.present(vc, animated: true)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// A file for the share sheet with a custom header title (the file name still comes from the URL).
private final class TitledFile: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    init(url: URL, title: String) { self.url = url; self.title = title }

    func activityViewControllerPlaceholderItem(_ vc: UIActivityViewController) -> Any { url }
    func activityViewController(_ vc: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ vc: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String {
        url.deletingPathExtension().lastPathComponent
    }
    func activityViewControllerLinkMetadata(_ vc: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.title = title
        m.originalURL = url
        m.url = url
        m.iconProvider = NSItemProvider(contentsOf: url)
        return m
    }
}
