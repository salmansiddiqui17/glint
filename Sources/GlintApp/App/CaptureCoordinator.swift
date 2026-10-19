import AppKit
import GlintCore
import os
import ScreenCaptureKit

/// Turns a trigger (hotkey, menu, re-open) into a capture session (FR-9, FR-12, FR-14, FR-15).
@MainActor
final class CaptureCoordinator {
    private let settings: AppSettings
    private let exporter: Exporter
    private let showOnboarding: () -> Void
    private var session: CaptureSession?
    private var isCapturing = false
    private let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "capture")

    init(settings: AppSettings, exporter: Exporter, showOnboarding: @escaping () -> Void) {
        self.settings = settings
        self.exporter = exporter
        self.showOnboarding = showOnboarding
    }

    func start() {
        guard session == nil, !isCapturing else { return }        // FR-9: ignore while capturing
        guard ScreenRecordingPermission.isGranted else { return showOnboarding() }
        isCapturing = true
        let started = ContinuousClock.now
        Task {
            defer { isCapturing = false }
            do {
                let captures = try await ScreenCapturer.captureAllDisplays()
                let session = CaptureSession(captures: captures, exporter: exporter, settings: settings) {
                    self.session = nil   // coordinator lives for the app's lifetime
                }
                self.session = session
                session.begin()
                logger.notice("capture ready: \(captures.count) display(s) in \(milliseconds(since: started)) ms")   // NFR-1
            } catch {
                logger.error("capture failed: \(String(describing: error), privacy: .public)")
                if Self.isPermissionFailure(error) {
                    showOnboarding()                                // FR-12
                } else {
                    NSSound.beep()                                  // timeout, display change: cancel quietly
                }
            }
        }
    }

    /// Screen Recording was refused or revoked, as opposed to a timeout or a display change. When
    /// every display failed, any one display's refusal counts.
    private static func isPermissionFailure(_ error: any Error) -> Bool {
        let errors = (error as? AllFailedError)?.errors ?? [error]
        if errors.contains(where: { ($0 as? SCStreamError)?.code == .userDeclined }) { return true }
        return !ScreenRecordingPermission.isGranted
    }
}
