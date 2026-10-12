import SwiftUI
import UIKit
import LinkPresentation

// iPad support. The iPhone layout is the approved design and is left exactly as it is; on iPad (regular width)
// scrolling content sits in a centered readable column (wider, often two columns, in landscape), big documents
// open full screen, the quick-comment list is a popover anchored to its field, the State list a form sheet, and every UIKit share sheet gets a popover anchor (it crashes without one).

enum Device {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

enum PadLayout {
    /// Max width of a screen's scrolling content in regular width (iPad portrait). Headers and bars stay full width.
    static let readableWidth: CGFloat = 740
    /// Narrower column for the sign-in / create-account / join forms.
    static let formWidth: CGFloat = 560
    /// Windows at least this wide (iPad landscape: 11", 13", mini) get the wide layout: a wider column and two
    /// columns where it helps. Portrait windows (up to 1032 pt) keep the 740 pt column.
    static let wideWindow: CGFloat = 1100
    /// Cap for the wide column, so lines and fields never stretch across a whole 13" landscape screen.
    static let maxWideWidth: CGFloat = 1080
    /// Long reading text (EULA, inspection agreement) keeps a comfortable line length on wide windows.
    static let documentWidth: CGFloat = 900
    /// Sign-in style forms on wide windows.
    static let wideFormWidth: CGFloat = 680

    /// The scrolling column for a window this wide: `base` below `wideWindow`, else 80 % of the window capped at
    /// `wideMax` (13" landscape 1376 → 1080, 11" 1210 → 968, mini 1133 → 906).
    static func columnWidth(window: CGFloat, base: CGFloat = readableWidth, wideMax: CGFloat = maxWideWidth) -> CGFloat {
        guard window >= wideWindow else { return base }
        return max(base, min(wideMax, (window * 0.8).rounded()))
    }
}

private struct WindowWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// Width of the app's window (set once at the root), so screens can pick the wide iPad layout.
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }
}

/// Reads whether this screen should use the wide (two-column) iPad layout: regular width and a landscape-sized window.
struct WideLayout: DynamicProperty {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.windowWidth) private var windowWidth
    var isWide: Bool { sizeClass == .regular && windowWidth >= PadLayout.wideWindow }
    var columnWidth: CGFloat { PadLayout.columnWidth(window: windowWidth) }
}

extension View {
    /// Root: publishes the window width to every screen (`windowWidth`).
    func measuresWindowWidth() -> some View { modifier(WindowWidthReader()) }
}

private struct WindowWidthReader: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .environment(\.windowWidth, width)
    }
}

/// Two views side by side on the wide iPad layout (top aligned, equal widths), stacked otherwise.
struct WideColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = 20
    var wide: Bool
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: 0) { leading() }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 0) { trailing() }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            leading()
            trailing()
        }
    }
}

/// Centers the content in a `maxWidth` column in regular width; a no-op on iPhone (compact width).
/// On a landscape-sized window the column grows with the window (`PadLayout.columnWidth`), up to 1080 pt.
/// The modifier never branches, so a size-class change (iPad multitasking) doesn't reset view state.
struct ReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.windowWidth) private var windowWidth
    var maxWidth: CGFloat = PadLayout.readableWidth
    /// Cap on wide (landscape) windows.
    var wideMax: CGFloat = PadLayout.maxWideWidth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? PadLayout.columnWidth(window: windowWidth, base: maxWidth, wideMax: wideMax) : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableColumn(_ maxWidth: CGFloat = PadLayout.readableWidth, wideMax: CGFloat = PadLayout.maxWideWidth) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth, wideMax: wideMax))
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
    let picker: () -> Picker

    func body(content: Content) -> some View {
        // iPad: a form-sized sheet, so the search field and a long list stay visible with the keyboard up (a popover
        // hanging off the field only had room for two rows above the keyboard). iPhone: the usual full-height sheet.
        content.sheet(isPresented: $isPresented) { picker().padFormSheet() }
    }
}

extension View {
    /// Pickers (e.g. the State list): iPad → a form-sized sheet; iPhone → the usual sheet.
    func pickerPresentation<Picker: View>(isPresented: Binding<Bool>, @ViewBuilder picker: @escaping () -> Picker) -> some View {
        modifier(PickerPresentation(isPresented: isPresented, picker: picker))
    }

    /// iPad: form-sized sheet (iOS 18+ `.form`; iOS 17's default iPad sheet is already a form sheet). iPhone: unchanged.
    @ViewBuilder
    func padFormSheet() -> some View {
        if #available(iOS 18.0, *), Device.isPad {
            presentationSizing(.form)
        } else {
            self
        }
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
