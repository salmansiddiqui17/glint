import AppKit
import GlintCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Preferences (FR-47). Everything applies immediately.
struct PreferencesView: View {
    @AppStorage(SettingsKey.saveAtStandardResolution)
    private var saveAtStandardResolution = SettingsDefault.saveAtStandardResolution
    @AppStorage(SettingsKey.defaultSaveFormat)
    private var defaultSaveFormat: ImageFormat = SettingsDefault.defaultSaveFormat
    @AppStorage(SettingsKey.redactionStyle)
    private var redactionStyle: RedactionStyle = SettingsDefault.redactionStyle
    @AppStorage(SettingsKey.snapsToWindows)
    private var snapsToWindows = SettingsDefault.snapsToWindows
    @State private var loginStatus = LoginItem.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(String(localized: "Capture shortcut:"), name: .captureScreenshot)
                .shortcutValidation(Self.validate)
                // FR-7: system shortcuts are rejected outright, with no "Use Anyway".
                .keyboardShortcutsConflictPolicy(.init(systemShortcut: .block))
                .help("Press a new shortcut, or clear it to use the menu only.")
            Toggle("Launch at login", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: { enabled in
                    do {
                        try LoginItem.setEnabled(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                    }
                    loginStatus = LoginItem.status
                }))
                .help("Starts Glint when you log in.")
            if loginStatus == .requiresApproval {
                HStack {
                    Text("Allow Glint in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items…") { LoginItem.openSystemSettings() }
                        .help("Opens System Settings › General › Login Items.")
                }
            }
            if let loginItemError {
                Text(loginItemError).font(.caption).foregroundStyle(.red)
            }
            // Off by default (OQ-21); read when a capture starts, so the next one follows it (FR-19).
            Toggle(isOn: $snapsToWindows) {
                Text("Select windows by clicking")
                Text("Hovering highlights the window under the pointer, and a click selects it.")
            }
            .help("When off, a capture just dims and you drag to select an area.")
            Toggle(isOn: $saveAtStandardResolution) {
                Text("Save at standard resolution (1×)")
                Text("Scales Retina captures down to their on-screen size in points.")
            }
            .help("Exports Retina captures at their on-screen size instead of full pixel resolution.")
            Picker("Default save format", selection: $defaultSaveFormat) {
                ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .help("The format the Save dialog starts with.")
            Picker(selection: $redactionStyle) {
                ForEach(RedactionStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                Text("Redaction style")
                Text("Pixelate is safer for text: a light blur can sometimes be reversed.")
            }
            .help("How the Redact tool (⌘B) hides what is under it.")
            ScreenRecordingRow()
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { loginStatus = LoginItem.status }
        // The user may change Login Items in System Settings while this window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = LoginItem.status
        }
    }

    /// Glint's own menu shortcuts, ⌘Q and ⌘, (FR-7). KeyboardShortcuts only checks the main menu,
    /// which an LSUIElement app doesn't have, and a global ⌘Q would hijack Quit in every app.
    /// Matched by the character the key types in the current layout, as menus do (AZERTY, Dvorak).
    private static func validate(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        let isMenuShortcut = shortcut.modifiers == .command
            && ["q", ","].contains(shortcut.nsMenuItemKeyEquivalent?.lowercased())
        return isMenuShortcut ? .disallow(reason: String(localized: "This shortcut is used by Glint's menu.")) : .allow
    }
}
