import Foundation

/// Largest-Triangle-Three-Buckets (LTTB) downsampling algorithm.
/// Preserves visual shape of the data while reducing point count for performance.
func downsampleLTTB<T>(
    _ samples: [T],
    targetCount: Int,
    x: (T) -> Double,
    y: (T) -> Double
) -> [T] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }

    var result: [T] = []
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
            avgX += x(samples[j])
            avgY += y(samples[j])
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)

        var maxArea: Double = -1
        var maxAreaIndex = bucketStart

        let pointA = samples[lastSelectedIndex]
        let pointAX = x(pointA)
        let pointAY = y(pointA)

        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            let area = abs(
                (pointAX - avgX) * (y(pointB) - pointAY) -
                (pointAX - x(pointB)) * (avgY - pointAY)
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
