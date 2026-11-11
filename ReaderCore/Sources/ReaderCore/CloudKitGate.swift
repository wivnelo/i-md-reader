import Foundation

public enum CloudKitGate {
    public static let disableArgument = "-IMDDisableCloudKit"
    public static let entitlementKey = "com.apple.developer.icloud-container-identifiers"

    public enum Verdict: Equatable, Sendable {
        case allowed, disabledByArgument, missingEntitlement
    }

    public static func verdict(containerID: String, arguments: [String], entitledContainers: [String]?) -> Verdict {
        if arguments.contains(disableArgument) { return .disabledByArgument }
        return entitledContainers?.contains(containerID) == true ? .allowed : .missingEntitlement
    }

    public static func containers(inEntitlementsPlist data: Data) -> [String]? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        guard let value = dictionary[entitlementKey] else { return [] }
        return value as? [String]
    }

    // Byte-wise reads avoid alignment assumptions and work for Data with a nonzero startIndex.
    private static func bytes(_ data: Data, at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { return nil }
        let start = data.index(data.startIndex, offsetBy: offset)
        return Data(data[start..<data.index(start, offsetBy: count)])
    }

    private static func word(_ data: Data, at offset: Int, littleEndian: Bool = false) -> UInt32? {
        guard let part = bytes(data, at: offset, count: 4) else { return nil }
        return (littleEndian ? Array(part.reversed()) : Array(part)).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func wide(_ data: Data, at offset: Int) -> UInt64? {
        guard let low = word(data, at: offset, littleEndian: true),
              let high = word(data, at: offset + 4, littleEndian: true) else { return nil }
        return UInt64(low) | (UInt64(high) << 32)
    }

    private static func named(_ data: Data, at offset: Int, _ name: String) -> Bool {
        guard let part = bytes(data, at: offset, count: 16) else { return false }
        return Array(part.prefix { $0 != 0 }) == Array(name.utf8)
    }

    public static func entitlementsPlist(inMachO data: Data) -> Data? {
        if word(data, at: 0) == 0xcafebabe {
            guard let count = word(data, at: 4), Int(count) <= (data.count - 8) / 20 else { return nil }
            #if arch(arm64)
            let cpu: UInt32 = 0x0100000c
            #else
            let cpu: UInt32 = 0x01000007
            #endif
            for index in 0..<Int(count) {
                let entry = 8 + index * 20
                guard let type = word(data, at: entry), let offset = word(data, at: entry + 8),
                      let size = word(data, at: entry + 12),
                      let slice = bytes(data, at: Int(offset), count: Int(size)) else { return nil }
                if type == cpu { return entitlementsPlist(inThinMachO: slice) }
            }
            return nil
        }
        return entitlementsPlist(inThinMachO: data)
    }

    static func entitlementsPlist(inThinMachO data: Data) -> Data? {
        guard word(data, at: 0, littleEndian: true) == 0xfeedfacf,
              let count = word(data, at: 16, littleEndian: true),
              let size = word(data, at: 20, littleEndian: true),
              bytes(data, at: 0, count: 32) != nil,
              bytes(data, at: 32, count: Int(size)) != nil,
              Int(count) <= Int(size) / 8 else { return nil }
        let end = 32 + Int(size)
        var cursor = 32
        var signature: (offset: Int, size: Int)?
        var entitlements: Data?
        for _ in 0..<Int(count) {
            guard cursor <= end - 8,
                  let command = word(data, at: cursor, littleEndian: true),
                  let length = word(data, at: cursor + 4, littleEndian: true),
                  length >= 8, Int(length) <= end - cursor else { return nil }
            if command == 0x19 { // segment_command_64
                guard length >= 72, let sections = word(data, at: cursor + 64, littleEndian: true),
                      Int(sections) <= (Int(length) - 72) / 80 else { return nil }
                if named(data, at: cursor + 8, "__TEXT") {
                    for index in 0..<Int(sections) {
                        let section = cursor + 72 + index * 80
                        if named(data, at: section, "__entitlements"), named(data, at: section + 16, "__TEXT") {
                            guard let size = wide(data, at: section + 40), size <= UInt64(Int.max),
                                  let offset = word(data, at: section + 48, littleEndian: true),
                                  let content = bytes(data, at: Int(offset), count: Int(size)) else { return nil }
                            entitlements = content
                        }
                    }
                }
            } else if command == 0x1d {
                guard length >= 16, let offset = word(data, at: cursor + 8, littleEndian: true),
                      let size = word(data, at: cursor + 12, littleEndian: true) else { return nil }
                signature = (Int(offset), Int(size))
            }
            cursor += Int(length)
        }
        guard cursor == end else { return nil }
        if let entitlements { return entitlements }
        guard let signature, let content = bytes(data, at: signature.offset, count: signature.size) else { return nil }
        return entitlementsPlist(inSuperBlob: content)
    }

    static func entitlementsPlist(inSuperBlob data: Data) -> Data? {
        guard word(data, at: 0) == 0xfade0cc0, let length = word(data, at: 4),
              length >= 12, Int(length) <= data.count, let count = word(data, at: 8),
              Int(count) <= (Int(length) - 12) / 8 else { return nil }
        let tableEnd = 12 + Int(count) * 8
        for index in 0..<Int(count) {
            let entry = 12 + index * 8
            guard let type = word(data, at: entry), let offset = word(data, at: entry + 4),
                  Int(offset) >= tableEnd, Int(offset) <= Int(length) - 8,
                  let blobLength = word(data, at: Int(offset) + 4), blobLength >= 8,
                  Int(blobLength) <= Int(length) - Int(offset) else { return nil }
            if type == 5 {
                guard word(data, at: Int(offset)) == 0xfade7171 else { return nil }
                return bytes(data, at: Int(offset) + 8, count: Int(blobLength) - 8)
            }
        }
        return nil
    }
}
