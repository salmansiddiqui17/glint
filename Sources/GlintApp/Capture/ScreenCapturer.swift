import AppKit
import GlintCore
import os
import ScreenCaptureKit

/// A frozen still image of one display, at native pixels, without the cursor (FR-14).
///
/// The display's geometry is snapshotted at capture time, so later display changes can't make the
/// overlay, crop or badge disagree with the image.
struct DisplayCapture {
    /// The display's frame (global points) when it was captured.
    let frame: CGRect
    let image: CGImage
    /// Pixels per point of the frozen image, from what ScreenCaptureKit actually returned.
    var scale: CGFloat { CGFloat(image.width) / frame.width }
}

enum CaptureError: Error {
    /// No connected display could be matched to ScreenCaptureKit's display list.
    case noDisplays
    /// Displays were added, removed or reconfigured while capturing (NFR-9).
    case displaysChanged
    /// ScreenCaptureKit returned an image whose aspect ratio doesn't match its display.
    case mismatchedImage
}

@MainActor
enum ScreenCapturer {
    /// Per-call limit for ScreenCaptureKit, whose calls can't be cancelled.
    nonisolated static let timeout: Duration = .seconds(2)
    private static let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "capture")

    /// Captures every connected display concurrently. Displays that fail or time out are skipped
    /// (FR-15); if all fail, `AllFailedError` carries every display's error (`TimeoutError` for a
    /// timeout). Throws `CaptureError.displaysChanged` if the display set changed while capturing.
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let before = displayLayout()
        let started = ContinuousClock.now
        let content = try await withTimeout(timeout) {
            UncheckedSendable(try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
        }.value
        logger.info("shareable content in \(milliseconds(since: started)) ms")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        var jobs: [(frame: CGRect, filter: SCContentFilter, configuration: SCStreamConfiguration)] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                logger.error("no ScreenCaptureKit display for screen \(screen.displayID ?? 0)")
                continue
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            // Size from the filter (Apple's recommendation); it matches the display it captures.
            let pixelScale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * pixelScale).rounded())
            configuration.height = Int((filter.contentRect.height * pixelScale).rounded())
            configuration.captureResolution = .best    // render at backing resolution, not upscaled
            configuration.showsCursor = false
            configuration.captureDynamicRange = .SDR   // NFR-10: P1 captures are SDR
            // colorSpaceName is left unset: ScreenCaptureKit then uses the display's own colour space.
            jobs.append((screen.frame, filter, configuration))
        }
        guard !jobs.isEmpty else { throw CaptureError.noDisplays }

        var results = [Result<CGImage, any Error>?](repeating: nil, count: jobs.count)
        await withTaskGroup(of: (Int, Result<CGImage, any Error>).self) { group in
            for (index, job) in jobs.enumerated() {
                // Both objects are fully configured above and never mutated again.
                let request = UncheckedSendable((job.filter, job.configuration))
                group.addTask {
                    do {
                        let image = try await withTimeout(timeout) {
                            let (filter, configuration) = request.value
                            return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                              configuration: configuration)
                        }
                        return (index, .success(image))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group { results[index] = result }
        }
        logger.info("captured \(jobs.count) display(s) in \(milliseconds(since: started)) ms")
        guard displayLayout() == before else { throw CaptureError.displaysChanged }

        let captures = zip(jobs, results).map { job, result -> Result<DisplayCapture, any Error> in
            switch result {
            case let .success(image)?:
                // The image's aspect must match the display, or y would be misaligned with the overlay.
                let widthScale = CGFloat(image.width) / job.frame.width
                let heightScale = CGFloat(image.height) / job.frame.height
                guard abs(widthScale - heightScale) < 0.01 else {
                    logger.error("capture \(image.width)x\(image.height) doesn't match display \(job.frame.debugDescription, privacy: .public)")
                    return .failure(CaptureError.mismatchedImage)
                }
                return .success(DisplayCapture(frame: job.frame, image: image))
            case let .failure(error)?:
                logger.error("display capture failed: \(error.localizedDescription, privacy: .public)")
                return .failure(error)
            case nil:
                assertionFailure("every capture task returns a result")
                return .failure(CaptureError.noDisplays)
            }
        }
        return try PartialResults.successes(captures)
    }

    /// Identity and geometry of every display, to detect changes during a capture.
    static func displayLayout() -> [String] {
        NSScreen.screens.map { "\($0.displayID ?? 0) \($0.frame) \($0.backingScaleFactor)" }
    }
}

/// Hands an immutable, non-Sendable value to a concurrent task.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Milliseconds elapsed since `start`, for latency logs (NFR-1).
func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
    let elapsed = (ContinuousClock.now - start).components
    return elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
