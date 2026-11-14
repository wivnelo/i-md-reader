// Renders the Mac DMG window background (660×400 pt) at 1x and 2x.
// Usage: swift design/dmg/render-background.swift "$TMPDIR" &&
//   tiffutil -cathidpicheck "$TMPDIR/background.png" "$TMPDIR/background@2x.png" -out design/dmg/background.tiff
// preview.jpg is a Finder capture of the finished window.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = NSSize(width: 660, height: 400)
// Icon centres used by scripts/build-mac-dmg.sh (Finder coordinates, origin top-left).
let appCenter = NSPoint(x: 180, y: 205)
let appsCenter = NSPoint(x: 480, y: 205)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let flip = { (p: NSPoint) in NSPoint(x: p.x, y: size.height - p.y) }

    // Soft vertical gradient.
    NSGradient(starting: NSColor(srgbRed: 0.988, green: 0.988, blue: 0.992, alpha: 1),
               ending: NSColor(srgbRed: 0.937, green: 0.945, blue: 0.957, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Title and subtitle.
    let center = NSMutableParagraphStyle(); center.alignment = .center
    func text(_ s: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: center]
        let h = (s as NSString).size(withAttributes: attrs).height
        (s as NSString).draw(in: NSRect(x: 0, y: size.height - y - h, width: size.width, height: h), withAttributes: attrs)
    }
    text("iMDReader", y: 40, font: .systemFont(ofSize: 26, weight: .bold), color: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1))
    text("为阅读，留一点空间。  Make room for reading.", y: 76, font: .systemFont(ofSize: 13, weight: .medium),
         color: NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1))

    // Arrow between the two icons.
    let blue = NSColor(srgbRed: 0, green: 0.443, blue: 0.890, alpha: 1)
    let start = flip(NSPoint(x: appCenter.x + 92, y: appCenter.y)), end = flip(NSPoint(x: appsCenter.x - 92, y: appsCenter.y))
    let shaft = NSBezierPath()
    shaft.move(to: start); shaft.line(to: NSPoint(x: end.x - 14, y: end.y))
    shaft.lineWidth = 4; shaft.lineCapStyle = .round
    let dash: [CGFloat] = [0.1, 11]; shaft.setLineDash(dash, count: 2, phase: 0)
    blue.withAlphaComponent(0.85).setStroke(); shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x, y: end.y))
    head.line(to: NSPoint(x: end.x - 18, y: end.y + 11))
    head.line(to: NSPoint(x: end.x - 18, y: end.y - 11))
    head.close(); blue.setFill(); head.fill()

    // Instruction under the icons (labels sit at about y = 280).
    text("将 iMDReader 拖到“应用程序”即可安装", y: 318, font: .systemFont(ofSize: 15, weight: .semibold),
         color: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1))
    text("Drag iMDReader to Applications to install", y: 342, font: .systemFont(ofSize: 12, weight: .regular),
         color: NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: "\(outDir)/background@2x.png"))
print("wrote background.png and background@2x.png to \(outDir)")
