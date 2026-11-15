// Draws Resources/AppIcon.icns: flat deep-blue macOS rounded square with a white mono "g".
// Run: scripts/make-icon.sh
import AppKit

let blue = NSColor(srgbRed: 0x1A / 255, green: 0x3F / 255, blue: 0xD1 / 255, alpha: 1)
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // Apple grid: 824×824 body centred on 1024, radius ≈ 185.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    blue.setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s).fill()

    let font = NSFont.monospacedSystemFont(ofSize: 560 * s, weight: .bold)
    let glyph = NSAttributedString(string: "g", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(glyph)
    let ink = CTLineGetImageBounds(line, nil)  // tight bounds of the drawn glyph
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: body.midX - ink.midX, y: body.midY - ink.midY)
    CTLineDraw(line, ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
