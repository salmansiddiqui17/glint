/// Whether a recognition, or the launch warm-up, has finished since Glint launched, so Vision's
/// text model is ready and Copy Text keeps the shorter limit (FR-46, OQ-18).
@MainActor
enum TextRecognitionReadiness {
    static var hasFinished = false
}
