import AppKit
import GlintCore

/// What the tools palette asks the overlay to do (FR-28).
enum PaletteAction {
    case tool(Tool)
    case color
    case undo
    case redo
}

/// The vertical tools palette beside the selection (FR-28): the eight tools, the colour swatch,
/// Undo and Redo.
final class ToolsPalette: NSVisualEffectView {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 2
    static let padding: CGFloat = 2

    private struct Item {
        let action: PaletteAction
        let symbol: String?
        let title: String
        let shortcut: String?
    }

    private static let items: [Item] = [
        Item(action: .tool(.pencil), symbol: "pencil", title: "Pencil", shortcut: nil),
        Item(action: .tool(.line), symbol: "line.diagonal", title: "Line", shortcut: nil),
        Item(action: .tool(.arrow), symbol: "arrow.up.right", title: "Arrow", shortcut: nil),
        Item(action: .tool(.ellipse), symbol: "circle", title: "Ellipse", shortcut: nil),
        Item(action: .tool(.rectangle), symbol: "rectangle", title: "Rectangle", shortcut: nil),
        Item(action: .tool(.marker), symbol: "highlighter", title: "Marker", shortcut: nil),
        Item(action: .tool(.text), symbol: "textformat", title: "Text", shortcut: nil),
        Item(action: .tool(.redact), symbol: "squareshape.split.3x3", title: "Redact", shortcut: "⌘B"),
        Item(action: .color, symbol: nil, title: "Colour", shortcut: nil),
        Item(action: .undo, symbol: "arrow.uturn.backward", title: "Undo", shortcut: "⌘Z"),
        Item(action: .redo, symbol: "arrow.uturn.forward", title: "Redo", shortcut: "⇧⌘Z"),
    ]

    static var size: CGSize {
        let count = CGFloat(items.count)
        return CGSize(width: buttonSize + 2 * padding,
                      height: count * buttonSize + (count - 1) * spacing + 2 * padding)
    }

    var onAction: ((PaletteAction) -> Void)?
    /// The selection in the superview's coordinates, which tooltips keep clear of.
    var selectionFrame: CGRect?
    private let tooltip = OverlayTooltip(placement: .rightOrLeft)
    private var buttons: [ToolbarButton] = []
    private var shownColor: RGBAColor?

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        setAccessibilityElement(true)   // otherwise VoiceOver skips the group (NFR-12)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Drawing tools")

        for (index, item) in Self.items.enumerated() {
            // Top to bottom in a bottom-left-origin view: the first item has the highest y.
            let y = Self.size.height - Self.padding - CGFloat(index + 1) * Self.buttonSize - CGFloat(index) * Self.spacing
            let button = ToolbarButton(frame: CGRect(x: Self.padding, y: y, width: Self.buttonSize,
                                                     height: Self.buttonSize))
            if let symbol = item.symbol {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title)
            }
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .white
            // System tooltips draw below the screen-saver-level overlay, so the palette shows its own.
            let help = item.shortcut.map { "\(item.title) (\($0))" } ?? item.title
            button.setAccessibilityLabel(item.title)
            button.setAccessibilityHelp(help)
            button.onHover = { [weak self, weak button] hovering in
                guard let self, let button else { return }
                hovering ? tooltip.show(help, for: button, avoiding: selectionFrame) : tooltip.hide(for: button)
            }
            button.tag = index
            button.target = self
            button.action = #selector(buttonPressed(_:))
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the active tool, the current colour and whether Undo and Redo can act.
    func update(activeTool: Tool?, color: RGBAColor, canUndo: Bool, canRedo: Bool) {
        for (item, button) in zip(Self.items, buttons) {
            switch item.action {
            case let .tool(tool):
                button.isActive = tool == activeTool
            case .color:
                if color != shownColor { button.image = Self.swatch(color) }
            case .undo:
                button.isEnabled = canUndo  // the system dims a disabled button
            case .redo:
                button.isEnabled = canRedo
            }
        }
        shownColor = color
    }

    override var isHidden: Bool {
        didSet { if isHidden { dismissHover() } }
    }

    /// Arrow keys move the palette under a still pointer, which posts no mouse-exited event.
    override var frame: NSRect {
        get { super.frame }
        set {
            if newValue != super.frame { dismissHover() }
            super.frame = newValue
        }
    }

    /// Hides the tooltip and any hover fill: hiding or moving under a still pointer posts no exit.
    private func dismissHover() {
        tooltip.hide()
        for case let button as ToolbarButton in subviews { button.resetHover() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        tooltip.hide()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        tooltip.hide()
        onAction?(Self.items[sender.tag].action)
    }

    /// A filled circle in `color` with a white ring, for the Colour button (§4.2).
    private static func swatch(_ color: RGBAColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            NSColor(cgColor: color.cgColor)?.setFill()
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            return true
        }
        image.accessibilityDescription = "Colour"
        return image
    }

    // Swallow clicks in the padding and gaps between buttons, so they never reach the overlay,
    // and scrolls, which would change the stroke width unseen.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
