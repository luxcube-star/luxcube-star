import XCTest

/// 추천 바 칸 폭 (`PredictionBarLayout.widths`) — 4칸 · 단어 길이에 맞춘 폭 (사용자 결정 2026-11-13).
final class PredictionBarLayoutTests: XCTestCase {

    private func assertWidths(_ actual: [CGFloat], _ expected: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 0.001, file: file, line: line)
        }
    }

    func testFits_eachGetsOwnWidthPlusEqualShareOfLeftover() {
        // 합 200, 바 400 → 남는 200 을 넷이 50 씩
        assertWidths(PredictionBarLayout.widths(natural: [30, 50, 40, 80], available: 400), [80, 100, 90, 130])
    }

    func testFits_sumIsBarWidth() {
        let widths = PredictionBarLayout.widths(natural: [42, 99, 57], available: 394)
        XCTAssertEqual(widths.reduce(0, +), 394, accuracy: 0.001)
    }

    func testOverflow_shortWordsKeptLongestShrinks() {
        // 합 420 > 300: 30·50 은 그대로, 남은 220 을 긴 둘이 110 씩
        assertWidths(PredictionBarLayout.widths(natural: [30, 200, 50, 140], available: 300), [30, 110, 50, 110])
    }

    func testOverflow_allLong_equalSplit() {
        assertWidths(PredictionBarLayout.widths(natural: [200, 150, 180, 160], available: 400), [100, 100, 100, 100])
    }

    func testOverflow_sumIsBarWidth() {
        let widths = PredictionBarLayout.widths(natural: [70, 130, 95, 160], available: 394)
        XCTAssertEqual(widths.reduce(0, +), 394, accuracy: 0.001)
        XCTAssertEqual(widths[0], 70, accuracy: 0.001, "가장 짧은 단어는 잘리지 않는다")
    }

    func testEmptyAndZeroWidth() {
        XCTAssertEqual(PredictionBarLayout.widths(natural: [], available: 300), [])
        assertWidths(PredictionBarLayout.widths(natural: [10, 20], available: 0), [0, 0])
    }
}
