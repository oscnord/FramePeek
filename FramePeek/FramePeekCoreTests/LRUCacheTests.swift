import Testing
@testable import FramePeekCore

struct LRUCacheTests {

    @Test func getOnMissReturnsNil() {
        var cache = LRUCache<String, Int>(capacity: 3)
        #expect(cache.get("absent") == nil)
    }

    @Test func setThenGetReturnsValue() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        #expect(cache.get("a") == 1)
    }

    @Test func evictsLeastRecentlyUsedAtCapacity() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3) // should evict "a"

        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
        #expect(cache.get("c") == 3)
    }

    @Test func gettingValuePromotesIt() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        _ = cache.get("a")    // promotes "a", "b" is now LRU
        cache.set("c", 3)     // should evict "b"

        #expect(cache.get("a") == 1)
        #expect(cache.get("b") == nil)
        #expect(cache.get("c") == 3)
    }

    @Test func reSetReplacesValueAndPromotes() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("a", 99)    // re-insert with new value
        cache.set("c", 3)     // should evict "b"

        #expect(cache.get("a") == 99)
        #expect(cache.get("b") == nil)
        #expect(cache.get("c") == 3)
    }

    @Test func removeAllClearsCache() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.removeAll()

        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == nil)
    }

    @Test func keysReflectsCurrentMembership() {
        var cache = LRUCache<Int, String>(capacity: 3)
        cache.set(1, "one")
        cache.set(2, "two")
        cache.set(3, "three")

        #expect(Set(cache.keys) == [1, 2, 3])
    }
}
