import Foundation

/// One step of a line comparison, with indices into the old and new lines.
public enum DiffOp: Equatable, Sendable {
    case same(old: Int, new: Int)
    case removed(old: Int)
    case added(new: Int)
}

/// Myers' O(ND) comparison. The common start and end are taken off first;
/// the middle is searched up to an edit distance of `cap`, past which it is
/// reported as all removed then all added. That keeps memory to about cap²
/// small integers however different two documents are.
public enum LineDiff {
    static let cap = 2_000

    public static func lines(old: [Substring], new: [Substring]) -> [DiffOp] {
        diff(old, new)
    }

    /// Word-level differences inside one changed line: the old ranges that
    /// went and the new ranges that came, white space not counted.
    public static func words(old: Substring, new: Substring) -> (removed: [Range<String.Index>], added: [Range<String.Index>]) {
        let a = tokens(old)
        let b = tokens(new)
        var removed: [Range<String.Index>] = []
        var added: [Range<String.Index>] = []
        for op in diff(a.map { old[$0] }, b.map { new[$0] }) {
            switch op {
            case .removed(let index) where !old[a[index]].allSatisfy(\.isWhitespace):
                removed.append(a[index])
            case .added(let index) where !new[b[index]].allSatisfy(\.isWhitespace):
                added.append(b[index])
            default:
                break
            }
        }
        return (removed, added)
    }

    // MARK: - Core

    static func diff<T: Equatable>(_ a: [T], _ b: [T]) -> [DiffOp] {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }

        var ops: [DiffOp] = (0..<prefix).map { .same(old: $0, new: $0) }
        let middleA = Array(a[prefix..<(a.count - suffix)])
        let middleB = Array(b[prefix..<(b.count - suffix)])
        if let middle = myers(middleA, middleB) {
            ops += middle.map { op in
                switch op {
                case .same(let x, let y): return .same(old: x + prefix, new: y + prefix)
                case .removed(let x): return .removed(old: x + prefix)
                case .added(let y): return .added(new: y + prefix)
                }
            }
        } else {
            ops += middleA.indices.map { .removed(old: $0 + prefix) }
            ops += middleB.indices.map { .added(new: $0 + prefix) }
        }
        let oldTail = a.count - suffix
        let newTail = b.count - suffix
        ops += (0..<suffix).map { .same(old: oldTail + $0, new: newTail + $0) }
        return ops
    }

    /// The shortest edit script, or nil when it is longer than `cap`.
    private static func myers<T: Equatable>(_ a: [T], _ b: [T]) -> [DiffOp]? {
        let n = a.count
        let m = b.count
        if n == 0 { return (0..<m).map { .added(new: $0) } }
        if m == 0 { return (0..<n).map { .removed(old: $0) } }
        let limit = min(n + m, cap)
        let offset = limit + 1
        var v = [Int](repeating: 0, count: 2 * limit + 3)
        var trace: [[Int32]] = []

        for d in 0...limit {
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n, y >= m {
                    return backtrack(trace, d: d, n: n, m: m)
                }
            }
            trace.append(v[(offset - d)...(offset + d)].map { Int32($0) })
        }
        return nil
    }

    /// Walks back from the end through the saved frontiers. `trace[d]` holds
    /// x for diagonals -d...d after step d.
    private static func backtrack(_ trace: [[Int32]], d final: Int, n: Int, m: Int) -> [DiffOp] {
        var ops: [DiffOp] = []
        var x = n
        var y = m
        var d = final
        while d > 0 {
            let previous = trace[d - 1]
            func frontier(_ k: Int) -> Int { Int(previous[k + d - 1]) }
            let k = x - y
            let previousK = (k == -d || (k != d && frontier(k - 1) < frontier(k + 1))) ? k + 1 : k - 1
            let previousX = frontier(previousK)
            let previousY = previousX - previousK
            while x > previousX, y > previousY {
                ops.append(.same(old: x - 1, new: y - 1))
                x -= 1
                y -= 1
            }
            if x == previousX {
                ops.append(.added(new: y - 1))
                y -= 1
            } else {
                ops.append(.removed(old: x - 1))
                x -= 1
            }
            d -= 1
        }
        while x > 0, y > 0 {
            ops.append(.same(old: x - 1, new: y - 1))
            x -= 1
            y -= 1
        }
        return ops.reversed()
    }

    /// Runs of non-space characters and runs of space, in order.
    private static func tokens(_ text: Substring) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex {
            let space = text[start].isWhitespace
            var end = text.index(after: start)
            while end < text.endIndex, text[end].isWhitespace == space {
                end = text.index(after: end)
            }
            result.append(start..<end)
            start = end
        }
        return result
    }
}
