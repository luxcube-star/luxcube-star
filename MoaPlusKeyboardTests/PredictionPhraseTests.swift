import XCTest

/// 구절 추천 · 앞 두 단어 (개선 방안 8번 · 10번 넓힘, 사용자 결정 2026-11-13: 구절 2칸까지 · 2번 쓴 뒤 ·
/// 단어와 따로 배움).
final class PredictionPhraseTests: XCTestCase {

    private func type(_ engine: PredictionEngine, _ words: [String]) {
        var preceding: [String] = []
        for word in words {
            engine.learn(word: word, previous: preceding.last, precedingWords: preceding)
            preceding.append(word)
            if preceding.count > PredictionEngine.maxPhraseWords - 1 { preceding.removeFirst() }
        }
    }

    func testPhrase_suggestedAfterTwoUses() {
        let engine = PredictionEngine()
        type(engine, ["수고", "많으셨습니다"])
        XCTAssertEqual(engine.suggestions(prefix: "수", previous: nil), [], "한 번 쓴 구절은 아직")
        type(engine, ["수고", "많으셨습니다"])
        XCTAssertEqual(engine.suggestions(prefix: "수", previous: nil), ["수고", "수고 많으셨습니다"])
        XCTAssertEqual(engine.suggestions(prefix: "수고", previous: nil), ["수고 많으셨습니다"], "첫 단어를 다 쳐도 구절은 남는다")
    }

    func testPhrase_wordsAndPhrasesAreCountedSeparately() {
        let engine = PredictionEngine()
        type(engine, ["수고", "많으셨습니다"])
        XCTAssertEqual(engine.model.words["수고"]?.count, 1)
        XCTAssertEqual(engine.model.phrases["수고 많으셨습니다"]?.count, 1)
        XCTAssertNil(engine.model.words["수고 많으셨습니다"])
    }

    func testPhrase_upToFourWords() {
        let engine = PredictionEngine()
        for _ in 0..<2 { type(engine, ["오늘", "확인", "후", "연락드리겠습니다", "감사"]) }
        XCTAssertNotNil(engine.model.phrases["오늘 확인 후 연락드리겠습니다"])
        XCTAssertNil(engine.model.phrases["오늘 확인 후 연락드리겠습니다 감사"], "다섯 단어는 배우지 않는다")
        XCTAssertNotNil(engine.model.phrases["확인 후 연락드리겠습니다 감사"])
    }

    func testPhrase_atMostTwoSlots_wordsFirst() {
        let engine = PredictionEngine()
        for word in ["가가", "가나", "가다", "가라"] { for _ in 0..<3 { engine.learn(word: word, previous: nil) } }
        for _ in 0..<2 {
            type(engine, ["가가", "하나"])
            type(engine, ["가나", "둘"])
            type(engine, ["가다", "셋"])
        }
        let shown = engine.suggestions(prefix: "가", previous: nil)
        XCTAssertEqual(shown.count, 4)
        XCTAssertEqual(shown.filter { $0.contains(" ") }.count, 2, "구절은 4칸 중 2칸까지")
        XCTAssertFalse(shown[0].contains(" "), "단어가 앞, 구절이 뒤")
    }

    func testPhrase_notLearnedAcrossUnlearnableWord() {
        let engine = PredictionEngine()
        for _ in 0..<2 { type(engine, ["ㅋㅋ", "알겠어"]) }
        XCTAssertTrue(engine.model.phrases.isEmpty, "낱자모 단어는 구절에도 안 들어간다")
    }

    func testPairContext_prefersTwoWordMatch() {
        let engine = PredictionEngine()
        for _ in 0..<2 { type(engine, ["확인", "후", "연락드리겠습니다"]) }
        for _ in 0..<3 { type(engine, ["식사", "후", "가자"]) }
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "후", beforePrevious: "확인"),
                       ["연락드리겠습니다", "가자"])
        XCTAssertEqual(engine.suggestions(prefix: "", previous: "후").first, "가자", "앞 한 단어만이면 지금처럼")
    }

    func testForgetPhrase_andForgetWordDropsItsPhrases() {
        let engine = PredictionEngine()
        for _ in 0..<2 { type(engine, ["수고", "많으셨습니다"]) }
        engine.forget(phrase: "수고 많으셨습니다")
        XCTAssertNil(engine.model.phrases["수고 많으셨습니다"])
        for _ in 0..<2 { type(engine, ["수고", "많으셨습니다"]) }
        engine.forget(word: "많으셨습니다")
        XCTAssertTrue(engine.model.phrases.isEmpty, "지운 단어(오타)가 든 구절도 지운다")
    }

    func testManualPhrase_addRenameDelete() {
        let engine = PredictionEngine()
        engine.apply(edits: [PredictionEditRequest(id: 1, edit: .addPhrase("잘  부탁드립니다"))])
        XCTAssertEqual(engine.suggestions(prefix: "잘", previous: nil), ["잘 부탁드립니다"], "넣자마자 추천 · 공백 하나로")
        engine.apply(edits: [PredictionEditRequest(id: 2, edit: .renamePhrase(from: "잘 부탁드립니다", to: "잘 부탁합니다"))])
        XCTAssertEqual(Array(engine.model.phrases.keys), ["잘 부탁합니다"])
        engine.apply(edits: [PredictionEditRequest(id: 3, edit: .deletePhrase("잘 부탁합니다"))])
        XCTAssertTrue(engine.model.phrases.isEmpty)
    }

    func testPhraseProblem() {
        XCTAssertNotNil(PredictionEngine.phraseProblem("하나"), "한 단어는 구절이 아니다")
        XCTAssertNotNil(PredictionEngine.phraseProblem("가 나 다 라 마"), "다섯 단어")
        XCTAssertNotNil(PredictionEngine.phraseProblem("감사 합니다."), "문장부호")
        XCTAssertNil(PredictionEngine.phraseProblem("3층 회의실"))
    }

    func testVersion3File_movesFrequentPairsIntoPhrases() {
        var old = PredictionModel()
        old.version = 3
        old.words = ["수고": PredictionWordEntry(count: 3, lastUsed: 1),
                     "많으셨습니다": PredictionWordEntry(count: 3, lastUsed: 1),
                     "한번": PredictionWordEntry(count: 1, lastUsed: 1)]
        old.bigrams = ["수고": ["많으셨습니다": 2], "많으셨습니다": ["한번": 1]]
        let engine = PredictionEngine(model: old)
        XCTAssertEqual(engine.model.version, 4)
        XCTAssertEqual(engine.model.phrases["수고 많으셨습니다"]?.count, 2)
        XCTAssertNil(engine.model.phrases["많으셨습니다 한번"], "한 번 이어 쓴 짝은 옮기지 않는다")
    }

    func testModel_roundTripsWithPhrases() throws {
        let engine = PredictionEngine()
        for _ in 0..<2 { type(engine, ["확인", "후", "연락드리겠습니다"]) }
        let data = try JSONEncoder().encode(engine.model)
        XCTAssertEqual(try JSONDecoder().decode(PredictionModel.self, from: data), engine.model)
    }

    func testPrecedingWords_stopAtSentenceEnd() {
        let engine = PredictionEngine()
        XCTAssertEqual(engine.precedingWords(in: "오늘 확인 후 ", max: 3), ["오늘", "확인", "후"])
        XCTAssertEqual(engine.precedingWords(in: "끝. 확인 후 ", max: 3), ["확인", "후"])
    }
}
