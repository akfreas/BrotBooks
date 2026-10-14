// Renders the app icon masters with Core Graphics.
// Usage: swiftc -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon <output dir>
// Writes icon-ios.png (full bleed; iOS applies the mask) and icon-mac.png (inset rounded tile with shadow).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(mac: Bool) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var tile = CGRect(x: 0, y: 0, width: size, height: size)
    if mac {
        // macOS icon grid: 824pt tile centered in 1024 with a soft drop shadow.
        tile = tile.insetBy(dx: 100, dy: 100)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.3))
        ctx.addPath(shape)
        ctx.setFillColor(rgb(0x4655D8))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(shape)
        ctx.clip()
    }
    let gradient = CGGradient(colorsSpace: cs, colors: [rgb(0x6B7CF6), rgb(0x3D49C9)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY),
                           options: [])

    // White sheet.
    let s = tile.width / 1024
    let sheet = CGRect(x: tile.minX + 232 * s, y: tile.minY + 196 * s, width: 560 * s, height: 632 * s)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: rgb(0x1A1F66, 0.35))
    ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 56 * s, cornerHeight: 56 * s, transform: nil))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Ledger lines.
    ctx.setFillColor(rgb(0xD9DDF9))
    for (i, w) in [300.0, 220.0].enumerated() {
        let r = CGRect(x: sheet.minX + 64 * s, y: sheet.maxY - (110 + Double(i) * 62) * s, width: w * s, height: 26 * s)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 13 * s, cornerHeight: 13 * s, transform: nil))
        ctx.fillPath()
    }

    // Rising area chart in the accent color, ending in a green dot.
    let pts: [(Double, Double)] = [(0, 0.10), (0.25, 0.32), (0.5, 0.28), (0.75, 0.62), (1, 0.85)]
    let chart = CGRect(x: sheet.minX + 64 * s, y: sheet.minY + 70 * s, width: sheet.width - 128 * s, height: 300 * s)
    func p(_ t: (Double, Double)) -> CGPoint { CGPoint(x: chart.minX + t.0 * chart.width, y: chart.minY + t.1 * chart.height) }
    let line = CGMutablePath()
    line.move(to: p(pts[0]))
    for i in 1..<pts.count {
        let a = p(pts[i - 1]), b = p(pts[i])
        let mid = (b.x - a.x) / 2
        line.addCurve(to: b, control1: CGPoint(x: a.x + mid, y: a.y), control2: CGPoint(x: b.x - mid, y: b.y))
    }
    let area = line.mutableCopy()!
    area.addLine(to: CGPoint(x: chart.maxX, y: chart.minY))
    area.addLine(to: CGPoint(x: chart.minX, y: chart.minY))
    area.closeSubpath()
    ctx.saveGState()
    ctx.addPath(area)
    ctx.clip()
    let fill = CGGradient(colorsSpace: cs, colors: [rgb(0x5266EB, 0.35), rgb(0x5266EB, 0.04)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: chart.maxY), end: CGPoint(x: 0, y: chart.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(line)
    ctx.setStrokeColor(rgb(0x5266EB))
    ctx.setLineWidth(26 * s)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.setFillColor(rgb(0x188A50))
    let end = p(pts.last!)
    ctx.fillEllipse(in: CGRect(x: end.x - 30 * s, y: end.y - 30 * s, width: 60 * s, height: 60 * s))

    let image = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

try render(mac: false).write(to: out.appendingPathComponent("icon-ios.png"))
try render(mac: true).write(to: out.appendingPathComponent("icon-mac.png"))
