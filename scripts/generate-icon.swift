import AppKit

// Draw a red O at each required size. No network requests or third-party artwork.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor.white.setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 205, yRadius: 205
    ).fill()
    NSColor(srgbRed: 0.83, green: 0.04, blue: 0.10, alpha: 1).setFill()
    let ring = NSBezierPath(ovalIn: NSRect(x: 172, y: 144, width: 680, height: 736))
    ring.appendOval(in: NSRect(x: 318, y: 290, width: 388, height: 444))
    ring.windingRule = .evenOdd
    ring.fill()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let file = destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: file)
  }
}
