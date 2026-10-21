import CoreGraphics
import Testing
@testable import GlintCore

struct SelectionEditorTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func editor(with selection: CGRect? = nil) -> SelectionEditor {
        var editor = SelectionEditor(bounds: display)
        if let selection { editor.select(selection) }
        return editor
    }

    // MARK: Creating (FR-18)

    @Test func dragCreatesNormalisedSelection() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 500, y: 400), clickCount: 1)
        let began = e.mouseDragged(to: CGPoint(x: 300, y: 250))
        #expect(e.isDragging)
        #expect(e.isCreating)
        #expect(e.resizingHandle == nil)
        let laterDrag = e.mouseDragged(to: CGPoint(x: 290, y: 240))
        let release = e.mouseUp(at: CGPoint(x: 300, y: 250))
        #expect(began)
        #expect(laterDrag == false)
        #expect(release == false)
        #expect(e.isDragging == false)
        #expect(e.isCreating == false)
        #expect(e.selection == CGRect(x: 300, y: 250, width: 200, height: 150))
    }

    @Test func movementWithinThresholdDoesNotCreateSelection() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 10, y: 10), clickCount: 1)
        let began = e.mouseDragged(to: CGPoint(x: 12, y: 12))
        e.mouseUp(at: CGPoint(x: 12, y: 12))
        #expect(began == false)
        #expect(e.selection == nil)
    }

    @Test func releaseWithoutDragEventsCanCreateSelectionAndReportsIt() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 100, y: 100), clickCount: 1)
        let began = e.mouseUp(at: CGPoint(x: 150, y: 150))
        #expect(began)
        #expect(e.selection == CGRect(x: 100, y: 100, width: 50, height: 50))
    }

    @Test func selectionIsClampedToDisplay() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 900, y: 700), clickCount: 1)
        e.mouseDragged(to: CGPoint(x: 1500, y: 1500))
        e.mouseUp(at: CGPoint(x: 1500, y: 1500))
        #expect(e.selection == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func zeroAreaDragLeavesNoSelectionAndReportsNothing() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 100, y: 100), clickCount: 1)
        let release = e.mouseUp(at: CGPoint(x: 100, y: 200))
        #expect(release == false)
        #expect(e.selection == nil)
    }

    @Test func pressOutsideExistingSelectionStartsANewOne() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 100, height: 100))
        e.mouseDown(at: CGPoint(x: 500, y: 500), clickCount: 1)
        let began = e.mouseDragged(to: CGPoint(x: 600, y: 650))
        e.mouseUp(at: CGPoint(x: 600, y: 650))
        #expect(began)
        #expect(e.selection == CGRect(x: 500, y: 500, width: 100, height: 150))
    }

    @Test func clickOutsideWithoutSnapTargetsKeepsSelection() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        var e = editor(with: rect)
        e.mouseDown(at: CGPoint(x: 500, y: 500), clickCount: 1)
        e.mouseUp(at: CGPoint(x: 500, y: 500))
        #expect(e.selection == rect)
    }

    // MARK: Moving (FR-22)

    @Test func dragInsideMovesWithoutResizingAndClampsAtEdges() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 200, height: 100))
        e.mouseDown(at: CGPoint(x: 150, y: 150), clickCount: 1)
        #expect(e.isMoving)
        let began = e.mouseDragged(to: CGPoint(x: 0, y: 0))
        e.mouseUp(at: CGPoint(x: 0, y: 0))
        #expect(began == false)
        #expect(e.selection == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    // MARK: Resizing (FR-21)

    @Test func handleDragResizes() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 200, height: 100))
        e.mouseDown(at: CGPoint(x: 300, y: 200), clickCount: 1)   // bottom-right handle
        let began = e.mouseDragged(to: CGPoint(x: 400, y: 300))
        #expect(e.resizingHandle == .bottomRight)
        #expect(e.isCreating == false)
        e.mouseUp(at: CGPoint(x: 400, y: 300))
        #expect(e.resizingHandle == nil)
        #expect(began == false)
        #expect(e.selection == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test func handleDragPastAnchorFlips() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 200, height: 100))
        e.mouseDown(at: CGPoint(x: 300, y: 150), clickCount: 1)   // right handle
        e.mouseUp(at: CGPoint(x: 50, y: 150))
        #expect(e.selection == CGRect(x: 50, y: 100, width: 50, height: 100))
    }

    @Test func resizeWithGrabOffsetStopsAtDisplayEdge() {
        var e = editor(with: CGRect(x: 0, y: 100, width: 200, height: 100))
        e.mouseDown(at: CGPoint(x: 4, y: 150), clickCount: 1)     // left handle, grabbed 4 pt right of centre
        e.mouseUp(at: CGPoint(x: -50, y: 150))
        #expect(e.selection == CGRect(x: 0, y: 100, width: 200, height: 100))
    }

    @Test func resizeToZeroRestoresOriginal() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var e = editor(with: rect)
        e.mouseDown(at: CGPoint(x: 300, y: 150), clickCount: 1)   // right handle
        e.mouseUp(at: CGPoint(x: 100, y: 150))
        #expect(e.selection == rect)
    }

    @Test func clickingAHandleOffCentreWithoutMovingKeepsSelection() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var e = editor(with: rect)
        e.mouseDown(at: CGPoint(x: 104, y: 104), clickCount: 1)   // inside top-left's hit area
        e.mouseUp(at: CGPoint(x: 104, y: 104))
        #expect(e.selection == rect)
    }

    // MARK: Full-display toggle (FR-23)

    @Test func doubleClickInsideTogglesFullDisplayAndBack() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var e = editor(with: rect)
        e.mouseDown(at: CGPoint(x: 150, y: 150), clickCount: 2)
        e.mouseUp(at: CGPoint(x: 150, y: 150))
        #expect(e.selection == display)
        e.mouseDown(at: CGPoint(x: 500, y: 400), clickCount: 2)
        e.mouseUp(at: CGPoint(x: 500, y: 400))
        #expect(e.selection == rect)
    }

    @Test func doubleClickTogglesEvenOnATinySelection() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 6, height: 6))   // interior covered by handle hit areas
        e.mouseDown(at: CGPoint(x: 103, y: 103), clickCount: 2)
        e.mouseUp(at: CGPoint(x: 103, y: 103))
        #expect(e.selection == display)
    }

    @Test func doubleClickOutsideWithoutSnapTargetsDoesNotToggle() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var e = editor(with: rect)
        e.mouseDown(at: CGPoint(x: 600, y: 600), clickCount: 2)
        e.mouseUp(at: CGPoint(x: 600, y: 600))
        #expect(e.selection == rect)
    }

    @Test func toggleWithoutSelectionSelectsDisplayThenClears() {
        var e = editor()
        e.toggleFullDisplay()
        #expect(e.selection == display)
        e.toggleFullDisplay()
        #expect(e.selection == nil)
    }

    @Test func toggleAfterEditingTheFullSelectionGoesFullAgain() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var e = editor(with: rect)
        e.toggleFullDisplay()
        e.nudge(dx: -10, dy: 0, resize: true)
        let shrunk = CGRect(x: 0, y: 0, width: 990, height: 800)
        #expect(e.selection == shrunk)
        e.toggleFullDisplay()
        #expect(e.selection == display)
        e.toggleFullDisplay()
        #expect(e.selection == shrunk)
    }

    @Test func commandsAreIgnoredMidDrag() {
        var e = editor(with: CGRect(x: 100, y: 100, width: 200, height: 100))
        e.mouseDown(at: CGPoint(x: 150, y: 150), clickCount: 1)
        e.mouseDragged(to: CGPoint(x: 160, y: 150))
        e.toggleFullDisplay()
        e.nudge(dx: 50, dy: 0, resize: false)
        #expect(e.selection == CGRect(x: 110, y: 100, width: 200, height: 100))
    }

    // MARK: Keyboard (FR-24)

    @Test func arrowNudgeMovesAndStopsAtEdgeWithoutShrinking() {
        var e = editor(with: CGRect(x: 0, y: 10, width: 50, height: 50))
        e.nudge(dx: -1, dy: 0, resize: false)
        #expect(e.selection == CGRect(x: 0, y: 10, width: 50, height: 50))
        e.nudge(dx: 2, dy: 2, resize: false)
        #expect(e.selection == CGRect(x: 2, y: 12, width: 50, height: 50))
    }

    @Test func nudgeWithoutSelectionDoesNothing() {
        var e = editor()
        e.nudge(dx: 5, dy: 5, resize: false)
        e.nudge(dx: 5, dy: 5, resize: true)
        #expect(e.selection == nil)
    }

    @Test func shiftArrowResizesFromBottomRight() {
        var e = editor(with: CGRect(x: 10, y: 10, width: 50, height: 50))
        e.nudge(dx: 1, dy: 0, resize: true)
        e.nudge(dx: 0, dy: -2, resize: true)
        #expect(e.selection == CGRect(x: 10, y: 10, width: 51, height: 48))
    }

    @Test func shiftArrowNeverShrinksBelowOnePoint() {
        var e = editor(with: CGRect(x: 10, y: 10, width: 1, height: 1))
        e.nudge(dx: -2, dy: -2, resize: true)
        #expect(e.selection == CGRect(x: 10, y: 10, width: 1, height: 1))
    }

    @Test func shiftArrowGrowthIsCappedAtDisplayEdges() {
        var e = editor(with: CGRect(x: 900, y: 700, width: 99, height: 99))
        e.nudge(dx: 2, dy: 2, resize: true)
        #expect(e.selection == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    // MARK: Commands

    @Test func clearSelectionRemovesIt() {
        var e = editor(with: CGRect(x: 10, y: 10, width: 10, height: 10))
        e.clearSelection()
        #expect(e.selection == nil)
    }

    @Test func selectClipsToDisplay() {
        var e = editor()
        e.select(CGRect(x: 900, y: -50, width: 300, height: 100))
        #expect(e.selection == CGRect(x: 900, y: 0, width: 100, height: 50))
    }

    @Test func selectOffDisplayOrTooSmallClears() {
        var e = editor(with: CGRect(x: 10, y: 10, width: 10, height: 10))
        e.select(CGRect(x: 2000, y: 2000, width: 50, height: 50))
        #expect(e.selection == nil)
        e.select(CGRect(x: 1000, y: 10, width: 50, height: 50))   // touches the right edge only
        #expect(e.selection == nil)
    }
}

struct SelectionEditorSnappingTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let window = CGRect(x: 100, y: 100, width: 400, height: 300)

    func editor() -> SelectionEditor {
        SelectionEditor(bounds: display, snapTargets: SnapTargets(windows: [window], display: display))
    }

    func click(_ editor: inout SelectionEditor, at point: CGPoint, count: Int = 1) -> Bool {
        editor.mouseDown(at: point, clickCount: count)
        return editor.mouseUp(at: point)
    }

    @Test func clickOnAWindowSelectsItsFrame() {
        var e = editor()
        let snapped = click(&e, at: CGPoint(x: 200, y: 200))
        #expect(snapped)
        #expect(e.selection == window)
    }

    @Test func clickOnTheDesktopSelectsTheWholeDisplay() {
        var e = editor()
        let snapped = click(&e, at: CGPoint(x: 900, y: 700))
        #expect(snapped)
        #expect(e.selection == display)
    }

    @Test func clickWithinTheDragThresholdStillSnaps() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 200, y: 200), clickCount: 1)
        e.mouseDragged(to: CGPoint(x: 202, y: 202))
        let snapped = e.mouseUp(at: CGPoint(x: 202, y: 202))
        #expect(snapped)
        #expect(e.selection == window)
    }

    @Test func dragIgnoresSnappingAndMakesAManualSelection() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 200, y: 200), clickCount: 1)
        e.mouseDragged(to: CGPoint(x: 260, y: 240))
        e.mouseUp(at: CGPoint(x: 260, y: 240))
        #expect(e.selection == CGRect(x: 200, y: 200, width: 60, height: 40))
    }

    @Test func clickOutsideTheSelectionSnapsAndReplacesIt() {
        var e = editor()
        e.select(CGRect(x: 600, y: 500, width: 100, height: 100))
        let snapped = click(&e, at: CGPoint(x: 200, y: 200))
        #expect(snapped)
        #expect(e.selection == window)
    }

    @Test func clickInsideTheSelectionKeepsIt() {
        var e = editor()
        let manual = CGRect(x: 600, y: 500, width: 100, height: 100)
        e.select(manual)
        let snapped = click(&e, at: CGPoint(x: 650, y: 550))
        #expect(snapped == false)
        #expect(e.selection == manual)
    }

    @Test func doubleClickOnAWindowSelectsItWithoutTogglingFullDisplay() {
        var e = editor()
        let first = click(&e, at: CGPoint(x: 200, y: 200))
        let second = click(&e, at: CGPoint(x: 200, y: 200), count: 2)
        #expect(first)
        #expect(second == false)
        #expect(e.selection == window)
        // A later double-click inside still toggles (FR-23).
        _ = click(&e, at: CGPoint(x: 200, y: 200), count: 2)
        #expect(e.selection == display)
    }

    @Test func theToggleTakesADesktopClickBackToNoSelection() {
        // OQ-16: so the pointer can hover and pick a window again.
        var e = editor()
        _ = click(&e, at: CGPoint(x: 900, y: 700))
        #expect(e.selection == display)
        e.toggleFullDisplay()
        #expect(e.selection == nil)
        #expect(e.snapHighlight(at: CGPoint(x: 200, y: 200)) == window)
    }

    @Test func theToggleAfterAWindowClickGoesFullAndBackToTheWindow() {
        var e = editor()
        _ = click(&e, at: CGPoint(x: 200, y: 200))
        e.toggleFullDisplay()
        #expect(e.selection == display)
        e.toggleFullDisplay()
        #expect(e.selection == window)
    }

    @Test func doubleClickOnTheDesktopSelectsTheDisplayWithoutToggling() {
        var e = editor()
        let first = click(&e, at: CGPoint(x: 900, y: 700))
        let second = click(&e, at: CGPoint(x: 900, y: 700), count: 2)
        #expect(first)
        #expect(second == false)
        #expect(e.selection == display)
        // A later double-click inside goes back to no selection (OQ-16).
        _ = click(&e, at: CGPoint(x: 900, y: 700), count: 2)
        #expect(e.selection == nil)
    }

    @Test func clickOnAHandleJustOutsideTheSelectionDoesNotSnap() {
        // Hit squares reach half their size past the border: here, over the window.
        var e = editor()
        let manual = CGRect(x: 200, y: 200, width: 100, height: 100)
        e.select(manual)
        let point = CGPoint(x: manual.minX - Handle.hitSize / 2 + 1, y: manual.minY - Handle.hitSize / 2 + 1)
        #expect(!manual.contains(point) && window.contains(point))
        #expect(Handle.hit(point, selection: manual) == .topLeft)
        let snapped = click(&e, at: point)
        #expect(snapped == false)
        #expect(e.selection == manual)
    }

    @Test func aClickWithSnappingOffDoesNothing() {
        var e = editor()
        e.mouseDown(at: CGPoint(x: 200, y: 200), clickCount: 1)
        let snapped = e.mouseUp(at: CGPoint(x: 200, y: 200), snapping: false)
        #expect(snapped == false)
        #expect(e.selection == nil)
        // A drag still makes a selection.
        e.mouseDown(at: CGPoint(x: 200, y: 200), clickCount: 1)
        e.mouseUp(at: CGPoint(x: 260, y: 240), snapping: false)
        #expect(e.selection == CGRect(x: 200, y: 200, width: 60, height: 40))
    }

    @Test func withoutSnapTargetsAClickDoesNothing() {
        var e = SelectionEditor(bounds: display)
        let snapped = click(&e, at: CGPoint(x: 200, y: 200))
        #expect(snapped == false)
        #expect(e.selection == nil)
        #expect(e.snapHighlight(at: CGPoint(x: 200, y: 200)) == nil)
    }

    @Test func highlightFollowsThePointerOnlyWithoutASelection() {
        var e = editor()
        #expect(e.snapHighlight(at: CGPoint(x: 200, y: 200)) == window)
        #expect(e.snapHighlight(at: CGPoint(x: 900, y: 700)) == display)
        #expect(e.snapHighlight(at: CGPoint(x: 5000, y: 5000)) == display)   // clamped onto the display
        e.mouseDown(at: CGPoint(x: 200, y: 200), clickCount: 1)
        #expect(e.snapHighlight(at: CGPoint(x: 200, y: 200)) == window)    // pressed, not yet a drag
        e.mouseDragged(to: CGPoint(x: 300, y: 300))
        #expect(e.snapHighlight(at: CGPoint(x: 300, y: 300)) == nil)       // drawing a selection
        e.mouseUp(at: CGPoint(x: 300, y: 300))
        #expect(e.snapHighlight(at: CGPoint(x: 900, y: 700)) == nil)       // a selection exists
    }
}
