import XCTest

/// 긋기 미리보기의 "완성 글자"와 위치 설정.
final class GesturePreviewTextTests: XCTestCase {

    func testNoVowel_noText() {
        let viewModel = KeyboardViewModel(predictionEngine: PredictionEngine())
        XCTAssertNil(viewModel.gesturePreviewText(for: nil))
    }

    func testVowelOnly_whenNothingComposing() {
        let viewModel = KeyboardViewModel(predictionEngine: PredictionEngine())
        XCTAssertEqual(viewModel.gesturePreviewText(for: .ㅗ), "ㅗ")
        XCTAssertEqual(viewModel.gesturePreviewText(for: .ㆍ), "ㆍ")
    }

    /// 모음 키로 긋는 경우: 조합 중인 초성과 합친 글자를 보여 준다.
    func testComposingConsonant_combinesWithVowel() {
        let viewModel = KeyboardViewModel(predictionEngine: PredictionEngine())
        let delegate = PreviewTextDelegate()
        viewModel.delegate = delegate
        viewModel.inputConsonant(.ㅈ)
        XCTAssertEqual(viewModel.gesturePreviewText(for: .ㅗ), "조")
    }

    func testFixedPositions() {
        XCTAssertNil(GesturePreviewPosition.auto.fixedHorizontalFraction)
        XCTAssertLessThan(GesturePreviewPosition.topLeft.fixedHorizontalFraction!, 0.5)
        XCTAssertEqual(GesturePreviewPosition.topCenter.fixedHorizontalFraction, 0.5)
        XCTAssertGreaterThan(GesturePreviewPosition.topRight.fixedHorizontalFraction!, 0.5)
    }
}

private final class PreviewTextDelegate: KeyboardViewModelDelegate {
    var text = ""
    func insertText(_ string: String) { text.append(string) }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func updateComposingText(from previous: String, to current: String) {
        for _ in previous where !text.isEmpty { text.removeLast() }
        text.append(current)
    }
    func switchToNextKeyboard() {}
    func triggerHapticFeedback() {}
    func moveCursor(by offset: Int) {}
    func textBeforeCursor() -> String? { text }
}

/// AltStore 로 설치했을 때 바뀐 App Group ID 를 쓰는지.
final class AppGroupResolutionTests: XCTestCase {
    func testDefaultsToBaseId() {
        XCTAssertEqual(KeyboardSettings.resolvedAppGroupId(infoDictionary: nil), "group.com.moaki.keyboard")
        XCTAssertEqual(KeyboardSettings.resolvedAppGroupId(infoDictionary: [:]), "group.com.moaki.keyboard")
    }

    func testUsesAltStoreResignedGroup() {
        let info: [String: Any] = ["ALTAppGroups": ["group.other.app.ABCDE12345", "group.com.moaki.keyboard.ABCDE12345"]]
        XCTAssertEqual(KeyboardSettings.resolvedAppGroupId(infoDictionary: info), "group.com.moaki.keyboard.ABCDE12345")
    }

    func testIgnoresUnrelatedGroups() {
        let info: [String: Any] = ["ALTAppGroups": ["group.com.moaki.keyboardX"]]
        XCTAssertEqual(KeyboardSettings.resolvedAppGroupId(infoDictionary: info), "group.com.moaki.keyboard")
    }
}
