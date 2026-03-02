import Foundation
import Metal

/// GPU-resident texture cache for preview frames
/// LRU eviction with dirty range tracking, replaces PreviewCache for Metal pipeline
final class PreviewTextureCache {

    // MARK: - Properties

    /// Cached textures (frameIndex -> MTLTexture)
    private var cache: [Int: MTLTexture] = [:]

    /// LRU order (oldest frames at front)
    private var accessOrder: [Int] = []

    /// Maximum cache size (number of frames)
    private let maxSize: Int

    /// Invalidated frame ranges
    private var dirtyRanges: [Range<Int>] = []

    /// Synchronize concurrent access
    private let lock = NSLock()

    /// Metal device for texture allocation
    private let device: MTLDevice

    /// Texture descriptor template (all cache textures share dimensions + format)
    private let textureDescriptor: MTLTextureDescriptor

    /// Pool of reusable textures (returned from eviction)
    private var texturePool: [MTLTexture] = []

    // MARK: - Initialization

    /// - Parameters:
    ///   - device: Metal device for texture allocation
    ///   - width: Texture width in pixels
    ///   - height: Texture height in pixels
    ///   - maxSize: Maximum number of cached frames
    init(device: MTLDevice, width: Int, height: Int, maxSize: Int = 60) {
        self.device = device
        self.maxSize = maxSize

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
        descriptor.storageMode = .shared // Required by CIContext.render and CIImage(mtlTexture:)
        self.textureDescriptor = descriptor
    }

    // MARK: - Cache Access

    /// Retrieve a cached texture
    /// - Parameter index: Frame index
    /// - Returns: Cached texture (nil if missing or invalidated)
    func texture(at index: Int) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }

        if isDirty(index) {
            if let tex = cache.removeValue(forKey: index) {
                texturePool.append(tex)
            }
            accessOrder.removeAll { $0 == index }
            return nil
        }

        guard let tex = cache[index] else { return nil }

        // Update LRU order
        accessOrder.removeAll { $0 == index }
        accessOrder.append(index)
        return tex
    }

    /// Store a texture in the cache
    /// - Parameters:
    ///   - texture: Texture to cache
    ///   - index: Frame index
    func store(_ texture: MTLTexture, at index: Int) {
        lock.lock()
        defer { lock.unlock() }

        if isDirty(index) { return }

        // Evict oldest if cache is full
        while cache.count >= maxSize, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                texturePool.append(evicted)
            }
        }

        // Return overwritten texture to pool (prevents leak on VFR key collisions)
        if let old = cache.removeValue(forKey: index) {
            texturePool.append(old)
        }

        cache[index] = texture
        accessOrder.removeAll { $0 == index }
        accessOrder.append(index)
    }

    /// Acquire a texture from the pool or allocate a new one
    /// - Returns: Reusable or newly allocated texture
    func acquireTexture() -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }

        if let pooled = texturePool.popLast() {
            return pooled
        }
        return device.makeTexture(descriptor: textureDescriptor)
    }

    // MARK: - Invalidation

    /// Invalidate cached frames within a range
    func invalidate(from startFrame: Int, to endFrame: Int) {
        lock.lock()
        defer { lock.unlock() }

        let range = startFrame..<(endFrame + 1)
        dirtyRanges.append(range)

        for index in range {
            if let evicted = cache.removeValue(forKey: index) {
                texturePool.append(evicted)
                accessOrder.removeAll { $0 == index }
            }
        }

        mergeOverlappingRanges()
    }

    /// Invalidate the entire cache
    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }

        for (_, tex) in cache {
            texturePool.append(tex)
        }
        cache.removeAll()
        accessOrder.removeAll()
        dirtyRanges.removeAll()
    }

    /// Clear dirty ranges
    func clearDirtyRanges() {
        lock.lock()
        defer { lock.unlock() }
        dirtyRanges.removeAll()
    }

    // MARK: - Status

    /// Texture width in pixels
    var textureWidth: Int { textureDescriptor.width }

    /// Texture height in pixels
    var textureHeight: Int { textureDescriptor.height }

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

    // MARK: - Private

    private func isDirty(_ index: Int) -> Bool {
        guard !dirtyRanges.isEmpty else { return false }
        var lo = 0, hi = dirtyRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if dirtyRanges[mid].contains(index) { return true }
            if index < dirtyRanges[mid].lowerBound { hi = mid - 1 }
            else { lo = mid + 1 }
        }
        return false
    }

    private func mergeOverlappingRanges() {
        guard dirtyRanges.count > 1 else { return }

        dirtyRanges.sort { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        var current = dirtyRanges[0]

        for i in 1..<dirtyRanges.count {
            let next = dirtyRanges[i]
            if current.upperBound >= next.lowerBound {
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

// MARK: - Statistics

extension PreviewTextureCache {

    struct Statistics {
        let cachedFrameCount: Int
        let maxSize: Int
        let dirtyRangeCount: Int
        let utilizationPercent: Double
        let poolSize: Int
    }

    var statistics: Statistics {
        lock.lock()
        defer { lock.unlock() }

        return Statistics(
            cachedFrameCount: cache.count,
            maxSize: maxSize,
            dirtyRangeCount: dirtyRanges.count,
            utilizationPercent: Double(cache.count) / Double(maxSize) * 100,
            poolSize: texturePool.count
        )
    }
}
