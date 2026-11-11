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
        XCTAssertEqual(engine.suggestions(prefix: "가", previous: nil).count, 3)
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
        XCTAssertEqual(decoded.version, 2)
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
                       "배운 단어 1개(추천 가능 1개) / 추천 보여 줌 1번 / 고름 2번 / 아낀 글자 7자")
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
}

private extension PredictionEngine {
    /// 같은 단어를 앞 단어 없이 여러 번 배운다.
    func learn(_ word: String, times: Int) {
        for _ in 0..<times { learn(word: word, previous: nil) }
    }
}
