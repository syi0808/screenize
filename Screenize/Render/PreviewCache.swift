import Foundation
import CoreGraphics

/// Preview frame cache
/// Caches recently used frames using an LRU policy
final class PreviewCache {

    // MARK: - Properties

    /// Cached frames (frameIndex → CGImage)
    private var cache: [Int: CGImage] = [:]

    /// LRU order (oldest frames at the front)
    private var accessOrder: [Int] = []

    /// Maximum cache size (number of frames)
    private let maxSize: Int

    /// Invalidated frame ranges
    private var dirtyRanges: [Range<Int>] = []

    /// Synchronize concurrent access
    private let lock = NSLock()

    // MARK: - Initialization

    init(maxSize: Int = 60) {
        self.maxSize = maxSize
    }

    // MARK: - Cache Access

    /// Retrieve a frame from the cache
    /// - Parameter index: Frame index
    /// - Returns: Cached image (nil if missing or invalidated)
    func frame(at index: Int) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        // Skip if the frame is invalidated
        if isDirty(index) {
            cache.removeValue(forKey: index)
            accessOrder.removeAll { $0 == index }
            return nil
        }

        guard let image = cache[index] else {
            return nil
        }

        // Update LRU order
        accessOrder.removeAll { $0 == index }
        accessOrder.append(index)

        return image
    }

    /// Store a frame in the cache
    /// - Parameters:
    ///   - image: Image to store
    ///   - index: Frame index
    func store(_ image: CGImage, at index: Int) {
        lock.lock()
        defer { lock.unlock() }

        // Do not store if the frame falls within an invalidated range
        if isDirty(index) {
            return
        }

        // If the cache is full, remove the oldest entry
        while cache.count >= maxSize, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        // Store the frame
        cache[index] = image
        accessOrder.removeAll { $0 == index }
        accessOrder.append(index)
    }

    // MARK: - Invalidation

    /// Invalidate a range of frames
    /// - Parameters:
    ///   - startFrame: Starting frame
    ///   - endFrame: Ending frame
    func invalidate(from startFrame: Int, to endFrame: Int) {
        lock.lock()
        defer { lock.unlock() }

        let range = startFrame..<(endFrame + 1)
        dirtyRanges.append(range)

        // Remove cached frames in that range
        for index in range {
            if cache.removeValue(forKey: index) != nil {
                accessOrder.removeAll { $0 == index }
            }
        }

        // Merge dirty ranges for optimization
        mergeOverlappingRanges()
    }

    /// Invalidate the entire cache
    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
        dirtyRanges.removeAll()
    }

    /// Clear dirty ranges (called when starting a new render)
    func clearDirtyRanges() {
        lock.lock()
        defer { lock.unlock() }

        dirtyRanges.removeAll()
    }

    // MARK: - Status

    /// Number of cached frames
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    /// Whether the cache is empty
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache.isEmpty
    }

    /// Whether a specific frame is cached
    func isCached(_ index: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[index] != nil && !isDirty(index)
    }

    // MARK: - Private Helpers

    /// Check whether a given index falls within a dirty range
    private func isDirty(_ index: Int) -> Bool {
        for range in dirtyRanges {
            if range.contains(index) {
                return true
            }
        }
        return false
    }

    /// Merge overlapping dirty ranges
    private func mergeOverlappingRanges() {
        guard dirtyRanges.count > 1 else { return }

        // Sort by start point
        dirtyRanges.sort { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        var current = dirtyRanges[0]

        for i in 1..<dirtyRanges.count {
            let next = dirtyRanges[i]

            if current.upperBound >= next.lowerBound {
                // Overlapping ranges – merge them
                current = current.lowerBound..<max(current.upperBound, next.upperBound)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)

        dirtyRanges = merged
    }
}

// MARK: - Cache Statistics

extension PreviewCache {
    /// Cache statistics
    struct Statistics {
        let cachedFrameCount: Int
        let maxSize: Int
        let dirtyRangeCount: Int
        let utilizationPercent: Double
    }

    /// Current cache statistics
    var statistics: Statistics {
        lock.lock()
        defer { lock.unlock() }

        return Statistics(
            cachedFrameCount: cache.count,
            maxSize: maxSize,
            dirtyRangeCount: dirtyRanges.count,
            utilizationPercent: Double(cache.count) / Double(maxSize) * 100
        )
    }
}
