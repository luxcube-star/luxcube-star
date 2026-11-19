import XCTest

/// 학습형 단어 추천 엔진 (`PredictionEngine`) 단위 테스트.
final class PredictionEngineTests: XCTestCase {

    // MARK: - 자모 키

    func testMatchKey_decomposesSyllablesAndCompounds() {
        XCTAssertEqual(PredictionEngine.matchKey(for: "간"), "ㄱㅏㄴ")
        XCTAssertEqual(PredictionEngine.matchKey(for: "과"), "ㄱㅗㅏ")
        XCTAssertEqual(PredictionEngine.matchKey(for: "닭"), "ㄷㅏㄹㄱ")
        XCTAssertEqual(PredictionEngine.matchKey(for: "ㄺ"), "ㄹㄱ")
        XCTAssertEqual(PredictionEngine.matchKey(for: "Hello"), "hello")
    }

    // MARK: - 단어 완성

    func testCompletion_matchesWhileFinalConsonantIsStillAttached() {
        // 모아키는 "가나다" 를 치는 도중 "간" 을 거친다 — 그래도 후보가 떠야 한다.
        let engine = PredictionEngine()
        engine.learn("가나다", times: 2)
        XCTAssertEqual(engine.suggestions(prefix: "간", previous: nil), ["가나다"])
        XCTAssertEqual(engine.suggestions(prefix: "가", previous: nil), ["가나다"])
    }

    func testCompletion_matchesPartialSyllable() {
        let engine = PredictionEngine()
        engine.learn("안녕하세요", times: 2)
        XCTAssertEqual(engine.suggestions(prefix: "안녀", previous: nil), ["안녕하세요"])
        XCTAssertEqual(engine.suggestions(prefix: "안녕ㅎ", previous: nil), ["안녕하세요"])
    }

    func testCompletion_hidesWordUsedOnlyOnce() {
        // 한 번 잘못 친 오타가 추천에 뜨지 않게, 두 번 써야 보여 준다 (배우기는 처음부터).
        let engine = PredictionEngine()
        engine.learn(word: "안녕하세오", previous: nil)
        XCTAssertEqual(engine.model.words["안녕하세오"]?.count, 1)
        XCTAssertEqual(engine.suggestions(prefix: "안녀", previous: nil), [])
        engine.learn(word: "안녕하세오", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "안녀", previous: nil), ["안녕하세오"])
    }

    func testCompletion_excludesExactWord() {
        let engine = PredictionEngine()
        engine.learn("감정", times: 2)
        engine.learn("감정평가서", times: 2)
        XCTAssertEqual(engine.suggestions(prefix: "감정", previous: nil), ["감정평가서"])
    }

    func testCompletion_ranksByFrequency() {
        let engine = PredictionEngine()
        engine.learn("감사합니다", times: 2)
        engine.learn("감정평가서", times: 3)
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil), ["감정평가서", "감사합니다"])
    }

    func testCompletion_prefersWordThatFollowedPreviousWord() {
        let engine = PredictionEngine()
        engine.learn(word: "토지", previous: nil)
        engine.learn(word: "토지", previous: "대상")
        engine.learn("토요일", times: 2)
        // 빈도는 같고 "토요일" 이 더 최근이지만 "대상" 뒤에서는 "토지" 를 쓴 적이 있다.
        XCTAssertEqual(engine.suggestions(prefix: "토", previous: nil).first, "토요일")
        XCTAssertEqual(engine.suggestions(prefix: "토", previous: "대상").first, "토지")
    }

    func testCompletion_englishIsCaseInsensitiveAndMatchesCase() {
        let engine = PredictionEngine()
        engine.learn(word: "thanks", previous: nil)
        engine.learn(word: "Thanks", previous: nil)
        XCTAssertEqual(engine.model.words.count, 1, "대소문자만 다른 단어는 하나로 센다")
        XCTAssertEqual(engine.suggestions(prefix: "th", previous: nil), ["thanks"])
        XCTAssertEqual(engine.suggestions(prefix: "Th", previous: nil), ["Thanks"])
    }

    func testCompletion_respectsLimit() {
        let engine = PredictionEngine()
        for word in ["가가", "가나", "가다", "가라", "가마"] {
            engine.learn(word, times: 2)
        }
        XCTAssertEqual(engine.suggestions(prefix: "가", previous: nil).count, 4)
    }

    // MARK: - 감쇠 (반감기)

    func testDecayedScore_halvesEveryHalfLife() {
        let entry = PredictionWordEntry(count: 4, lastUsed: 0, score: 4)
        XCTAssertEqual(PredictionEngine.decayedScore(entry, at: 0), 4, accuracy: 1e-9)
        XCTAssertEqual(PredictionEngine.decayedScore(entry, at: Int(PredictionEngine.halfLife)), 2, accuracy: 1e-9)
        XCTAssertEqual(PredictionEngine.decayedScore(entry, at: Int(PredictionEngine.halfLife) * 2), 1, accuracy: 1e-9)
    }

    func testDecay_recentWordOvertakesOldFrequentWord() {
        let engine = PredictionEngine()
        engine.learn("감사합니다", times: 3)
        engine.learn("감정평가서", times: 2)
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil).first, "감사합니다", "지금은 많이 쓴 쪽이 앞")

        // 반감기 두 번만큼 다른 단어를 친다 → 3점이 0.75점으로.
        engine.learn("나", times: Int(PredictionEngine.halfLife) * 2)
        engine.learn("감정평가서", times: 2)
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil).first, "감정평가서", "오래 안 쓴 단어는 서서히 밀려난다")
        XCTAssertEqual(engine.model.words["감사합니다"]?.count, 3, "쓴 횟수는 줄지 않는다")
    }

    // MARK: - 다음 단어

    func testNextWord_afterSpace() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "합니다", previous: "감사")
        engine.learn(word: "합니다", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), ["드립니다", "합니다"])
        XCTAssertEqual(engine.suggestions(prefix: "", previous: nil), [])
    }

    func testNextWord_hidesFollowerUsedOnlyOnce() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드림", previous: "감사")
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), [])
    }

    // MARK: - 학습 규칙

    func testLearn_rejectsNumbersPunctuationAndCheonjiinMarks() {
        XCTAssertFalse(PredictionEngine.isLearnable("010"))
        XCTAssertFalse(PredictionEngine.isLearnable("abc123"))
        XCTAssertFalse(PredictionEngine.isLearnable("a@b"))
        XCTAssertFalse(PredictionEngine.isLearnable("ㅇㆍ"))
        XCTAssertFalse(PredictionEngine.isLearnable(""))
        XCTAssertFalse(PredictionEngine.isLearnable(String(repeating: "가", count: 31)))
        XCTAssertTrue(PredictionEngine.isLearnable("감정평가"))
        XCTAssertTrue(PredictionEngine.isLearnable("don't"))
    }

    func testLearn_rejectsWordsWithStandaloneJamo() {
        // 덜 끝난 글자가 섞인 오타, 자모만 쓴 말 (사용자 결정 2026-11-11)
        XCTAssertFalse(PredictionEngine.isLearnable("안ㄴ"))
        XCTAssertFalse(PredictionEngine.isLearnable("ㅇㅋ"))
        XCTAssertFalse(PredictionEngine.isLearnable("ㅎㅎ"))
        XCTAssertFalse(PredictionEngine.isLearnable("ㅋㅋㅋㅋ"))
        XCTAssertFalse(PredictionEngine.isLearnable("가\u{1100}"))
        // 같은 글자가 이어진 완성 글자는 배운다 (사용자 결정 2026-11-11)
        XCTAssertTrue(PredictionEngine.isLearnable("아아아"))
    }

    func testForget_removesWordAndFollowers() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "드립니다", previous: "감사")
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), ["드립니다"])
        engine.forget(word: "드립니다")
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), [])
        XCTAssertEqual(engine.suggestions(prefix: "드", previous: nil), [])
    }

    func testReset_keepsAppliedTokenAndClearsStats() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.recordShown()
        engine.reset(appliedResetToken: "token-1")
        XCTAssertTrue(engine.model.words.isEmpty)
        XCTAssertEqual(engine.model.appliedResetToken, "token-1")
        XCTAssertEqual(engine.model.stats, PredictionStats())
    }

    func testPrune_keepsWordCountBounded() {
        let engine = PredictionEngine()
        let syllables = (0..<80).map { String(Character(UnicodeScalar(0xAC00 + $0 * 28)!)) }
        var learned = 0
        outer: for a in syllables {
            for b in syllables {
                engine.learn(word: a + b, previous: nil)
                learned += 1
                if learned > PredictionEngine.maxWords + 10 { break outer }
            }
        }
        XCTAssertLessThanOrEqual(engine.model.words.count, PredictionEngine.maxWords)
    }

    // MARK: - 저장 형식

    func testModel_roundTripsThroughJSON() throws {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "드립니다", previous: nil)
        engine.recordAccepted(word: "드립니다", typed: "드")
        let data = try JSONEncoder().encode(engine.model)
        let decoded = try JSONDecoder().decode(PredictionModel.self, from: data)
        XCTAssertEqual(decoded, engine.model)
        XCTAssertEqual(decoded.version, 4)
        XCTAssertEqual(PredictionEngine(model: decoded).suggestions(prefix: "드", previous: nil), ["드립니다"])
    }

    func testModel_readsVersion1FileAndCarriesCountAsScore() throws {
        // 판 1 (2026-11-10 배포본) 파일: score · stats 가 없다.
        let json = """
        {"version":1,"words":{"감사합니다":{"count":3,"lastUsed":5},"ㅇㅋ":{"count":9,"lastUsed":4}},
         "bigrams":{"ㅇㅋ":{"감사합니다":2}},"tick":5,"appliedResetToken":"t"}
        """
        let decoded = try JSONDecoder().decode(PredictionModel.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.words["감사합니다"]?.score, 3, "쓴 횟수를 그대로 점수로 이어받는다")
        XCTAssertEqual(decoded.stats, PredictionStats())

        let engine = PredictionEngine(model: decoded)
        XCTAssertEqual(engine.model.version, PredictionModel.currentVersion, "다음 저장부터 판 2")
        XCTAssertNil(engine.model.words["ㅇㅋ"], "지금 규칙으로 배우지 않을 단어는 비운다")
        XCTAssertNil(engine.model.bigrams["ㅇㅋ"])
        XCTAssertEqual(engine.model.appliedResetToken, "t")
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil), ["감사합니다"])
    }

    // MARK: - 효과 측정

    func testStats_countAcceptedAndSavedCharacters() {
        let engine = PredictionEngine()
        engine.learn("안녕하세요", times: 2)
        engine.recordShown()
        engine.recordAccepted(word: "안녕하세요", typed: "안녀")
        engine.recordAccepted(word: "드립니다", typed: "")
        XCTAssertEqual(engine.model.stats.shown, 1)
        XCTAssertEqual(engine.model.stats.accepted, 2)
        XCTAssertEqual(engine.model.stats.savedCharacters, 3 + 4)
        XCTAssertEqual(engine.diagnosticLine,
                       "배운 단어 1개(추천 가능 1개) / 구절 0개 / 추천 보여 줌 1번 / 고름 2번 / 아낀 글자 7자"
                       + " / 절약률 70.0% (친 글자 10자 중 아낀 7자) / 구절 보여 줌 0번 · 고름 0번")
    }

    // MARK: - 새 순위 (2026-11-20 사용자 결정 — Stupid Backoff · 고른 단어 3배 · 절약률 · 구절 횟수)

    func testStats_phraseShownAndAccepted() {
        let engine = PredictionEngine()
        engine.recordShown(includesPhrase: true)
        engine.recordShown()
        engine.recordAccepted(word: "수고 많으셨습니다", typed: "수")
        engine.recordAccepted(word: "수고", typed: "수")
        XCTAssertEqual(engine.model.stats.shown, 2)
        XCTAssertEqual(engine.model.stats.phraseShown, 1)
        XCTAssertEqual(engine.model.stats.phraseAccepted, 1)
        XCTAssertNil(engine.keystrokeSavingPercent, "단어를 아직 안 배웠으면 절약률은 모름")
    }

    func testNextWord_backoffRanksByOneScore() {
        let engine = PredictionEngine()
        // "확인 후" 뒤: 가자 1번 · 연락 9번 → 가자 비율 0.1
        engine.learn(word: "가자", previous: nil); engine.learn(word: "연락", previous: nil)
        engine.learn(word: "가자", previous: "후", precedingWords: ["확인", "후"])
        for _ in 0..<9 { engine.learn(word: "연락", previous: "후", precedingWords: ["확인", "후"]) }
        // "후" 뒤에만: 출발 10번 → 0.4 × 10/20 = 0.2
        for _ in 0..<10 { engine.learn(word: "출발", previous: "후", precedingWords: ["식사", "후"]) }
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "후", beforePrevious: "확인"),
                       ["연락", "출발", "가자"], "앞 두 단어가 맞아도 비율이 낮으면 앞 한 단어로 많이 쓴 단어 뒤로")
    }

    func testCompletion_contextBeatsFrequentWord() {
        let engine = PredictionEngine()
        engine.learn("토요일", times: 20)
        engine.learn(word: "토지", previous: "대상")
        engine.learn(word: "토지", previous: "대상")
        XCTAssertEqual(engine.suggestions(prefix: "토", previous: "대상").first, "토지")
        XCTAssertEqual(engine.suggestions(prefix: "토", previous: nil).first, "토요일")
    }

    func testAcceptedWord_weighsThreeTimes() {
        let engine = PredictionEngine()
        engine.learn(word: "감사합니다", previous: nil)
        engine.learn(word: "감사합니다", previous: nil)
        engine.learn(word: "감정평가", previous: nil)
        engine.learn(word: "감정평가", previous: nil, accepted: true)
        XCTAssertEqual(engine.model.words["감정평가"]?.count, 2, "쓴 횟수는 1씩")
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil).first, "감정평가", "고른 단어는 점수 3")
    }

    // MARK: - 문맥 해석

    func testCurrentContext() {
        XCTAssertEqual(PredictionEngine.currentContext(in: "오늘 감정").previous, "오늘")
        XCTAssertEqual(PredictionEngine.currentContext(in: "오늘 감정").current, "감정")
        XCTAssertEqual(PredictionEngine.currentContext(in: "오늘 감정 ").previous, "감정")
        XCTAssertEqual(PredictionEngine.currentContext(in: "오늘 감정 ").current, "")
        XCTAssertNil(PredictionEngine.currentContext(in: "끝. 다음").previous, "문장이 바뀌면 앞 단어로 치지 않는다")
        XCTAssertEqual(PredictionEngine.currentContext(in: "").current, "")
    }

    func testCompletedWord() {
        let completed = PredictionEngine.completedWord(in: "감사 드립니다. ")
        XCTAssertEqual(completed?.word, "드립니다")
        XCTAssertEqual(completed?.previous, "감사")
        XCTAssertNil(PredictionEngine.completedWord(in: "감사 드립"), "아직 입력 중인 단어는 끝난 단어가 아니다")
        // 스페이스를 한 번 더 쳐 "안녕. " 이 돼도 같은 단어로 본다 (중복 학습 방지).
        XCTAssertEqual(PredictionEngine.completedWord(in: "안녕 ")?.signature,
                       PredictionEngine.completedWord(in: "안녕. ")?.signature)
    }

    // MARK: - 직접 넣은 단어 · 앱 편집 요청 (「학습한 단어」 화면, 2026-11-12)

    private func edits(_ list: [PredictionEdit], from start: Int = 1) -> [PredictionEditRequest] {
        list.enumerated().map { PredictionEditRequest(id: start + $0.offset, edit: $0.element) }
    }

    func testAddEdit_suggestsRightAway() {
        let engine = PredictionEngine()
        XCTAssertTrue(engine.apply(edits: edits([.add("감정평가사")])))
        XCTAssertEqual(engine.model.words["감정평가사"]?.count, 2, "넣자마자 추천되도록 두 번 쓴 것으로 친다")
        XCTAssertTrue(engine.isManual("감정평가사"))
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil), ["감정평가사"])
    }

    func testAddEdit_keepsJamoWordThatAutoLearningWouldDrop() {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("ㅇㅋ")]))
        XCTAssertEqual(engine.suggestions(prefix: "ㅇ", previous: nil), ["ㅇㅋ"])
        // 다시 읽어도(키보드를 새로 띄워도) 규칙 정리에 지워지지 않는다. 직접 넣지 않은 자모 단어는 지운다.
        var model = engine.model
        model.words["ㅎㅎ"] = PredictionWordEntry(count: 3, lastUsed: 0)
        let reloaded = PredictionEngine(model: model)
        XCTAssertNotNil(reloaded.model.words["ㅇㅋ"])
        XCTAssertNil(reloaded.model.words["ㅎㅎ"])
    }

    func testDigitWord_onlyWhenAddedByHand() {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("3층")]))
        let context = engine.suggestionContext(in: "회의는 3")
        XCTAssertEqual(context.current, "3")
        XCTAssertEqual(context.previous, "회의는")
        XCTAssertEqual(engine.suggestions(prefix: context.current, previous: context.previous), ["3층"])
        // 직접 넣은 단어로 끝내면 쓴 횟수가 오른다.
        let completed = engine.completedWordConsideringManual(in: "회의는 3층 ")
        XCTAssertEqual(completed?.word, "3층")
        XCTAssertTrue(engine.learn(word: "3층", previous: completed?.previous))
        XCTAssertEqual(engine.model.words["3층"]?.count, 3)
        // 숫자는 여전히 저절로 배우지 않는다 (전화번호·인증번호).
        XCTAssertFalse(engine.learn(word: "01012345678", previous: nil))
        XCTAssertFalse(engine.learn(word: "5층", previous: nil))
        XCTAssertEqual(engine.suggestionContext(in: "번호 010").current, "", "직접 넣은 단어가 아니면 예전처럼 글자만 읽는다")
    }

    func testManualAwareParsing_matchesOldParsingForOrdinaryText() {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("A-4")]))
        for text in ["오늘 감정", "오늘 감정 ", "끝. 다음", "안녕~ ", "(안녕", "3층 "] {
            let new = engine.suggestionContext(in: text)
            let old = PredictionEngine.currentContext(in: text)
            XCTAssertEqual(new.current, old.current, text)
            XCTAssertEqual(new.previous, old.previous, text)
            XCTAssertEqual(engine.completedWordConsideringManual(in: text)?.signature,
                           PredictionEngine.completedWord(in: text)?.signature, text)
        }
        XCTAssertEqual(engine.completedWordConsideringManual(in: "A-4 ")?.word, "A-4")
    }

    func testRenameEdit_carriesCountsAndPairs() {
        let engine = PredictionEngine()
        engine.learn("감정평가서", times: 3)
        engine.learn(word: "작성", previous: "감정평가서")
        engine.learn(word: "감정평가서", previous: "검토")
        engine.apply(edits: edits([.rename(from: "감정평가서", to: "감정평가사")]))
        XCTAssertNil(engine.model.words["감정평가서"])
        XCTAssertEqual(engine.model.words["감정평가사"]?.count, 4)
        XCTAssertEqual(engine.followers(of: "감정평가사").first?.word, "작성", "앞 단어 자리도 옮긴다")
        XCTAssertEqual(engine.followers(of: "검토").first?.word, "감정평가사", "뒤 단어 자리도 옮긴다")
        XCTAssertTrue(engine.isManual("감정평가사"))
        XCTAssertEqual(engine.suggestions(prefix: "감정", previous: nil), ["감정평가사"])
    }

    func testRenameEdit_mergesIntoExistingWord() {
        let engine = PredictionEngine()
        engine.learn("감사함니다", times: 2)
        engine.learn("감사합니다", times: 3)
        engine.apply(edits: edits([.rename(from: "감사함니다", to: "감사합니다")]))
        XCTAssertNil(engine.model.words["감사함니다"])
        XCTAssertEqual(engine.model.words["감사합니다"]?.count, 5)
    }

    func testDeleteEdit_forgetsWordAndManualMark() {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("A-4"), .delete("A-4")]))
        XCTAssertNil(engine.model.words["A-4"])
        XCTAssertFalse(engine.isManual("A-4"))
    }

    func testApplyEdits_onlyNewOnesInOrder() {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("가나다")]))
        engine.forget(word: "가나다")
        XCTAssertFalse(engine.apply(edits: edits([.add("가나다")])), "이미 반영한 번호는 다시 반영하지 않는다")
        XCTAssertNil(engine.model.words["가나다"])
        engine.apply(edits: edits([.add("가나다"), .delete("가나다"), .add("라마바")], from: 1))
        XCTAssertNil(engine.model.words["가나다"])
        XCTAssertNotNil(engine.model.words["라마바"])
        XCTAssertEqual(engine.model.appliedEditId, 3)
        engine.reset(appliedResetToken: "t")
        XCTAssertEqual(engine.model.appliedEditId, 0, "지우기 뒤 편집 요청은 1 번부터 다시 온다")
    }

    func testManualWordProblem() {
        XCTAssertNil(PredictionEngine.manualWordProblem("A-4"))
        XCTAssertNil(PredictionEngine.manualWordProblem("ㅇㅋ"))
        XCTAssertNil(PredictionEngine.manualWordProblem("3층"))
        XCTAssertNotNil(PredictionEngine.manualWordProblem(""))
        XCTAssertNotNil(PredictionEngine.manualWordProblem("수고 많으셨습니다"))
        XCTAssertNotNil(PredictionEngine.manualWordProblem("감사합니다."))
        XCTAssertNotNil(PredictionEngine.manualWordProblem("(주)"))
        XCTAssertNotNil(PredictionEngine.manualWordProblem(String(repeating: "가", count: 31)))
        let engine = PredictionEngine()
        XCTAssertFalse(engine.apply(edits: []))
        engine.apply(edits: edits([.add("감사합니다.")]))
        XCTAssertNil(engine.model.words["감사합니다."], "넣을 수 없는 단어는 요청이 와도 넣지 않는다")
    }

    func testModelCodable_keepsManualWordsAndEditId() throws {
        let engine = PredictionEngine()
        engine.apply(edits: edits([.add("A-4")]))
        let data = try JSONEncoder().encode(engine.model)
        let decoded = try JSONDecoder().decode(PredictionModel.self, from: data)
        XCTAssertEqual(decoded.manualWords, ["a-4"])
        XCTAssertEqual(decoded.appliedEditId, 1)
        let old = try JSONDecoder().decode(PredictionModel.self, from: Data(#"{"version":2,"words":{}}"#.utf8))
        XCTAssertTrue(old.manualWords.isEmpty)
        XCTAssertEqual(old.appliedEditId, 0)
        let request = try JSONDecoder().decode(
            [PredictionEditRequest].self,
            from: JSONEncoder().encode([PredictionEditRequest(id: 1, edit: .rename(from: "가", to: "나"))]))
        XCTAssertEqual(request.first?.edit, .rename(from: "가", to: "나"))
    }

    // MARK: - 조사 나눠 배우기 (개선 방안 6번, 2026-11-12)

    func testJosaSplit_followsJosaListFinalConsonantAndLength() {
        func split(_ word: String) -> String? {
            PredictionEngine.josaSplit(word).map { "\($0.stem)+\($0.josa)" }
        }
        XCTAssertEqual(split("감정평가를"), "감정평가+를")
        XCTAssertEqual(split("감정평가에서"), "감정평가+에서", "긴 조사부터 맞춘다")
        XCTAssertEqual(split("책상을"), "책상+을")
        XCTAssertEqual(split("서울로"), "서울+로", "ㄹ 받침 뒤는 로")
        XCTAssertEqual(split("부산으로"), "부산+으로")
        XCTAssertNil(split("나이"), "앞부분이 한 글자")
        XCTAssertNil(split("사이"), "받침 없는 글자 뒤 '이' 는 조사가 아니다")
        XCTAssertNil(split("학교은"), "받침이 맞지 않는다")
        XCTAssertNil(split("서울으로"), "ㄹ 받침 뒤 으로는 아니다")
        XCTAssertNil(split("책이라도"), "가장 긴 조사가 맞지 않으면 더 짧은 조사로 다시 자르지 않는다")
        XCTAssertNil(split("책으로"))
        XCTAssertNil(split("바다"))
    }

    func testJosaForms_creditStemOnlyWithEvidence() {
        let engine = PredictionEngine()
        engine.learn("감정평가사", times: 2)
        engine.learn(word: "감정평가를", previous: nil)
        XCTAssertNil(engine.model.words["감정평가"], "조사 한 가지로는 앞부분을 단어로 치지 않는다")
        engine.learn(word: "감정평가의", previous: nil)
        XCTAssertEqual(engine.model.words["감정평가"]?.count, 1, "서로 다른 조사 두 가지 = 증거")
        engine.learn(word: "감정평가는", previous: nil)
        XCTAssertEqual(engine.model.words["감정평가"]?.count, 2)
        XCTAssertEqual(engine.model.words["감정평가를"]?.count, 1, "조사 붙은 꼴도 그대로 배운다")
        XCTAssertEqual(Set(engine.suggestions(prefix: "감정", previous: nil).prefix(2)), ["감정평가", "감정평가사"])
    }

    func testJosaForm_creditsStemAlreadyUsedAlone() {
        let engine = PredictionEngine()
        engine.learn(word: "회의", previous: nil)
        engine.learn(word: "회의를", previous: nil)
        XCTAssertEqual(engine.model.words["회의"]?.count, 2, "따로 쓴 적이 있는 앞부분은 바로 센다")
    }

    func testJosaLookalike_withoutEvidence_isNotSplit() {
        let engine = PredictionEngine()
        engine.learn("고양이", times: 3)
        XCTAssertNil(engine.model.words["고양"], "고양+이 꼴이지만 증거가 없다")
    }

    func testForget_clearsStemEvidence() {
        let engine = PredictionEngine()
        engine.learn(word: "회의", previous: nil)
        engine.learn(word: "회의를", previous: nil)
        engine.forget(word: "회의")
        engine.learn(word: "회의의", previous: nil)
        XCTAssertNil(engine.model.words["회의"], "지운 단어가 조사 앞부분으로 곧바로 되살아나지 않는다")
    }

    func testVersion2File_backfillsStemsOnce() {
        var old = PredictionModel()
        old.version = 2
        old.tick = 10
        old.words["감정평가사"] = PredictionWordEntry(count: 5, lastUsed: 9)
        old.words["감정평가를"] = PredictionWordEntry(count: 1, lastUsed: 3)
        old.words["감정평가의"] = PredictionWordEntry(count: 1, lastUsed: 4)
        old.words["고양이"] = PredictionWordEntry(count: 4, lastUsed: 5)
        let engine = PredictionEngine(model: old)
        XCTAssertEqual(engine.model.words["감정평가"]?.count, 2, "이미 배운 조사 꼴의 횟수를 앞부분에 센다")
        XCTAssertNil(engine.model.words["고양"])
        XCTAssertEqual(engine.model.version, 4)
        XCTAssertEqual(PredictionEngine(model: engine.model).model.words["감정평가"]?.count, 2, "한 번만 한다")
    }
}

private extension PredictionEngine {
    /// 같은 단어를 앞 단어 없이 여러 번 배운다.
    func learn(_ word: String, times: Int) {
        for _ in 0..<times { learn(word: word, previous: nil) }
    }
}
