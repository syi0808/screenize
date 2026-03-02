import Foundation
import SwiftUI

/// Identifies a specific segment in a specific track.
struct SegmentIdentifier: Hashable {
    let id: UUID
    let trackType: TrackType
}

/// Multi-select capable segment selection model.
struct SegmentSelection: Equatable {
    private(set) var segments: Set<SegmentIdentifier> = []

    var isEmpty: Bool { segments.isEmpty }
    var count: Int { segments.count }
    var isSingle: Bool { segments.count == 1 }

    /// Returns the single selected segment, or nil if not exactly one.
    var single: SegmentIdentifier? {
        isSingle ? segments.first : nil
    }

    /// Replace selection with a single segment.
    mutating func select(_ id: UUID, trackType: TrackType) {
        segments = [SegmentIdentifier(id: id, trackType: trackType)]
    }

    /// Toggle a segment in/out of selection (for Shift+Click).
    mutating func toggle(_ id: UUID, trackType: TrackType) {
        let ident = SegmentIdentifier(id: id, trackType: trackType)
        if segments.contains(ident) {
            segments.remove(ident)
        } else {
            segments.insert(ident)
        }
    }

    /// Add a segment to the selection.
    mutating func add(_ id: UUID, trackType: TrackType) {
        segments.insert(SegmentIdentifier(id: id, trackType: trackType))
    }

    /// Remove a segment by ID (regardless of track type).
    mutating func remove(_ id: UUID) {
        segments = segments.filter { $0.id != id }
    }

    /// Clear all selection.
    mutating func clear() {
        segments.removeAll()
    }

    /// Check if a segment ID is selected.
    func contains(_ id: UUID) -> Bool {
        segments.contains { $0.id == id }
    }
}

/// Snapshot of undoable editor state
struct EditorSnapshot {
    let timeline: Timeline
    let renderSettings: RenderSettings
    let selection: SegmentSelection
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
