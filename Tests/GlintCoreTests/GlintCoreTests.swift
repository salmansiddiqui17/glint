import Testing
@testable import GlintCore

@Test func bundleIdentifierIsGlint() {
    #expect(GlintCore.bundleIdentifier == "com.salmanfurqan.glint")
}
