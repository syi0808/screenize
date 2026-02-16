import Foundation
import SwiftUI

/// Snapshot of undoable editor state
struct EditorSnapshot {
    let timeline: Timeline
    let renderSettings: RenderSettings
    let selectedSegmentID: UUID?
    let selectedSegmentTrackType: TrackType?
}

/// Stack-based undo/redo manager for value-type state
@MainActor
final class UndoStack: ObservableObject {

    // MARK: - Published Properties

    /// Whether undo is available
    @Published private(set) var canUndo: Bool = false

    /// Whether redo is available
    @Published private(set) var canRedo: Bool = false

    // MARK: - Private Properties

    private var undoSnapshots: [EditorSnapshot] = []
    private var redoSnapshots: [EditorSnapshot] = []
    private let maxHistory: Int = 100

    // MARK: - Public Methods

    /// Save a snapshot before a mutation
    func push(_ snapshot: EditorSnapshot) {
        undoSnapshots.append(snapshot)
        if undoSnapshots.count > maxHistory {
            undoSnapshots.removeFirst()
        }
        // Any new edit invalidates the redo stack
        redoSnapshots.removeAll()
        updateState()
    }

    /// Undo: returns the previous snapshot, pushing current state to redo stack
    func undo(current: EditorSnapshot) -> EditorSnapshot? {
        guard let snapshot = undoSnapshots.popLast() else { return nil }
        redoSnapshots.append(current)
        updateState()
        return snapshot
    }

    /// Redo: returns the next snapshot, pushing current state to undo stack
    func redo(current: EditorSnapshot) -> EditorSnapshot? {
        guard let snapshot = redoSnapshots.popLast() else { return nil }
        undoSnapshots.append(current)
        updateState()
        return snapshot
    }

    /// Clear all history
    func clear() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        updateState()
    }

    // MARK: - Private Methods

    private func updateState() {
        canUndo = !undoSnapshots.isEmpty
        canRedo = !redoSnapshots.isEmpty
    }
}
