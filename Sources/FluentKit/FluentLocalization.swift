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

    private static func bundleForLocale(_ locale: Locale, in bundle: Bundle) -> Bundle? {
        var candidates = [locale.identifier, locale.identifier.replacingOccurrences(of: "_", with: "-")]
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
        label.setAccessibilityLabel(label.stringValue)
        return label
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let label = view as? NSTextField else { return false }
        label.stringValue = resolved(in: context)
        label.font = context.theme.typography.font(for: textStyle)
        label.textColor = color ?? context.theme.textPrimary
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
