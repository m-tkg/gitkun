import XCTest
@testable import gitkunCore

final class SystemSoundNamesTests: XCTestCase {

    func testExtractsAndSortsAiffNamesIgnoringOtherFiles() {
        let files = ["Glass.aiff", "Basso.aiff", "readme.txt", "Ping.aiff", ".DS_Store"]
        let names = SystemSoundNames.names(fromFiles: files)
        XCTAssertEqual(names, ["Basso", "Glass", "Ping"])
    }

    func testEmptyListFallsBackToGlass() {
        XCTAssertEqual(SystemSoundNames.names(fromFiles: []), ["Glass"])
    }

    func testNonAiffOnlyFallsBackToGlass() {
        XCTAssertEqual(SystemSoundNames.names(fromFiles: ["readme.txt", ".DS_Store"]), ["Glass"])
    }

    func testResultIsSorted() {
        let files = ["Zap.aiff", "Blow.aiff", "Funk.aiff"]
        XCTAssertEqual(SystemSoundNames.names(fromFiles: files), ["Blow", "Funk", "Zap"])
    }
}
