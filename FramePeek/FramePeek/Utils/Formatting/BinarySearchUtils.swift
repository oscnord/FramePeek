import Foundation

/// Binary search utilities for time-sorted arrays.
/// All arrays passed to these functions MUST be pre-sorted by their time property in ascending order.

/// Finds the index of the element closest to `targetTime` using binary search.
/// Returns nil if the array is empty.
/// - Complexity: O(log n)
func binarySearchClosest<T>(
    in array: [T],
    targetTime: Double,
    timeKeyPath: KeyPath<T, Double>
) -> Int? {
    guard !array.isEmpty else { return nil }

    var low = 0
    var high = array.count - 1

    while low < high {
        let mid = low + (high - low) / 2
        if array[mid][keyPath: timeKeyPath] < targetTime {
            low = mid + 1
        } else {
            high = mid
        }
    }

    // low is now the first element >= targetTime
    // Check if previous element is closer
    if low > 0 {
        let distCurrent = abs(array[low][keyPath: timeKeyPath] - targetTime)
        let distPrev = abs(array[low - 1][keyPath: timeKeyPath] - targetTime)
        return distPrev <= distCurrent ? low - 1 : low
    }

    return low
}

/// Finds the index of the first element with time >= targetTime.
/// Returns array.count if all elements are < targetTime.
/// - Complexity: O(log n)
func lowerBound<T>(
    in array: [T],
    targetTime: Double,
    timeKeyPath: KeyPath<T, Double>
) -> Int {
    var low = 0
    var high = array.count

    while low < high {
        let mid = low + (high - low) / 2
        if array[mid][keyPath: timeKeyPath] < targetTime {
            low = mid + 1
        } else {
            high = mid
        }
    }

    return low
}

/// Finds the interpolation pair for a given time in a pre-sorted array.
/// Returns the two bracketing elements and interpolation factor t in [0,1].
/// - Complexity: O(log n)
func binarySearchInterpolationPair<T>(
    in sortedArray: [T],
    targetTime: Double,
    timeKeyPath: KeyPath<T, Double>
) -> (T, T, Double)? {
    guard sortedArray.count >= 2 else { return nil }

    let idx = lowerBound(in: sortedArray, targetTime: targetTime, timeKeyPath: timeKeyPath)

    // Before first element
    if idx == 0 { return nil }
    // After last element
    if idx >= sortedArray.count { return nil }

    let before = sortedArray[idx - 1]
    let after = sortedArray[idx]
    let time1 = before[keyPath: timeKeyPath]
    let time2 = after[keyPath: timeKeyPath]

    guard time2 > time1 else { return nil }
    let t = (targetTime - time1) / (time2 - time1)
    return (before, after, t)
}

/// Returns indices for all elements within the given time range from a pre-sorted array.
/// - Complexity: O(log n) for finding bounds (the returned range itself is the slice).
func indicesInRange<T>(
    in array: [T],
    from startTime: Double,
    to endTime: Double,
    timeKeyPath: KeyPath<T, Double>
) -> Range<Int> {
    let start = lowerBound(in: array, targetTime: startTime, timeKeyPath: timeKeyPath)
    let end = lowerBound(in: array, targetTime: endTime, timeKeyPath: timeKeyPath)
    // Include the element at endTime if it exists
    let adjustedEnd = end < array.count && array[end][keyPath: timeKeyPath] <= endTime ? end + 1 : end
    return start..<adjustedEnd
}
