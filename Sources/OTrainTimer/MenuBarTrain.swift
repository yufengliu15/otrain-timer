import AppKit

@MainActor
enum MenuBarTrain {
  // Cache rendered, non-template images so macOS does not discard the status colours.
  private static let coloured: [DepartureStatus: NSImage] = [
    .leave: render(colour: .systemGreen),
    .tight: render(colour: .systemYellow),
    .late: render(colour: .systemRed),
  ]
  private static let neutral: NSImage = {
    let image =
      NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Train") ?? NSImage()
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }()

  static func image(for status: DepartureStatus?) -> NSImage {
    guard let status, let image = coloured[status] else { return neutral }
    return image
  }

  private static func render(colour: NSColor) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = NSRect(origin: .zero, size: size)
    let symbol = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Train")
    symbol?.draw(in: rect)
    colour.setFill()
    rect.fill(using: .sourceAtop)
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
