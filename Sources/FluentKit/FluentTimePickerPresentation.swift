import AppKit

/// The same locale-dependent field order and labels are used by the closed surface and flyout.
struct FluentTimePickerPresentation {
    enum Field: String { case hour, minute, period }
    let locale: Locale
    let usesTwelveHour: Bool
    private let pattern: String

    init(clock: FluentClockIdentifier, locale: Locale) {
        self.locale = locale
        let systemPattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
        usesTwelveHour = clock == .twelveHour || (clock == .system && systemPattern.contains("a"))
        pattern = DateFormatter.dateFormat(fromTemplate: usesTwelveHour ? "hm" : "Hm", options: 0, locale: locale) ?? "h:mm a"
    }
    func fields(rightToLeft: Bool) -> [Field] {
        var result: [Field] = []
        var quoted = false
        for character in pattern {
            if character == "'" { quoted.toggle(); continue }
            guard !quoted else { continue }
            let field: Field?
            switch character {
            case "h", "H", "k", "K": field = .hour
            case "m": field = .minute
            case "a", "b", "B": field = usesTwelveHour ? .period : nil
            default: field = nil
            }
            if let field, !result.contains(field) { result.append(field) }
        }
        for field in usesTwelveHour ? [Field.hour, .minute, .period] : [.hour, .minute] {
            if !result.contains(field) { result.append(field) }
        }
        let localeIsRTL: Bool
        if #available(macOS 13, *) { localeIsRTL = Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft }
        else { localeIsRTL = Locale.characterDirection(forLanguage: locale.languageCode ?? "") == .rightToLeft }
        if rightToLeft || localeIsRTL {
            // WinUI swaps hour/minute before applying RTL so the numeric pair still reads H M.
            if let hour = result.firstIndex(of: .hour), let minute = result.firstIndex(of: .minute) { result.swapAt(hour, minute) }
            result.reverse()
        }
        return result
    }
    func number(_ value: Int, digits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumIntegerDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    var periods: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        return [formatter.amSymbol, formatter.pmSymbol]
    }
    func text(for field: Field, time: FluentTime?) -> String {
        guard let time else { return field.rawValue }
        switch field {
        case .hour: return number(usesTwelveHour ? (time.hour % 12 == 0 ? 12 : time.hour % 12) : time.hour)
        case .minute: return number(time.minute, digits: 2)
        case .period: return periods[time.hour < 12 ? 0 : 1]
        }
    }
}
