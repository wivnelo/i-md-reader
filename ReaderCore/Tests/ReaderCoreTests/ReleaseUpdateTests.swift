import Foundation
import Testing
@testable import ReaderCore

private func release(_ version: String = "0.2.0", draft: Bool = false, prerelease: Bool = false,
                     host: String = "https://github.com/wivnelo/i-md-reader", extensions: [String] = ["zip", "dmg"]) throws -> Data {
    let assets = extensions.map { ext in
        let name = "iMDReader-\(version)-macOS-universal.\(ext)"
        return ["name": name, "browser_download_url": "\(host)/releases/download/v\(version)/\(name)"]
    }
    return try JSONSerialization.data(withJSONObject: ["tag_name": "v" + version, "draft": draft,
        "prerelease": prerelease, "assets": assets])
}

@Test func stableUpdateRequiresNewerVersionAndMatchingMacAsset() throws {
    let candidate = try ReleaseUpdate.macRelease(from: release(), currentVersion: "0.1.0")
    let update = try #require(candidate)
    #expect(update.version == "0.2.0")
    #expect(update.downloadURL.pathExtension == "dmg")
    #expect(try ReleaseUpdate.macRelease(from: release(extensions: ["zip"]), currentVersion: "0.1.0")?.downloadURL.pathExtension == "zip")
    for current in ["0.2.0", "0.3.0", "1.0.0", "invalid"] {
        #expect(try ReleaseUpdate.macRelease(from: release(), currentVersion: current) == nil)
    }
    #expect(try ReleaseUpdate.macRelease(from: release("0.10.0"), currentVersion: "0.9.0") != nil)
}

@Test func updateMetadataCannotOfferDraftsPrereleasesOrForeignDownloads() throws {
    for data in [try release(draft: true), try release(prerelease: true), try release("0.2.0-beta"),
                 try release(host: "https://evil.example"), try release(host: "https://github.com/other/repo"),
                 try release(host: "http://github.com/wivnelo/i-md-reader"), try release(extensions: ["ipa"])] {
        #expect(try ReleaseUpdate.macRelease(from: data, currentVersion: "0.1.0") == nil)
    }
    #expect(throws: (any Error).self) {
        try ReleaseUpdate.macRelease(from: Data("{}".utf8), currentVersion: "0.1.0")
    }
}

@Test func startupCheckAttemptsOnlyOnceEvenWhenConcurrentOrOffline() async throws {
    actor Counter {
        var calls = 0
        func fetch(fail: Bool) throws -> Data? {
            calls += 1
            if fail { throw URLError(.notConnectedToInternet) }
            return try release()
        }
    }
    for fail in [false, true] {
        let counter = Counter()
        let checker = StartupUpdateCheck { try await counter.fetch(fail: fail) }
        async let first = checker.checkMac(currentVersion: "0.1.0")
        async let second = checker.checkMac(currentVersion: "0.1.0")
        let results = await [first, second]
        #expect(results.compactMap { $0 }.count == (fail ? 0 : 1))
        #expect(await checker.checkMac(currentVersion: "0.1.0") == nil)
        #expect(await counter.calls == 1)
    }
}
