import XCTest
import CoreGraphics

/// 긋기 버릇 맞추기 (개선 방안 13번, 사용자 결정 2026-11-13).
/// 오타 가르기 · 5번에 한 걸음 · 상한 · 되돌리기 · 지운 글과 다시 친 글 짝짓기 · 판정에 적용.
final class GestureHabitTests: XCTestCase {

    private func sample(_ key: Choseong, _ vowel: Jungseong?, _ directions: [GestureDirection],
                        maxDisplacement: CGFloat = 60, threshold: CGFloat = 20) -> GestureHabitSample {
        GestureHabitSample(key: key, vowel: vowel, directions: directions,
                           maxDisplacement: maxDisplacement, swipeThreshold: threshold)
    }

    // MARK: 오타 가르기

    func testClassify_oneStepAngle() {
        // ↗(ㅣ) 로 읽혔는데 →(ㅏ) 였다 — 다시 그은 방향이 시계 쪽.
        let o = GestureHabitLearner.classify(wrong: sample(.ㄱ, .ㅣ, [.upRight]), correct: sample(.ㄱ, .ㅏ, [.right]))
        XCTAssertEqual(o, GestureHabitObservation(key: "ㄱ", axis: .angle, sign: -1))
        let back = GestureHabitLearner.classify(wrong: sample(.ㄱ, .ㅏ, [.right]), correct: sample(.ㄱ, .ㅣ, [.upRight]))
        XCTAssertEqual(back?.sign, 1)
    }

    func testClassify_strokeCount() {
        let more = GestureHabitLearner.classify(wrong: sample(.ㅁ, .ㅘ, [.up, .right]), correct: sample(.ㅁ, .ㅗ, [.up]))
        XCTAssertEqual(more, GestureHabitObservation(key: "ㅁ", axis: .strokes, sign: 1))
        let fewer = GestureHabitLearner.classify(wrong: sample(.ㄱ, .ㅏ, [.right]), correct: sample(.ㄱ, .ㅐ, [.right, .left]))
        XCTAssertEqual(fewer?.sign, -1)
    }

    func testClassify_minLength() {
        // 긋다 만 탭 → 문턱 내림. 거의 안 움직인 탭은 일부러 친 자음으로 보고 세지 않는다.
        let short = GestureHabitLearner.classify(wrong: sample(.ㄴ, nil, [], maxDisplacement: 12),
                                                 correct: sample(.ㄴ, .ㅏ, [.right]))
        XCTAssertEqual(short, GestureHabitObservation(key: "ㄴ", axis: .minLength, sign: -1))
        XCTAssertNil(GestureHabitLearner.classify(wrong: sample(.ㄴ, nil, [], maxDisplacement: 2),
                                                  correct: sample(.ㄴ, .ㅏ, [.right])))
    }

    func testClassify_ignoresOtherKeysAndFarDirections() {
        XCTAssertNil(GestureHabitLearner.classify(wrong: sample(.ㄱ, .ㅣ, [.upRight]), correct: sample(.ㄷ, .ㅏ, [.right])),
                     "다른 자음 키로 다시 친 것은 자음 오타 — 세지 않는다")
        XCTAssertNil(GestureHabitLearner.classify(wrong: sample(.ㄱ, .ㅗ, [.up]), correct: sample(.ㄱ, .ㅜ, [.down])),
                     "한 칸(45°)보다 크게 어긋난 것은 각도 버릇이 아니다")
    }

    // MARK: 5번에 한 걸음 · 상한 · 사다리

    func testFiveSameErrors_makeOneStep() {
        let learner = GestureHabitLearner()
        let o = GestureHabitObservation(key: "ㄱ", axis: .angle, sign: -1)
        for _ in 0..<4 { XCTAssertNil(learner.record(o)) }
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ"), .zero, "4번까지는 맞추지 않는다")
        let event = learner.record(o)
        XCTAssertEqual(event?.knob, .angle)
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ").rotationDeg, 2, accuracy: 1e-9)
        XCTAssertEqual(learner.model.adjustment(for: "ㄴ"), .zero, "다른 키는 그대로")
        XCTAssertEqual(learner.model.observedCount, 5)
    }

    func testAngle_capsAtTenDegrees_andOppositeStepsBack() {
        let learner = GestureHabitLearner()
        let o = GestureHabitObservation(key: "ㄱ", axis: .angle, sign: -1)
        for _ in 0..<30 { learner.record(o) }
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ").rotationDeg, 10, accuracy: 1e-9, "모두 합쳐 10°까지")
        let opposite = GestureHabitObservation(key: "ㄱ", axis: .angle, sign: 1)
        for _ in 0..<5 { learner.record(opposite) }
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ").rotationDeg, 8, accuracy: 1e-9, "반대쪽 오타가 쌓이면 물러선다")
    }

    func testStrokes_ladder() {
        let learner = GestureHabitLearner()
        let more = GestureHabitObservation(key: "ㅁ", axis: .strokes, sign: 1)
        let fewer = GestureHabitObservation(key: "ㅁ", axis: .strokes, sign: -1)
        for _ in 0..<5 { learner.record(more) }
        XCTAssertEqual(learner.model.adjustment(for: "ㅁ").curveDeg, 2, accuracy: 1e-9, "획이 더 생기면 먼저 휜 획을 더 합친다")
        for _ in 0..<5 { learner.record(fewer) }
        XCTAssertEqual(learner.model.adjustment(for: "ㅁ").curveDeg, 0, accuracy: 1e-9, "모자라면 넓혀 둔 휨부터 되돌린다")
        for _ in 0..<5 { learner.record(fewer) }
        XCTAssertEqual(learner.model.adjustment(for: "ㅁ").lengthRatio, -0.02, accuracy: 1e-9, "그다음 길이 문턱을 키폭 2% 내린다")
        for _ in 0..<5 { learner.record(more) }
        XCTAssertEqual(learner.model.adjustment(for: "ㅁ"), .zero, "내려 둔 길이부터 되돌린다")
        for _ in 0..<25 { learner.record(fewer) }
        XCTAssertEqual(learner.model.adjustment(for: "ㅁ").lengthRatio, -0.08, accuracy: 1e-9, "길이는 8%까지")
    }

    // MARK: 되돌리기 · 처음으로

    func testRevertAndReset() {
        let learner = GestureHabitLearner()
        let o = GestureHabitObservation(key: "ㄱ", axis: .angle, sign: -1)
        for _ in 0..<10 { learner.record(o) }
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ").rotationDeg, 4, accuracy: 1e-9)
        let first = learner.model.events[0].id
        XCTAssertTrue(learner.apply(edits: [GestureHabitEditRequest(id: 1, edit: .revert(eventId: first))]))
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ").rotationDeg, 2, accuracy: 1e-9)
        XCTAssertTrue(learner.model.events[0].reverted)
        XCTAssertFalse(learner.apply(edits: [GestureHabitEditRequest(id: 1, edit: .revert(eventId: first))]),
                       "반영한 요청은 다시 반영하지 않는다")
        XCTAssertTrue(learner.apply(edits: [GestureHabitEditRequest(id: 2, edit: .resetAll)]))
        XCTAssertEqual(learner.model.adjustment(for: "ㄱ"), .zero)
        XCTAssertTrue(learner.model.events.isEmpty)
        XCTAssertEqual(learner.model.appliedEditId, 2)
    }

    func testModel_roundTrips() throws {
        let learner = GestureHabitLearner()
        for _ in 0..<5 { learner.record(GestureHabitObservation(key: "ㅅ", axis: .minLength, sign: -1)) }
        let data = try JSONEncoder().encode(learner.model)
        let decoded = try JSONDecoder().decode(GestureHabitModel.self, from: data)
        XCTAssertEqual(decoded, learner.model)
        XCTAssertEqual(try JSONDecoder().decode(GestureHabitModel.self, from: Data("{}".utf8)), GestureHabitModel())
    }

    // MARK: 지운 글 · 다시 친 글 짝짓기

    /// 키보드가 하는 순서를 그대로 흉내 낸다: 긋기 → 문맥 갱신(tick).
    private func type(_ tracker: GestureHabitTracker, _ sample: GestureHabitSample?, then text: String,
                      idle: Bool = false) -> (wrong: GestureHabitSample, correct: GestureHabitSample)? {
        if let sample { tracker.note(sample) }
        return tracker.tick(before: text, composerIdle: idle)
    }

    private func delete(_ tracker: GestureHabitTracker, from text: String, to after: String) {
        tracker.noteDeletion(before: text)
        XCTAssertNil(tracker.tick(before: after, composerIdle: true))
    }

    func testTracker_gikToGak_withBatchim() {
        let t = GestureHabitTracker()
        let wrong = sample(.ㄱ, .ㅣ, [.upRight])
        XCTAssertNil(type(t, wrong, then: "기"))
        XCTAssertNil(type(t, sample(.ㄱ, nil, [], maxDisplacement: 1), then: "긱"))   // 받침 탭
        delete(t, from: "긱", to: "기")
        delete(t, from: "기", to: "ㄱ")
        delete(t, from: "ㄱ", to: "")
        let correct = sample(.ㄱ, .ㅏ, [.right])
        XCTAssertNil(type(t, correct, then: "가"))
        XCTAssertNil(type(t, sample(.ㄱ, nil, [], maxDisplacement: 1), then: "각"), "조합 중이면 아직 끝나지 않음")
        let pair = type(t, nil, then: "각 ", idle: true)
        XCTAssertEqual(pair?.wrong, wrong)
        XCTAssertEqual(pair?.correct, correct)
    }

    func testTracker_afterSpace_spaceAndOneSyllableDeleted() {
        let t = GestureHabitTracker()
        let wrong = sample(.ㄱ, .ㅣ, [.upRight])
        _ = type(t, wrong, then: "기")
        _ = type(t, nil, then: "기 ", idle: true)
        delete(t, from: "기 ", to: "기")
        delete(t, from: "기", to: "")
        let correct = sample(.ㄱ, .ㅏ, [.right])
        XCTAssertNil(type(t, correct, then: "가"))
        let pair = type(t, nil, then: "가 ", idle: true)
        XCTAssertEqual(pair?.wrong, wrong, "띄어쓰기 뒤 그 띄어쓰기와 앞 글자 하나를 지운 것도 센다 (2나)")
        XCTAssertEqual(pair?.correct, correct)
    }

    func testTracker_severalCharactersDeleted() {
        // 「긱종 서류」 → 지우고 → 「각종 서류」 (4나 · 10글자까지).
        let t = GestureHabitTracker()
        let wrong = sample(.ㄱ, .ㅣ, [.upRight])
        _ = type(t, wrong, then: "기")
        _ = type(t, nil, then: "긱")
        _ = type(t, sample(.ㅈ, .ㅗ, [.up]), then: "긱조")
        _ = type(t, nil, then: "긱종")
        _ = type(t, nil, then: "긱종 ", idle: true)
        _ = type(t, sample(.ㅅ, .ㅓ, [.left]), then: "긱종 서")
        _ = type(t, sample(.ㄹ, .ㅠ, [.down, .up, .down]), then: "긱종 서류")
        var text = "긱종 서류"
        while !text.isEmpty {
            let after = String(text.dropLast())
            delete(t, from: text, to: after)
            text = after
        }
        let correct = sample(.ㄱ, .ㅏ, [.right])
        var pair: (wrong: GestureHabitSample, correct: GestureHabitSample)?
        for (s, typed) in [(correct, "가"), (nil, "각"), (sample(.ㅈ, .ㅗ, [.up]), "각조"), (nil, "각종"),
                           (nil, "각종 "), (sample(.ㅅ, .ㅓ, [.left]), "각종 서"), (sample(.ㄹ, .ㅠ, [.down, .up, .down]), "각종 서류")] {
            XCTAssertNil(pair)
            pair = type(t, s, then: typed, idle: typed.hasSuffix(" "))
        }
        XCTAssertNil(pair, "마지막 글자가 조합 중이면 아직")
        pair = type(t, nil, then: "각종 서류 ", idle: true)
        XCTAssertEqual(pair?.wrong, wrong)
        XCTAssertEqual(pair?.correct, correct)
    }

    func testTracker_rewrittenText_isNotCounted() {
        // 「오늘 회의」 → 「내일 회의」: 두 곳이 다르면 고쳐 쓴 글 (2가).
        let t = GestureHabitTracker()
        _ = type(t, sample(.ㅇ, .ㅗ, [.up]), then: "오")
        _ = type(t, sample(.ㄴ, .ㅡ, [.downRight]), then: "오느")
        _ = type(t, nil, then: "오늘")
        delete(t, from: "오늘", to: "오")
        delete(t, from: "오", to: "")
        _ = type(t, sample(.ㄴ, .ㅐ, [.right, .left]), then: "내")
        _ = type(t, sample(.ㅇ, .ㅣ, [.upRight]), then: "내이")
        _ = type(t, nil, then: "내일")
        XCTAssertNil(type(t, nil, then: "내일 ", idle: true))
    }

    func testTracker_otherConsonant_isNotCounted() {
        let t = GestureHabitTracker()
        _ = type(t, sample(.ㄱ, .ㅣ, [.upRight]), then: "기")
        delete(t, from: "기", to: "")
        _ = type(t, sample(.ㄷ, .ㅏ, [.right]), then: "다")
        XCTAssertNil(type(t, nil, then: "다 ", idle: true), "다른 자음 키 = 자음 오타 — 세지 않는다")
    }

    func testTracker_moreThanTenCharacters_isNotCounted() {
        let t = GestureHabitTracker()
        _ = type(t, sample(.ㄱ, .ㅣ, [.upRight]), then: "기")
        let long = "기" + String(repeating: "가", count: 10)
        _ = type(t, nil, then: long, idle: true)
        tracker(t, deleteAllOf: long)
        _ = type(t, sample(.ㄱ, .ㅏ, [.right]), then: "가")
        XCTAssertNil(type(t, nil, then: "가" + String(repeating: "가", count: 10) + " ", idle: true))
    }

    private func tracker(_ t: GestureHabitTracker, deleteAllOf text: String) {
        var text = text
        while !text.isEmpty {
            let after = String(text.dropLast())
            delete(t, from: text, to: after)
            text = after
        }
    }

    // MARK: 판정에 적용

    /// 한 획을 그은 결과 방향.
    private func direction(angle degrees: Double, habit: GestureHabitAdjustment) -> GestureDirection? {
        let analyzer = GestureAnalyzer(settings: .default, columnId: 0)
        analyzer.keyWidth = 50
        analyzer.habit = habit
        analyzer.reset()
        let radians = degrees * .pi / 180
        for i in 0...12 {
            let r = CGFloat(i) * 5
            analyzer.addPoint(CGPoint(x: 100 + r * CGFloat(cos(radians)), y: 100 - r * CGFloat(sin(radians))))
        }
        return analyzer.finalizeGesture().first
    }

    func testAnalyzer_rotationHabit_shiftsSectors() {
        var habit = GestureHabitAdjustment.zero
        habit.set(.angle, to: 4)
        var changed = 0
        for degrees in stride(from: 0.0, to: 360.0, by: 1.0) {
            XCTAssertEqual(direction(angle: degrees, habit: habit), direction(angle: degrees - 4, habit: .zero),
                           "회전 4° = 4° 덜 기운 획과 같은 판정 (\(degrees)°)")
            if direction(angle: degrees, habit: habit) != direction(angle: degrees, habit: .zero) { changed += 1 }
        }
        XCTAssertGreaterThan(changed, 0, "경계 가까운 각도는 판정이 바뀐다")
        XCTAssertEqual(direction(angle: 45, habit: habit), .upRight, "구역 가운데는 그대로")
    }

    func testAnalyzer_minLengthHabit_lowersSwipeThreshold() {
        let analyzer = GestureAnalyzer(settings: .default, columnId: 0)
        analyzer.keyWidth = 50
        let base = analyzer.effectiveThreshold
        var habit = GestureHabitAdjustment.zero
        habit.set(.minLength, to: -0.04)
        analyzer.habit = habit
        XCTAssertEqual(Double(analyzer.effectiveThreshold), Double(base) - 2, accuracy: 1e-6, "키폭 50pt 의 4% = 2pt")
    }

    func testAdjustment_zeroKeepsOldJudgement() {
        for degrees in stride(from: 0.0, to: 360.0, by: 5.0) {
            let a = GestureAnalyzer(settings: .default, columnId: 0)
            a.keyWidth = 50
            let radians = degrees * .pi / 180
            for i in 0...12 {
                let r = CGFloat(i) * 5
                a.addPoint(CGPoint(x: 100 + r * CGFloat(cos(radians)), y: 100 - r * CGFloat(sin(radians))))
            }
            XCTAssertEqual(a.finalizeGesture().first, direction(angle: degrees, habit: .zero))
        }
    }
}

/// 실제 입력 경로 (자음 키 긋기 → 지우기 → 다시 긋기 → 스페이스) 로 센다 — 뷰모델 연결 가드.
final class KeyboardViewModelGestureHabitTests: XCTestCase {
    private var savedAutoSpace = true
    private var savedHabitEnabled = true
    private var savedAbbreviation: ShortcutExpansionStore!

    override func setUp() {
        super.setUp()
        let s = KeyboardSettings.shared
        savedAutoSpace = s.autoSpaceOnPauseEnabled
        savedHabitEnabled = s.gestureHabitEnabled
        savedAbbreviation = s.shortcutExpansionStore
        s.autoSpaceOnPauseEnabled = false
        s.gestureHabitEnabled = true
        s.shortcutExpansionStore = ShortcutExpansionStore()
    }

    override func tearDown() {
        let s = KeyboardSettings.shared
        s.autoSpaceOnPauseEnabled = savedAutoSpace
        s.gestureHabitEnabled = savedHabitEnabled
        s.shortcutExpansionStore = savedAbbreviation
        super.tearDown()
    }

    private func key(for consonant: Choseong) -> (row: Int, column: Int)? {
        let layout = KeyboardSettings.shared.layoutCustomization
        for row in 0..<4 {
            for column in 0..<8 {
                if case .consonant(let c)? = KeyboardMetrics.keyContent(at: row, column: column, mode: .korean, layout: layout),
                   c == consonant { return (row, column) }
            }
        }
        return nil
    }

    private func swipe(_ vm: KeyboardViewModel, key: (row: Int, column: Int), dx: CGFloat, dy: CGFloat) {
        let start = CGPoint(x: 150, y: 150)
        vm.gestureStarted(row: key.row, column: key.column, at: start)
        for i in 1...10 {
            let f = CGFloat(i) / 10
            vm.gestureMoved(row: key.row, column: key.column, to: CGPoint(x: start.x + dx * f, y: start.y + dy * f))
        }
        vm.gestureEnded(row: key.row, column: key.column)
    }

    func testDeleteAndRedrawOnSameKey_countsOneVowelError() throws {
        let delegate = HabitTextDelegate()
        let learner = GestureHabitLearner()
        let vm = KeyboardViewModel(predictionEngine: PredictionEngine(), gestureHabitLearner: learner)
        vm.delegate = delegate
        let giyeok = try XCTUnwrap(key(for: .ㄱ))

        swipe(vm, key: giyeok, dx: 42, dy: -42)          // ↗ = ㅣ → 「기」
        vm.refreshPredictions()
        XCTAssertEqual(delegate.text, "기")
        vm.deleteBackward(); vm.refreshPredictions()     // 기 → ㄱ
        vm.deleteBackward(); vm.refreshPredictions()     // ㄱ → (빈)
        XCTAssertEqual(delegate.text, "")
        swipe(vm, key: giyeok, dx: 60, dy: 0)            // → = ㅏ → 「가」
        vm.refreshPredictions()
        XCTAssertEqual(delegate.text, "가")
        vm.inputSpace(); vm.refreshPredictions()

        XCTAssertEqual(vm.gestureHabitModel.observedCount, 1)
        XCTAssertEqual(vm.gestureHabitModel.counters["ㄱ|angle|-"], 1)
    }

    func testTurnedOff_countsNothing() throws {
        KeyboardSettings.shared.gestureHabitEnabled = false
        let delegate = HabitTextDelegate()
        let vm = KeyboardViewModel(predictionEngine: PredictionEngine(), gestureHabitLearner: GestureHabitLearner())
        vm.delegate = delegate
        let giyeok = try XCTUnwrap(key(for: .ㄱ))
        swipe(vm, key: giyeok, dx: 42, dy: -42); vm.refreshPredictions()
        vm.deleteBackward(); vm.refreshPredictions()
        vm.deleteBackward(); vm.refreshPredictions()
        swipe(vm, key: giyeok, dx: 60, dy: 0); vm.refreshPredictions()
        vm.inputSpace(); vm.refreshPredictions()
        XCTAssertEqual(vm.gestureHabitModel.observedCount, 0)
    }
}

private final class HabitTextDelegate: KeyboardViewModelDelegate {
    var text: String = ""
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
    func textAfterCursor() -> String? { nil }
    func hostAllowsAutoCapitalization() -> Bool { true }
    func hostInputTraitsDebugInfo() -> String { "" }
}
