import AppKit
import GlintCore
import os

/// One capture: an overlay panel per display, a single selection across them, the tool and
/// style they share, Copy Text, and teardown that releases every frozen image (FR-17, FR-18,
/// FR-27, FR-28, FR-42, FR-46).
@MainActor
final class CaptureSession: OverlayViewDelegate {
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private let exporter: Exporter
    private let drawing: DrawingState
    private let colorPanel = ColorPanel()
    private let onFinish: () -> Void
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    /// The app that was in front before the overlay, which gets focus back afterwards, so ⌘V
    /// after a copy lands there instead of in Glint.
    private var previousApp: NSRunningApplication?
    /// Copy Text's recognition while it runs (FR-46).
    private var recognition: Task<Void, Never>?
    /// Says "Still reading text…" if the recognition is slow (OQ-18).
    private var recognitionNotice: Task<Void, Never>?
    /// Whether a recognition has finished in this process, so Vision's text model is ready and
    /// later ones keep the shorter limit (OQ-18).
    private static var recognitionHasFinished = false
    private let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "capture")

    init(captures: [DisplayCapture], windows: WindowSnapshot, exporter: Exporter, settings: AppSettings,
         onFinish: @escaping () -> Void) {
        self.exporter = exporter
        self.onFinish = onFinish
        drawing = DrawingState(settings: settings)
        for capture in captures {
            let panel = OverlayPanel(frame: capture.frame)
            let view = OverlayView(capture: capture, snapTargets: windows.targets(for: capture.frame), drawing: drawing,
                                   standardResolution: settings.saveAtStandardResolution)
            view.delegate = self
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }
        drawing.onChange = { [weak self] in
            self?.views.forEach { $0.drawingStateDidChange() }
        }
    }

    func begin() {
        // Commit every layer tree (and the frozen image) before showing, so no black frame flashes.
        panels.forEach { $0.displayIfNeeded() }
        CATransaction.flush()
        panels.forEach { $0.orderFrontRegardless() }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        // Key display = the one under the pointer, falling back to the first.
        let mouse = NSEvent.mouseLocation
        let index = views.firstIndex { NSMouseInRect(mouse, $0.capture.frame, false) } ?? 0
        if views.indices.contains(index) {
            panels[index].makeKeyAndOrderFront(nil)
            panels[index].makeFirstResponder(views[index])
            views[index].pointerDidMove()   // crosshair and snap highlight before the first mouse move (FR-19, FR-21)
        }
        observeChanges()
    }

    /// Cancels the capture when the frozen image would no longer match what is underneath
    /// (NFR-9), or when another app takes focus and would receive the overlay's keystrokes.
    /// None of these hand focus back: the user has already moved somewhere else.
    private func observeChanges() {
        let layoutAtStart = ScreenCapturer.displayLayout()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { session in
            // Also posted for Dock and menu-bar changes; cancel only on a real display change.
            if ScreenCapturer.displayLayout() != layoutAtStart {
                session.end(reason: "display change", restoringFocus: false)
            }
        }
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification) { session in
            session.end(reason: "app deactivated", restoringFocus: false)
        }
        // With "Displays have separate Spaces", merely moving focus to another display posts this
        // notification too, so cancel only if the other apps' normal windows actually changed.
        let windowsAtStart = Self.otherAppsNormalWindows()
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { session in
            let windowsNow = Self.otherAppsNormalWindows()
            // Counts only, never window details (§7.2): shows why a Space change did or didn't cancel.
            session.logger.notice("active Space changed: \(windowsAtStart.count) → \(windowsNow.count) other-app windows, \(windowsAtStart.intersection(windowsNow).count) unchanged")
            if windowsNow != windowsAtStart {
                session.end(reason: "Space change", restoringFocus: false)
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (CaptureSession) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        observers.append((center, token))
    }

    /// IDs of other apps' on-screen normal windows, which belong to a Space (see `WindowList`).
    private static func otherAppsNormalWindows() -> Set<Int> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return WindowList.normalWindowIDs(in: info, excludingProcess: Int(ProcessInfo.processInfo.processIdentifier))
    }

    /// Closes the overlay and finishes the session without exporting.
    func end(reason: String, restoringFocus: Bool = true) {
        guard tearDown() else { return }   // already ended
        logger.notice("capture ended: \(reason, privacy: .public)")
        finish(restoringFocus: restoringFocus)
    }

    /// Hides and releases the overlay. Returns false if it was already torn down.
    @discardableResult
    private func tearDown() -> Bool {
        guard !panels.isEmpty else { return false }
        if let recognition {
            recognition.cancel()
            views.forEach { $0.setRecognizingText(false) }   // the spinner stops before its view is released
        }
        recognition = nil
        recognitionNotice?.cancel()
        recognitionNotice = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        colorPanel.close()
        let closing = panels
        panels.removeAll()
        views.removeAll()
        closing.forEach { $0.orderOut(nil) }
        NSCursor.arrow.set()   // don't leave the overlay's crosshair or hand over the app underneath
        // Release the views and frozen images (FR-27) on the next run-loop turn: end() usually runs
        // inside an overlay view's own key handler or a toolbar button's action.
        Task { @MainActor in
            for panel in closing {
                panel.contentView = nil
                panel.close()   // leaves NSApp.windows now (isReleasedWhenClosed is false)
            }
        }
        return true
    }

    /// Hands focus back (unless the user already switched apps) and frees the coordinator for
    /// the next capture (FR-9).
    private func finish(restoringFocus: Bool) {
        if restoringFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated,
           previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        Redaction.releaseCaches()   // Core Image's memory goes with the frozen images (NFR-6)
        onFinish()
    }

    // MARK: OverlayViewDelegate

    func overlayDidBeginSelection(_ view: OverlayView) {
        for other in views where other !== view {
            other.clearSelection()
        }
    }

    func overlaySelectionOwner() -> OverlayView? {
        views.first { $0.selection != nil }
    }

    func overlayEscape(_ view: OverlayView) {
        if recognition != nil { return end(reason: "cancelled") }   // Esc cancels Copy Text and the capture
        switch EscapeAction.resolve(isEditingText: overlayTextEditor() != nil, isToolActive: drawing.tool != nil) {
        case .commitText:
            overlayTextEditor()?.commitText()   // the Text tool stays selected
        case .deselectTool:
            drawing.tool = nil
        case .cancelCapture:
            end(reason: "cancelled")
        }
    }

    func overlayTextEditor() -> OverlayView? {
        views.first { $0.isEditingText }
    }

    func overlayIsRecognizingText() -> Bool {
        recognition != nil
    }

    func overlayShowColorPanel(near anchor: CGRect) {
        colorPanel.show(drawing.style.color, near: anchor) { [weak self] color in
            self?.drawing.style.color = color
        }
    }

    func overlay(_ view: OverlayView, perform action: OverlayAction) {
        guard recognition == nil || action == .close else { return }
        switch action {
        case .close:
            end(reason: "cancelled")
        case .copyText:
            // Not mid-drag (⌘O with the mouse down): the selection or a shape would keep changing
            // while the old image is read, and Esc would only end the drag.
            guard !views.contains(where: \.isInGesture) else { return NSSound.beep() }
            views.forEach { $0.commitText() }   // FR-42: pending text is committed first
            guard let owner = overlaySelectionOwner() else { return NSSound.beep() }
            // The rendered selection, so redactions are applied and the 1× option counts (FR-45).
            guard let image = owner.renderSelection() else {
                logger.error("text recognition render failed")
                return NSSound.beep()
            }
            // Input is ignored while recognising, but an open colour panel could still change the colour.
            colorPanel.close()
            recognizeText(in: image, shownOn: owner)
        case .copy, .save:
            views.forEach { $0.commitText() }   // FR-42: any export commits pending text first
            let started = ContinuousClock.now
            guard let owner = overlaySelectionOwner() else { return NSSound.beep() }
            guard let image = owner.renderSelection() else {
                // Nothing to export, or a redaction couldn't be made: never an unredacted image (FR-36).
                logger.error("export render failed")
                return NSSound.beep()
            }
            logger.notice("rendered \(image.width)x\(image.height) in \(milliseconds(since: started)) ms")   // NFR-3
            let dpi = owner.outputDPI
            tearDown()   // the overlay closes before the action runs (FR-42)
            // Export from a clean stack, after the teardown task: the Save panel runs a modal loop,
            // which must not run inside the overlay's key handler while its views are released.
            // The session stays open until the export is done, so the hotkey can't start another
            // capture over the Save panel (FR-9).
            Task { @MainActor in
                if action == .copy {
                    await exporter.copy(image, dpi: dpi)
                } else {
                    await exporter.save(image, dpi: dpi)
                }
                finish(restoringFocus: true)
            }
        }
    }

    /// Recognises the text in `image` while the overlay waits (FR-46). Found text is copied and
    /// the overlay closes; otherwise `owner` shows why for 1.5 s and the overlay stays open.
    /// The first recognition in a session may run longer, and says so while it does (OQ-18).
    private func recognizeText(in image: CGImage, shownOn owner: OverlayView) {
        let started = ContinuousClock.now
        let timeout = TextRecognitionLimits.timeout(afterEarlierFinished: Self.recognitionHasFinished)
        owner.setRecognizingText(true)
        // `owner` is held weakly: if Esc ends the capture while Vision is still busy, its frozen
        // image is released at once (FR-27).
        recognitionNotice = Task { [weak owner] in
            try? await Task.sleep(for: TextRecognitionLimits.noticeDelay)
            guard !Task.isCancelled else { return }
            owner?.showMessage(String(localized: "Still reading text… Esc cancels"), for: nil)
        }
        recognition = Task { [weak self, weak owner] in
            let result = await Self.recognize(image, timeout: timeout)
            // Vision answered, with or without text, so its model is ready (OQ-18).
            if case .success = result { CaptureSession.recognitionHasFinished = true }
            guard let self, let owner, !Task.isCancelled else { return }   // Esc or ⌘X ended the capture
            recognition = nil
            recognitionNotice?.cancel()
            recognitionNotice = nil
            owner.setRecognizingText(false)
            switch result {
            case let .success(text) where !text.isEmpty:
                logger.notice("recognised text in \(milliseconds(since: started)) ms")   // never the text (§7.2)
                tearDown()
                exporter.copyText(text)
                finish(restoringFocus: true)
            case .success:
                logger.notice("no text found in \(milliseconds(since: started)) ms")
                owner.showMessage(String(localized: "No text found"))
            case let .failure(error):
                logger.error("text recognition failed: \(String(describing: error), privacy: .public)")
                owner.showMessage(String(localized: "Couldn't read text"))
            }
        }
    }

    /// Vision's text in `image`, given up after `timeout`. Cancelling the caller, or the timeout,
    /// cancels the recognition too.
    private nonisolated static func recognize(_ image: CGImage, timeout: Duration) async -> Result<String, any Error> {
        let work = Task.detached(priority: .userInitiated) { try await TextRecognition.recognizeText(in: image) }
        return await withTaskCancellationHandler {
            do {
                return .success(try await withTimeout(timeout) { try await work.value })
            } catch {
                work.cancel()
                return .failure(error)
            }
        } onCancel: {
            work.cancel()
        }
    }
}
