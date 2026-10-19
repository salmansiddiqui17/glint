import CoreGraphics
import Testing
@testable import GlintCore

struct OverlayLayoutTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let badge = CGSize(width: 90, height: 22)
    let toolbar = CGSize(width: 130, height: 32)

    // MARK: Badge (FR-25)

    @Test func badgeSitsAboveTopLeft() {
        let frame = OverlayLayout.badgeFrame(size: badge, selection: CGRect(x: 100, y: 100, width: 300, height: 200),
                                             bounds: display)
        #expect(frame == CGRect(x: 100, y: 73, width: 90, height: 22))
    }

    @Test func badgeStaysAboveWhenItExactlyFits() {
        let frame = OverlayLayout.badgeFrame(size: badge, selection: CGRect(x: 100, y: 27, width: 300, height: 200),
                                             bounds: display)
        #expect(frame == CGRect(x: 100, y: 0, width: 90, height: 22))
    }

    @Test func badgeMovesInsideWhenNoRoomAbove() {
        let frame = OverlayLayout.badgeFrame(size: badge, selection: CGRect(x: 100, y: 10, width: 300, height: 200),
                                             bounds: display)
        #expect(frame == CGRect(x: 105, y: 15, width: 90, height: 22))
    }

    @Test func badgeIsClampedHorizontally() {
        let frame = OverlayLayout.badgeFrame(size: badge, selection: CGRect(x: 950, y: 400, width: 50, height: 50),
                                             bounds: display)
        #expect(frame == CGRect(x: 910, y: 373, width: 90, height: 22))
    }

    @Test func badgeMovesInsideToAvoidTheToolbar() {
        let selection = CGRect(x: 100, y: 500, width: 100, height: 290)   // toolbar must go above
        let bar = OverlayLayout.actionToolbarFrame(size: toolbar, selection: selection, bounds: display)
        let frame = OverlayLayout.badgeFrame(size: badge, selection: selection, bounds: display, avoiding: bar)
        #expect(!frame.intersects(bar))
        #expect(frame == CGRect(x: 105, y: 505, width: 90, height: 22))
    }

    @Test func badgeStaysAboveWhenTheToolbarIsElsewhere() {
        let selection = CGRect(x: 100, y: 100, width: 300, height: 200)
        let bar = OverlayLayout.actionToolbarFrame(size: toolbar, selection: selection, bounds: display)
        let frame = OverlayLayout.badgeFrame(size: badge, selection: selection, bounds: display, avoiding: bar)
        #expect(frame == CGRect(x: 100, y: 73, width: 90, height: 22))
    }

    /// A tiny selection at the bottom edge: no room inside or below, and the toolbar sits above it.
    @Test func badgeGoesBesideOrAboveTheToolbarForATinySelectionAtTheBottom() {
        for (x, expected) in [(500.0, CGPoint(x: 375, y: 752)),   // left of the toolbar
                              (100.0, CGPoint(x: 70, y: 725))] {  // no room on the left: above it
            let selection = CGRect(x: x, y: 790, width: 100, height: 10)
            let bar = OverlayLayout.actionToolbarFrame(size: toolbar, selection: selection, bounds: display)
            let frame = OverlayLayout.badgeFrame(size: badge, selection: selection, bounds: display, avoiding: bar)
            #expect(display.contains(frame) && !frame.intersects(bar))
            #expect(frame.origin == expected)
        }
    }

    @Test func badgeHonoursNonZeroOriginBounds() {
        let left = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        let frame = OverlayLayout.badgeFrame(size: badge, selection: CGRect(x: -1440, y: -100, width: 40, height: 40),
                                             bounds: left)
        #expect(frame == CGRect(x: -1435, y: -95, width: 90, height: 22))
    }

    // MARK: Action toolbar (FR-26)

    @Test func toolbarDefaultsBelowRightAligned() {
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar,
                                                     selection: CGRect(x: 100, y: 100, width: 300, height: 200),
                                                     bounds: display)
        #expect(frame == CGRect(x: 270, y: 306, width: 130, height: 32))
    }

    @Test func toolbarFitsBelowExactly() {
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar,
                                                     selection: CGRect(x: 100, y: 100, width: 300, height: 662),
                                                     bounds: display)
        #expect(frame == CGRect(x: 270, y: 768, width: 130, height: 32))
    }

    @Test func toolbarGoesAboveWhenNoRoomBelow() {
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar,
                                                     selection: CGRect(x: 100, y: 500, width: 300, height: 290),
                                                     bounds: display)
        #expect(frame == CGRect(x: 270, y: 462, width: 130, height: 32))
    }

    @Test func toolbarGoesInsideForFullDisplaySelection() {
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar, selection: display, bounds: display)
        #expect(frame == CGRect(x: 864, y: 762, width: 130, height: 32))
    }

    @Test func toolbarIsClampedForNarrowSelectionAtLeftEdge() {
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar,
                                                     selection: CGRect(x: 0, y: 100, width: 40, height: 40),
                                                     bounds: display)
        #expect(frame == CGRect(x: 0, y: 146, width: 130, height: 32))
    }

    @Test func narrowSelectionInBottomLeftCornerGetsToolbarAboveNotOnTop() {
        let selection = CGRect(x: 0, y: 770, width: 40, height: 30)
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar, selection: selection, bounds: display)
        #expect(frame == CGRect(x: 0, y: 732, width: 130, height: 32))
        #expect(!frame.intersects(selection))
    }

    @Test func insideIsOnlyUsedWhenTheToolbarFitsInsideTheSelection() {
        let tallNarrow = CGRect(x: 500, y: 0, width: 40, height: 800)
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar, selection: tallNarrow, bounds: display)
        #expect(frame == CGRect(x: 410, y: 768, width: 130, height: 32))   // clamped "below"
    }

    @Test func toolbarHonoursNonZeroOriginBounds() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = OverlayLayout.actionToolbarFrame(size: toolbar,
                                                     selection: CGRect(x: -1440, y: 100, width: 40, height: 40),
                                                     bounds: left)
        #expect(frame == CGRect(x: -1440, y: 146, width: 130, height: 32))
    }

    // MARK: Tools palette (FR-26)

    let palette = CGSize(width: 32, height: 332)

    func layout(_ selection: CGRect, in bounds: CGRect? = nil) -> (palette: CGRect, toolbar: CGRect) {
        let bounds = bounds ?? display
        let bar = OverlayLayout.actionToolbarFrame(size: toolbar, selection: selection, bounds: bounds)
        return (OverlayLayout.toolsPaletteFrame(size: palette, selection: selection, bounds: bounds, avoiding: bar), bar)
    }

    @Test func paletteSitsRightOfTheSelectionBottomAligned() {
        let frame = layout(CGRect(x: 100, y: 100, width: 300, height: 400)).palette
        #expect(frame == CGRect(x: 406, y: 168, width: 32, height: 332))
    }

    @Test func paletteStaysOnTheDisplayForAShortSelectionNearTheTop() {
        let frame = layout(CGRect(x: 100, y: 10, width: 300, height: 50)).palette
        #expect(frame == CGRect(x: 406, y: 0, width: 32, height: 332))
    }

    @Test func paletteGoesLeftWhenThereIsNoRoomOnTheRight() {
        let frame = layout(CGRect(x: 600, y: 100, width: 380, height: 400)).palette
        #expect(frame == CGRect(x: 562, y: 168, width: 32, height: 332))
    }

    @Test func paletteGoesInsideTheRightEdgeWhenBothSidesAreFull() {
        let frame = layout(CGRect(x: 20, y: 100, width: 960, height: 600)).palette
        #expect(frame == CGRect(x: 942, y: 362, width: 32, height: 332))
    }

    @Test func fullDisplayPaletteStacksAboveTheInsideToolbar() {
        let (frame, bar) = layout(display)
        #expect(bar.maxY == display.maxY - 6)                 // the action toolbar is inside, bottom-right
        #expect(frame == CGRect(x: 962, y: bar.minY - 6 - 332, width: 32, height: 332))
    }

    @Test func paletteGoesBesideAToolbarThatWasPushedUnderIt() {
        // A tiny selection at the left edge: the clamped toolbar runs under the palette's usual spot.
        let (frame, bar) = layout(CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(bar == CGRect(x: 0, y: 8, width: 130, height: 32))
        #expect(frame == CGRect(x: 136, y: 0, width: 32, height: 332))
    }

    @Test func paletteGoesBesideTheToolbarForATinySelectionInTheBottomRightCorner() {
        // The toolbar sits above the selection; the palette goes beside it, not stacked above it.
        let (frame, bar) = layout(CGRect(x: 990, y: 790, width: 10, height: 10))
        #expect(bar == CGRect(x: 870, y: 752, width: 130, height: 32))
        #expect(frame == CGRect(x: 832, y: 452, width: 32, height: 332))
    }

    @Test func paletteTallerThanTheDisplayIsPinnedToTheTop() {
        let short = CGRect(x: 0, y: 100, width: 1280, height: 300)
        let (frame, _) = layout(CGRect(x: 100, y: 150, width: 200, height: 100), in: short)
        #expect(frame.minY == short.minY)
    }

    @Test func badgeStepsAsideFromThePaletteBesideANarrowSelection() {
        let selection = CGRect(x: 500, y: 400, width: 50, height: 50)
        let (frame, bar) = layout(selection)
        let badgeFrame = OverlayLayout.badgeFrame(size: badge, selection: selection, bounds: display,
                                                  avoiding: bar, palette: frame)
        #expect(badgeFrame == CGRect(x: 461, y: 373, width: 90, height: 22))   // still above, left of the palette
    }

    @Test(arguments: [CGSize(width: 130, height: 32), CGSize(width: 92, height: 32)])   // 92 × 32 is ActionToolbar.size
    func toolbarsAndBadgeNeverLeaveTheDisplayNorOverlap(toolbar bar: CGSize) {
        let displays = [display, CGRect(x: -1440, y: -300, width: 1440, height: 900),
                        CGRect(x: 0, y: 0, width: 1024, height: 600), CGRect(x: 2000, y: -200, width: 600, height: 1024),
                        CGRect(x: 0, y: 0, width: 1280, height: 340)]
        for bounds in displays {
            for x in stride(from: bounds.minX, to: bounds.maxX - 2, by: 97) {
                for y in stride(from: bounds.minY, to: bounds.maxY - 2, by: 89) {
                    let sizes = [CGSize(width: 2, height: 2), CGSize(width: 60, height: 60), CGSize(width: 40, height: 800),
                                 CGSize(width: 300, height: 120), CGSize(width: bounds.maxX - x, height: 60),
                                 CGSize(width: bounds.maxX - x, height: bounds.maxY - y)]
                    for size in sizes {
                        let selection = CGRect(origin: CGPoint(x: x, y: y), size: size).intersection(bounds)
                        let toolbarFrame = OverlayLayout.actionToolbarFrame(size: bar, selection: selection,
                                                                            bounds: bounds)
                        let frame = OverlayLayout.toolsPaletteFrame(size: palette, selection: selection, bounds: bounds,
                                                                    avoiding: toolbarFrame)
                        let badgeFrame = OverlayLayout.badgeFrame(size: badge, selection: selection, bounds: bounds,
                                                                  avoiding: toolbarFrame, palette: frame)
                        guard bounds.contains(frame), !frame.intersects(toolbarFrame), bounds.contains(badgeFrame),
                              !badgeFrame.intersects(frame), !badgeFrame.intersects(toolbarFrame) else {
                            Issue.record("selection \(selection), palette \(frame), toolbar \(toolbarFrame), badge \(badgeFrame)")
                            return
                        }
                    }
                }
            }
        }
    }
}
