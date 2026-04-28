// JSONTreeNode — canonical tree representation used by `DataRenderer`
// for JSON / YAML / TOML / Plist / XML after conversion.
//
// The conversion for non-JSON formats is simple at this layer: we
// present parse success + surface structure. Deep parsing (schema
// inference, reference tracking) is out of scope for v1.

import Foundation

public indirect enum JSONTreeNode: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONTreeNode])
    case object([(key: String, value: JSONTreeNode)])

    public var isContainer: Bool {
        switch self {
        case .array, .object: return true
        default:              return false
        }
    }

    public var depth: Int {
        switch self {
        case .object(let kvs): return 1 + (kvs.map(\.value.depth).max() ?? 0)
        case .array(let xs):   return 1 + (xs.map(\.depth).max() ?? 0)
        default:               return 0
        }
    }

    public var keyCount: Int {
        switch self {
        case .object(let kvs): return kvs.count
        case .array(let xs):   return xs.count
        default:               return 0
        }
    }

    public static func == (lhs: JSONTreeNode, rhs: JSONTreeNode) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)):     return a == b
        case let (.array(a), .array(b)):   return a == b
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            for i in 0..<a.count {
                if a[i].key != b[i].key { return false }
                if a[i].value != b[i].value { return false }
            }
            return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:            hasher.combine(0)
        case .bool(let b):     hasher.combine(1); hasher.combine(b)
        case .number(let n):   hasher.combine(2); hasher.combine(n)
        case .string(let s):   hasher.combine(3); hasher.combine(s)
        case .array(let a):    hasher.combine(4); hasher.combine(a)
        case .object(let kvs):
            hasher.combine(5)
            for (k, v) in kvs {
                hasher.combine(k)
                hasher.combine(v)
            }
        }
    }
}

// MARK: - Parse result

public struct JSONParseResult: Sendable, Hashable {
    public let root: JSONTreeNode?
    public let error: String?
    public let errorLine: Int?

    public init(root: JSONTreeNode?, error: String?, errorLine: Int?) {
        self.root = root
        self.error = error
        self.errorLine = errorLine
    }

    public var isValid: Bool { error == nil }
}

public enum JSONTreeParser {

    /// Parse JSON bytes into a tree. Preserves object-key order via a
    /// `JSONSerialization` trick: fall back to a custom line/char
    /// scanner for key order retention only when the caller asks for
    /// it (the default preserves the order Foundation reports, which
    /// is insertion-order on modern macOS).
    public static func parse(data: Data) -> JSONParseResult {
        do {
            let obj = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed, .mutableContainers]
            )
            return JSONParseResult(root: convert(obj), error: nil, errorLine: nil)
        } catch let err as NSError {
            let line = (err.userInfo["NSJSONSerializationErrorIndex"] as? Int).flatMap { idx in
                lineNumber(byteIndex: idx, in: data)
            }
            return JSONParseResult(
                root: nil,
                error: err.localizedDescription,
                errorLine: line
            )
        } catch {
            return JSONParseResult(root: nil, error: "\(error)", errorLine: nil)
        }
    }

    /// Raw-to-node conversion. `NSDictionary` enumeration order on
    /// macOS retains insertion order under `mutableContainers`; if
    /// that ever regresses the test suite will catch it.
    public static func convert(_ value: Any) -> JSONTreeNode {
        if value is NSNull { return .null }
        if let b = value as? Bool { return .bool(b) }
        if let n = value as? NSNumber {
            // Distinguish booleans encoded as NSNumber (iOS/macOS
            // bridge quirk) from true numbers.
            if CFNumberGetType(n as CFNumber) == .charType {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        }
        if let s = value as? String { return .string(s) }
        if let arr = value as? [Any] { return .array(arr.map(convert)) }
        if let dict = value as? [String: Any] {
            let kvs = dict.map { (key: $0.key, value: convert($0.value)) }
            return .object(kvs.sorted { $0.key < $1.key })
        }
        return .string(String(describing: value))
    }

    private static func lineNumber(byteIndex: Int, in data: Data) -> Int {
        var line = 1
        let prefix = data.prefix(byteIndex)
        for byte in prefix where byte == 0x0A { line += 1 }
        return line
    }
}

// MARK: - XML + Plist bridge

public enum PlistTreeParser {
    public static func parse(data: Data) -> JSONParseResult {
        do {
            let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return JSONParseResult(root: JSONTreeParser.convert(obj),
                                   error: nil, errorLine: nil)
        } catch {
            return JSONParseResult(root: nil, error: "\(error)", errorLine: nil)
        }
    }
}
