/// The annotations on one display, in drawing order, with undo and redo (FR-39).
///
/// Each committed annotation (a stroke, a shape, a text box, a redaction) is one undo step.
/// Drawing a new one clears the redo history. History starts empty with each capture.
public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undone.removeAll()
    }

    /// Removes the last annotation. Returns false when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = annotations.popLast() else { return false }
        undone.append(last)
        return true
    }

    /// Restores the last undone annotation. Returns false when there is nothing to redo.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = undone.popLast() else { return false }
        annotations.append(next)
        return true
    }
}
