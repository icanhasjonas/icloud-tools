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

    @discardableResult
    private func runMove(_ paths: [String], force: Bool = false, noClobber: Bool = false, ignoreMissing: Bool = false, pruneSource: Bool = false) throws -> SilentRenderer {
        let renderer = SilentRenderer()
        let absolute = paths.map { workDir.appendingPathComponent($0).path }
        try FileOperation.execute(
            paths: absolute,
            verb: .move,
            allowDirectories: true,
            force: force,
            noClobber: noClobber,
            ignoreMissing: ignoreMissing,
            pruneSource: pruneSource,
            renderer: renderer
        ) { fm, src, dst in
            try fm.moveItem(at: src, to: dst)
        }
        return renderer
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

    func testMissingSourceThrowsByDefault() throws {
        try write("one", to: "a.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try runMove(["a.txt", "nope.txt", "dst/"])) { error in
            if case .sourceNotFound = error as? FileOperationError { return }
            XCTFail("expected sourceNotFound, got \(error)")
        }
    }

    func testIgnoreMissingWarnsAndContinues() throws {
        try write("one", to: "a.txt")
        try write("two", to: "b.txt")
        try write("three", to: "c.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        let renderer = try runMove(["a.txt", "b.txt", "nope.txt", "c.txt", "dst/"], ignoreMissing: true)

        XCTAssertEqual(read("dst/a.txt"), "one", "a should be moved")
        XCTAssertEqual(read("dst/b.txt"), "two", "b should be moved")
        XCTAssertEqual(read("dst/c.txt"), "three", "c should be moved AFTER the missing one")
        XCTAssertFalse(exists("dst/nope.txt"), "missing source must not produce a destination")
        XCTAssertEqual(renderer.missing.count, 1, "expected exactly one sourceMissing event")
        XCTAssertEqual(renderer.missing.first?.lastPathComponent, "nope.txt")
    }

    func testPartialFailureErrorIncludesCount() throws {
        try write("a", to: "src/a.txt")
        try write("b", to: "src/b.txt")
        try write("c", to: "src/c.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        enum FakeOp: Error { case simulated }
        let renderer = SilentRenderer()
        let srcPath = workDir.appendingPathComponent("src").path
        let dstPath = workDir.appendingPathComponent("dst/").path

        var caught: Error?
        do {
            try FileOperation.execute(
                paths: [srcPath, dstPath],
                verb: .move,
                allowDirectories: true,
                force: false, noClobber: false,
                renderer: renderer
            ) { _, _, _ in
                throw FakeOp.simulated
            }
        } catch {
            caught = error
        }

        guard let err = caught as? FileOperationError,
              case .partialFailure(_, let n) = err else {
            XCTFail("expected partialFailure, got \(String(describing: caught))")
            return
        }
        XCTAssertEqual(n, 3, "all 3 files failed")
        XCTAssertTrue(err.localizedDescription.contains("3"), "error message must include the count: \(err.localizedDescription)")
    }

    func testFailedOperationCleansUpCreatedParentDirs() throws {
        try write("hello", to: "src.txt")
        // `dst/deep/nested/out.txt` -- none of dst, dst/deep, dst/deep/nested exists yet.
        enum FakeOp: Error { case simulated }
        let renderer = SilentRenderer()
        let srcPath = workDir.appendingPathComponent("src.txt").path
        let dstPath = workDir.appendingPathComponent("dst/deep/nested/out.txt").path

        XCTAssertThrowsError(try FileOperation.execute(
            paths: [srcPath, dstPath],
            verb: .move,
            allowDirectories: true,
            force: false, noClobber: false,
            renderer: renderer
        ) { _, _, _ in
            throw FakeOp.simulated
        })

        XCTAssertFalse(exists("dst/deep/nested"), "innermost created dir must be cleaned up")
        XCTAssertFalse(exists("dst/deep"), "middle created dir must be cleaned up")
        XCTAssertFalse(exists("dst"), "outermost created dir must be cleaned up")
        XCTAssertTrue(exists("src.txt"), "source file must survive a failed op")
    }

    func testCleanupStopsAtPreExistingDir() throws {
        // Pre-create dst/. Op fails. dst/ must survive. dst/deep (created by us) must not.
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)
        try write("hello", to: "src.txt")
        enum FakeOp: Error { case simulated }
        let renderer = SilentRenderer()
        let srcPath = workDir.appendingPathComponent("src.txt").path
        let dstPath = workDir.appendingPathComponent("dst/deep/out.txt").path

        XCTAssertThrowsError(try FileOperation.execute(
            paths: [srcPath, dstPath],
            verb: .move,
            allowDirectories: true,
            force: false, noClobber: false,
            renderer: renderer
        ) { _, _, _ in
            throw FakeOp.simulated
        })

        XCTAssertFalse(exists("dst/deep"), "created subdir must be cleaned up")
        XCTAssertTrue(exists("dst"), "pre-existing dir must NOT be removed")
    }

    func testCleanupDoesNotTouchNonEmptyDirs() throws {
        // Pre-populate dst/deep with an unrelated file. Op fails. dst/deep must survive.
        try write("survivor", to: "dst/deep/unrelated.txt")
        try write("hello", to: "src.txt")
        enum FakeOp: Error { case simulated }
        let renderer = SilentRenderer()
        let srcPath = workDir.appendingPathComponent("src.txt").path
        let dstPath = workDir.appendingPathComponent("dst/deep/out.txt").path

        XCTAssertThrowsError(try FileOperation.execute(
            paths: [srcPath, dstPath],
            verb: .move,
            allowDirectories: true,
            force: false, noClobber: false,
            renderer: renderer
        ) { _, _, _ in
            throw FakeOp.simulated
        })

        XCTAssertTrue(exists("dst/deep/unrelated.txt"), "non-empty dir must NOT be removed")
    }

    // MARK: - --prune-source

    func testPruneSourceDeletesWhenSizeMatches() throws {
        try write("hello world", to: "a.txt")          // 11 bytes
        try write("hello world", to: "dst/a.txt")       // 11 bytes -- size match

        let renderer = try runMove(["a.txt", "dst/"], noClobber: true, pruneSource: true)

        XCTAssertFalse(exists("a.txt"), "source must be unlinked when sizes match")
        XCTAssertEqual(read("dst/a.txt"), "hello world", "destination must be untouched")
        XCTAssertEqual(renderer.pruned.count, 1, "one opPruned event expected")
        XCTAssertEqual(renderer.skipped.count, 0, "size-match should NOT emit opSkipped")
    }

    func testPruneSourceKeepsWhenSizeDiffers() throws {
        try write("hello world", to: "a.txt")          // 11 bytes
        try write("DIFFERENT CONTENT HERE", to: "dst/a.txt")  // 22 bytes -- size mismatch

        let renderer = try runMove(["a.txt", "dst/"], noClobber: true, pruneSource: true)

        XCTAssertTrue(exists("a.txt"), "source must survive when sizes differ")
        XCTAssertEqual(read("dst/a.txt"), "DIFFERENT CONTENT HERE", "destination must be untouched")
        XCTAssertEqual(renderer.pruned.count, 0, "no prune on size mismatch")
        XCTAssertEqual(renderer.skipped.count, 1, "falls through to normal noClobber skip")
    }

    func testPruneSourceMovesWhenDestAbsent() throws {
        try write("hello", to: "a.txt")
        try FileManager.default.createDirectory(at: workDir.appendingPathComponent("dst"), withIntermediateDirectories: true)

        let renderer = try runMove(["a.txt", "dst/"], noClobber: true, pruneSource: true)

        XCTAssertFalse(exists("a.txt"), "source moved into dst")
        XCTAssertEqual(read("dst/a.txt"), "hello")
        XCTAssertEqual(renderer.pruned.count, 0, "flag is a no-op when dst doesn't exist")
    }

    func testPruneSourceRefusesSamePath() throws {
        // src and dst point at the same file. Without the same-path guard we'd unlink
        // the user's only copy. Regression guard.
        try write("important", to: "a.txt")

        let renderer = SilentRenderer()
        let path = workDir.appendingPathComponent("a.txt").path

        // Single source + single file dest = same-path move. Normally a no-op move.
        // Execute WILL fail because default mv -n throws on existing dest, but we
        // want the prune path to also refuse -- the file must survive either way.
        _ = try? FileOperation.execute(
            paths: [path, path],
            verb: .move,
            allowDirectories: true,
            force: false, noClobber: true,
            ignoreMissing: false, pruneSource: true,
            renderer: renderer
        ) { fm, src, dst in
            try fm.moveItem(at: src, to: dst)
        }

        XCTAssertTrue(exists("a.txt"), "same-path prune must NEVER delete the only copy")
        XCTAssertEqual(renderer.pruned.count, 0, "same-path must not emit opPruned")
    }

    func testPruneSourceMixedBatch() throws {
        // 3 sources: one matches (prune), one mismatches (skip), one is new (move).
        try write("same", to: "a.txt")
        try write("same", to: "dst/a.txt")            // match -> prune
        try write("big content here", to: "b.txt")
        try write("small", to: "dst/b.txt")           // mismatch -> skip
        try write("fresh", to: "c.txt")                // dst/c.txt doesn't exist -> move

        let renderer = try runMove(["a.txt", "b.txt", "c.txt", "dst/"], noClobber: true, pruneSource: true)

        XCTAssertFalse(exists("a.txt"), "pruned source gone")
        XCTAssertTrue(exists("b.txt"), "skipped source remains")
        XCTAssertFalse(exists("c.txt"), "moved source gone")
        XCTAssertEqual(read("dst/a.txt"), "same", "pruned dst untouched")
        XCTAssertEqual(read("dst/b.txt"), "small", "skipped dst untouched")
        XCTAssertEqual(read("dst/c.txt"), "fresh", "moved dst populated")
        XCTAssertEqual(renderer.pruned.count, 1)
        XCTAssertEqual(renderer.skipped.count, 1)
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

/// Renderer that swallows output but records events for assertion.
private final class SilentRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?
    private(set) var missing: [URL] = []
    private(set) var pruned: [URL] = []
    private(set) var skipped: [(URL, String)] = []
    func handle(_ event: OpEvent) throws {
        switch event {
        case .sourceMissing(let src): missing.append(src)
        case .opPruned(_, let src, _, _): pruned.append(src)
        case .opSkipped(_, let src, _, let reason, _): skipped.append((src, reason))
        default: break
        }
    }
    func finish() throws {}
}
