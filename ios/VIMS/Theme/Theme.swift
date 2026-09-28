import SwiftUI
import UIKit
import CoreText

// MARK: - Design tokens (docs/design-tokens.md — match exactly)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Parses "#rrggbb" strings from the shared JSON (cover colors).
    init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(s, radix: 16) ?? 0x2F5EC9)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    convenience init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(s, radix: 16) ?? 0x2F5EC9)
    }
}

enum VC {
    static let brand = Color(hex: 0x2F5EC9)
    static let brandBright = Color(hex: 0x5580E6)
    static let brandDeep = Color(hex: 0x1E3D94)
    static let hdr = Color(hex: 0x2F5EC9)
    static let hdrSub = Color(hex: 0xD7E3F7)
    static let ink = Color(hex: 0x17222E)
    static let ink2 = Color(hex: 0x3F4E5E)
    static let ink3 = Color(hex: 0x5F6D7D)
    static let line = Color(hex: 0xDDE5EE)
    static let line2 = Color(hex: 0xEEF2F7)
    static let paper = Color.white
    static let paper2 = Color(hex: 0xF4F7FA)
    static let paper3 = Color(hex: 0xE9EEF4)
    static let signal = Color(hex: 0xE4A11B)
    static let signalDeep = Color(hex: 0xA5730A)
    static let c1 = Color(hex: 0xD0584A)
    static let c1bg = Color(hex: 0xFBE9E6)
    static let c2 = Color(hex: 0xC98A1A)
    static let c2bg = Color(hex: 0xFBF1DD)
    static let c3 = Color(hex: 0x2F9E6B)
    static let c3bg = Color(hex: 0xE7F4EE)
    static let pass = Color(hex: 0x2F9E6B)
    static let fail = Color(hex: 0xD0584A)
    static let placeholder = Color(hex: 0xA7B4C2)
    static let chevron = Color(hex: 0xB7C3D0)
    static let doneText = Color(hex: 0x1F7A52)

    static func category(_ n: Int) -> Color { n == 1 ? c1 : n == 2 ? c2 : c3 }
    static func categoryBg(_ n: Int) -> Color { n == 1 ? c1bg : n == 2 ? c2bg : c3bg }
}

// MARK: - Fonts (shared/fonts, registered at runtime)

enum FontRegistry {
    static func registerBundledFonts() {
        let names = ["Archivo-Variable", "IBMPlexSans-Variable", "IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold"]
        for n in names {
            guard let url = Bundle.main.url(forResource: n, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum VWeight { case regular, medium, semibold, bold, heavy }

enum VFont {
    // PostScript names of the named instances inside the variable fonts.
    static func displayName(_ w: VWeight) -> String {
        switch w {
        case .regular, .medium, .semibold: return "Archivo-SemiBold"
        case .bold: return "ArchivoRoman-Bold"
        case .heavy: return "ArchivoRoman-ExtraBold"
        }
    }
    static func uiName(_ w: VWeight) -> String {
        switch w {
        case .regular: return "IBMPlexSans-Regular"
        case .medium: return "IBMPlexSans-Medium"
        case .semibold: return "IBMPlexSans-SemiBold"
        case .bold, .heavy: return "IBMPlexSans-Bold"
        }
    }
    static func monoName(_ w: VWeight) -> String {
        switch w {
        case .regular: return "IBMPlexMono-Regular"
        case .medium: return "IBMPlexMono-Medium"
        default: return "IBMPlexMono-SemiBold"
        }
    }

    private static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.8: return .caption
        case ..<14: return .footnote
        case ..<15.5: return .subheadline
        case ..<17.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        default: return .title
        }
    }

    static func display(_ size: CGFloat, _ w: VWeight = .bold) -> Font {
        .custom(displayName(w), size: size, relativeTo: style(for: size))
    }
    static func ui(_ size: CGFloat, _ w: VWeight = .regular) -> Font {
        .custom(uiName(w), size: size, relativeTo: style(for: size))
    }
    static func mono(_ size: CGFloat, _ w: VWeight = .regular) -> Font {
        .custom(monoName(w), size: size, relativeTo: style(for: size))
    }

    // UIKit variants (PDF rendering)
    static func uDisplay(_ size: CGFloat, _ w: VWeight = .bold) -> UIFont {
        UIFont(name: displayName(w), size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
    static func uUI(_ size: CGFloat, _ w: VWeight = .regular) -> UIFont {
        UIFont(name: uiName(w), size: size) ?? .systemFont(ofSize: size)
    }
    static func uMono(_ size: CGFloat, _ w: VWeight = .regular) -> UIFont {
        UIFont(name: monoName(w), size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Formatting (forced en_US — the simulator region may be Indian)

enum Fmt {
    static let locale = Locale(identifier: "en_US")

    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    static func price(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f.string(from: d)
    }

    static func parse(_ s: String, _ format: String) -> Date? {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f.date(from: s)
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Icons (SF Symbols mapped to the prototype's line icons)

enum VIcon {
    static func symbol(_ key: String?) -> String {
        switch key ?? "info" {
        case "info": return "info.circle"
        case "tree": return "tree"
        case "wall": return "square.split.2x2"
        case "home": return "house"
        case "deck": return "rectangle.split.3x1"
        case "pool": return "figure.pool.swim"
        case "shed": return "house.lodge"
        case "layers": return "square.3.layers.3d"
        case "box": return "shippingbox"
        case "car": return "car"
        case "sofa": return "sofa"
        case "chef": return "fork.knife"
        case "bed": return "bed.double"
        case "drop", "water": return "drop"
        case "bolt": return "bolt"
        case "wind": return "wind"
        case "flame": return "flame"
        case "list": return "list.bullet"
        case "hall": return "door.left.hand.open"
        case "plug": return "powerplug"
        case "flask": return "flask"
        case "grid": return "square.grid.2x2"
        case "file": return "doc.text"
        default: return "info.circle"
        }
    }
}
