// Génère les icônes PWA à partir de l'emoji 🍲 (macOS uniquement, une fois).
//   swift scripts/icons.swift public
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "public"
let cream = NSColor(red: 0xfb/255, green: 0xf5/255, blue: 0xec/255, alpha: 1)

func render(_ size: Int, scale: CGFloat, background: NSColor?, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    if let bg = background { bg.setFill(); rect.fill() }
    let font = NSFont(name: "Apple Color Emoji", size: CGFloat(size) * scale)!
    let text = NSAttributedString(string: "🍲", attributes: [.font: font])
    let b = text.size()
    text.draw(at: NSPoint(x: (CGFloat(size) - b.width) / 2, y: (CGFloat(size) - b.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

render(192, scale: 0.78, background: nil, name: "pwa-192.png")
render(512, scale: 0.78, background: nil, name: "pwa-512.png")
// Android découpe les icônes « maskable » en cercle : marge de sécurité de 20 %.
render(512, scale: 0.55, background: cream, name: "pwa-maskable-512.png")
// iOS ne gère pas la transparence sur l'écran d'accueil.
render(180, scale: 0.68, background: cream, name: "apple-touch-icon.png")
