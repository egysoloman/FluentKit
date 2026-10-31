import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@main struct SettingsResizeAudit {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-ResizeAudit-" + UUID().uuidString)
        let engine = try RimeEngine(sharedDirectory:URL(fileURLWithPath:CommandLine.arguments[2]),userDirectory:userData)
        // Close the process-local engine before librime's global C++ destructors. AppKit may
        // retain the window controller beyond main(), so ARC alone is insufficient for this probe.
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine:engine)
        controller.showWindow(nil)
        let window = controller.window!, root = window.contentView!
        window.makeKeyAndOrderFront(nil)
        func capture(_ name: String) throws {
            root.layoutSubtreeIfNeeded();root.displayIfNeeded();CATransaction.flush()
            print(name,"root",root.bounds,"layered",root.layer != nil)
            for view in root.subviews {
                print(String(describing:type(of:view)),view.frame,view.bounds)
                if let material = view as? FluentMaterialView {
                    for layer in material.layer?.sublayers ?? [] {
                        print(" layer",layer.name ?? "native",layer.frame,"presentation",layer.presentation()?.frame as Any,"animation",layer.animationKeys() as Any)
                    }
                }
            }
            guard let layer = root.layer else { throw NSError(domain:"LayerMissing",code:1) }
            let size = root.bounds.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*2),pixelsHigh:Int(size.height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let cg = NSGraphicsContext(bitmapImageRep:bitmap)!.cgContext;cg.scaleBy(x:2,y:2)
            if root.isFlipped {cg.translateBy(x:0,y:size.height);cg.scaleBy(x:1,y:-1)}
            (layer.presentation() ?? layer).render(in:cg)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        try capture("initial")
        window.performZoom(nil)
        try capture("zoom-00")
        for frame in 1...12 {
            RunLoop.current.run(until:Date().addingTimeInterval(1.0/30))
            try capture(String(format:"zoom-%02d",frame))
        }
        try capture("enlarged-settled")
        window.setContentSize(NSSize(width:640,height:837))
        RunLoop.current.run(until:Date().addingTimeInterval(0.4))
        try capture("restored")
        window.close()
    }
}
