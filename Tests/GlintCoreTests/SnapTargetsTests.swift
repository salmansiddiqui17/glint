import CoreGraphics
import Testing
@testable import GlintCore

struct SnapFramesTests {
    func window(pid: Int = 10, layer: Int = 0, alpha: Double? = 1,
                x: Double = 0, y: Double = 0, width: Double = 400, height: Double = 300) -> [String: Any] {
        var window: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height],
        ]
        if let alpha { window[kCGWindowAlpha as String] = alpha }
        return window
    }

    @Test func keepsOtherAppsVisibleNormalWindowsInOrder() {
        let windows = [
            window(x: 10, y: 20),
            window(pid: 99),                  // Glint's own window
            window(layer: 25),                // menu extra
            window(x: 50, y: 60, width: 800, height: 600),
        ]
        #expect(WindowList.snapFrames(in: windows, excludingProcess: 99) == [
            CGRect(x: 10, y: 20, width: 400, height: 300), CGRect(x: 50, y: 60, width: 800, height: 600),
        ])
    }

    @Test func dropsTransparentWindows() {
        #expect(WindowList.snapFrames(in: [window(alpha: 0)], excludingProcess: 99).isEmpty)
        #expect(WindowList.snapFrames(in: [window(alpha: 0.01)], excludingProcess: 99).count == 1)
        #expect(WindowList.snapFrames(in: [window(alpha: nil)], excludingProcess: 99).count == 1)
    }

    @Test(arguments: [(39.0, 300.0), (300.0, 39.0), (1.0, 1.0)])
    func dropsWindowsUnder40Points(width: Double, height: Double) {
        #expect(WindowList.snapFrames(in: [window(width: width, height: height)], excludingProcess: 99).isEmpty)
    }

    @Test func keepsWindowsOfExactly40Points() {
        #expect(WindowList.snapFrames(in: [window(width: 40, height: 40)], excludingProcess: 99).count == 1)
    }

    @Test func dropsIncompleteEntries() {
        var noBounds = window()
        noBounds[kCGWindowBounds as String] = nil
        #expect(WindowList.snapFrames(in: [noBounds, [kCGWindowLayer as String: 0]], excludingProcess: 99).isEmpty)
    }
}

struct SnapTargetsTests {
    /// A 1000 × 800 display to the right of a main display, in global top-left coordinates.
    let display = CGRect(x: 1440, y: 0, width: 1000, height: 800)

    @Test func framesBecomeDisplayLocalAndClipped() {
        let targets = SnapTargets(windows: [
            CGRect(x: 1540, y: 100, width: 300, height: 200),   // inside
            CGRect(x: 1340, y: 700, width: 300, height: 200),   // over the left and bottom edges
            CGRect(x: 0, y: 0, width: 800, height: 600),        // on the main display only
        ], display: display)
        #expect(targets.bounds == CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(targets.frames == [
            CGRect(x: 100, y: 100, width: 300, height: 200), CGRect(x: 0, y: 700, width: 200, height: 100),
        ])
    }

    @Test func windowTouchingTheDisplayOnlyAtAnEdgeIsDropped() {
        let targets = SnapTargets(windows: [CGRect(x: 1040, y: 0, width: 400, height: 400)], display: display)
        #expect(targets.frames.isEmpty)
    }

    @Test func aWindowGrazingADisplayIsNoTargetThere() {
        // OQ-17: the 40 pt minimum applies to the part on each display, not only the whole window.
        let window = CGRect(x: 1142, y: 100, width: 300, height: 200)   // 2 pt onto `display`
        #expect(SnapTargets(windows: [window], display: display).frames.isEmpty)
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(SnapTargets(windows: [window], display: main).frames
            == [CGRect(x: 1142, y: 100, width: 298, height: 200)])
        let below = CGRect(x: 1540, y: 798, width: 300, height: 200)    // 2 pt tall on `display`
        #expect(SnapTargets(windows: [below], display: display).frames.isEmpty)
    }

    @Test func aPartExactly40PointsWideIsKept() {
        let targets = SnapTargets(windows: [CGRect(x: 1180, y: 100, width: 300, height: 200)], display: display)
        #expect(targets.frames == [CGRect(x: 0, y: 100, width: 40, height: 200)])
    }

    @Test func frontmostWindowUnderThePointerWins() {
        let front = CGRect(x: 1640, y: 200, width: 200, height: 200)
        let back = CGRect(x: 1540, y: 100, width: 600, height: 500)
        let targets = SnapTargets(windows: [front, back], display: display)
        #expect(targets.target(at: CGPoint(x: 250, y: 250)) == CGRect(x: 200, y: 200, width: 200, height: 200))
        #expect(targets.target(at: CGPoint(x: 150, y: 150)) == CGRect(x: 100, y: 100, width: 600, height: 500))
    }

    @Test func nothingUnderThePointerSelectsTheWholeDisplay() {
        let targets = SnapTargets(windows: [CGRect(x: 1540, y: 100, width: 300, height: 200)], display: display)
        #expect(targets.target(at: CGPoint(x: 900, y: 700)) == targets.bounds)
        #expect(SnapTargets(windows: [], display: display).target(at: .zero) == targets.bounds)
    }

    @Test func globalFrameFlipsAgainstTheMainDisplay() {
        // Main display 1440 × 900; a second display 1080 pt tall whose bottom sits 100 pt below
        // the main display's bottom edge, to its right.
        let appKit = CGRect(x: 1440, y: -100, width: 1920, height: 1080)
        #expect(SnapTargets.globalFrame(ofDisplay: appKit, mainDisplayHeight: 900)
            == CGRect(x: 1440, y: -80, width: 1920, height: 1080))
        #expect(SnapTargets.globalFrame(ofDisplay: CGRect(x: 0, y: 0, width: 1440, height: 900), mainDisplayHeight: 900)
            == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }
}
