import XCTest
@testable import Screenize

final class SpringSimulationCacheTests: XCTestCase {

    func test_lookup_emptyCache_returnsNil() {
        let cache = SpringSimulationCache()
        XCTAssertNil(cache.transforms(for: UUID()))
    }

    func test_simulateAndLookup_manualSegments_returnsCachedTransforms() {
        let cache = SpringSimulationCache()
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(
                startTransform: TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)),
                endTransform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
            )
        )
        cache.populate(segments: [segment])
        let result = cache.transforms(for: segment.id)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
    }

    func test_lookup_continuousSegment_returnsNil() {
        let cache = SpringSimulationCache()
        let transform = TimedTransform(
            time: 0,
            transform: TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        )
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .continuous(transforms: [transform])
        )
        cache.populate(segments: [segment])
        XCTAssertNil(cache.transforms(for: segment.id))
    }

    func test_invalidate_clearsAllCachedTransforms() {
        let cache = SpringSimulationCache()
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(
                startTransform: .identity,
                endTransform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
            )
        )
        cache.populate(segments: [segment])
        XCTAssertNotNil(cache.transforms(for: segment.id))
        cache.invalidate()
        XCTAssertNil(cache.transforms(for: segment.id))
    }

    func test_isValid_lifecycle() {
        let cache = SpringSimulationCache()
        XCTAssertFalse(cache.isValid, "New cache should be invalid")
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(startTransform: .identity, endTransform: .identity)
        )
        cache.populate(segments: [segment])
        XCTAssertTrue(cache.isValid, "Cache should be valid after populate")
        cache.invalidate()
        XCTAssertFalse(cache.isValid, "Cache should be invalid after invalidate")
    }
}
