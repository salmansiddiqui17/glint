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
        // At trigger time, like the frozen image (FR-16). Read now, so a change in Preferences
        // applies to the next capture; with snapping off, no window list is taken (OQ-21).
        let windows = settings.snapsToWindows ? WindowSnapshot.current() : nil
        Task {
            defer { isCapturing = false }
            do {
                let captures = try await ScreenCapturer.captureAllDisplays()
                let session = CaptureSession(captures: captures, windows: windows, exporter: exporter,
                                             settings: settings) {
                    self.session = nil   // coordinator lives for the app's lifetime
                    self.returnFreedMemory()
                }
                self.session = session
                session.begin()
                // Counts only, never window details (§7.2).
                logger.notice("capture ready: \(captures.count) display(s), snap \(windows.map { "\($0.frames.count) window(s)" } ?? "off", privacy: .public) in \(milliseconds(since: started)) ms")   // NFR-1
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

    /// Hands the allocator's free pages back to macOS once a capture's peak (frozen images,
    /// Vision) is gone, or the idle footprint stays near that peak (NFR-5, NFR-6). A second
    /// later, so the session is released and its panels' close task and autorelease pools have run.
    private func returnFreedMemory() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard session == nil, !isCapturing else { return }   // the next capture is using it
            let freed = malloc_zone_pressure_relief(nil, 0)
            logger.info("returned \(freed / 1024) KB to the system after a capture")
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
