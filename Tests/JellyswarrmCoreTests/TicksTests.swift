// MARK: - TicksTests.swift
import XCTest
@testable import JellyswarrmCore

final class TicksTests: XCTestCase {
    func testTicksToSeconds() {
        let ticks: Int64 = 36_000_000_000  // 1 hour
        XCTAssertEqual(ticks.ticksToSeconds, 3600.0)
    }

    func testSecondsToTicks() {
        let seconds: Double = 3600
        XCTAssertEqual(seconds.secondsToTicks, 36_000_000_000)
    }

    func testDurationString() {
        let ticks: Int64 = 5_400_000_000  // 1h 30m
        XCTAssertEqual(ticks.ticksToDurationString, "1h 30m")
    }
}
