import XCTest

/// 단어 추천 바와 키보드 뷰모델의 연결 (학습 시점, 추천 선택, 바 표시 조건).
final class KeyboardViewModelPredictionTests: XCTestCase {
    private var viewModel: KeyboardViewModel!
    private var delegate: PredictionTextDelegate!
    private var engine: PredictionEngine!

    private var savedStore: ShortcutExpansionStore!
    private var savedPeriodEnabled: Bool!
    private var savedPredictionEnabled: Bool!
    private var savedLearningEnabled: Bool!
    private var savedResetToken: String!

    override func setUp() {
        super.setUp()
        let settings = KeyboardSettings.shared
        savedStore = settings.shortcutExpansionStore
        savedPeriodEnabled = settings.periodOnDoubleSpaceEnabled
        savedPredictionEnabled = settings.predictionEnabled
        savedLearningEnabled = settings.predictionLearningEnabled
        savedResetToken = settings.predictionResetToken
        // 약어 확장·마침표 단축키가 끼어들지 않게 끈다.
        settings.shortcutExpansionStore = ShortcutExpansionStore()
        settings.periodOnDoubleSpaceEnabled = false
        settings.predictionEnabled = true
        settings.predictionLearningEnabled = true
        settings.predictionResetToken = ""

        engine = PredictionEngine()
        delegate = PredictionTextDelegate()
        viewModel = KeyboardViewModel(predictionEngine: engine)
        viewModel.delegate = delegate
    }

    override func tearDown() {
        let settings = KeyboardSettings.shared
        settings.shortcutExpansionStore = savedStore
        settings.periodOnDoubleSpaceEnabled = savedPeriodEnabled
        settings.predictionEnabled = savedPredictionEnabled
        settings.predictionLearningEnabled = savedLearningEnabled
        settings.predictionResetToken = savedResetToken
        viewModel = nil
        delegate = nil
        engine = nil
        super.tearDown()
    }

    func testSpaceLearnsWord_thenPrefixSuggestsIt() {
        delegate.text = "감정평가서"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["감정평가서"]?.count, 1)

        delegate.text = "감정평가서 감정"
        viewModel.refreshPredictions()
        XCTAssertEqual(viewModel.predictionSuggestions, ["감정평가서"])
    }

    func testSecondSpaceDoesNotLearnSameWordTwice() {
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["안녕"]?.count, 1)
    }

    func testLearningOff_doesNotLearn() {
        KeyboardSettings.shared.predictionLearningEnabled = false
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        XCTAssertTrue(engine.model.words.isEmpty)
    }

    func testHostDisallowsLearning_doesNotLearn() {
        delegate.allowsLearning = false
        delegate.text = "secretword"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        XCTAssertTrue(engine.model.words.isEmpty)
    }

    func testAcceptPrediction_replacesPartialWordAndAddsSpace() {
        engine.learn(word: "안녕하세요", previous: nil)
        delegate.text = "네 안녀"
        viewModel.acceptPrediction("안녕하세요")
        XCTAssertEqual(delegate.text, "네 안녕하세요 ")
    }

    func testAcceptPrediction_afterSpaceAppendsNextWord() {
        delegate.text = "감사 "
        viewModel.acceptPrediction("드립니다")
        XCTAssertEqual(delegate.text, "감사 드립니다 ")
    }

    func testForgetPrediction_removesWord() {
        engine.learn(word: "오타단어", previous: nil)
        viewModel.forgetPrediction("오타단어")
        XCTAssertNil(engine.model.words["오타단어"])
    }

    func testCandidateBarVisibility() {
        XCTAssertTrue(viewModel.isCandidateBarVisible, "추천을 켜면 바 자리를 항상 지킨다")

        viewModel.previewMode = true
        XCTAssertFalse(viewModel.isCandidateBarVisible, "설정 미리보기에는 추천 바를 그리지 않는다")
        viewModel.previewMode = false

        KeyboardSettings.shared.predictionEnabled = false
        XCTAssertFalse(viewModel.isCandidateBarVisible)

        viewModel.isAbbreviationCandidateVisible = true
        XCTAssertTrue(viewModel.isCandidateBarVisible, "약어 후보는 추천 설정과 상관없이 뜬다")
    }

    func testResetToken_clearsLearnedWords() {
        engine.learn(word: "안녕", previous: nil)
        KeyboardSettings.shared.predictionResetToken = "reset-1"
        XCTAssertTrue(engine.model.words.isEmpty)
        XCTAssertEqual(engine.model.appliedResetToken, "reset-1")
    }
}

private final class PredictionTextDelegate: KeyboardViewModelDelegate {
    var text: String = ""
    var allowsLearning = true

    func insertText(_ string: String) { text.append(string) }

    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    func updateComposingText(from previous: String, to current: String) {
        for _ in previous where !text.isEmpty { text.removeLast() }
        text.append(current)
    }

    func switchToNextKeyboard() {}
    func triggerHapticFeedback() {}
    func moveCursor(by offset: Int) {}
    func textBeforeCursor() -> String? { text }
    func hostAllowsLearning() -> Bool { allowsLearning }
}
