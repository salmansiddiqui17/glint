import Foundation
import GlintCore

/// UserDefaults keys (FR-47). Stable: never rename.
enum SettingsKey {
    static let saveAtStandardResolution = "saveAtStandardResolution"
    static let defaultSaveFormat = "defaultSaveFormat"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let hasRequestedScreenRecording = "hasRequestedScreenRecording"
    static let lastSaveDirectory = "lastSaveDirectory"
    static let redactionStyle = "redactionStyle"
    static let annotationColor = "annotationColor"
    static let strokeWidth = "strokeWidth"
    static let textFontSize = "textFontSize"
    static let textRecognitionWarmedUpBuild = "textRecognitionWarmedUpBuild"
}

/// Default values, shared by `AppSettings` and the SwiftUI `@AppStorage` declarations.
enum SettingsDefault {
    static let saveAtStandardResolution = false
    static let defaultSaveFormat = ImageFormat.png
    static let redactionStyle = RedactionStyle.pixelate
}

/// Typed access to Glint's preferences. SwiftUI views use `@AppStorage` with the same keys and
/// `SettingsDefault` values.
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var saveAtStandardResolution: Bool {
        get { defaults.object(forKey: SettingsKey.saveAtStandardResolution) as? Bool
            ?? SettingsDefault.saveAtStandardResolution }
        set { defaults.set(newValue, forKey: SettingsKey.saveAtStandardResolution) }
    }

    var defaultSaveFormat: ImageFormat {
        get { defaults.string(forKey: SettingsKey.defaultSaveFormat).flatMap(ImageFormat.init(rawValue:))
            ?? SettingsDefault.defaultSaveFormat }
        set { defaults.set(newValue.rawValue, forKey: SettingsKey.defaultSaveFormat) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: SettingsKey.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: SettingsKey.hasCompletedOnboarding) }
    }

    var redactionStyle: RedactionStyle {
        get { defaults.string(forKey: SettingsKey.redactionStyle).flatMap(RedactionStyle.init(rawValue:))
            ?? SettingsDefault.redactionStyle }
        set { defaults.set(newValue.rawValue, forKey: SettingsKey.redactionStyle) }
    }

    /// The drawing colour, width and text size, kept across captures and launches (FR-37, FR-38),
    /// with the redaction style from Preferences. Out-of-range stored values are clamped, and the
    /// colour is always opaque (Glint never writes another alpha; a hand-edited 0 would hide everything).
    var drawingStyle: DrawingStyle {
        get {
            DrawingStyle(
                color: (defaults.array(forKey: SettingsKey.annotationColor) as? [Double])
                    .flatMap(RGBAColor.init(components:))?.withAlpha(1) ?? .red,
                strokeWidth: defaults.object(forKey: SettingsKey.strokeWidth) as? Double
                    ?? DrawingLimits.defaultStrokeWidth,
                fontSize: defaults.object(forKey: SettingsKey.textFontSize) as? Double ?? DrawingLimits.defaultFontSize,
                redactionStyle: redactionStyle)
        }
        set {
            defaults.set(newValue.color.components, forKey: SettingsKey.annotationColor)
            defaults.set(Double(newValue.strokeWidth), forKey: SettingsKey.strokeWidth)
            defaults.set(Double(newValue.fontSize), forKey: SettingsKey.textFontSize)
        }
    }

    /// Folder of the last successful save (FR-44). Stored as a path; the save panel grants access.
    var lastSaveDirectory: URL? {
        get { defaults.string(forKey: SettingsKey.lastSaveDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: SettingsKey.lastSaveDirectory) }
    }

    /// The build whose text recognition warm-up last succeeded (OQ-18): see `TextRecognitionWarmUp`.
    var textRecognitionWarmedUpBuild: String? {
        get { defaults.string(forKey: SettingsKey.textRecognitionWarmedUpBuild) }
        set { defaults.set(newValue, forKey: SettingsKey.textRecognitionWarmedUpBuild) }
    }
}
