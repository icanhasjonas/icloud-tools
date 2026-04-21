import XCTest
@testable import icloud

final class ScannerTests: XCTestCase {
    private func makeFile(status: ICloudStatus, size: Int64 = 100, allocated: Int64 = 100, ubiquitous: Bool = true) -> ICloudFile {
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

    // A file reporting .local but with size>0 && allocated==0 is dataless -- no bytes
    // on disk. It must count as cloud, not local, or `icloud status` lies about what's
    // actually downloaded.
    func testDatalessLocalCountsAsCloud() {
        let dataless = makeFile(status: .local, size: 100, allocated: 0)
        let realLocal = makeFile(status: .local, size: 100, allocated: 100)
        let realCloud = makeFile(status: .cloud, size: 100, allocated: 0)

        let r = ScanResult(files: [dataless, realLocal, realCloud])

        XCTAssertEqual(r.localCount, 1, "only the file with actual bytes is local")
        XCTAssertEqual(r.cloudCount, 2, "dataless + cloud both count as cloud")
    }

    func testDatalessLocalNotCountedInEvictable() {
        let dataless = makeFile(status: .local, size: 100, allocated: 0)
        let r = ScanResult(files: [dataless])
        XCTAssertEqual(r.totalEvictableSize, 0, "dataless files have no bytes to evict")
    }

    func testRealLocalContributesToEvictable() {
        let realLocal = makeFile(status: .local, size: 100, allocated: 100)
        let r = ScanResult(files: [realLocal])
        XCTAssertEqual(r.totalEvictableSize, 100)
    }

    func testZeroByteLocalIsLocalNotDataless() {
        // size==0 && allocated==0 is an empty file, not dataless.
        let empty = makeFile(status: .local, size: 0, allocated: 0)
        let r = ScanResult(files: [empty])
        XCTAssertEqual(r.localCount, 1)
        XCTAssertEqual(r.cloudCount, 0)
    }
}
