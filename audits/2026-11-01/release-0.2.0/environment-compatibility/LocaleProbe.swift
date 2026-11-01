import Foundation
import FluentKit
let b = Bundle(path: "/tmp/fluentkit-native-quality/arm64-apple-macosx/release/FluentKit_FluentKit.bundle")!
print("localizations", b.localizations)
for locale in ["zh_CN", "zh_TW"] { print(locale, FluentLocalization.controlString("Copy", locale: Locale(identifier:locale))) }
for name in ["zh-Hans", "zh-hans", "zh-Hant", "zh-hant"] { print(name, b.path(forResource:name, ofType:"lproj") ?? "nil") }
