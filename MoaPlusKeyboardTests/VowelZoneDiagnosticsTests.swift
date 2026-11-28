import XCTest
@testable import MoaPlusKeyboard

/// 구역 보기 진단 (새모아 2026-11-28). 실기기에서 앱 스위치는 켜짐인데 키보드는 꺼짐을 들고 있었다 —
/// 키보드가 들고 있던 값과 누른 순간 저장소에서 바로 읽은 값을 견줘 어긋남을 세야 한다.
final class VowelZoneDiagnosticsTests: XCTestCase {

    func test_recordPress_countsShownAndMismatches() {
        var d = VowelZoneDiagnostics(since: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(d.recordPress(held: true, stored: true))
        XCTAssertTrue(d.recordPress(held: false, stored: true))    // 저장소는 켜짐인데 키보드는 꺼짐 = 제보 상태
        XCTAssertFalse(d.recordPress(held: false, stored: nil))    // 값 없음 = 기본 꺼짐
        XCTAssertTrue(d.recordPress(held: true, stored: false))
        XCTAssertEqual(d.presses, 4)
        XCTAssertEqual(d.shown, 2)
        XCTAssertEqual(d.mismatches, 2)
        XCTAssertEqual(d.lastHeld, true)
        XCTAssertEqual(d.lastStored, false)
        XCTAssertNotNil(d.lastMismatchAt)
    }

    func test_line_showsHeldStoredAndReload() {
        var d = VowelZoneDiagnostics(since: Date())
        d.recordPress(held: false, stored: true)
        let line = d.line(lastLoad: (at: Date(), reason: "키보드 뜸", vowelZone: false), notices: 3, dropped: 1)
        XCTAssertTrue(line.contains("자음 누름 1"), line)
        XCTAssertTrue(line.contains("구역 띄움 0"), line)
        XCTAssertTrue(line.contains("키보드 값 꺼짐 · 저장소 값 켜짐"), line)
        XCTAssertTrue(line.contains("어긋남 1 (마지막"), line)
        XCTAssertTrue(line.contains("키보드 뜸 · 그때 읽은 값 꺼짐"), line)
        XCTAssertTrue(line.contains("앱 알림 받음 3 · 겹쳐 버림 1"), line)

        let empty = VowelZoneDiagnostics().line(lastLoad: nil, notices: 0, dropped: 0)
        XCTAssertTrue(empty.contains("자음 누름 0"), empty)
        XCTAssertTrue(empty.contains("키보드 값 - · 저장소 값 -"), empty)
        XCTAssertTrue(empty.contains("설정 다시 읽음 -"), empty)
    }

    func test_loadAll_recordsReasonAndReadValue() {
        let s = KeyboardSettings.shared
        s.loadAll(reason: .keyboardAppeared)
        XCTAssertEqual(s.lastLoad?.reason, .keyboardAppeared)
        XCTAssertEqual(s.lastLoad?.vowelZone, s.showVowelZoneOnPress)
        XCTAssertEqual(s.storedShowVowelZoneOnPress() ?? false, s.showVowelZoneOnPress)
    }
}
