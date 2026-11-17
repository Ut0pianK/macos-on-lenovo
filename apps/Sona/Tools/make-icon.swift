
import AppKit
import CoreGraphics

@main struct MakeIcon {
    static func main() {
        let S: CGFloat = 1024
        let cs = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
        func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }

        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: c(0, 0, 0, 0.35))
        ctx.addPath(shape); ctx.setFillColor(c(0.1, 0.1, 0.2)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.drawLinearGradient(grad([c(0.09, 0.07, 0.30), c(0.30, 0.14, 0.62), c(0.05, 0.55, 0.78)], [0, 0.55, 1]),
                               start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

        ctx.drawRadialGradient(grad([c(0.95, 0.45, 0.85, 0.55), c(0.95, 0.45, 0.85, 0)], [0, 1]),
                               startCenter: CGPoint(x: 300, y: 300), startRadius: 0, endCenter: CGPoint(x: 300, y: 300), endRadius: 420, options: [])
        ctx.drawRadialGradient(grad([c(0.35, 0.95, 1.0, 0.45), c(0.35, 0.95, 1.0, 0)], [0, 1]),
                               startCenter: CGPoint(x: 760, y: 760), startRadius: 0, endCenter: CGPoint(x: 760, y: 760), endRadius: 380, options: [])

        let center = CGPoint(x: 512, y: 500)

        for (i, r) in [CGFloat(330), 262, 196].enumerated() {
            let w: CGFloat = 30 - CGFloat(i) * 2
            let alpha: CGFloat = 0.22 + CGFloat(i) * 0.12
            let ring = CGMutablePath()
            ring.addArc(center: center, radius: r, startAngle: -.pi * 0.30, endAngle: .pi * 0.30, clockwise: false)
            let stroked = ring.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
            let ring2 = CGMutablePath()
            ring2.addArc(center: center, radius: r, startAngle: .pi * 0.70, endAngle: .pi * 1.30, clockwise: false)
            let stroked2 = ring2.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
            for p in [stroked, stroked2] {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: c(0.02, 0.0, 0.15, 0.45))
                ctx.addPath(p); ctx.setFillColor(c(1, 1, 1, alpha)); ctx.fillPath()
                ctx.restoreGState()

                ctx.saveGState(); ctx.addPath(p); ctx.clip()
                ctx.drawLinearGradient(grad([c(1, 1, 1, 0.55), c(1, 1, 1, 0)], [0, 1]),
                                       start: CGPoint(x: 0, y: center.y + r + w), end: CGPoint(x: 0, y: center.y - r), options: [])
                ctx.restoreGState()
            }
        }

        let discR: CGFloat = 128
        let disc = CGPath(ellipseIn: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2), transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: c(0.03, 0.0, 0.2, 0.55))
        ctx.addPath(disc); ctx.setFillColor(c(1, 1, 1, 0.30)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(disc); ctx.clip()

        ctx.drawLinearGradient(grad([c(1, 1, 1, 0.75), c(0.85, 0.80, 1.0, 0.25), c(0.55, 0.95, 1.0, 0.45)], [0, 0.55, 1]),
                               start: CGPoint(x: center.x, y: center.y + discR), end: CGPoint(x: center.x, y: center.y - discR), options: [])

        ctx.setFillColor(c(1, 1, 1, 0.55))
        ctx.fillEllipse(in: CGRect(x: center.x - discR * 0.62, y: center.y + discR * 0.30, width: discR * 1.24, height: discR * 0.52))
        ctx.restoreGState()

        ctx.addPath(disc); ctx.setStrokeColor(c(1, 1, 1, 0.85)); ctx.setLineWidth(5); ctx.strokePath()

        let dotR: CGFloat = 34
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: c(0.6, 0.95, 1.0, 0.9))
        ctx.setFillColor(c(1, 1, 1, 1))
        ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.restoreGState()

        ctx.drawLinearGradient(grad([c(1, 1, 1, 0.28), c(1, 1, 1, 0.0)], [0, 1]),
                               start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 600), options: [])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.setStrokeColor(c(1, 1, 1, 0.35)); ctx.setLineWidth(4); ctx.strokePath()
        ctx.restoreGState()

        let img = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage: img)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
