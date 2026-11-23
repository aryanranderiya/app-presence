import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icons"
let size = 512

try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let roots = [
    "/Applications",
    "/System/Applications",
    "/System/Applications/Utilities",
    "/System/Library/CoreServices",
    NSHomeDirectory() + "/Applications",
]

var seen = Set<String>()
var written: [(String, String, Int)] = []

for root in roots {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
    for name in names.sorted() where name.hasSuffix(".app") {
        let path = root + "/" + name
        guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { continue }
        guard !seen.contains(id) else { continue }
        seen.insert(id)

        let icon = NSWorkspace.shared.icon(forFile: path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { continue }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.size = NSSize(width: size, height: size)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        let target = output + "/" + id + ".png"
        do {
            try png.write(to: URL(fileURLWithPath: target))
            written.append((id, name, png.count))
        } catch {
            FileHandle.standardError.write(Data("failed \(id): \(error)\n".utf8))
        }
    }
}

let total = written.reduce(0) { $0 + $1.2 }
print("exported \(written.count) icons, \(total / 1024) KB")
for item in written.sorted(by: { $0.0 < $1.0 }) {
    print("  \(item.0)\t\(item.1)")
}
