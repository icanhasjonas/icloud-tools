import XCTest
@testable import icloud

/// End-to-end tests using plain /tmp paths (no iCloud needed).
/// These cover the regressions that cost us hours:
/// - merge semantics (never delete a destination directory)
/// - per-file conflict handling with -f
/// - no-clobber
/// - verification (no lying success)
final class FileOperationTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    // MARK: - helpers

    private func write(_ content: String, to path: String) throws {
        let url = workDir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) -> String? {
        try? String(contentsOf: workDir.appendingPathComponent(path), encoding: .utf8)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: workDir.appendingPathComponent(path).path)
    }

    private func runMove(_ paths: [String], force: Bool = false, noClobber: Bool = false) throws {
        let renderer = SilentRenderer()
        let absolute = paths.map { workDir.appendingPathComponent($0).path }
        try FileOperation.execute(
            paths: absolute,
            verb: .move,
            allowDirectories: true,
            force: force,
            noClobber: noClobber,
            renderer: renderer
        ) { fm, src, dst in
            try fm.moveItem(at: src, to: dst)
        }
    }

    // MARK: - tests

    func testSimpleMove() throws {
        try write("hello", to: "a.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)
        try runMove(["a.txt", "dst/"])
        XCTAssertFalse(exists("a.txt"))
        XCTAssertEqual(read("dst/a.txt"), "hello")
    }

    func testMergeKeepsNonConflictingFiles() throws {
        // Source dir
        try write("SRC a", to: "src/a.txt")
        try write("SRC b", to: "src/sub/b.txt")
        // Destination dir with an existing same-named file (conflict) and an unrelated file (must survive)
        try write("OLD a", to: "dst/src/a.txt")
        try write("SURVIVOR", to: "dst/src/keep.txt")

        try runMove(["src", "dst/"], force: true)

        // Files move out of source, but source directory itself is left behind (the "never delete
        // directories" covenant). User can rmdir the empty tree themselves if they want.
        XCTAssertFalse(exists("src/a.txt"), "source file moved out")
        XCTAssertFalse(exists("src/sub/b.txt"), "source file moved out")
        XCTAssertEqual(read("dst/src/a.txt"), "SRC a", "conflicting file replaced with source")
        XCTAssertEqual(read("dst/src/keep.txt"), "SURVIVOR", "non-conflicting file must NOT be deleted by merge")
        XCTAssertEqual(read("dst/src/sub/b.txt"), "SRC b", "new subdir created and populated")
    }

    func testNoClobberSkipsExisting() throws {
        try write("SRC", to: "src/a.txt")
        try write("OLD", to: "dst/src/a.txt")

        try runMove(["src", "dst/"], noClobber: true)

        XCTAssertEqual(read("dst/src/a.txt"), "OLD", "noClobber must preserve existing file")
    }

    func testConflictWithoutForceThrows() throws {
        try write("SRC", to: "src/a.txt")
        try write("OLD", to: "dst/src/a.txt")

        XCTAssertThrowsError(try runMove(["src", "dst/"])) { error in
            // Either a typed partialFailure or destinationExists is acceptable
            XCTAssertNotNil(error as? FileOperationError)
        }

        XCTAssertEqual(read("dst/src/a.txt"), "OLD", "existing file must be untouched on error")
    }

    func testNeverReplaceDirectoryWithFile() throws {
        try write("SRC", to: "src/a.txt")
        // At dst, a.txt is a DIRECTORY, not a file. Must NOT be deleted.
        try FileManager.default.createDirectory(
            at: workDir.appendingPathComponent("dst/src/a.txt"),
            withIntermediateDirectories: true
        )
        try write("must survive", to: "dst/src/a.txt/inner.txt")

        XCTAssertThrowsError(try runMove(["src", "dst/"], force: true))

        XCTAssertTrue(exists("dst/src/a.txt/inner.txt"), "directory at target path must not be deleted, even with -f")
    }

    func testMultiSourceMove() throws {
        try write("one", to: "x.txt")
        try write("two", to: "y.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        try runMove(["x.txt", "y.txt", "dst/"])

        XCTAssertFalse(exists("x.txt"))
        XCTAssertFalse(exists("y.txt"))
        XCTAssertEqual(read("dst/x.txt"), "one")
        XCTAssertEqual(read("dst/y.txt"), "two")
    }

    func testForceConflictWithBackupCleanedUp() throws {
        try write("NEW", to: "x.txt")
        try write("OLD", to: "dst/x.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        try runMove(["x.txt", "dst/"], force: true)

        XCTAssertEqual(read("dst/x.txt"), "NEW")
        // No leftover backup files
        let dstEntries = (try? FileManager.default.contentsOfDirectory(atPath: workDir.appendingPathComponent("dst").path)) ?? []
        for name in dstEntries {
            XCTAssertFalse(name.contains("icloud-backup"), "backup file left behind: \(name)")
        }
    }
}

/// Renderer that swallows all events. For tests that only care about filesystem outcomes.
private final class SilentRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?
    func handle(_ event: OpEvent) throws {}
    func finish() throws {}
}
