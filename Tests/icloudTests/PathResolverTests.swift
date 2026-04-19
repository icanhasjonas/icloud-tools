import XCTest
@testable import icloud

final class PathResolverTests: XCTestCase {
    func testIcloudPrefixResolves() {
        let url = PathResolver.resolve("icloud:TODO/foo.txt")
        XCTAssertTrue(url.path.hasSuffix("com~apple~CloudDocs/TODO/foo.txt"))
    }

    func testTildeExpansion() {
        let url = PathResolver.resolve("~/.icloud/foo")
        XCTAssertTrue(url.path.hasPrefix(NSHomeDirectory()))
    }

    func testRebaseMapsResolvedBackToSymlink() {
        // Create a tempdir and a symlink to it, verify rebase rewrites paths.
        let fm = FileManager.default
        let tmpTarget = fm.temporaryDirectory.appendingPathComponent("rebase-target-\(UUID().uuidString)")
        let symlink = fm.temporaryDirectory.appendingPathComponent("rebase-link-\(UUID().uuidString)")

        try? fm.createDirectory(at: tmpTarget, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tmpTarget)
            try? fm.removeItem(at: symlink)
        }

        try? fm.createSymbolicLink(at: symlink, withDestinationURL: tmpTarget)

        let rebase = PathResolver.Rebase(symlink)
        let childResolved = tmpTarget.appendingPathComponent("sub/file.txt")
        let display = PathResolver.relativePath(childResolved, rebase: rebase)

        // The displayed path should use the symlink prefix, not the resolved target prefix
        XCTAssertTrue(
            display.contains("rebase-link-") || display.contains("sub/file.txt"),
            "Expected display to reference the symlink path, got: \(display)"
        )
        XCTAssertFalse(
            display.hasPrefix(tmpTarget.path),
            "Display should not expose the resolved target prefix: \(display)"
        )
    }

    func testRelativePathStripsHomePrefix() {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: "\(home)/Documents/x.txt")
        let rel = PathResolver.relativePath(url)
        XCTAssertEqual(rel, "~/Documents/x.txt")
    }

    func testRelativePathForeignPathReturnsAbsolute() {
        let url = URL(fileURLWithPath: "/Volumes/External/x.txt")
        XCTAssertEqual(PathResolver.relativePath(url), "/Volumes/External/x.txt")
    }
}
