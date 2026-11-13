// 앱 아이콘(1024px PNG) 생성: swift scripts/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
           ending: NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.86, alpha: 1))!.draw(in: path, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
