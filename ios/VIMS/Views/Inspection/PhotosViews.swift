import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 14 Photos by category

struct ViewerTarget: Identifiable, Hashable {
    var id: UUID { photoID }
    let category: String
    let photoID: UUID
}

struct PhotosView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    let section: String

    @State private var captureCategory: String?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var viewer: ViewerTarget?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var regular: Bool { sizeClass == .regular }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            let cats = store.catalog(for: inspectionID).photoCategories(section, depth: insp.depth)
            let existing = insp.photos[section] ?? [:]
            let extra = existing.keys.filter { !cats.contains($0) && !(existing[$0]?.isEmpty ?? true) }.sorted()
            Screen(title: store.catalog(for: inspectionID).isPhotosOnly(section) ? store.catalog(for: inspectionID).title(section) : "\(store.catalog(for: inspectionID).title(section)) photos", subtitle: insp.addressLine1,
                   actions: [HeaderAction(symbol: "hdr-sections", label: "Sections") { store.popToSections(inspectionID) }, store.homeAction()],
                   maxContentWidth: 1100) {
                let photosOnly = store.catalog(for: inspectionID).isPhotosOnly(section)
                Text(md((photosOnly ? "These pictures print on the picture pages after the checklist. " : "") + "Tap **Add** to capture a photo, tap a photo to mark it up or flag it, or tap **×** to delete one."))
                    .font(VFont.ui(13)).foregroundStyle(VC.ink3)
                    .padding(.top, 2).padding(.bottom, 14)
                    .fixedSize(horizontal: false, vertical: true)
                if regular {
                    // iPad: each photo slot is a card, laid out side by side (2–3 across), so a slot with one or two
                    // photos doesn't leave a mostly empty full-width row.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(cats + extra, id: \.self) { cat in
                            categoryBlock(cat, photos: existing[cat] ?? [])
                                .vCard(EdgeInsets(top: 13, leading: 14, bottom: 14, trailing: 14))
                        }
                    }
                    .padding(.bottom, 16)
                } else {
                    ForEach(cats + extra, id: \.self) { cat in
                        categoryBlock(cat, photos: existing[cat] ?? [])
                            .padding(.bottom, 16)
                    }
                }
                if photosOnly {
                    // Client Oct 29: same plain arrow as "Save & next section" (shared icon save-return-svg).
                    Button { store.finishPictures(inspectionID, section) } label: {
                        IconLabel("Save & continue to \(insp.hasSummary ? "summary" : "report")", icon: "save-return-svg")
                    }
                    .buttonStyle(.vPrimary)
                    .padding(.top, 6)
                    .readableColumn()
                } else {
                    Button("Done") { store.back() }
                        .buttonStyle(.vPrimary)
                        .padding(.top, 6)
                        .readableColumn()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in handleCaptured(img) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { img in handleCaptured(img) }
                    .ignoresSafeArea()
                    .padPageSheet()
            }
            // Files covers iCloud Drive, Google Drive and other file providers (document picker); images only.
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { captureCategory = nil; return }
                if let img = PhotoFiles.image(at: url) { handleCaptured(img) } else {
                    captureCategory = nil
                    store.toast("Couldn't open that image")
                }
            }
            .fullScreenCover(item: $viewer) { t in
                PhotoMarkupView(inspectionID: inspectionID, section: section, category: t.category, photoID: t.photoID,
                                onReturnToSection: {
                                    // Pictures (photos-only) pages are their own "section": stay on them.
                                    if !store.catalog(for: inspectionID).isPhotosOnly(section), case .photos = store.path.last { store.path.removeLast() }
                                })
            }
            .onAppear {
                endEditing()
                if DebugFlags.openMarkup {
                    DebugFlags.openMarkup = false
                    if let (c, arr) = cats.map({ ($0, existing[$0] ?? []) }).first(where: { !$0.1.isEmpty }), let p = arr.first {
                        viewer = ViewerTarget(category: c, photoID: p.id)
                    }
                }
            }
        }
    }

    private func categoryBlock(_ cat: String, photos: [PhotoRef]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(cat).font(VFont.ui(14, .semibold)).foregroundStyle(VC.ink)
                Spacer()
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")").font(VFont.mono(11)).foregroundStyle(VC.ink3)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(photos) { p in
                    PhotoTile(url: store.repo.url(for: p.file), flag: p.flag, onOpen: {
                        viewer = ViewerTarget(category: cat, photoID: p.id)
                    }, onDelete: {
                        store.deletePhoto(inspectionID, section: section, category: cat, photoID: p.id)
                        store.toast("Photo deleted")
                    })
                }
                // Client Oct 17: choose the source first — Photo Library, Camera or Files (iCloud Drive, Google Drive…),
                // like Jeremy's reference menu (Photos / Camera / Drive). A Menu on the tile, so on iPad it opens beside it.
                Menu {
                    Button { pick(cat) { showLibrary = true } } label: { sourceLabel("Photo Library", icon: "grid") }
                    Button { pick(cat) { showCamera = true } } label: {
                        sourceLabel(cameraAvailable ? "Camera" : "Camera (not on this device)", icon: "camera")
                    }
                    .disabled(!cameraAvailable)
                    Button { pick(cat) { showFiles = true } } label: { sourceLabel("Files / Drive", icon: "file") }
                } label: {
                    Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 3) {
                            ProtoIcon("camera", size: 22)
                            Text("Add").font(VFont.ui(10.5, .semibold))
                        }
                        .foregroundStyle(VC.brand)
                    }
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(VC.brand, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .contentShape(Rectangle())
                }
                .menuOrder(.fixed)
                .simultaneousGesture(TapGesture().onEnded { endEditing() })
                .accessibilityLabel("Add photo to \(cat)")
                .accessibilityHint("Choose Photo Library, Camera or Files")
            }
        }
    }

    private func pick(_ cat: String, _ open: () -> Void) {
        endEditing()
        captureCategory = cat
        open()
    }

    private func sourceLabel(_ title: String, icon: String) -> some View {
        Label { Text(title) } icon: { Image(uiImage: ProtoIcon.uiImage(icon, size: 22, color: .label).withRenderingMode(.alwaysTemplate)) }
    }

    /// Presenting a full-screen cover while the keyboard is still animating away can leave it with a
    /// zero top safe area; make sure no text field is focused first.
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleCaptured(_ image: UIImage?) {
        guard let image, let cat = captureCategory else { captureCategory = nil; return }
        captureCategory = nil
        if let ref = store.addPhoto(inspectionID, section: section, category: cat, image: image) {
            store.toast("Photo captured")
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                viewer = ViewerTarget(category: cat, photoID: ref.id)
            }
        } else {
            store.toast("Couldn't save that photo")
        }
    }
}

struct PhotoTile: View {
    let url: URL
    let flag: Int?
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = ImageCache.shared.thumbnail(url, maxPixel: 300) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    VC.paper3
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(VC.line, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .overlay(alignment: .topLeading) {
                Button(action: onDelete) {
                    Text("×").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color(hex: 0x0C1119, alpha: 0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .frame(width: 44, height: 44, alignment: .topLeading)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete photo")
            }
            .overlay(alignment: .topTrailing) {
                if let flag {
                    Text("\(flag)").font(VFont.mono(11, .semibold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(VC.category(flag))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(5)
                        .accessibilityLabel("Flagged category \(flag)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
    }
}

/// An image picked in Files (iCloud Drive / Google Drive / On My iPhone): read through its security-scoped URL.
enum PhotoFiles {
    static func image(at url: URL) -> UIImage? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var out: UIImage?
        // Coordinated read so a cloud file not on the device yet is downloaded first.
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in
            if let d = try? Data(contentsOf: u) { out = UIImage(data: d) }
        }
        return out
    }
}

// MARK: - Capture (real camera on device, photo library fallback on simulator)

struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            parent.dismiss()
            parent.onDone(img)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
            parent.onDone(nil)
        }
    }
}

struct LibraryPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPicker
        init(_ p: LibraryPicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onDone(nil); return
            }
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                let img = obj as? UIImage
                DispatchQueue.main.async { self.parent.onDone(img) }
            }
        }
    }
}

// MARK: - 15 Photo markup viewer

struct MarkStroke: Identifiable {
    let id = UUID()
    var color: Color
    var uiColor: UIColor
    var points: [CGPoint]          // normalized to the image (0…1)
    var stamp: String?
}

struct PhotoMarkupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let inspectionID: UUID
    let section: String
    let category: String
    let photoID: UUID
    let onReturnToSection: () -> Void

    @State private var image: UIImage?
    @State private var strokes: [MarkStroke] = []
    @State private var current: MarkStroke?
    @State private var penIndex = 0
    @State private var stamp: String?
    @State private var quick: String?
    @State private var custom = ""
    @State private var showFinding = false
    @State private var displayWidth: CGFloat = 0
    /// Client Oct 29: pinch (two fingers) zooms the photo about the fingers, two fingers pan it, double-tap zooms in /
    /// resets; one finger still draws and stamps. `zoom` 1…5 about the photo area's center, then `pan`.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    /// When the last single-tap mark (dot / stamp) was added — a double-tap removes the marks its own taps made.
    @State private var tapMarks: [Date] = []
    private let maxZoom: CGFloat = 5

    private let pens: [(Color, UIColor, String)] = [
        (Color(hex: 0xE5483B), UIColor(hex: 0xE5483B), "Red"),
        (Color(hex: 0xF0C020), UIColor(hex: 0xF0C020), "Yellow"),
        (Color(hex: 0x3D8BF0), UIColor(hex: 0x3D8BF0), "Blue")
    ]
    private let stamps = ["★", "↑", "↓", "←", "→"]
    private let lineWidth: CGFloat = 4
    private let stampSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                darkButton("close", label: "Close") { dismiss() }
                Text("\(section) — \(category)").font(VFont.ui(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                darkButton("flag", label: "Flag a finding") {
                    // Commit the custom comment being typed (incl. keyboard marked text) so the sheet gets all of it.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    DispatchQueue.main.async { showFinding = true }
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            GeometryReader { geo in
                let base = imageRect(in: geo.size)
                let rect = zoomed(base, in: geo.size)
                ZStack(alignment: .topLeading) {
                    if let image {
                        // Drawn at the zoomed size from the full-resolution photo, so it stays sharp when zoomed.
                        Image(uiImage: image).resizable()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityLabel("Inspection photo, \(category)")
                    }
                    Canvas { ctx, _ in
                        for s in strokes + (current.map { [$0] } ?? []) { draw(s, in: &ctx, rect: rect) }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onAppear {
                    displayWidth = base.width
                    if let z = DebugFlags.markupZoom { DebugFlags.markupZoom = nil; zoom = min(max(z, 1), maxZoom) }
                }
                .onChange(of: base.width) { _, w in displayWidth = w; clampPan(base: base, size: geo.size) }
                // One finger draws / stamps; two fingers pinch-zoom and pan; double-tap zooms in or resets.
                .overlay(MarkupTouchSurface(
                    onDraw: { phase, loc in drawTouch(phase, at: loc, rect: rect) },
                    onPinch: { factor, loc in pinch(by: factor, at: loc, base: base, size: geo.size) },
                    onPan: { d in
                        current = nil
                        pan.width += d.width; pan.height += d.height
                        clampPan(base: base, size: geo.size)
                    },
                    onDoubleTap: { loc in doubleTap(at: loc, base: base, size: geo.size) }))
                .overlay(alignment: .topTrailing) {
                    if zoom > 1.01 {
                        Button { zoom = 1; pan = .zero } label: {
                            Text("Reset zoom · \(String(format: "%.1f", zoom))×").font(VFont.ui(12, .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .background(Color(hex: 0x0C1119, alpha: 0.7))
                                .clipShape(Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .accessibilityLabel("Reset zoom")
                    }
                }
            }
            .clipped()
            .accessibilityHint("Pinch with two fingers or double-tap to zoom. Draw with one finger.")

            VStack(alignment: .leading, spacing: 12) {
                // Client Oct 16: no "Comment" label — the quick-comment dropdown takes the full row.
                QuickCommentMenu(placeholder: "Add a quick comment…", selection: $quick, dark: true) { _ in }
                FilteredTextField(text: $custom, kind: .plain(max: 200), placeholder: "Custom comment…", font: VFont.uUI(13),
                                  textColor: .white, placeholderColor: UIColor(hex: 0x9AA8BA), tint: .white)
                    .padding(.horizontal, 11).frame(minHeight: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                HStack(spacing: 9) {
                    toolLabel("Draw")
                    ForEach(Array(pens.enumerated()), id: \.offset) { i, pen in
                        let on = penIndex == i && stamp == nil
                        Button { penIndex = i; stamp = nil } label: {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pen.0)
                                .frame(width: 34, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(on ? Color.white : Color.white.opacity(0.25), lineWidth: 2))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(on ? Color.white : .clear, lineWidth: 2))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pen.2) pen")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    toolButton(systemImage: "clear-stamp-button", label: "Undo") { _ = strokes.popLast() }
                    toolButton(text: "Clear", label: "Clear") { strokes.removeAll() }
                }
                HStack(spacing: 9) {
                    toolLabel("Stamp")
                    ForEach(stamps, id: \.self) { s in
                        toolButton(text: s, label: "Stamp \(s)", selected: stamp == s, big: true) { stamp = (stamp == s ? nil : s) }
                    }
                }
                HStack(spacing: 10) {
                    Button { save(); store.toast("Markup saved to photo"); dismiss() } label: { IconLabel("Save markup", icon: "link-my-account") }
                        .buttonStyle(.vSignal)
                    Button { save(); dismiss(); onReturnToSection() } label: { IconLabel("Save & return", icon: "save-return-svg") }
                        .buttonStyle(.vPrimary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 18)
            .readableColumn(wideMax: PadLayout.readableWidth)   // iPad: tools stay a compact centered panel under the full-width photo
            .background(Color(hex: 0x12181F).ignoresSafeArea(edges: .bottom))
        }
        .background(Color(hex: 0x0B0F15).ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if let ref = store.photo(inspectionID, section: section, category: category, photoID: photoID) {
                image = UIImage(contentsOfFile: store.repo.url(for: ref.file).path)
                // The saved photo comment is "quick — custom" (combinedComment): split it back into the two fields.
                if let c = ref.comment {
                    if let q = store.config.findings.quickComments.filter({ c == $0 || c.hasPrefix($0 + " — ") }).max(by: { $0.count < $1.count }) {
                        quick = q
                        custom = Finding.customPart(c, quick: q)
                    } else { custom = c }
                }
            }
            if DebugFlags.openFlag { DebugFlags.openFlag = false; showFinding = true }
        }
        .sheet(isPresented: $showFinding) {
            FindingSheet(section: section, initialText: custom.trimmingCharacters(in: .whitespacesAndNewlines), initialQuick: quick) { cat, text, q in
                store.addFinding(inspectionID, category: cat, custom: text, quick: q, section: section, photo: (category, photoID))
            }
        }
    }

    // MARK: zoom

    /// The photo's rect on screen at the current zoom / pan (`base` = the fitted, unzoomed rect).
    private func zoomed(_ base: CGRect, in size: CGSize) -> CGRect {
        guard zoom != 1 || pan != .zero else { return base }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGRect(x: c.x + (base.minX - c.x) * zoom + pan.width, y: c.y + (base.minY - c.y) * zoom + pan.height,
                      width: base.width * zoom, height: base.height * zoom)
    }

    /// Keeps the zoomed photo covering the area it can (no panning it off-screen); centered on an axis it doesn't fill.
    private func clampPan(base: CGRect, size: CGSize) {
        let mx = max(0, base.width * zoom / 2 - size.width / 2), my = max(0, base.height * zoom / 2 - size.height / 2)
        pan = CGSize(width: min(max(pan.width, -mx), mx), height: min(max(pan.height, -my), my))
    }

    /// Zooms by `factor` keeping the photo point under `anchor` (the fingers) where it is.
    private func pinch(by factor: CGFloat, at anchor: CGPoint, base: CGRect, size: CGSize) {
        current = nil
        let z0 = zoom, z1 = min(max(zoom * factor, 1), maxZoom)
        guard z1 != z0 else { return }
        let dx = anchor.x - size.width / 2, dy = anchor.y - size.height / 2
        pan = CGSize(width: dx - (dx - pan.width) * z1 / z0, height: dy - (dy - pan.height) * z1 / z0)
        zoom = z1
        clampPan(base: base, size: size)
    }

    /// Double-tap: 2.5× about the tapped point, or back to the whole photo when zoomed. The dots / stamps its two taps
    /// placed are taken back off.
    private func doubleTap(at p: CGPoint, base: CGRect, size: CGSize) {
        current = nil
        let now = Date()
        while let t = tapMarks.last, now.timeIntervalSince(t) < 0.7, !strokes.isEmpty, strokes.last?.points.count == 1 {
            strokes.removeLast(); tapMarks.removeLast()
        }
        // Not animated: the marks (Canvas) and the photo must move together.
        if zoom > 1.01 {
            zoom = 1; pan = .zero
        } else {
            let z1: CGFloat = 2.5
            let dx = p.x - size.width / 2, dy = p.y - size.height / 2
            pan = CGSize(width: dx - dx * z1, height: dy - dy * z1)
            zoom = z1
            clampPan(base: base, size: size)
        }
    }

    private func drawTouch(_ phase: MarkupTouchSurface.Phase, at loc: CGPoint, rect: CGRect) {
        switch phase {
        case .began, .moved:
            guard rect.width > 0 else { return }
            let p = CGPoint(x: (loc.x - rect.minX) / rect.width, y: (loc.y - rect.minY) / rect.height)
            if let stamp {
                if current == nil {
                    current = MarkStroke(color: pens[penIndex].0, uiColor: pens[penIndex].1, points: [p], stamp: stamp)
                } else { current?.points = [p] }
            } else if current == nil {
                current = MarkStroke(color: pens[penIndex].0, uiColor: pens[penIndex].1, points: [p], stamp: nil)
            } else {
                current?.points.append(p)
            }
        case .ended:
            if let c = current {
                strokes.append(c)
                if c.points.count == 1 { tapMarks.append(Date()) }
            }
            current = nil
        case .cancelled:
            current = nil       // a second finger landed (pinch / pan): that touch wasn't a mark
        }
    }

    // MARK: drawing

    private func imageRect(in size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let s = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func draw(_ s: MarkStroke, in ctx: inout GraphicsContext, rect: CGRect) {
        let pts = s.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        if let stamp = s.stamp, let p = pts.first {
            ctx.draw(Text(stamp).font(.system(size: stampSize * zoom, weight: .bold)).foregroundColor(s.color), at: p, anchor: .center)
            return
        }
        var path = Path()
        if let f = pts.first {
            path.move(to: f)
            if pts.count == 1 { path.addLine(to: CGPoint(x: f.x + 0.1, y: f.y + 0.1)) }
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
        // Marks scale with the photo (the saved photo gets them at the unzoomed size, `save()`).
        ctx.stroke(path, with: .color(s.color), style: StrokeStyle(lineWidth: lineWidth * zoom, lineCap: .round, lineJoin: .round))
    }

    private func combinedComment() -> String? {
        let parts = [quick, custom.trimmingCharacters(in: .whitespacesAndNewlines)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// Flattens the strokes onto the full-resolution photo.
    private func save() {
        var flattened: UIImage?
        if let image, !strokes.isEmpty {
            let scale = image.size.width / max(displayWidth, 1)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            flattened = UIGraphicsImageRenderer(size: image.size, format: fmt).image { rc in
                image.draw(at: .zero)
                let cg = rc.cgContext
                for s in strokes {
                    let pts = s.points.map { CGPoint(x: $0.x * image.size.width, y: $0.y * image.size.height) }
                    if let stamp = s.stamp, let p = pts.first {
                        let font = UIFont.systemFont(ofSize: stampSize * scale, weight: .bold)
                        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: s.uiColor]
                        let sz = (stamp as NSString).size(withAttributes: attrs)
                        (stamp as NSString).draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2), withAttributes: attrs)
                        continue
                    }
                    guard let f = pts.first else { continue }
                    cg.setStrokeColor(s.uiColor.cgColor)
                    cg.setLineWidth(lineWidth * scale)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    cg.move(to: f)
                    if pts.count == 1 { cg.addLine(to: CGPoint(x: f.x + 0.5, y: f.y + 0.5)) }
                    for p in pts.dropFirst() { cg.addLine(to: p) }
                    cg.strokePath()
                }
            }
        }
        store.saveMarkup(inspectionID, section: section, category: category, photoID: photoID, flattened: flattened, comment: combinedComment())
    }

    // MARK: tool UI

    private func toolLabel(_ s: String) -> some View {
        Text(s).font(VFont.mono(12)).foregroundStyle(Color(hex: 0x9AA8BA)).frame(width: 58, alignment: .leading)
    }

    private func darkButton(_ symbol: String, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProtoIcon(symbol, size: 19).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityLabel(label)
    }

    private func toolButton(systemImage: String? = nil, text: String? = nil, label: String, selected: Bool = false, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage { ProtoIcon(systemImage, size: 17) }
                else { Text(text ?? "").font(big ? .system(size: 17, weight: .semibold) : VFont.ui(13)) }
            }
            .foregroundStyle(selected ? VC.ink : .white)
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 40)
            .background(selected ? Color.white : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Markup touch surface (one finger draws, two fingers zoom / pan, double-tap zooms)

/// UIKit touch handling over the markup photo: SwiftUI can't tell a one-finger stroke from the first finger of a pinch,
/// so single touches are tracked directly (a stroke starts on touch-down, like before) and a pinch / two-finger pan /
/// double-tap recognizer cancels it (`Phase.cancelled`) when it takes over.
struct MarkupTouchSurface: UIViewRepresentable {
    enum Phase { case began, moved, ended, cancelled }

    var onDraw: (Phase, CGPoint) -> Void
    /// Incremental scale factor since the last call, about the fingers' midpoint.
    var onPinch: (CGFloat, CGPoint) -> Void
    /// Incremental two-finger translation.
    var onPan: (CGSize) -> Void
    var onDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> SurfaceView { SurfaceView() }

    func updateUIView(_ v: SurfaceView, context: Context) {
        v.onDraw = onDraw; v.onPinch = onPinch; v.onPan = onPan; v.onDoubleTap = onDoubleTap
    }

    final class SurfaceView: UIView, UIGestureRecognizerDelegate {
        var onDraw: ((Phase, CGPoint) -> Void)?
        var onPinch: ((CGFloat, CGPoint) -> Void)?
        var onPan: ((CGSize) -> Void)?
        var onDoubleTap: ((CGPoint) -> Void)?
        private weak var drawing: UITouch?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            dbl.numberOfTapsRequired = 2
            dbl.delaysTouchesEnded = false     // single taps (dots / stamps) land at once
            for g in [pinch, pan, dbl] as [UIGestureRecognizer] { g.delegate = self; addGestureRecognizer(g) }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
        }

        // One finger: a stroke. A second finger cancels it (the pinch / pan takes over).
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if (event?.allTouches?.count ?? touches.count) > 1 {
                if drawing != nil { drawing = nil; onDraw?(.cancelled, .zero) }
                return
            }
            guard drawing == nil, let t = touches.first else { return }
            drawing = t
            onDraw?(.began, t.location(in: self))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = drawing, touches.contains(t) else { return }
            onDraw?(.moved, t.location(in: self))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = drawing, touches.contains(t) else { return }
            drawing = nil
            onDraw?(.ended, t.location(in: self))
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = drawing, touches.contains(t) else { return }
            drawing = nil
            onDraw?(.cancelled, .zero)
        }

        @objc private func pinched(_ g: UIPinchGestureRecognizer) {
            guard g.state == .began || g.state == .changed, g.numberOfTouches >= 2 else { return }
            onPinch?(g.scale, g.location(in: self))
            g.scale = 1
        }
        @objc private func panned(_ g: UIPanGestureRecognizer) {
            guard g.state == .began || g.state == .changed else { return }
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            onPan?(CGSize(width: t.x, height: t.y))
        }
        @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
            if drawing != nil { drawing = nil; onDraw?(.cancelled, .zero) }
            onDoubleTap?(g.location(in: self))
        }
    }
}
