import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func makeIcon(_ size: Int) -> NSImage {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let full = NSRect(x: 0, y: 0, width: side, height: side)
    let inset = side * 0.04
    let path = NSBezierPath(roundedRect: full.insetBy(dx: inset, dy: inset), xRadius: side * 0.22, yRadius: side * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.52, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.58, green: 0.34, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.86, green: 0.38, blue: 0.72, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -55)

    let faceWidth = side * 0.60
    let faceHeight = side * 0.54
    let faceX = (side - faceWidth) / 2 - side * 0.02
    let faceY = (side - faceHeight) / 2 - side * 0.01
    let face = NSBezierPath(
        roundedRect: NSRect(x: faceX, y: faceY, width: faceWidth, height: faceHeight),
        xRadius: faceWidth * 0.30,
        yRadius: faceWidth * 0.30
    )
    NSColor.white.setFill()
    face.fill()

    NSGraphicsContext.current?.compositingOperation = .clear
    let eye = faceWidth * 0.12
    for offset in [0.27, 0.63] {
        NSBezierPath(ovalIn: NSRect(
            x: faceX + faceWidth * offset - eye / 2,
            y: faceY + faceHeight * 0.52 - eye / 2,
            width: eye,
            height: eye
        )).fill()
    }

    let badge = NSPoint(x: faceX + faceWidth + side * 0.005, y: faceY + faceHeight - side * 0.005)
    let gap = side * 0.085
    NSBezierPath(ovalIn: NSRect(x: badge.x - gap, y: badge.y - gap, width: gap * 2, height: gap * 2)).fill()

    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSColor.white.setFill()
    let dot = side * 0.052
    NSBezierPath(ovalIn: NSRect(x: badge.x - dot, y: badge.y - dot, width: dot * 2, height: dot * 2)).fill()

    image.unlockFocus()
    return image
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let image = makeIcon(size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
print("wrote \(output)")
