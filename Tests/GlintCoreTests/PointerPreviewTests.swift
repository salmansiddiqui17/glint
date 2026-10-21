import CoreGraphics
import Testing
@testable import GlintCore

struct PointerPreviewTests {
    let point = CGPoint(x: 50, y: 60)

    func preview(_ tool: Tool?, width: CGFloat = 3, drafting: Bool = false, overToolbars: Bool = false) -> PointerPreview? {
        PointerPreview(tool: tool, at: point, strokeWidth: width, drafting: drafting, overToolbars: overToolbars)
    }

    @Test func strokingToolsShowTheBrushCircle() {
        #expect(preview(.pencil, width: 5) == .brush(CGRect(x: 47.5, y: 57.5, width: 5, height: 5)))
        #expect(preview(.rectangle, width: 5, drafting: true, overToolbars: true)   // a drag can pass over a toolbar
                == .brush(CGRect(x: 47.5, y: 57.5, width: 5, height: 5)))
        #expect(preview(.marker, overToolbars: true) == nil)
    }

    @Test func redactShowsABarAsTallAsTheBandBeforeDragging() {
        #expect(preview(.redact) == .band(CGRect(x: 49, y: 51, width: 2, height: 18)))
        #expect(preview(.redact, width: 10) == .band(CGRect(x: 49, y: 30, width: 2, height: 60)))
        #expect(preview(.redact, drafting: true) == nil)                 // the dashed draft outline takes over
        #expect(preview(.redact, overToolbars: true) == nil)
    }

    @Test func otherwiseThereIsNoPreview() {
        #expect(preview(.text) == nil)
        #expect(preview(nil) == nil)
    }
}
