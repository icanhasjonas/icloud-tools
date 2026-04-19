import XCTest
@testable import icloud

final class DownloaderTests: XCTestCase {
    private func makeFile(status: ICloudStatus, ubiquitous: Bool = true, size: Int64 = 100, allocated: Int64 = 100) -> ICloudFile {
        ICloudFile(
            url: URL(fileURLWithPath: "/tmp/x"),
            name: "x",
            isDirectory: false,
            status: status,
            fileSize: size,
            allocatedSize: allocated,
            isUbiquitous: ubiquitous,
            isPinned: false,
            tagNames: []
        )
    }

    // Regression: v0.6.4 and audit follow-up. .downloading and dataless files were silently skipped
    // and mv/cp proceeded with dataless content. They must be picked up for download.

    func testCloudNeedsDownload() {
        XCTAssertTrue(Downloader.needsDownload(makeFile(status: .cloud, size: 100, allocated: 0)))
    }

    func testDownloadingStatusNeedsWait() {
        XCTAssertTrue(Downloader.needsDownload(makeFile(status: .downloading, size: 100, allocated: 0)))
    }

    func testDatalessLocalStillNeeds() {
        XCTAssertTrue(Downloader.needsDownload(makeFile(status: .local, size: 100, allocated: 0)))
    }

    func testDatalessUnknownStillNeeds() {
        XCTAssertTrue(Downloader.needsDownload(makeFile(status: .unknown, size: 100, allocated: 0)))
    }

    func testLocalWithDataSkips() {
        XCTAssertFalse(Downloader.needsDownload(makeFile(status: .local, size: 100, allocated: 100)))
    }

    func testUploadingSkips() {
        XCTAssertFalse(Downloader.needsDownload(makeFile(status: .uploading, size: 100, allocated: 100)))
    }

    func testExcludedSkips() {
        XCTAssertFalse(Downloader.needsDownload(makeFile(status: .excluded, size: 100, allocated: 100)))
    }

    func testNonUbiquitousSkips() {
        XCTAssertFalse(Downloader.needsDownload(makeFile(status: .cloud, ubiquitous: false)))
    }

    func testZeroByteLocalNotDataless() {
        // fileSize == 0 && allocated == 0 is an empty file, not dataless
        XCTAssertFalse(Downloader.needsDownload(makeFile(status: .local, size: 0, allocated: 0)))
    }
}
