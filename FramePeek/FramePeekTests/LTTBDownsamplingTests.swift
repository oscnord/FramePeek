import Testing
@testable import FramePeek

private struct LTTBPoint: Equatable {
    let time: Double
    let value: Double
}

private struct SeededLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextDouble() -> Double {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return Double(state >> 11) * (1.0 / Double(1 << 53))
    }
}

private func makeDataset(count: Int, seed: UInt64 = 42) -> [LTTBPoint] {
    var rng = SeededLCG(seed: seed)
    return (0..<count).map { i in
        LTTBPoint(time: Double(i) * 0.1, value: rng.nextDouble() * 100)
    }
}

/// Reference LTTB implementation, ported verbatim from the original
/// `downsampleLTTB(_ samples: [BitrateSample], targetCount:)` prior to
/// generalization. Pins the new generic implementation to the same
/// point selection.
private func referenceLTTB(_ samples: [LTTBPoint], targetCount: Int) -> [LTTBPoint] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }

    var result: [LTTBPoint] = []
    result.reserveCapacity(targetCount)

    result.append(samples[0])

    let bucketSize = Double(samples.count - 2) / Double(targetCount - 2)
    var lastSelectedIndex = 0

    for i in 0..<(targetCount - 2) {
        let bucketStart = Int(Double(i) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, samples.count - 1)

        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)

        var avgX: Double = 0
        var avgY: Double = 0
        let nextBucketCount = nextBucketEnd - nextBucketStart + 1

        for j in nextBucketStart...nextBucketEnd {
            avgX += samples[j].time
            avgY += samples[j].value
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)

        var maxArea: Double = -1
        var maxAreaIndex = bucketStart

        let pointA = samples[lastSelectedIndex]

        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            let area = abs(
                (pointA.time - avgX) * (pointB.value - pointA.value) -
                (pointA.time - pointB.time) * (avgY - pointA.value)
            ) * 0.5

            if area > maxArea {
                maxArea = area
                maxAreaIndex = j
            }
        }

        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }

    result.append(samples[samples.count - 1])

    return result
}

private func genericLTTB(_ samples: [LTTBPoint], targetCount: Int) -> [LTTBPoint] {
    downsampleLTTB(samples, targetCount: targetCount, x: { $0.time }, y: { $0.value })
}

struct LTTBDownsamplingTests {

    @Test func matchesReferenceOnLargeDataset500() {
        let dataset = makeDataset(count: 5000)
        #expect(genericLTTB(dataset, targetCount: 500) == referenceLTTB(dataset, targetCount: 500))
    }

    @Test func matchesReferenceOnLargeDataset100() {
        let dataset = makeDataset(count: 5000)
        #expect(genericLTTB(dataset, targetCount: 100) == referenceLTTB(dataset, targetCount: 100))
    }

    @Test func matchesReferenceOnEmptyInput() {
        let dataset: [LTTBPoint] = []
        #expect(genericLTTB(dataset, targetCount: 500) == referenceLTTB(dataset, targetCount: 500))
        #expect(genericLTTB(dataset, targetCount: 500) == [])
    }

    @Test func matchesReferenceOnSinglePoint() {
        let dataset = makeDataset(count: 1)
        #expect(genericLTTB(dataset, targetCount: 500) == referenceLTTB(dataset, targetCount: 500))
        #expect(genericLTTB(dataset, targetCount: 500) == dataset)
    }

    @Test func matchesReferenceWhenTargetCountExceedsSampleCount() {
        let dataset = makeDataset(count: 50)
        #expect(genericLTTB(dataset, targetCount: 200) == referenceLTTB(dataset, targetCount: 200))
        #expect(genericLTTB(dataset, targetCount: 200) == dataset)
    }

    @Test func matchesReferenceForTargetCountTwo() {
        let dataset = makeDataset(count: 5000)
        let result = genericLTTB(dataset, targetCount: 2)
        #expect(result == referenceLTTB(dataset, targetCount: 2))
        #expect(result == [dataset.first!, dataset.last!])
    }
}
