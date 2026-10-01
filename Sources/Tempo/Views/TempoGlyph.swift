import AppKit
import SwiftUI

/// The Tempo mark (clock ring + "T" hand), traced from Resources/Icon/menubar-icon.svg.
enum TempoGlyph {
    /// The open ring, already outlined so it can be filled.
    static let ring: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 345, y: 345))
        p.addCurve(to: CGPoint(x: 260, y: 544), control1: CGPoint(x: 294, y: 390), control2: CGPoint(x: 260, y: 462))
        p.addCurve(to: CGPoint(x: 555, y: 839), control1: CGPoint(x: 260, y: 707), control2: CGPoint(x: 392, y: 839))
        p.addCurve(to: CGPoint(x: 850, y: 544), control1: CGPoint(x: 718, y: 839), control2: CGPoint(x: 850, y: 707))
        p.addCurve(to: CGPoint(x: 771, y: 344), control1: CGPoint(x: 850, y: 466), control2: CGPoint(x: 820, y: 396))
        return p.copy(strokingWithWidth: 76, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }()

    /// The "T" that doubles as the clock hand.
    static let hand: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 327, y: 309))
        p.addCurve(to: CGPoint(x: 388, y: 248), control1: CGPoint(x: 327, y: 275), control2: CGPoint(x: 354, y: 248))
        p.addLine(to: CGPoint(x: 683, y: 248))
        p.addCurve(to: CGPoint(x: 707, y: 289), control1: CGPoint(x: 705, y: 248), control2: CGPoint(x: 718, y: 270))
        p.addCurve(to: CGPoint(x: 628, y: 336), control1: CGPoint(x: 691, y: 318), control2: CGPoint(x: 661, y: 336))
        p.addLine(to: CGPoint(x: 574, y: 336))
        p.addLine(to: CGPoint(x: 574, y: 529))
        p.addCurve(to: CGPoint(x: 598, y: 577), control1: CGPoint(x: 574, y: 548), control2: CGPoint(x: 583, y: 566))
        p.addLine(to: CGPoint(x: 710, y: 661))
        p.addCurve(to: CGPoint(x: 721, y: 737), control1: CGPoint(x: 734, y: 679), control2: CGPoint(x: 739, y: 713))
        p.addCurve(to: CGPoint(x: 645, y: 748), control1: CGPoint(x: 703, y: 761), control2: CGPoint(x: 669, y: 766))
        p.addLine(to: CGPoint(x: 512, y: 648))
        p.addCurve(to: CGPoint(x: 482, y: 587), control1: CGPoint(x: 493, y: 634), control2: CGPoint(x: 482, y: 611))
        p.addLine(to: CGPoint(x: 482, y: 336))
        p.addLine(to: CGPoint(x: 388, y: 336))
        p.addCurve(to: CGPoint(x: 327, y: 309), control1: CGPoint(x: 354, y: 336), control2: CGPoint(x: 327, y: 309))
        p.closeSubpath()
        return p
    }()

    /// Ring and hand merged into one outline (they overlap at the top-left).
    static let path: CGPath = ring.union(hand)

    static let bounds: CGRect = path.boundingBoxOfPath

    /// Transform that aspect-fits the glyph into `rect` (y-down coordinates).
    static func transform(fitting rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let dx = rect.midX - bounds.midX * scale
        let dy = rect.midY - bounds.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)
    }

    /// Monochrome template image for the menu bar; macOS tints it for light/dark menu bars.
    static func menuBarImage(height: CGFloat = 16) -> NSImage {
        let size = NSSize(width: (height * bounds.width / bounds.height).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var t = transform(fitting: rect)
            guard let scaled = path.copy(using: &t) else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(scaled)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tempo"
        return image
    }

    static let menuBar = menuBarImage()

    // MARK: Running-timer icon

    private static var progressCache: [String: NSImage] = [:]

    /// Fixed-width menu bar icon for a running timer: a ring showing time left with the minutes inside.
    /// It stays the same width as the idle icon so it can't be pushed behind the notch.
    static func progressImage(remaining: TimeInterval, fraction: Double, isBreak: Bool, height: CGFloat = 16) -> NSImage {
        let minutes = max(0, Int((remaining / 60).rounded(.up)))
        let step = Int((max(0, min(1, fraction)) * 60).rounded())
        let key = "\(minutes)-\(step)-\(isBreak)"
        if let cached = progressCache[key] { return cached }

        let size = NSSize(width: height, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 1.6
            let ringRect = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = ringRect.width / 2

            // Faint full track.
            NSColor.black.withAlphaComponent(0.3).setStroke()
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            track.stroke()

            // Remaining time, clockwise from 12 o'clock.
            if step > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(step) / 60, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            if isBreak {
                let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                if let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let s = cup.size
                    cup.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2,
                                        width: s.width, height: s.height))
                }
            } else {
                let text = "\(minutes)" as NSString
                let font = NSFont.monospacedDigitSystemFont(ofSize: minutes >= 100 ? 6 : 8, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                let textSize = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                          withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isBreak ? "Tempo break, \(minutes) minutes left"
                                                 : "Tempo focus, \(minutes) minutes left"
        progressCache[key] = image
        return image
    }
}

struct TempoGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var t = TempoGlyph.transform(fitting: rect)
        return Path(TempoGlyph.path.copy(using: &t) ?? TempoGlyph.path)
    }
}

/// The mark as a SwiftUI view, filled with the current foreground style.
struct TempoGlyphView: View {
    var body: some View {
        TempoGlyphShape()
            .aspectRatio(TempoGlyph.bounds.width / TempoGlyph.bounds.height, contentMode: .fit)
    }
}
