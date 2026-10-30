import AppKit
import ObjectiveC

/// A semantic layout direction propagated through the Fluent render environment.
public enum FluentLayoutDirection: Hashable, Sendable {
    case system
    case leftToRight
    case rightToLeft

    var appKitValue: NSUserInterfaceLayoutDirection {
        switch self {
        case .system: return NSApplication.shared.userInterfaceLayoutDirection
        case .leftToRight: return .leftToRight
        case .rightToLeft: return .rightToLeft
        }
    }
}

/// A localizable string resource resolved from the current Fluent locale and bundle.
public struct FluentLocalizedStringResource: Hashable, Sendable, ExpressibleByStringLiteral {
    public let key: String
    public let defaultValue: String?
    public let tableName: String?

    public init(
        _ key: String,
        defaultValue: String? = nil,
        tableName: String? = nil
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.tableName = tableName
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public enum FluentLocalization {
    public static func localizedString(
        _ resource: FluentLocalizedStringResource,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        let localizedBundle = bundleForLocale(locale, in: bundle) ?? bundle
        return localizedBundle.localizedString(
            forKey: resource.key,
            value: resource.defaultValue,
            table: resource.tableName
        )
    }

    /// Framework defaults first consult the application bundle, then bundled translations.
    public static func controlString(_ english: String, bundle: Bundle = .main, locale: Locale = .current) -> String {
        let key = "FluentKit." + english
        let application = localizedString(.init(key, defaultValue: key, tableName: "FluentKit"), bundle: bundle, locale: locale)
        if application != key { return application }
        return localizedString(.init(key, defaultValue: english, tableName: "FluentKit"), bundle: .module, locale: locale)
    }

    private static func bundleForLocale(_ locale: Locale, in bundle: Bundle) -> Bundle? {
        var candidates = [locale.identifier, locale.identifier.replacingOccurrences(of: "_", with: "-")]
        if locale.languageCode == "zh" {
            candidates.append(locale.scriptCode == "Hant" || ["TW", "HK", "MO"].contains(locale.regionCode ?? "") ? "zh-Hant" : "zh-Hans")
        }
        if let languageCode = locale.languageCode { candidates.append(languageCode) }
        for candidate in candidates where !candidate.isEmpty {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return nil
    }
}

/// A semantic text view that resolves its value from the inherited localization environment.
public struct FluentLocalizedTextView: FluentUpdatablePrimitiveView {
    public let resource: FluentLocalizedStringResource
    public let textStyle: FluentTextStyle
    public let color: NSColor?

    public init(
        _ resource: FluentLocalizedStringResource,
        style: FluentTextStyle = .body,
        color: NSColor? = nil
    ) {
        self.resource = resource
        textStyle = style
        self.color = color
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let label = NSTextField(labelWithString: resolved(in: context))
        label.font = context.theme.typography.font(for: textStyle)
        label.textColor = color ?? context.theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        fluentApplySemanticText(label, text: resolved(in: context), style: textStyle, color: color ?? context.theme.textPrimary, typography: context.theme.typography)
        label.setAccessibilityLabel(label.stringValue)
        return label
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let label = view as? NSTextField else { return false }
        label.stringValue = resolved(in: context)
        label.font = context.theme.typography.font(for: textStyle)
        label.textColor = color ?? context.theme.textPrimary
        fluentApplySemanticText(label, text: resolved(in: context), style: textStyle, color: color ?? context.theme.textPrimary, typography: context.theme.typography)
        label.setAccessibilityLabel(label.stringValue)
        return true
    }

    private func resolved(in context: FluentRenderContext) -> String {
        FluentLocalization.localizedString(
            resource,
            bundle: context.localizationBundle,
            locale: context.locale
        )
    }
}

public func FluentLocalizedText(
    _ key: String,
    defaultValue: String? = nil,
    tableName: String? = nil,
    style: FluentTextStyle = .body,
    color: NSColor? = nil
) -> FluentLocalizedTextView {
    FluentLocalizedTextView(
        FluentLocalizedStringResource(key, defaultValue: defaultValue, tableName: tableName),
        style: style,
        color: color
    )
}

private var fluentLayoutDirectionOverrideKey: UInt8 = 0

extension NSView {
    func fluentApplyLayoutDirection(_ direction: FluentLayoutDirection, establishesOverride: Bool = false) {
        if !establishesOverride,
           objc_getAssociatedObject(self, &fluentLayoutDirectionOverrideKey) != nil {
            return
        }
        userInterfaceLayoutDirection = direction.appKitValue
        if establishesOverride {
            objc_setAssociatedObject(
                self,
                &fluentLayoutDirectionOverrideKey,
                NSNumber(value: direction.appKitValue.rawValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        subviews.forEach { $0.fluentApplyLayoutDirection(direction) }
    }
}

private var fluentLocalizationEnvironmentKey: UInt8 = 0
private final class FluentLocalizationEnvironment {
    let locale: Locale
    let bundle: Bundle
    init(locale: Locale, bundle: Bundle) { self.locale = locale; self.bundle = bundle }
}

public extension NSView {
    /// Overrides framework defaults for a native subtree. Declarative hosts set this from context.
    func fluentSetLocalization(locale: Locale, bundle: Bundle = .main) {
        objc_setAssociatedObject(self, &fluentLocalizationEnvironmentKey,
                                 FluentLocalizationEnvironment(locale: locale, bundle: bundle), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func fluentControlString(_ english: String) -> String {
        var ancestor: NSView? = self
        while let view = ancestor {
            if let environment = objc_getAssociatedObject(view, &fluentLocalizationEnvironmentKey) as? FluentLocalizationEnvironment {
                return FluentLocalization.controlString(english, bundle: environment.bundle, locale: environment.locale)
            }
            ancestor = view.superview
        }
        return FluentLocalization.controlString(english)
    }
}

func fluentApplySemanticText(_ label: NSTextField, text: String, style: FluentTextStyle, color: NSColor, typography: FluentTypography) {
    guard typography.metrics(for: style).lineHeight != nil else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = typography.lineHeight(for: style)
    paragraph.maximumLineHeight = typography.lineHeight(for: style)
    paragraph.lineBreakMode = label.lineBreakMode
    let value = NSAttributedString(string: text, attributes: [.font: typography.font(for: style), .foregroundColor: color, .paragraphStyle: paragraph])
    if !label.attributedStringValue.isEqual(to: value) { label.attributedStringValue = value }
}

private var fluentDefaultStringsKey: UInt8 = 0
private final class FluentDefaultStrings {
    var values: [String: (english: String, resolved: String)] = [:]
}

extension NSView {
    func fluentSetDefaultAccessibilityLabel(_ text: String) { fluentSetDefaultString(text, attribute: "label") }
    func fluentSetDefaultAccessibilityTitle(_ text: String) { fluentSetDefaultString(text, attribute: "title") }
    func fluentSetDefaultAccessibilityHelp(_ text: String) { fluentSetDefaultString(text, attribute: "help") }
    func fluentSetDefaultAccessibilityValue(_ text: String) { fluentSetDefaultString(text, attribute: "value") }
    func fluentSetDefaultToolTip(_ text: String) { fluentSetDefaultString(text, attribute: "toolTip") }

    private func fluentSetDefaultString(_ text: String, attribute: String) {
        let strings = objc_getAssociatedObject(self, &fluentDefaultStringsKey) as? FluentDefaultStrings ?? FluentDefaultStrings()
        let resolved = fluentControlString(text)
        strings.values[attribute] = (text, resolved)
        objc_setAssociatedObject(self, &fluentDefaultStringsKey, strings, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        fluentWriteDefaultString(resolved, attribute: attribute)
    }

    private func fluentReadDefaultString(attribute: String) -> String? {
        switch attribute {
        case "label": return accessibilityLabel()
        case "title": return accessibilityTitle()
        case "help": return accessibilityHelp()
        case "value": return accessibilityValue() as? String
        default: return toolTip
        }
    }

    private func fluentWriteDefaultString(_ value: String, attribute: String) {
        guard fluentReadDefaultString(attribute: attribute) != value else { return }
        switch attribute {
        case "label": setAccessibilityLabel(value)
        case "title": setAccessibilityTitle(value)
        case "help": setAccessibilityHelp(value)
        case "value": setAccessibilityValue(value)
        default: toolTip = value
        }
    }

    func fluentRefreshDefaultLocalization() {
        if let strings = objc_getAssociatedObject(self, &fluentDefaultStringsKey) as? FluentDefaultStrings {
            for (attribute, entry) in strings.values {
                // Application-authored accessibility text takes precedence over a framework default.
                guard fluentReadDefaultString(attribute: attribute) == entry.resolved else {
                    strings.values.removeValue(forKey: attribute)
                    continue
                }
                let resolved = fluentControlString(entry.english)
                fluentWriteDefaultString(resolved, attribute: attribute)
                strings.values[attribute] = (entry.english, resolved)
            }
        }
        subviews.forEach { $0.fluentRefreshDefaultLocalization() }
    }
}
