import SwiftUI
import PhotosUI
import UIKit

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
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var viewer: ViewerTarget?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            let cats = store.catalog.photoCategories(section, depth: insp.depth)
            let existing = insp.photos[section] ?? [:]
            let extra = existing.keys.filter { !cats.contains($0) && !(existing[$0]?.isEmpty ?? true) }.sorted()
            Screen(title: "\(section) photos", subtitle: insp.addressLine1,
                   actions: [HeaderAction(symbol: "list.bullet", label: "Sections") { store.popToSections(inspectionID) }, store.homeAction()]) {
                Text(md("Tap **Add** to capture a photo, tap a photo to mark it up or flag it, or tap **×** to delete one."))
                    .font(VFont.ui(13)).foregroundStyle(VC.ink3)
                    .padding(.top, 2).padding(.bottom, 14)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(cats + extra, id: \.self) { cat in
                    categoryBlock(cat, photos: existing[cat] ?? [])
                }
                Button("Done") { store.back() }
                    .buttonStyle(.vPrimary)
                    .padding(.top, 6)
            }
            .confirmationDialog("Add a photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("Take photo") { showCamera = true }
                Button("Choose from library") { showLibrary = true }
                Button("Cancel", role: .cancel) { captureCategory = nil }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in handleCaptured(img) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { img in handleCaptured(img) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $viewer) { t in
                PhotoMarkupView(inspectionID: inspectionID, section: section, category: t.category, photoID: t.photoID,
                                onReturnToSection: {
                                    if case .photos = store.path.last { store.path.removeLast() }
                                })
            }
            .onAppear {
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
                Button {
                    captureCategory = cat
                    if cameraAvailable { showSourceDialog = true } else { showLibrary = true }
                } label: {
                    Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 3) {
                            Image(systemName: "camera").font(.system(size: 20))
                            Text("Add").font(VFont.ui(10.5, .semibold))
                        }
                        .foregroundStyle(VC.brand)
                    }
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(VC.brand, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(ChipPressStyle())
                .accessibilityLabel("Add photo to \(cat)")
            }
        }
        .padding(.bottom, 16)
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
                darkButton("xmark", label: "Close") { dismiss() }
                Text("\(section) — \(category)").font(VFont.ui(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                darkButton("flag", label: "Flag a finding") { showFinding = true }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            GeometryReader { geo in
                let rect = imageRect(in: geo.size)
                ZStack(alignment: .topLeading) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .accessibilityLabel("Inspection photo, \(category)")
                    }
                    Canvas { ctx, _ in
                        for s in strokes + (current.map { [$0] } ?? []) { draw(s, in: &ctx, rect: rect) }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onAppear { displayWidth = rect.width }
                .onChange(of: rect.width) { _, w in displayWidth = w }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard rect.width > 0 else { return }
                        let p = CGPoint(x: (v.location.x - rect.minX) / rect.width, y: (v.location.y - rect.minY) / rect.height)
                        if let stamp {
                            if current == nil {
                                current = MarkStroke(color: pens[penIndex].0, uiColor: pens[penIndex].1, points: [p], stamp: stamp)
                            } else { current?.points = [p] }
                        } else if current == nil {
                            current = MarkStroke(color: pens[penIndex].0, uiColor: pens[penIndex].1, points: [p], stamp: nil)
                        } else {
                            current?.points.append(p)
                        }
                    }
                    .onEnded { _ in
                        if let c = current { strokes.append(c) }
                        current = nil
                    })
            }
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    toolLabel("Comment")
                    QuickCommentMenu(placeholder: "Add a quick comment…", selection: $quick, dark: true) { _ in }
                }
                TextField("", text: $custom, prompt: Text("Custom comment…").foregroundStyle(Color(hex: 0x9AA8BA)))
                    .font(VFont.ui(13)).foregroundStyle(.white).tint(.white)
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
                    toolButton(systemImage: "arrow.uturn.backward", label: "Undo") { _ = strokes.popLast() }
                    toolButton(text: "Clear", label: "Clear") { strokes.removeAll() }
                }
                HStack(spacing: 9) {
                    toolLabel("Stamp")
                    ForEach(stamps, id: \.self) { s in
                        toolButton(text: s, label: "Stamp \(s)", selected: stamp == s, big: true) { stamp = (stamp == s ? nil : s) }
                    }
                }
                HStack(spacing: 10) {
                    Button { save(); store.toast("Markup saved to photo"); dismiss() } label: { Label("Save markup", systemImage: "checkmark") }
                        .buttonStyle(.vSignal)
                    Button { save(); dismiss(); onReturnToSection() } label: { Label("Save & return", systemImage: "arrow.uturn.left") }
                        .buttonStyle(.vPrimary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 18)
            .background(Color(hex: 0x12181F).ignoresSafeArea(edges: .bottom))
        }
        .background(Color(hex: 0x0B0F15).ignoresSafeArea())
        .onAppear {
            if let ref = store.photo(inspectionID, section: section, category: category, photoID: photoID) {
                image = UIImage(contentsOfFile: store.repo.url(for: ref.file).path)
                if let c = ref.comment {
                    if store.config.findings.quickComments.contains(c) { quick = c } else { custom = c }
                }
            }
            if DebugFlags.openFlag { DebugFlags.openFlag = false; showFinding = true }
        }
        .sheet(isPresented: $showFinding) {
            FindingSheet(section: section, initialText: combinedComment() ?? "") { cat, text in
                store.addFinding(inspectionID, category: cat, text: text, section: section, photo: (category, photoID))
            }
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
            ctx.draw(Text(stamp).font(.system(size: stampSize, weight: .bold)).foregroundColor(s.color), at: p, anchor: .center)
            return
        }
        var path = Path()
        if let f = pts.first {
            path.move(to: f)
            if pts.count == 1 { path.addLine(to: CGPoint(x: f.x + 0.1, y: f.y + 0.1)) }
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
        ctx.stroke(path, with: .color(s.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
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
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
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
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
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
