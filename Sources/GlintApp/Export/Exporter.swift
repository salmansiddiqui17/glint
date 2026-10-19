import AppKit
import GlintCore
import os
import UniformTypeIdentifiers

/// Copy to the clipboard (FR-43) and Save… (FR-44).
@MainActor
final class Exporter {
    private let settings: AppSettings
    private let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "export")

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Writes PNG and TIFF representations in one step, once both are encoded; no notification.
    /// Encoding runs off the main thread (a full 5K display takes a few hundred milliseconds), so
    /// the hotkey and menu stay responsive.
    func copy(_ image: CGImage, dpi: CGFloat) async {
        let started = ContinuousClock.now
        let (png, tiff) = await Task.detached {
            (ImageEncoder.encode(image, as: .png, dpi: dpi), Self.tiffData(image, dpi: dpi))
        }.value
        let item = NSPasteboardItem()
        if let png { item.setData(png, forType: .png) }
        if let tiff { item.setData(tiff, forType: .tiff) }
        // Leave the user's clipboard alone if nothing could be encoded.
        guard !item.types.isEmpty else { return NSSound.beep() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        logger.notice("copied \(image.width)x\(image.height) in \(milliseconds(since: started)) ms")   // NFR-3
    }

    /// Save dialog with a Format pop-up; remembers the folder. Cancel discards the capture.
    func save(_ image: CGImage, dpi: CGFloat) async {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        // The last folder may have been deleted or its volume unmounted; fall back to the Desktop.
        let lastFolder = settings.lastSaveDirectory.flatMap { url -> URL? in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? url : nil
        }
        panel.directoryURL = lastFolder ?? Self.realDesktop
        let accessory = SaveFormatAccessory(format: settings.defaultSaveFormat)
        let apply = { [weak panel] (format: ImageFormat) in
            guard let panel else { return }
            panel.allowedContentTypes = [format.contentType]
            panel.nameFieldStringValue = FileNaming.fileName(panel.nameFieldStringValue, withExtensionOf: format)
        }
        panel.nameFieldStringValue = FileNaming.defaultFileName(for: Date(), format: accessory.format)
        apply(accessory.format)
        accessory.onChange = apply
        panel.accessoryView = accessory.view

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let format = accessory.format
        let started = ContinuousClock.now
        let data = await Task.detached { ImageEncoder.encode(image, as: format, dpi: dpi) }.value
        logger.notice("encoded \(image.width)x\(image.height) for saving in \(milliseconds(since: started)) ms")   // NFR-3
        do {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            settings.lastSaveDirectory = url.deletingLastPathComponent()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// TIFF with the display's colour profile and a DPI tag, so TIFF-only apps paste it at its
    /// on-screen size.
    private nonisolated static func tiffData(_ image: CGImage, dpi: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) * 72 / dpi, height: CGFloat(image.height) * 72 / dpi)
        return rep.tiffRepresentation
    }

    /// The user's real Desktop (inside the sandbox, the home directory is the app container).
    private static var realDesktop: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true).appendingPathComponent("Desktop")
    }
}

/// "Format: [PNG ▾]" accessory for the save panel.
@MainActor
final class SaveFormatAccessory: NSObject {
    let view: NSStackView
    private(set) var format: ImageFormat
    var onChange: ((ImageFormat) -> Void)?
    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)

    init(format: ImageFormat) {
        self.format = format
        let label = NSTextField(labelWithString: "Format:")
        view = NSStackView(views: [label, popUp])
        super.init()
        view.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        popUp.addItems(withTitles: ImageFormat.allCases.map(\.displayName))
        popUp.selectItem(at: ImageFormat.allCases.firstIndex(of: format) ?? 0)
        popUp.setAccessibilityTitleUIElement(label)   // VoiceOver: "Format, PNG, pop-up button"
        popUp.target = self
        popUp.action = #selector(changed)
        view.setFrameSize(view.fittingSize)
    }

    @objc private func changed() {
        format = ImageFormat.allCases[popUp.indexOfSelectedItem]
        onChange?(format)
    }
}
