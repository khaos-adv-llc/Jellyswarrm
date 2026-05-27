// MARK: - KeychainTests.swift

@testable import JellyswarrmCore
import XCTest

final class KeychainTests: XCTestCase {
    func testSaveAndLoad() throws {
        let key = "test_key_\(UUID().uuidString)"
        let value = "test_secret_value"
        try KeychainManager.save(key: key, value: value)
        let loaded = try KeychainManager.load(key: key)
        XCTAssertEqual(loaded, value)
        try KeychainManager.delete(key: key)
    }

    func testLoadMissingKey() {
        XCTAssertThrowsError(try KeychainManager.load(key: "nonexistent_\(UUID().uuidString)"))
    }

    func testDeleteNonexistentIsOK() {
        XCTAssertNoThrow(try KeychainManager.delete(key: "nonexistent_\(UUID().uuidString)"))
    }
}
