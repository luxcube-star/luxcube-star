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
        engine.learn(word: "가나다", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "간", previous: nil), ["가나다"])
        XCTAssertEqual(engine.suggestions(prefix: "가", previous: nil), ["가나다"])
    }

    func testCompletion_matchesPartialSyllable() {
        let engine = PredictionEngine()
        engine.learn(word: "안녕하세요", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "안녀", previous: nil), ["안녕하세요"])
        XCTAssertEqual(engine.suggestions(prefix: "안녕ㅎ", previous: nil), ["안녕하세요"])
    }

    func testCompletion_excludesExactWord() {
        let engine = PredictionEngine()
        engine.learn(word: "감정", previous: nil)
        engine.learn(word: "감정평가서", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "감정", previous: nil), ["감정평가서"])
    }

    func testCompletion_ranksByFrequency() {
        let engine = PredictionEngine()
        engine.learn(word: "감사합니다", previous: nil)
        engine.learn(word: "감정평가서", previous: nil)
        engine.learn(word: "감정평가서", previous: nil)
        XCTAssertEqual(engine.suggestions(prefix: "감", previous: nil), ["감정평가서", "감사합니다"])
    }

    func testCompletion_prefersWordThatFollowedPreviousWord() {
        let engine = PredictionEngine()
        engine.learn(word: "토지", previous: nil)
        engine.learn(word: "토요일", previous: nil)
        engine.learn(word: "토요일", previous: nil)
        engine.learn(word: "토지", previous: "대상")
        // 빈도는 같지만 "대상" 뒤에서는 "토지" 를 쓴 적이 있다.
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
            engine.learn(word: word, previous: nil)
        }
        XCTAssertEqual(engine.suggestions(prefix: "가", previous: nil).count, 3)
    }

    // MARK: - 다음 단어

    func testNextWord_afterSpace() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "드립니다", previous: "감사")
        engine.learn(word: "합니다", previous: "감사")
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), ["드립니다", "합니다"])
        XCTAssertEqual(engine.suggestions(prefix: "", previous: nil), [])
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

    func testForget_removesWordAndFollowers() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        engine.forget(word: "드립니다")
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "감사"), [])
        XCTAssertEqual(engine.suggestions(prefix: "드", previous: nil), [])
    }

    func testReset_keepsAppliedToken() {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.reset(appliedResetToken: "token-1")
        XCTAssertTrue(engine.model.words.isEmpty)
        XCTAssertEqual(engine.model.appliedResetToken, "token-1")
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

    func testModel_roundTripsThroughJSON() throws {
        let engine = PredictionEngine()
        engine.learn(word: "감사", previous: nil)
        engine.learn(word: "드립니다", previous: "감사")
        let data = try JSONEncoder().encode(engine.model)
        let decoded = try JSONDecoder().decode(PredictionModel.self, from: data)
        XCTAssertEqual(decoded, engine.model)
        XCTAssertEqual(PredictionEngine(model: decoded).suggestions(prefix: "드", previous: nil), ["드립니다"])
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
