import AppKit
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
let views: [NSView] = [NSButton(title: "Button", target: nil, action: nil), NSTextField(labelWithString: "Label"), NSTextField(string: "Editable")]
let window = NSWindow(contentRect: NSRect(x: 30, y: 200, width: 300, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
for (i,v) in views.enumerated() {
 func show(_ phase: String) { print(phase, type(of:v), "element",v.isAccessibilityElement(), "role",v.accessibilityRole()?.rawValue ?? "nil", "label",v.accessibilityLabel() ?? "nil", "title",v.accessibilityTitle() ?? "nil", "value",v.accessibilityValue() ?? "nil") }
 show("before")
 v.frame = NSRect(x: 10, y: i * 45, width: 200, height: 32); window.contentView!.addSubview(v)
 window.makeKeyAndOrderFront(nil); show("attached")
}
window.close()
