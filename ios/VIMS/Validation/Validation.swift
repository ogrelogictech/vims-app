import Foundation

// One reusable implementation of docs/validation-rules.md (shared with Android).
// `FieldKind.filter` runs while typing; `Validator.error(for:rule:)` runs on submit.

enum FieldKind: Equatable {
    case plain(max: Int?)
    case email
    case password
    case personName
    case companyName
    case phone
    case joinCode
    case address
    case license
    case policy
    case year
    case decimal            // sq ft, valuation, lot size, amps, `num` checklist items
    case temperature
    case url
    case price              // admin plan price / per-inspector rate
    case cardNumber
    case expiry
    case cvc(amex: Bool)
    case zip
    case sectionName
    case question
    case option

    var maxLength: Int? {
        switch self {
        case .plain(let m): return m
        case .email: return 254
        case .personName: return 60
        case .companyName: return 80
        case .address: return 120
        case .license: return 20
        case .policy: return 30
        case .year: return 4
        case .sectionName, .option: return 60
        case .question: return 120
        case .zip: return 5
        default: return nil
        }
    }
}

struct FieldRule {
    var kind: FieldKind
    var required = false
    var label: String
    /// Extra check run after the standard ones (e.g. "must match password", "must be unique").
    var custom: ((String) -> String?)? = nil

    static func req(_ kind: FieldKind, _ label: String, custom: ((String) -> String?)? = nil) -> FieldRule {
        FieldRule(kind: kind, required: true, label: label, custom: custom)
    }
    static func opt(_ kind: FieldKind, _ label: String, custom: ((String) -> String?)? = nil) -> FieldRule {
        FieldRule(kind: kind, required: false, label: label, custom: custom)
    }
}

enum CardBrand: String {
    case visa = "Visa", mastercard = "Mastercard", amex = "Amex", discover = "Discover", unknown = ""

    static func detect(_ digits: String) -> CardBrand {
        if digits.hasPrefix("34") || digits.hasPrefix("37") { return .amex }
        if digits.hasPrefix("4") { return .visa }
        if let two = Int(digits.prefix(2)), (51...55).contains(two) { return .mastercard }
        if let four = Int(digits.prefix(4)), (2221...2720).contains(four) { return .mastercard }
        if digits.hasPrefix("6011") || digits.hasPrefix("65") { return .discover }
        if let three = Int(digits.prefix(3)), (644...649).contains(three) { return .discover }
        return .unknown
    }
}

extension FieldKind {
    /// While-typing filter/formatter. Applied to every keystroke and paste.
    func filter(_ raw: String) -> String {
        var s = Validator.collapseSpaces(raw)
        switch self {
        case .email, .password, .url:
            s = s.filter { !$0.isWhitespace }
        case .personName:
            s = String(s.filter { $0.isLetter || $0 == " " || $0 == "." || $0 == "'" || $0 == "’" || $0 == "-" })
        case .phone:
            s = Validator.formatPhone(s)
        case .joinCode:
            s = Validator.formatJoinCode(s)
        case .license:
            s = String(s.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }).uppercased()
        case .policy:
            s = String(s.filter { $0.isLetter || $0.isNumber || $0 == "-" }).uppercased()
        case .year, .zip:
            s = String(s.filter(\.isNumber))
        case .decimal:
            s = Validator.decimalOnly(s, maxDecimals: nil)
        case .price:
            s = Validator.decimalOnly(s, maxDecimals: 2)
        case .temperature:
            let neg = s.hasPrefix("-")
            s = (neg ? "-" : "") + String(s.filter(\.isNumber))
        case .cardNumber:
            s = Validator.formatCard(s)
        case .expiry:
            s = Validator.formatExpiry(s)
        case .cvc(let amex):
            s = String(s.filter(\.isNumber).prefix(amex ? 4 : 3))
        default:
            break
        }
        if let m = maxLength, s.count > m { s = String(s.prefix(m)) }
        return s
    }
}

enum Validator {
    static let emailRegex = #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#

    /// No leading space; never two spaces in a row (pasted text too).
    static func collapseSpaces(_ s: String) -> String {
        var out = ""
        var lastSpace = true   // treats the start as "after a space" -> strips leading spaces
        for ch in s {
            if ch == " " || ch == "\u{00A0}" || ch == "\t" {
                if !lastSpace { out.append(" ") }
                lastSpace = true
            } else {
                out.append(ch)
                lastSpace = ch == "\n"
            }
        }
        return out
    }

    static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func formatPhone(_ s: String) -> String {
        var d = s.filter(\.isNumber)
        if d.count == 11, d.hasPrefix("1") { d.removeFirst() }
        d = String(d.prefix(10))
        switch d.count {
        case 0: return ""
        case 1...3: return "(\(d)"
        case 4...6: return "(\(d.prefix(3))) \(d.dropFirst(3))"
        default: return "(\(d.prefix(3))) \(d.dropFirst(3).prefix(3))-\(d.dropFirst(6))"
        }
    }

    static func formatJoinCode(_ s: String) -> String {
        let up = s.uppercased().filter { $0.isLetter || $0.isNumber }
        let letters = String(up.prefix { $0.isLetter }.prefix(3))
        let rest = up.dropFirst(letters.count).filter(\.isNumber)
        if letters.count < 3 { return letters }
        let digits = String(rest.prefix(4))
        return digits.isEmpty ? (s.hasSuffix("-") ? letters + "-" : letters) : "\(letters)-\(digits)"
    }

    static func decimalOnly(_ s: String, maxDecimals: Int?) -> String {
        var out = ""
        var seenDot = false
        var decimals = 0
        for ch in s {
            if ch.isNumber {
                if seenDot { if let m = maxDecimals, decimals >= m { continue }; decimals += 1 }
                out.append(ch)
            } else if ch == "." && !seenDot {
                seenDot = true
                out.append(ch)
            }
        }
        return out
    }

    static func formatCard(_ s: String) -> String {
        let d = String(s.filter(\.isNumber).prefix(19))
        if CardBrand.detect(d) == .amex {
            let a = String(d.prefix(15))
            let groups = [a.prefix(4), a.dropFirst(4).prefix(6), a.dropFirst(10)].map(String.init).filter { !$0.isEmpty }
            return groups.joined(separator: " ")
        }
        return stride(from: 0, to: d.count, by: 4).map { i -> String in
            let a = d.index(d.startIndex, offsetBy: i)
            return String(d[a..<d.index(a, offsetBy: min(4, d.count - i))])
        }.joined(separator: " ")
    }

    static func formatExpiry(_ s: String) -> String {
        var d = String(s.filter(\.isNumber).prefix(4))
        if d.count == 1, let f = d.first, f > "1" { d = "0" + d }     // "4" -> "04"
        return d.count > 2 ? "\(d.prefix(2))/\(d.dropFirst(2))" : d
    }

    static func luhn(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count >= 12 else { return false }
        var sum = 0
        for (i, n) in nums.reversed().enumerated() {
            if i % 2 == 1 { let x = n * 2; sum += x > 9 ? x - 9 : x } else { sum += n }
        }
        return sum % 10 == 0
    }

    /// On-submit error for a value, or nil when valid.
    static func error(for raw: String, rule: FieldRule, now: Date = Date()) -> String? {
        let v = trimmed(raw)
        if v.isEmpty {
            return rule.required ? "\(rule.label) is required" : nil
        }
        if let m = rule.kind.maxLength, v.count > m { return "\(rule.label) must be \(m) characters or fewer" }
        let cal = Calendar(identifier: .gregorian)
        switch rule.kind {
        case .email:
            if v.range(of: emailRegex, options: .regularExpression) == nil { return "Enter a valid email address" }
        case .password:
            if v.count < 8 { return "Password must be at least 8 characters" }
        case .personName:
            if !v.contains(where: \.isLetter) { return "Enter a valid name" }
        case .phone:
            if v.filter(\.isNumber).count != 10 { return "Enter a 10-digit phone number" }
        case .joinCode:
            if v.range(of: #"^[A-Z]{3}-\d{4}$"#, options: .regularExpression) == nil { return "Enter the code as 3 letters and 4 digits (VIS-4827)" }
        case .year:
            let y = Int(v) ?? 0
            let current = cal.component(.year, from: now)
            if y < 1800 || y > current { return "Enter a year between 1800 and \(current)" }
        case .decimal:
            guard let d = Double(v), d > 0 else { return "Enter a number greater than 0" }
        case .temperature:
            guard let t = Int(v), (-60...140).contains(t) else { return "Enter a temperature between -60 and 140" }
        case .url:
            let lower = v.lowercased()
            guard lower.hasPrefix("https://") || lower.hasPrefix("http://"),
                  let host = URL(string: v)?.host, host.contains(".") else { return "Enter a full link starting with https://" }
        case .price:
            guard let d = Double(v), d >= 0.01, d <= 9999.99 else { return "Enter a price from $0.01 to $9,999.99" }
        case .cardNumber:
            let digits = v.filter(\.isNumber)
            let amex = CardBrand.detect(digits) == .amex
            if amex ? digits.count != 15 : !(13...19).contains(digits.count) { return "Enter a valid card number" }
            if !luhn(digits) { return "That card number isn't valid" }
        case .expiry:
            let d = v.filter(\.isNumber)
            guard d.count == 4, let mm = Int(d.prefix(2)), let yy = Int(d.suffix(2)), (1...12).contains(mm) else {
                return "Enter the expiry as MM/YY"
            }
            let year = 2000 + yy
            let cy = cal.component(.year, from: now), cm = cal.component(.month, from: now)
            if year < cy || (year == cy && mm < cm) { return "This card has expired" }
            if year > cy + 20 { return "Enter a valid expiry date" }
        case .cvc(let amex):
            if v.filter(\.isNumber).count != (amex ? 4 : 3) { return amex ? "Enter the 4-digit CVC" : "Enter the 3-digit CVC" }
        case .zip:
            if v.count != 5 { return "Enter a 5-digit ZIP code" }
        default:
            break
        }
        return rule.custom?(v)
    }

    /// Validates fields in display order; returns errors keyed by field id.
    static func check(_ fields: [(id: String, value: String, rule: FieldRule)]) -> [String: String] {
        var out: [String: String] = [:]
        for f in fields { if let e = error(for: f.value, rule: f.rule) { out[f.id] = e } }
        return out
    }

    static func firstErrorID(_ fields: [(id: String, value: String, rule: FieldRule)], _ errors: [String: String]) -> String? {
        fields.first { errors[$0.id] != nil }?.id
    }
}

/// Holds a form's inline errors; fields re-validate themselves once they have an error.
@Observable
final class FormErrors {
    var map: [String: String] = [:]
    var scrollTarget: String?
    @ObservationIgnored var rules: [String: FieldRule] = [:]

    subscript(_ id: String) -> String? { map[id] }

    /// Runs the given checks; shows every error and asks the screen to scroll to the first one.
    @discardableResult
    func validate(_ fields: [(id: String, value: String, rule: FieldRule)]) -> Bool {
        for f in fields { rules[f.id] = f.rule }
        let errs = Validator.check(fields)
        map = errs
        if let first = Validator.firstErrorID(fields, errs) { scrollTarget = first }
        return errs.isEmpty
    }

    /// Called while typing: clears (or updates) the error once the value is valid.
    func revalidate(_ id: String, _ value: String) {
        guard map[id] != nil, let rule = rules[id] else { return }
        map[id] = Validator.error(for: value, rule: rule)
    }

    func set(_ id: String, _ message: String?) {
        map[id] = message
        if message != nil { scrollTarget = id }
    }

    func clear() { map = [:] }
}
