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
    private var savedAutoSpaceEnabled: Bool!

    override func setUp() {
        super.setUp()
        let settings = KeyboardSettings.shared
        savedStore = settings.shortcutExpansionStore
        savedPeriodEnabled = settings.periodOnDoubleSpaceEnabled
        savedPredictionEnabled = settings.predictionEnabled
        savedLearningEnabled = settings.predictionLearningEnabled
        savedResetToken = settings.predictionResetToken
        savedAutoSpaceEnabled = settings.autoSpaceOnPauseEnabled
        settings.autoSpaceOnPauseEnabled = true
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
        settings.autoSpaceOnPauseEnabled = savedAutoSpaceEnabled
        KeyboardViewModel.autoSpaceDelay = 1.0
        viewModel?.cancelAutoSpace()
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

    // MARK: - 구절 (개선 방안 10번 넓힘)

    func testTypedPhraseTwice_isSuggestedWhileTypingFirstWord() {
        for _ in 0..<2 {
            delegate.text = "수고"
            viewModel.inputSpace()
            viewModel.refreshPredictions()
            delegate.text += "많으셨습니다"
            viewModel.inputSpace()
            viewModel.refreshPredictions()
            delegate.text += "다음"
            viewModel.refreshPredictions()
            viewModel.inputReturn()
            viewModel.refreshPredictions()
            delegate.text = ""
        }
        delegate.text = "수"
        viewModel.refreshPredictions()
        XCTAssertTrue(viewModel.predictionSuggestions.contains("수고 많으셨습니다"), "\(viewModel.predictionSuggestions)")
    }

    func testAcceptPhrase_insertsWholePhraseAndCountsWords() {
        engine.apply(edits: [PredictionEditRequest(id: 1, edit: .addPhrase("수고 많으셨습니다"))])
        delegate.text = "네 수"
        viewModel.acceptPrediction("수고 많으셨습니다")
        XCTAssertEqual(delegate.text, "네 수고 많으셨습니다 ")
        XCTAssertEqual(engine.model.words["수고"]?.count, 1, "안쪽 단어는 고를 때 센다")
        viewModel.refreshPredictions()
        delegate.text += "다"
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["많으셨습니다"]?.count, 1, "마지막 단어는 직접 친 단어처럼 보류했다 배운다")
        XCTAssertEqual(engine.model.phrases["수고 많으셨습니다"]?.count, 3, "직접 넣은 2 + 고른 1")
    }

    func testForgetPrediction_phrase() {
        engine.apply(edits: [PredictionEditRequest(id: 1, edit: .addPhrase("수고 많으셨습니다"))])
        viewModel.forgetPrediction("수고 많으셨습니다")
        XCTAssertTrue(engine.model.phrases.isEmpty)
    }

    // MARK: - 추천 고른 뒤 문장부호 붙이기 (개선 방안 9번)

    func testAcceptPrediction_thenPunctuation_attachesToWord() {
        for mark in ["?", ".", ",", "!"] {
            delegate.text = "감사합"
            viewModel.acceptPrediction("감사합니다")
            viewModel.inputSymbol(mark)
            XCTAssertEqual(delegate.text, "감사합니다" + mark, "추천이 붙인 공백은 지우고 붙인다 (\(mark))")
        }
    }

    func testAcceptPrediction_thenSpaceThenPunctuation_keepsUserSpace() {
        delegate.text = "감사합"
        viewModel.acceptPrediction("감사합니다")
        viewModel.inputSpace()
        viewModel.inputSymbol("?")
        XCTAssertTrue(delegate.text.hasSuffix(" ?"), "직접 친 스페이스 뒤는 지우지 않는다: \(delegate.text)")
    }

    func testAcceptPrediction_thenLetterThenPunctuation_doesNotEatSpace() {
        delegate.text = "감사 "
        viewModel.acceptPrediction("드립니다")
        typeGa()
        viewModel.inputSymbol("?")
        XCTAssertEqual(delegate.text, "감사 드립니다 가?")
    }

    func testAcceptPrediction_thenOtherSymbol_keepsSpace() {
        delegate.text = "감사합"
        viewModel.acceptPrediction("감사합니다")
        viewModel.inputSymbol("~")
        XCTAssertEqual(delegate.text, "감사합니다 ~", ". , ? ! 밖의 기호는 그대로")
    }

    func testAcceptPrediction_thenCursorMove_doesNotAttach() {
        delegate.text = "감사합"
        viewModel.acceptPrediction("감사합니다")
        viewModel.moveCursor(by: -1)
        XCTAssertFalse(viewModel.autoSpaceJustInserted, "커서를 옮기면 붙이기를 끈다")
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

    // MARK: - 직접 넣은 단어 (「학습한 단어」 화면, 2026-11-12)

    func testManualSymbolWord_isLearnedWhole_notItsLetterPart() {
        engine.apply(edits: [PredictionEditRequest(id: 1, edit: .add("A-4"))])
        delegate.text = "A"
        viewModel.inputSymbol("-")
        viewModel.refreshPredictions()
        XCTAssertEqual(viewModel.predictionSuggestions, ["A-4"])
        delegate.text += "4"
        viewModel.refreshPredictions()
        viewModel.inputSpace()
        viewModel.refreshPredictions()
        delegate.text += "다"
        viewModel.refreshPredictions()
        XCTAssertEqual(engine.model.words["A-4"]?.count, 3)
        XCTAssertNil(engine.model.words["A"], "직접 넣은 단어를 치는 도중 앞부분을 따로 배우지 않는다")
    }

    func testAcceptManualDigitWord_replacesDigitPrefix() {
        engine.apply(edits: [PredictionEditRequest(id: 1, edit: .add("3층"))])
        delegate.text = "회의는 3"
        viewModel.refreshPredictions()
        XCTAssertEqual(viewModel.predictionSuggestions, ["3층"])
        viewModel.acceptPrediction("3층")
        XCTAssertEqual(delegate.text, "회의는 3층 ")
    }

    // MARK: - 멈추면 저절로 띄기 (2026-11-11)

    private func typeGa() {
        viewModel.inputConsonant(.ㄱ)
        viewModel.inputVowel(.ㅏ)
    }

    private func spinMainQueue(for seconds: TimeInterval) {
        let done = expectation(description: "main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    func testAutoSpace_insertsSpaceAfterHangul() {
        typeGa()
        XCTAssertEqual(delegate.text, "가")
        XCTAssertTrue(viewModel.insertAutoSpaceIfAppropriate())
        XCTAssertEqual(delegate.text, "가 ")
        XCTAssertTrue(viewModel.autoSpaceJustInserted)
    }

    func testAutoSpace_timerFiresAfterPause() {
        KeyboardViewModel.autoSpaceDelay = 0.05
        typeGa()
        spinMainQueue(for: 0.3)
        XCTAssertEqual(delegate.text, "가 ")
    }

    func testAutoSpace_keyPressCancelsWaiting() {
        KeyboardViewModel.autoSpaceDelay = 0.05
        typeGa()
        viewModel.keyPressFeedback()
        spinMainQueue(for: 0.3)
        XCTAssertEqual(delegate.text, "가", "키를 누르는 순간 기다리던 띄기를 멈춘다")
    }

    func testAutoSpace_pausedAfterBackspace_untilUserSpace() {
        typeGa()
        viewModel.deleteBackward()
        viewModel.inputConsonant(.ㄱ)
        viewModel.inputVowel(.ㅏ)
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate(), "백스페이스 뒤에는 고치는 동안 띄지 않는다")
        viewModel.inputSpace()
        viewModel.inputConsonant(.ㄴ)
        viewModel.inputVowel(.ㅏ)
        XCTAssertTrue(viewModel.insertAutoSpaceIfAppropriate(), "직접 스페이스로 다음 단어로 넘어가면 다시 켠다")
    }

    func testAutoSpace_acceptPredictionResumes() {
        typeGa()
        viewModel.deleteBackward()
        viewModel.acceptPrediction("가나")
        viewModel.inputConsonant(.ㄷ)
        viewModel.inputVowel(.ㅏ)
        XCTAssertTrue(viewModel.insertAutoSpaceIfAppropriate())
    }

    func testAutoSpace_punctuationRightAfterAttaches() {
        typeGa()
        viewModel.insertAutoSpaceIfAppropriate()
        viewModel.inputSymbol(".")
        XCTAssertEqual(delegate.text, "가.")
    }

    func testAutoSpace_punctuationAfterUserSpaceStaysSpaced() {
        typeGa()
        viewModel.inputSpace()
        viewModel.inputSymbol(".")
        XCTAssertEqual(delegate.text, "가 .", "직접 친 공백은 지우지 않는다")
    }

    func testAutoSpace_thenSpace_givesPeriodWhenShortcutOn() {
        KeyboardSettings.shared.periodOnDoubleSpaceEnabled = true
        typeGa()
        viewModel.insertAutoSpaceIfAppropriate()
        viewModel.inputSpace()
        XCTAssertEqual(delegate.text, "가. ")
    }

    func testAutoSpace_skipsBlockedField() {
        delegate.allowsLearning = false
        typeGa()
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate())
        XCTAssertEqual(delegate.text, "가")
    }

    func testAutoSpace_skipsInsideText() {
        delegate.after = "뒤"
        typeGa()
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate(), "글 가운데에서는 띄지 않는다")
        delegate.after = "\n다음 줄"
        XCTAssertTrue(viewModel.insertAutoSpaceIfAppropriate(), "줄 끝이면 띄운다")
    }

    func testAutoSpace_skipsEnglishAndNonHangul() {
        delegate.text = "abc"
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate(), "맨 끝이 한글이 아니면 띄지 않는다")
        viewModel.keyboardMode = .english
        delegate.text = "가"
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate(), "영문 모드에서는 띄지 않는다")
    }

    func testAutoSpace_settingOff() {
        KeyboardSettings.shared.autoSpaceOnPauseEnabled = false
        typeGa()
        XCTAssertFalse(viewModel.insertAutoSpaceIfAppropriate())
    }

    func testAutoSpace_endSessionClearsBackspacePause() {
        typeGa()
        viewModel.deleteBackward()
        viewModel.endAutoSpaceSession()
        typeGa()
        XCTAssertTrue(viewModel.insertAutoSpaceIfAppropriate())
    }
}

private final class PredictionTextDelegate: KeyboardViewModelDelegate {
    var text: String = ""
    var after: String?
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
    func textAfterCursor() -> String? { after }
    func hostAllowsLearning() -> Bool { allowsLearning }
}
