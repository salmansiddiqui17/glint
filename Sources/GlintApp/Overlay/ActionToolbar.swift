import AppKit

/// Actions the overlay can perform on the selection (FR-41).
enum OverlayAction {
    case copyText, copy, save, close
}

/// The horizontal action toolbar under the selection (FR-41): Copy Text, Copy, Save, Close, or
/// just Copy, Save, Close while Copy Text is turned off (OQ-22).
final class ActionToolbar: NSVisualEffectView {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 2
    static let padding: CGFloat = 2

    private struct Item {
        let action: OverlayAction
        let symbol: String
        let title: String
        let shortcut: String
    }

    private static let allItems = [
        Item(action: .copyText, symbol: "text.viewfinder", title: String(localized: "Copy Text"), shortcut: "⌘O"),
        Item(action: .copy, symbol: "doc.on.doc", title: String(localized: "Copy"),
             shortcut: String(localized: "⌘C or Return")),
        Item(action: .save, symbol: "square.and.arrow.down", title: String(localized: "Save"), shortcut: "⌘S"),
        Item(action: .close, symbol: "xmark", title: String(localized: "Close"),
             shortcut: String(localized: "⌘X or Esc")),
    ]

    private let items: [Item]

    /// The toolbar's size, which follows its number of buttons.
    override var intrinsicContentSize: NSSize {
        let count = CGFloat(items.count)
        return CGSize(width: count * Self.buttonSize + (count - 1) * Self.spacing + 2 * Self.padding,
                      height: Self.buttonSize + 2 * Self.padding)
    }

    var onAction: ((OverlayAction) -> Void)?
    /// The selection in the superview's coordinates, which tooltips keep clear of.
    var selectionFrame: CGRect?
    private let tooltip = OverlayTooltip()
    private var buttons: [ToolbarButton] = []
    /// Shown in place of the Copy Text icon while text is being recognised (FR-46).
    private let spinner = NSProgressIndicator()
    private var spinnerDelay: Task<Void, Never>?

    /// - Parameter includesCopyText: whether Copy Text is turned on (OQ-22).
    init(includesCopyText: Bool) {
        items = Self.allItems.filter { includesCopyText || $0.action != .copyText }
        super.init(frame: .zero)
        setFrameSize(intrinsicContentSize)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        setAccessibilityElement(true)   // otherwise VoiceOver skips the group (NFR-12)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "Capture actions"))

        for (index, item) in items.enumerated() {
            let button = ToolbarButton(frame: CGRect(
                x: Self.padding + CGFloat(index) * (Self.buttonSize + Self.spacing), y: Self.padding,
                width: Self.buttonSize, height: Self.buttonSize))
            button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .white
            // System tooltips draw below the screen-saver-level overlay, so the toolbar shows its own.
            // A format key, so a translation can reorder or restyle it (NFR-15).
            let help = String(format: String(localized: "%@ (%@)",
                                             comment: "Toolbar tooltip: a button's name, then its keyboard shortcut"),
                              item.title, item.shortcut)
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
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel(String(localized: "Reading text"))
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isHidden: Bool {
        didSet { if isHidden { dismissHover() } }
    }

    /// Arrow keys move the toolbar under a still pointer, which posts no mouse-exited event.
    /// (`OverlayView.refresh()` assigns the frame on every update, so only a real change counts.)
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
        onAction?(items[sender.tag].action)
    }

    /// While text is recognised, the Copy Text button shows a spinner instead of its icon (FR-46).
    /// It appears only after 0.2 s, so a quick recognition doesn't flicker the button.
    func setRecognizingText(_ recognizing: Bool) {
        spinnerDelay?.cancel()
        spinnerDelay = nil
        guard recognizing else { return showSpinner(false) }
        spinnerDelay = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.showSpinner(true)
        }
    }

    private func showSpinner(_ shown: Bool) {
        guard let index = items.firstIndex(where: { $0.action == .copyText }) else { return }
        let button = buttons[index]
        let item = items[index]
        button.image = shown ? nil : NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        if shown {
            let size = spinner.fittingSize
            spinner.frame = CGRect(x: button.frame.midX - size.width / 2, y: button.frame.midY - size.height / 2,
                                   width: size.width, height: size.height)
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    // Swallow clicks in the padding and gaps between buttons, so they never reach the overlay's
    // selection editor underneath, and scrolls, which would change the stroke width unseen.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

/// Fires on the first click even when its window is not key, reports hovering, shows a hover
/// fill, and can show an active state (the selected tool, §4.2).
final class ToolbarButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var isHovered = false {
        didSet { if isHovered != oldValue { updateFill() } }
    }

    /// Fills the button with the accent colour.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            updateFill()
            setAccessibilitySelected(isActive)
        }
    }

    override var isEnabled: Bool {
        didSet { if isEnabled != oldValue { updateFill() } }
    }

    private func updateFill() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isActive ? NSColor.controlAccentColor.cgColor
            : isHovered && isEnabled ? NSColor.white.withAlphaComponent(0.15).cgColor : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Never takes keyboard focus, even with Keyboard navigation on, so typing stays in the text box.
    override var acceptsFirstResponder: Bool { false }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        isHovered = false
    }

    func resetHover() {
        isHovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard event.trackingArea === hoverArea else { return }
        isHovered = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === hoverArea else { return }
        isHovered = false
        onHover?(false)
    }
}

/// A tooltip drawn inside the overlay after the usual hover delay: below a horizontal toolbar,
/// else above it, or right of a vertical one, else left of it, whichever fits on the display
/// without covering the selection.
@MainActor
final class OverlayTooltip {
    enum Placement {
        /// Horizontal toolbars: below, else above.
        case belowOrAbove
        /// Vertical palettes: to the right, else to the left.
        case rightOrLeft
    }

    private let placement: Placement
    private let bubble = TooltipBubble()
    private var pending: Task<Void, Never>?
    /// The button the tooltip belongs to, so a late exit from a neighbour doesn't hide it.
    private weak var owner: NSView?

    init(placement: Placement = .belowOrAbove) {
        self.placement = placement
    }

    func show(_ text: String, for button: NSView, avoiding selection: CGRect?) {
        hide()
        owner = button
        pending = Task { [weak self, weak button] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let button, let toolbar = button.superview,
                  let overlay = toolbar.superview else { return }
            self.place(text, for: button, of: toolbar, in: overlay, avoiding: selection)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        owner = nil
        bubble.removeFromSuperview()
    }

    func hide(for button: NSView) {
        if owner === button { hide() }
    }

    private func place(_ text: String, for button: NSView, of toolbar: NSView, in overlay: NSView,
                       avoiding selection: CGRect?) {
        let size = bubble.setText(text)
        // The overlay view has a bottom-left origin: "below" is a smaller y.
        let anchor = button.convert(button.bounds, to: overlay)
        let bar = toolbar.frame
        let gap: CGFloat = 4
        let origins: [CGPoint]
        switch placement {
        case .belowOrAbove:
            let x = min(max(anchor.midX - size.width / 2, overlay.bounds.minX), overlay.bounds.maxX - size.width)
            origins = [CGPoint(x: x, y: bar.minY - gap - size.height), CGPoint(x: x, y: bar.maxY + gap)]
        case .rightOrLeft:
            let y = min(max(anchor.midY - size.height / 2, overlay.bounds.minY), overlay.bounds.maxY - size.height)
            origins = [CGPoint(x: bar.maxX + gap, y: y), CGPoint(x: bar.minX - gap - size.width, y: y)]
        }
        let candidates = origins.map { CGRect(origin: $0, size: size).integral }
        let onDisplay = candidates.filter { overlay.bounds.contains($0) }
        bubble.frame = onDisplay.first { !(selection?.intersects($0) ?? false) } ?? onDisplay.first ?? candidates[0]
        overlay.addSubview(bubble)
    }
}

/// The tooltip's rounded box with its text centred, equal padding on every side. Never takes
/// clicks, so the overlay underneath keeps working while a tooltip shows.
private final class TooltipBubble: NSView {
    private static let padding = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 5
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .white
        addSubview(label)
        setAccessibilityElement(false)   // the button already carries this as its help text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Sets the text and returns the bubble's size.
    func setText(_ text: String) -> CGSize {
        label.stringValue = text
        let text = label.intrinsicContentSize
        let pad = Self.padding
        label.frame = CGRect(x: pad.left, y: pad.bottom, width: ceil(text.width), height: ceil(text.height))
        return CGSize(width: ceil(text.width) + pad.left + pad.right, height: ceil(text.height) + pad.top + pad.bottom)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
