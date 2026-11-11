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

    func testSpaceHoldsWord_nextLetterLearnsIt_secondUseSuggestsIt() {
        delegate.text = "감정평가서"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        XCTAssertNil(engine.model.words["감정평가서"], "끝내자마자 배우지 않고 보류한다 (바로 지우면 오타)")

        delegate.text = "감정평가서 감"
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["감정평가서"]?.count, 1, "다음 글자를 치면 배운다")
        XCTAssertEqual(viewModel.predictionSuggestions, [], "한 번 쓴 단어는 아직 추천하지 않는다")

        delegate.text = "감정평가서 감정평가서"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        delegate.text += "감정"
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["감정평가서"]?.count, 2)
        XCTAssertEqual(viewModel.predictionSuggestions, ["감정평가서"])
        XCTAssertEqual(engine.model.stats.shown, 1)
    }

    func testBackspaceRightAfterWord_doesNotLearnIt() {
        delegate.text = "안녕하세오"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.deleteBackward()
        XCTAssertEqual(delegate.text, "안녕하세오")
        viewModel.flushPredictionSave()
        XCTAssertTrue(engine.model.words.isEmpty, "끝내자마자 지운 단어는 오타로 보고 배우지 않는다")
    }

    func testBackspaceThenRetypedWord_learnsCorrectedWord() {
        delegate.text = "안녕하세오"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.deleteBackward()
        delegate.text = "안녕하세요"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.flushPredictionSave()
        XCTAssertNil(engine.model.words["안녕하세오"])
        XCTAssertEqual(engine.model.words["안녕하세요"]?.count, 1)
    }

    func testBackspaceInsideNextWord_keepsPreviousWord() {
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        delegate.text = "안녕 하"
        viewModel.refreshPredictions()
        viewModel.deleteBackward()
        XCTAssertEqual(engine.model.words["안녕"]?.count, 1, "다음 단어를 고치는 백스페이스는 앞 단어와 상관없다")
    }

    func testCloseKeyboard_learnsHeldWord() {
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.flushPredictionSave()
        XCTAssertEqual(engine.model.words["안녕"]?.count, 1)
    }

    func testSecondSpaceDoesNotLearnSameWordTwice() {
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.flushPredictionSave()
        XCTAssertEqual(engine.model.words["안녕"]?.count, 1)
    }

    func testLearningOff_doesNotLearn() {
        KeyboardSettings.shared.predictionLearningEnabled = false
        delegate.text = "안녕"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.flushPredictionSave()
        XCTAssertTrue(engine.model.words.isEmpty)
    }

    func testHostDisallowsLearning_doesNotLearn() {
        delegate.allowsLearning = false
        delegate.text = "secretword"
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        viewModel.flushPredictionSave()
        XCTAssertTrue(engine.model.words.isEmpty)
    }

    func testAcceptPrediction_replacesPartialWordAndAddsSpace() {
        engine.learn(word: "안녕하세요", previous: nil)
        delegate.text = "네 안녀"
        viewModel.acceptPrediction("안녕하세요")
        XCTAssertEqual(delegate.text, "네 안녕하세요 ")
        XCTAssertEqual(engine.model.stats.accepted, 1)
        XCTAssertEqual(engine.model.stats.savedCharacters, 3, "다섯 글자 중 두 글자는 이미 쳤다")
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
