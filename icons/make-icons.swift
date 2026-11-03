// Draws both apps' icons from one source: the Remote's AppIcon.icns and Home's TV banner.
// Run from the repo root with `swift icons/make-icons.swift`, then commit what it writes. Design notes and the
// board the drawing came from: launcher/design/icon-level.html.
//
// Level: black level is the line a picture sits on. Below it, nothing; above it, everything. The line sits on the
// golden section, below it is darker than the field above, and small sizes are redrawn with a thicker line and a
// stronger glow rather than shrunk.
import AppKit
import CoreText

// Home's palette (launcher/app/assets/index.html), converted from oklch to sRGB
let field = rgb(0.0153, 0.0101, 0.0068)  // oklch(9.5% .007 60)
let below = rgb(0.0016, 0.0011, 0.0008)  // oklch(4.5% .003 60)
let amber = rgb(0.9074, 0.5827, 0.3179)  // oklch(74% .13 58)
let hot = rgb(0.9916, 0.8093, 0.5851)    // oklch(88% .09 72)
let ink = rgb(0.9313, 0.8908, 0.8252)    // oklch(92% .025 80)
let golden: CGFloat = 61.8

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func with(_ c: CGColor, alpha: CGFloat) -> CGColor { c.copy(alpha: alpha)! }
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

/// A canvas `w`×`h` pixels with y pointing down, like the SVG it was designed in.
func canvas(_ w: Int, _ h: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return rep
}

/// The level: field and glow above `y`, the line, and the darker nothing below, across `width`.
func level(_ ctx: CGContext, width: CGFloat, height: CGFloat, y: CGFloat, line t: CGFloat,
           glow: CGFloat, core: CGFloat, coreRadius: CGFloat, coreSquash: CGFloat) {
    let top = y - t / 2
    ctx.setFillColor(field)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: top))
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: width, height: top))
    ctx.drawLinearGradient(gradient([(0, with(amber, alpha: glow)), (0.5, with(amber, alpha: glow * 0.18)),
                                     (1, with(amber, alpha: 0))]),
                           start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: 0), options: [])
    if core > 0 {
        ctx.translateBy(x: width / 2, y: y)
        ctx.scaleBy(x: 1, y: coreSquash)
        ctx.drawRadialGradient(gradient([(0, with(hot, alpha: core)), (1, with(hot, alpha: 0))]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: coreRadius, options: [])
    }
    ctx.restoreGState()
    ctx.setFillColor(below)
    ctx.fill(CGRect(x: 0, y: top, width: width, height: height - top))
    // a little of the light spills just under the line
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: top + t, width: width, height: t + 0.03 * height))
    ctx.drawLinearGradient(gradient([(0, with(amber, alpha: 0.14)), (1, with(amber, alpha: 0))]),
                           start: CGPoint(x: 0, y: top + t), end: CGPoint(x: 0, y: top + t + 0.03 * height), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: top, width: width, height: t))
    ctx.drawLinearGradient(gradient([(0, with(amber, alpha: 0.6)), (0.5, hot), (1, with(amber, alpha: 0.6))]),
                           start: .zero, end: CGPoint(x: width, y: 0), options: [])
    ctx.restoreGState()
}

// MARK: - Remote: macOS app icon

/// Apple's icon grid: an 824 body centred on a 1024 canvas, with a continuous-corner rounded square.
func squircle(in r: CGRect) -> CGPath {
    let p = CGMutablePath(), s = r.width / 100
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
    p.move(to: pt(22.5, 0)); p.addLine(to: pt(77.5, 0))
    p.addCurve(to: pt(100, 22.5), control1: pt(90, 0), control2: pt(100, 10)); p.addLine(to: pt(100, 77.5))
    p.addCurve(to: pt(77.5, 100), control1: pt(100, 90), control2: pt(90, 100)); p.addLine(to: pt(22.5, 100))
    p.addCurve(to: pt(0, 77.5), control1: pt(10, 100), control2: pt(0, 90)); p.addLine(to: pt(0, 22.5))
    p.addCurve(to: pt(22.5, 0), control1: pt(0, 10), control2: pt(10, 0))
    p.closeSubpath()
    return p
}

func appIcon(_ px: Int) -> NSBitmapImageRep {
    canvas(px, px) { ctx in
        let size = CGFloat(px), body = size * 824 / 1024, inset = (size - body) / 2
        let rect = CGRect(x: inset, y: inset, width: body, height: body)
        let u = body / 100 // one unit of the 100 grid the icon was designed on
        // optical sizes, by the pixels the body actually gets
        let (t, glow, core): (CGFloat, CGFloat, CGFloat) =
            body >= 100 ? (2.2, 0.34, 0.26) : body >= 50 ? (2.8, 0.36, 0.28) : body >= 26 ? (4.2, 0.42, 0.3) : (6.4, 0.5, 0)
        let shape = squircle(in: rect)
        if px >= 64 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: rgb(0, 0, 0, 0.35))
            ctx.addPath(shape); ctx.setFillColor(below); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.translateBy(x: inset, y: inset)
        level(ctx, width: body, height: body, y: golden * u, line: max(t * u, 1), glow: glow, core: core,
              coreRadius: 46 * u, coreSquash: 0.42)
        ctx.restoreGState()
        if px >= 64 {
            ctx.saveGState()
            ctx.addPath(shape); ctx.clip()
            ctx.addPath(shape); ctx.setStrokeColor(rgb(1, 1, 1, 0.07)); ctx.setLineWidth(1.2 * u); ctx.strokePath()
            ctx.restoreGState()
        }
    }
}

// MARK: - Home: Android TV banner

func banner(scale: CGFloat) -> NSBitmapImageRep {
    canvas(Int(320 * scale), Int(180 * scale)) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        let l: CGFloat = 111
        level(ctx, width: 320, height: 180, y: l, line: 2.6, glow: 0.3, core: 0.22, coreRadius: 150, coreSquash: 0.35)
        let fonts = CTFontManagerCreateFontDescriptorsFromURL(
            URL(fileURLWithPath: "launcher/app/assets/fonts/InstrumentSerif-Regular.ttf") as CFURL) as! [CTFontDescriptor]
        let font = CTFontCreateWithFontDescriptor(fonts[0], 54, nil)
        let text = NSAttributedString(string: "Blacklevel", attributes: [
            .init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): ink,
            .init(kCTKernAttributeName as String): -0.3])
        let ctLine = CTLineCreateWithAttributedString(text)
        let w = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        // the word stands on the line
        ctx.saveGState()
        ctx.translateBy(x: (320 - w) / 2, y: l - 12)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
    }
}

func png(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    png(appIcon(pt), "\(iconset)/icon_\(pt)x\(pt).png")
    png(appIcon(pt * 2), "\(iconset)/icon_\(pt)x\(pt)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "menubar/Resources/AppIcon.icns"]
try! iconutil.run(); iconutil.waitUntilExit()
print("Wrote menubar/Resources/AppIcon.icns")

try! fm.createDirectory(atPath: "launcher/app/res/drawable-xhdpi", withIntermediateDirectories: true)
png(banner(scale: 2), "launcher/app/res/drawable-xhdpi/banner.png")
print("Wrote launcher/app/res/drawable-xhdpi/banner.png")
