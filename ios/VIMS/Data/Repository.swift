import Foundation
import UIKit
import ImageIO

/// Offline-first local persistence. Everything lives on-device as JSON + image files
/// so the app works with no network. A future Laravel-backed implementation (Phase 2)
/// can sit behind the same protocol or feed it via SyncService.
protocol Repository: AnyObject {
    func loadAppState() -> AppState?
    func saveAppState(_ state: AppState)

    func loadInspections() -> [Inspection]
    func saveInspection(_ inspection: Inspection)
    func deleteInspection(id: UUID)

    /// Writes image data and returns its relative path.
    func saveImage(_ data: Data, folder: String, name: String) -> String?
    /// Writes an arbitrary file (e.g. an inspection agreement) and returns its relative path.
    func saveFile(_ data: Data, folder: String, name: String) -> String?
    func url(for relativePath: String) -> URL
    func deleteFile(_ relativePath: String)
    func wipeAll()
}

final class FileRepository: Repository {
    let root: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let io = DispatchQueue(label: "vims.repository.io", qos: .utility)

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("vims", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root.appendingPathComponent("inspections"), withIntermediateDirectories: true)
    }

    private var appStateURL: URL { root.appendingPathComponent("app.json") }
    private func inspectionURL(_ id: UUID) -> URL { root.appendingPathComponent("inspections/\(id.uuidString).json") }

    func loadAppState() -> AppState? {
        guard let data = try? Data(contentsOf: appStateURL) else { return nil }
        return try? decoder.decode(AppState.self, from: data)
    }

    func saveAppState(_ state: AppState) {
        guard let data = try? encoder.encode(state) else { return }
        let url = appStateURL
        io.async { try? data.write(to: url, options: .atomic) }
    }

    func loadInspections() -> [Inspection] {
        let dir = root.appendingPathComponent("inspections")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let d = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Inspection.self, from: d)
        }
    }

    func saveInspection(_ inspection: Inspection) {
        guard let data = try? encoder.encode(inspection) else { return }
        let url = inspectionURL(inspection.id)
        io.async { try? data.write(to: url, options: .atomic) }
    }

    func deleteInspection(id: UUID) {
        let url = inspectionURL(id)
        let photos = root.appendingPathComponent("photos/\(id.uuidString)")
        let report = root.appendingPathComponent("reports/\(id.uuidString).pdf")
        io.async {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: photos)
            try? FileManager.default.removeItem(at: report)
        }
    }

    func saveImage(_ data: Data, folder: String, name: String) -> String? {
        saveFile(data, folder: folder, name: name)
    }

    func saveFile(_ data: Data, folder: String, name: String) -> String? {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            ImageCache.shared.invalidate(url)
            return "\(folder)/\(name)"
        } catch {
            return nil
        }
    }

    func url(for relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    func deleteFile(_ relativePath: String) {
        let url = url(for: relativePath)
        ImageCache.shared.invalidate(url)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    func wipeAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("inspections"), withIntermediateDirectories: true)
    }

    /// Blocks until queued writes are flushed (used before generating a report / in tests).
    func flush() { io.sync {} }
}

// MARK: - Image helpers

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func thumbnail(_ url: URL, maxPixel: CGFloat = 400) -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let img = ImageTools.downsample(url, maxPixel: maxPixel) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    func invalidate(_ url: URL) {
        for size in [200, 300, 400, 600, 900, 1200, 1600] {
            cache.removeObject(forKey: "\(url.path)#\(size)" as NSString)
        }
    }
}

enum ImageTools {
    static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Normalizes orientation and caps the long edge (camera photos -> ~750 KB JPGs).
    static func jpegData(_ image: UIImage, maxEdge: CGFloat = 2048, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: quality)
    }
}
