import SwiftUI
import AppKit

/// Where the PNGs land; passed in by render-snapshots.sh.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

@MainActor
func render(_ name: String, _ model: UsageViewModel, expand: Bool = false) {
    let renderer = ImageRenderer(content: PopoverContent(manager: model, showCredentials: .constant(expand), now: Date()).background(Color(nsColor: .windowBackgroundColor)))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("FAILED \(name)"); return
    }
    let url = outputDirectory.appendingPathComponent("\(name).png")
    try? png.write(to: url)
    print("wrote \(name).png  \(Int(image.size.width))x\(Int(image.size.height))")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

MainActor.assumeIsolated {
    render("01-loaded-all", .preview(.loaded(.richSample, fetchedAt: Date().addingTimeInterval(-120)),
                                     nextRefreshAt: Date().addingTimeInterval(60)))
    render("02-loaded-sparse", .preview(.loaded(.sparseSample, fetchedAt: Date().addingTimeInterval(-30))))
    render("03-empty", .preview(.loaded(.emptySample, fetchedAt: Date())))
    render("04-needs-setup", .preview(.needsSetup, sessionKey: "", orgId: ""), expand: true)
    render("05-session-expired", .preview(.failed(.sessionExpired)))
    render("06-cloudflare", .preview(.failed(.cloudflareChallenge)))
    render("07-offline", .preview(.failed(.offline)))
}
