import AppKit

/// The menu bar mark: a desk lamp, with a coloured dot when something is going on. See docs/design/States.dc.html.
enum LampMark {
    @MainActor
    static func image(for state: PanelViewModel.BarState) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "lamp.desk", accessibilityDescription: "Olive Lamp")?
            .withSymbolConfiguration(configuration) else { return NSImage() }
        let dot: NSColor? = switch state {
        case .quiet: nil
        case .running: Palette.nsAmber
        case .failed: Palette.nsBad
        case .attention: .secondaryLabelColor
        }
        guard let dot else {
            symbol.isTemplate = true
            return symbol
        }
        // With a dot the image cannot be a template; it draws the lamp in the menu bar's own label colour.
        let size = NSSize(width: symbol.size.width + 4, height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { rect in
            let tinted = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor])) ?? symbol
            tinted.draw(in: NSRect(x: 0, y: (rect.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            let diameter: CGFloat = 6
            let circle = NSBezierPath(ovalIn: NSRect(x: rect.width - diameter, y: 1, width: diameter, height: diameter))
            dot.setFill()
            circle.fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Olive Lamp"
        return image
    }
}
