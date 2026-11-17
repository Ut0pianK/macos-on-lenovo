
import AppKit
let a = CommandLine.arguments
guard a.count == 5 else { print("usage: mkicon symbol top bottom out.png"); exit(1) }
func col(_ h: String) -> NSColor { let v = UInt32(h, radix: 16) ?? 0; return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1) }
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

let sh = NSShadow(); sh.shadowOffset = NSSize(width: 0, height: -14); sh.shadowBlurRadius = 36; sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
NSGraphicsContext.saveGraphicsState(); sh.set(); col(a[3]).setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()

NSGradient(starting: col(a[2]), ending: col(a[3]))!.draw(in: shape, angle: -90)
NSGraphicsContext.saveGraphicsState(); shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!.draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.22).setStroke(); let edge = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183); edge.lineWidth = 6; edge.stroke()

let cfg = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let sym = NSImage(systemSymbolName: a[1], accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { print("기호 없음: \(a[1])"); exit(2) }
let maxSide: CGFloat = 500; let sc = min(maxSide / sym.size.width, maxSide / sym.size.height)
let w = sym.size.width * sc, h = sym.size.height * sc
let gs = NSShadow(); gs.shadowOffset = NSSize(width: 0, height: -10); gs.shadowBlurRadius = 24; gs.shadowColor = NSColor.black.withAlphaComponent(0.28)
NSGraphicsContext.saveGraphicsState(); gs.set()
sym.draw(in: NSRect(x: (S - w) / 2, y: (S - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[4]))
