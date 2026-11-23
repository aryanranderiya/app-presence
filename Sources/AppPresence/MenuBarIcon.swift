import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let points = NSSize(width: 20, height: 18)
        let scale: CGFloat = 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(points.width * scale),
            pixelsHigh: Int(points.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: points)
        }
        rep.size = points

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()

        let face = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 2.5, width: 14, height: 13), xRadius: 5.2, yRadius: 5.2)
        face.fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 4.0, y: 9.4, width: 2.9, height: 2.9)).fill()
        NSBezierPath(ovalIn: NSRect(x: 9.1, y: 9.4, width: 2.9, height: 2.9)).fill()
        NSBezierPath(ovalIn: NSRect(x: 13.2, y: 10.4, width: 6.8, height: 6.8)).fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14.5, y: 11.7, width: 4.2, height: 4.2)).fill()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: points)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
