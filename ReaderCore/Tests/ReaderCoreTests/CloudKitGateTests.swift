import Foundation
import Testing
@testable import ReaderCore

private let gateContainer = "iCloud.test.reader"

private func entitlementPlist(_ format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: [CloudKitGate.entitlementKey: [gateContainer]],
                                       format: format, options: 0)
}

@Test func cloudKitVerdictsRespectOverrideAndContainer() {
    let overridden: [[String]?] = [nil, [], ["other"], [gateContainer]]
    for containers in overridden {
        #expect(CloudKitGate.verdict(containerID: gateContainer, arguments: [CloudKitGate.disableArgument],
                                     entitledContainers: containers) == .disabledByArgument)
    }
    let missing: [[String]?] = [nil, [], ["other"]]
    for containers in missing {
        #expect(CloudKitGate.verdict(containerID: gateContainer, arguments: [],
                                     entitledContainers: containers) == .missingEntitlement)
    }
    #expect(CloudKitGate.verdict(containerID: gateContainer, arguments: [],
                                 entitledContainers: ["other", gateContainer]) == .allowed)
}

@Test func entitlementPlistsDecodeBothFormats() throws {
    for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
        #expect(CloudKitGate.containers(inEntitlementsPlist: try entitlementPlist(format)) == [gateContainer])
    }
    let empty = try PropertyListSerialization.data(fromPropertyList: [String: String](), format: .xml, options: 0)
    let wrongType = try PropertyListSerialization.data(fromPropertyList: [CloudKitGate.entitlementKey: "wrong"], format: .xml, options: 0)
    #expect(CloudKitGate.containers(inEntitlementsPlist: empty) == [])
    #expect(CloudKitGate.containers(inEntitlementsPlist: wrongType) == nil)
    #expect(CloudKitGate.containers(inEntitlementsPlist: Data("bad".utf8)) == nil)
}

private func put(_ value: UInt32, into data: inout Data, at offset: Int, little: Bool = false) {
    let shifts = little ? [0, 8, 16, 24] : [24, 16, 8, 0]
    data.replaceSubrange(offset..<offset + 4, with: shifts.map { UInt8(truncatingIfNeeded: value >> $0) })
}

private func putName(_ value: String, into data: inout Data, at offset: Int) {
    data.replaceSubrange(offset..<offset + value.utf8.count, with: value.utf8)
}

private func superBlob(_ plist: Data) -> Data {
    var data = Data(repeating: 0, count: 28)
    put(0xfade0cc0, into: &data, at: 0)
    put(UInt32(28 + plist.count), into: &data, at: 4)
    put(1, into: &data, at: 8)
    put(5, into: &data, at: 12)
    put(20, into: &data, at: 16)
    put(0xfade7171, into: &data, at: 20)
    put(UInt32(8 + plist.count), into: &data, at: 24)
    data.append(plist)
    return data
}

private func thinMachO(_ plist: Data, section: Bool) -> Data {
    let commandSize = section ? 152 : 16
    var data = Data(repeating: 0, count: 32 + commandSize)
    put(0xfeedfacf, into: &data, at: 0, little: true)
    put(1, into: &data, at: 16, little: true)
    put(UInt32(commandSize), into: &data, at: 20, little: true)
    put(section ? 0x19 : 0x1d, into: &data, at: 32, little: true)
    put(UInt32(commandSize), into: &data, at: 36, little: true)
    if section {
        putName("__TEXT", into: &data, at: 40)
        put(1, into: &data, at: 96, little: true)
        putName("__entitlements", into: &data, at: 104)
        putName("__TEXT", into: &data, at: 120)
        put(UInt32(plist.count), into: &data, at: 144, little: true)
        put(UInt32(data.count), into: &data, at: 152, little: true)
        data.append(plist)
    } else {
        let signature = superBlob(plist)
        put(UInt32(data.count), into: &data, at: 40, little: true)
        put(UInt32(signature.count), into: &data, at: 44, little: true)
        data.append(signature)
    }
    return data
}

private func fatMachO(_ thin: Data) -> Data {
    // The first architecture is deliberately not the host architecture.
    #if arch(arm64)
    let host: UInt32 = 0x0100000c, other: UInt32 = 0x01000007
    #else
    let host: UInt32 = 0x01000007, other: UInt32 = 0x0100000c
    #endif
    var data = Data(repeating: 0, count: 48)
    put(0xcafebabe, into: &data, at: 0)
    put(2, into: &data, at: 4)
    put(other, into: &data, at: 8)
    put(48, into: &data, at: 16)
    put(4, into: &data, at: 20)
    put(host, into: &data, at: 28)
    put(52, into: &data, at: 36)
    put(UInt32(thin.count), into: &data, at: 40)
    data.append(Data(repeating: 0, count: 4))
    data.append(thin)
    return data
}

@Test func embeddedEntitlementsDecodeWithoutCloudKit() throws {
    let plist = try entitlementPlist()
    #expect(CloudKitGate.entitlementsPlist(inSuperBlob: superBlob(plist)) == plist)
    for section in [true, false] {
        let thin = thinMachO(plist, section: section)
        #expect(CloudKitGate.entitlementsPlist(inMachO: thin) == plist)
        #expect(CloudKitGate.entitlementsPlist(inMachO: fatMachO(thin)) == plist)
    }
}

@Test func malformedEntitlementBinariesFailSafely() throws {
    let plist = try entitlementPlist()
    let blob = superBlob(plist)
    for length in 0..<blob.count {
        #expect(CloudKitGate.entitlementsPlist(inSuperBlob: Data(blob.prefix(length))) == nil)
    }
    for section in [true, false] {
        let thin = thinMachO(plist, section: section)
        let fat = fatMachO(thin)
        for data in [thin, fat] {
            for length in 0..<data.count {
                #expect(CloudKitGate.entitlementsPlist(inMachO: Data(data.prefix(length))) == nil)
            }
        }
        var bad = thin
        put(.max, into: &bad, at: section ? 152 : 40, little: true)
        #expect(CloudKitGate.entitlementsPlist(inMachO: bad) == nil)
        bad = thin
        put(.max, into: &bad, at: section ? 148 : 44, little: true)
        #expect(CloudKitGate.entitlementsPlist(inMachO: bad) == nil)
        bad = thin
        put(0, into: &bad, at: 36, little: true)
        #expect(CloudKitGate.entitlementsPlist(inMachO: bad) == nil)
    }
    var bad = blob
    put(.max, into: &bad, at: 16)
    #expect(CloudKitGate.entitlementsPlist(inSuperBlob: bad) == nil)
    bad = blob
    put(.max, into: &bad, at: 24)
    #expect(CloudKitGate.entitlementsPlist(inSuperBlob: bad) == nil)
    bad = blob
    put(0, into: &bad, at: 20)
    #expect(CloudKitGate.entitlementsPlist(inSuperBlob: bad) == nil)
}
