import AppKit
import SwiftUI

/// The About window (FR-5): icon, name, version, copyright and acknowledgements. It has no links
/// and no buttons that open URLs.
struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    private let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        ?? "© 2026 SFS Tech"

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "Glint").font(.title.bold())
            Text("Version \(version) (build \(build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(verbatim: copyright).font(.callout)
            GroupBox("Acknowledgements") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "KeyboardShortcuts").bold()
                        // Plain text: the URL in the licence is not a link (FR-5).
                        Text(verbatim: Self.keyboardShortcutsLicense)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .frame(height: 160)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    /// KeyboardShortcuts' licence, which its MIT terms ask us to include.
    static let keyboardShortcutsLicense = """
        MIT License

        Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
