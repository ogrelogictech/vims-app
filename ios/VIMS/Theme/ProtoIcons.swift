import SwiftUI
import UIKit

// The approved prototype's own line icons (shared/icons/icons.json — 24×24 stroke paths,
// stroke-width 2, round caps/joins, tinted with the current color), rendered natively.

enum ProtoIconSet {
    /// name -> SVG path data list
    static let paths: [String: [String]] = {
        var out: [String: [String]] = [:]
        if let url = Bundle.main.url(forResource: "icons", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let icons = root["icons"] as? [String: Any] {
            for (k, v) in icons {
                if let d = v as? [String: Any], let p = d["paths"] as? [String] { out[k] = p }
            }
        }
        // Inline SVGs the prototype builds in JS (wrapSvg(...) in index.html) that are not in icons.json.
        for (k, v) in extras where out[k] == nil { out[k] = v }
        return out
    }()

    /// From index.html (renderOverview / renderAdmin / renderInspectors / counters) — same stroke style.
    static let extras: [String: [String]] = [
        "chevron-right": ["m9 18 6-6-6-6"],
        "chevron-down": ["m6 9 6 6 6-6"],
        "chevron-up": ["m18 15-6-6-6 6"],
        "trash": ["M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"],
        "copy": ["M11 9h11v13H11z", "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"],
        "minus": ["M5 12h14"],
        // Not in the prototype (it used native date/select inputs); drawn in the same style.
        "calendar": ["M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z", "M16 2v4M8 2v4M3 10h18"],
        "select": ["m7 15 5 5 5-5M7 9l5-5 5 5"]
    ]

    private static var cache: [String: CGPath] = [:]

    /// Combined CGPath in the 24×24 space.
    static func cgPath(_ name: String) -> CGPath {
        if let c = cache[name] { return c }
        let p = CGMutablePath()
        for d in paths[name] ?? paths["info"] ?? [] { SVGPathParser.append(d, to: p) }
        cache[name] = p
        return p
    }
}

/// A prototype icon, e.g. `ProtoIcon("hdr-back", size: 20)`.
struct ProtoIcon: View {
    let name: String
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2    // in the 24-unit design space (scales with size, like the SVG)

    init(_ name: String, size: CGFloat = 20, lineWidth: CGFloat = 2) {
        self.name = name
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ProtoIconShape(name: name)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ProtoIconShape: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var t = CGAffineTransform(translationX: rect.minX + (rect.width - 24 * s) / 2, y: rect.minY + (rect.height - 24 * s) / 2).scaledBy(x: s, y: s)
        guard let p = ProtoIconSet.cgPath(name).copy(using: &t) else { return Path() }
        return Path(p)
    }
}

extension ProtoIcon {
    /// UIKit image (PDF report, UIKit contexts).
    static func uiImage(_ name: String, size: CGFloat, color: UIColor) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 4
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: size / 24, y: size / 24)
            cg.addPath(ProtoIconSet.cgPath(name))
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
    }
}

/// Label with a prototype icon (buttons use VLabelStyle: 19 pt icon + title).
struct IconLabel: View {
    let title: String
    let icon: String
    var iconSize: CGFloat = 19
    init(_ title: String, icon: String, iconSize: CGFloat = 19) {
        self.title = title
        self.icon = icon
        self.iconSize = iconSize
    }
    var body: some View {
        Label { Text(title) } icon: { ProtoIcon(icon, size: iconSize) }
    }
}

// MARK: - SVG path data -> CGPath (M L H V C S Q T A Z, absolute + relative)

enum SVGPathParser {
    static func append(_ d: String, to path: CGMutablePath) {
        var tokens = Tokenizer(d)
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint? = nil      // for S / T reflection
        var lastCmd: Character = " "

        while let next = tokens.nextCommandOrNumber() {
            if case .command(let c) = next { cmd = c; if c == "Z" || c == "z" {
                path.closeSubpath(); cur = start; lastCtrl = nil; lastCmd = c; continue
            } } else { tokens.pushBack(next) }

            let rel = cmd.isLowercase
            func pt() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
            }
            switch cmd {
            case "M", "m":
                guard let p = pt() else { return }
                path.move(to: p); cur = p; start = p; lastCtrl = nil
                cmd = rel ? "l" : "L"   // subsequent pairs are lineto
            case "L", "l":
                guard let p = pt() else { return }
                path.addLine(to: p); cur = p; lastCtrl = nil
            case "H", "h":
                guard let x = tokens.number() else { return }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); path.addLine(to: cur); lastCtrl = nil
            case "V", "v":
                guard let y = tokens.number() else { return }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); path.addLine(to: cur); lastCtrl = nil
            case "C", "c":
                guard let c1 = pt(), let c2 = pt(), let p = pt() else { return }
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastCtrl = c2
            case "S", "s":
                guard let c2 = pt(), let p = pt() else { return }
                let c1 = (lastCtrl != nil && "CcSs".contains(lastCmd)) ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastCtrl = c2
            case "Q", "q":
                guard let c = pt(), let p = pt() else { return }
                path.addQuadCurve(to: p, control: c); cur = p; lastCtrl = c
            case "T", "t":
                guard let p = pt() else { return }
                let c = (lastCtrl != nil && "QqTt".contains(lastCmd)) ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                path.addQuadCurve(to: p, control: c); cur = p; lastCtrl = c
            case "A", "a":
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(), let p = pt() else { return }
                arc(path, from: cur, to: p, rx: rx, ry: ry, angle: rot, large: large, sweep: sweep)
                cur = p; lastCtrl = nil
            default:
                return
            }
            lastCmd = cmd
        }
    }

    /// SVG elliptical arc (endpoint parameterization) -> cubic Béziers.
    private static func arc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                            angle: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = angle * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }
        let segs = Int(ceil(abs(dTheta) / (.pi / 2)))
        let delta = dTheta / CGFloat(segs)
        let t = 4 / 3 * tan(delta / 4)
        var th = theta1
        for _ in 0..<segs {
            let c1 = cos(th), s1 = sin(th), c2 = cos(th + delta), s2 = sin(th + delta)
            let e1 = CGPoint(x: c1 - t * s1, y: s1 + t * c1)
            let e2 = CGPoint(x: c2 + t * s2, y: s2 - t * c2)
            let e3 = CGPoint(x: c2, y: s2)
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: cx + rx * p.x * cosP - ry * p.y * sinP, y: cy + rx * p.x * sinP + ry * p.y * cosP)
            }
            path.addCurve(to: map(e3), control1: map(e1), control2: map(e2))
            th += delta
        }
    }

    enum Token { case command(Character), number(CGFloat) }

    struct Tokenizer {
        let chars: [Character]
        var i = 0
        var pushed: Token?
        init(_ s: String) { chars = Array(s) }

        mutating func pushBack(_ t: Token) { pushed = t }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        mutating func nextCommandOrNumber() -> Token? {
            if let p = pushed { pushed = nil; return p }
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter && c != "e" && c != "E" { i += 1; return .command(c) }
            if let n = number() { return .number(n) }
            return nil
        }

        mutating func number() -> CGFloat? {
            if let p = pushed, case .number(let n) = p { pushed = nil; return n }
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            var seenDot = false, seenExp = false
            if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." && !seenDot && !seenExp { seenDot = true; s.append(c); i += 1 }
                else if (c == "e" || c == "E") && !seenExp { seenExp = true; s.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 } }
                else { break }
            }
            guard let v = Double(s) else { return nil }
            return CGFloat(v)
        }

        /// Arc flags may be written without separators ("0 1 0" or "010").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            guard c == "0" || c == "1" else { return nil }
            i += 1
            return c == "1"
        }
    }
}
