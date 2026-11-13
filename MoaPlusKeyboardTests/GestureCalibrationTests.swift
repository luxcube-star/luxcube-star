import XCTest
import CoreGraphics

/// 처음 맞추기 (개선 방안 15번) — 문장 · 짝짓기 · 셈 · 키보드 반영.
final class GestureCalibrationTests: XCTestCase {

    private func sample(_ key: Choseong, vowel: Jungseong?, directions: [GestureDirection] = [],
                        angle: Double = 0, length: CGFloat = 60,
                        strokes: [CGVector] = [], maxDisplacement: CGFloat? = nil,
                        returnDistance: CGFloat = 0, rotation: Double = 0) -> GestureCalibrationSample {
        let rad = angle * .pi / 180
        let net = CGVector(dx: length * CGFloat(cos(rad)), dy: -length * CGFloat(sin(rad)))
        return GestureCalibrationSample(
            key: key, vowel: vowel, directions: directions, netVector: net,
            strokeVectors: strokes.isEmpty && !directions.isEmpty ? [net] : strokes,
            maxDisplacement: maxDisplacement ?? length, returnDistance: returnDistance,
            keyWidth: 50, swipeThreshold: 20, reversalThreshold: 14,
            rotationOffset: rotation, fourWay: false)
    }

    private func vector(_ degrees: Double, _ length: CGFloat) -> CGVector {
        let rad = degrees * .pi / 180
        return CGVector(dx: length * CGFloat(cos(rad)), dy: -length * CGFloat(sin(rad)))
    }

    // MARK: 문장

    func testTargets_syllableThenFinalConsonantTaps() {
        XCTAssertEqual(GestureCalibrationScript.targets(for: "각"), [
            GestureCalibrationTarget(key: .ㄱ, vowel: .ㅏ),
            GestureCalibrationTarget(key: .ㄱ, vowel: nil),
        ])
        // 겹받침은 낱자마다 탭, 띄어쓰기 · 문장부호는 건너뜀.
        XCTAssertEqual(GestureCalibrationScript.targets(for: "괜찮다."), [
            GestureCalibrationTarget(key: .ㄱ, vowel: .ㅙ),
            GestureCalibrationTarget(key: .ㄴ, vowel: nil),
            GestureCalibrationTarget(key: .ㅊ, vowel: .ㅏ),
            GestureCalibrationTarget(key: .ㄴ, vowel: nil),
            GestureCalibrationTarget(key: .ㅎ, vowel: nil),
            GestureCalibrationTarget(key: .ㄷ, vowel: .ㅏ),
        ])
    }

    func testScript_coversEveryConsonantKeyAndEveryVowel() {
        let targets = GestureCalibrationScript.sentences.flatMap { GestureCalibrationScript.targets(for: $0) }
        let singles: Set<Jungseong> = [.ㅏ, .ㅓ, .ㅗ, .ㅜ, .ㅣ, .ㅡ]
        for key in Choseong.allCases {
            let count = targets.filter { $0.key == key && $0.vowel.map(singles.contains) == true }.count
            XCTAssertGreaterThanOrEqual(count, GestureCalibrator.minAngleSamples, "\(key) 키 한 획 긋기")
        }
        let vowels = Set(targets.compactMap(\.vowel))
        for vowel in Jungseong.allCases where vowel != .ㆍ {
            XCTAssertTrue(vowels.contains(vowel), "모음 \(vowel.compatibilityCharacter)")
        }
        XCTAssertGreaterThanOrEqual(targets.count, 200)
    }

    // MARK: 짝짓기

    func testIngest_matchesNextSameKey_andDropsStrangers() {
        let calibrator = GestureCalibrator()
        calibrator.begin(sentence: "가나")
        XCTAssertFalse(calibrator.ingest(sample(.ㅂ, vowel: .ㅏ, directions: [.right])))   // 없는 키
        XCTAssertTrue(calibrator.ingest(sample(.ㄱ, vowel: .ㅓ, directions: [.left])))     // 틀린 모음도 잼
        XCTAssertTrue(calibrator.ingest(sample(.ㄴ, vowel: .ㅏ, directions: [.right])))
        XCTAssertFalse(calibrator.ingest(sample(.ㄴ, vowel: .ㅏ, directions: [.right])))   // 다 침
        XCTAssertEqual(calibrator.measurements.map(\.target.vowel), [.ㅏ, .ㅏ])
        calibrator.restartSentence()
        XCTAssertEqual(calibrator.sentenceMeasuredCount, 0)
    }

    // MARK: 각도

    func testAngle_medianDeviationPerKey() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = [
            (.init(key: .ㄱ, vowel: .ㅏ), sample(.ㄱ, vowel: .ㅏ, directions: [.right], angle: 7)),
            (.init(key: .ㄱ, vowel: .ㅗ), sample(.ㄱ, vowel: .ㅗ, directions: [.up], angle: 99)),
            (.init(key: .ㄱ, vowel: .ㅣ), sample(.ㄱ, vowel: .ㅣ, directions: [.upRight], angle: 53)),
        ]
        let result = GestureCalibrator.compute(m)
        XCTAssertEqual(result.keys["ㄱ"]?.rotationDeg, 8)   // 가운데값 8° → 2° 걸음
        XCTAssertEqual(result.angleSampleCounts["ㄱ"], 3)
    }

    func testAngle_subtractsColumnRotation_andClampsAtTen() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = (0..<3).map { _ in
            (.init(key: .ㅎ, vowel: .ㅓ), sample(.ㅎ, vowel: .ㅓ, directions: [.left], angle: 205, rotation: 5))
        }
        let result = GestureCalibrator.compute(m)
        XCTAssertEqual(result.keys["ㅎ"]?.rotationDeg, 10)   // 205 − 5 − 180 = 20 → 한도 10
        XCTAssertEqual(result.clamped["ㅎ"], [.angle])
    }

    func testAngle_needsThreeSwipes() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = (0..<2).map { _ in
            (.init(key: .ㅂ, vowel: .ㅏ), sample(.ㅂ, vowel: .ㅏ, directions: [.right], angle: 9))
        }
        XCTAssertNil(GestureCalibrator.compute(m).keys["ㅂ"])
    }

    // MARK: 손 전체

    func testMinLength_raisedWhenFinalTapsBecomeSwipes() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = [
            (.init(key: .ㄱ, vowel: nil), sample(.ㄱ, vowel: .ㅏ, directions: [.right], length: 22)),
            (.init(key: .ㄴ, vowel: nil), sample(.ㄴ, vowel: .ㅗ, directions: [.up], length: 21)),
            (.init(key: .ㄹ, vowel: nil), sample(.ㄹ, vowel: nil, length: 8)),
        ]
        // 미끄러짐 최대 22pt × 1.1 = 24.2pt → 문턱 20pt 보다 4.2pt = 키폭 8.4% → 한도 8%.
        let result = GestureCalibrator.compute(m)
        XCTAssertEqual(result.handWide.minLengthRatio, 0.08, accuracy: 1e-9)
        XCTAssertEqual(result.clamped[GestureCalibrationResult.handWideLabel], [.minLength])
        XCTAssertEqual(result.keys.count, Choseong.allCases.count)   // 손 전체 값은 19키 모두에
    }

    func testMinLength_loweredWhenSwipesBecomeTaps() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = [
            (.init(key: .ㄱ, vowel: .ㅏ), sample(.ㄱ, vowel: nil, maxDisplacement: 17)),
            (.init(key: .ㄴ, vowel: .ㅏ), sample(.ㄴ, vowel: nil, maxDisplacement: 18)),
            (.init(key: .ㄹ, vowel: nil), sample(.ㄹ, vowel: nil, maxDisplacement: 4)),
        ]
        // 17 × 0.9 = 15.3pt → 문턱보다 4.7pt 낮게 = −9.4% → 걸음 맞춤 후 한도 −8%.
        XCTAssertEqual(GestureCalibrator.compute(m).handWide.minLengthRatio, -0.08, accuracy: 1e-9)
    }

    func testCurve_splitSingleStrokesWidenMergeLimit() {
        func split(_ key: Choseong, turn: Double) -> (target: GestureCalibrationTarget, sample: GestureCalibrationSample) {
            (.init(key: key, vowel: .ㅣ),
             sample(key, vowel: .ㅘ, directions: [.up, .upRight],
                    strokes: [vector(90, 30), vector(90 - turn, 40)]))
        }
        // 세로 시작 한도 35° — 꺾임 39° · 41° → 필요 5 · 7 → 두 번째로 큰 5 → 2° 걸음 올림 6.
        let result = GestureCalibrator.compute([split(.ㄱ, turn: 39), split(.ㄴ, turn: 41)])
        XCTAssertEqual(result.handWide.curveDeg, 6)
    }

    func testLength_loweredWhenReturnStrokesAreShort() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = (0..<4).map { i in
            (.init(key: .ㄱ, vowel: .ㅐ),
             sample(.ㄱ, vowel: .ㅐ, directions: [.right, .left],
                    strokes: [vector(0, 50), vector(180, 15 + CGFloat(i))]))
        }
        // 짧은 획 아래 20% ≈ 15.6pt / 1.25 ≈ 12.5pt → 문턱 14pt 보다 약 1.5pt 낮게 = 약 −3% → 2% 걸음으로 −4%.
        let ratio = GestureCalibrator.compute(m).handWide.lengthRatio
        XCTAssertLessThan(ratio, 0)
        XCTAssertGreaterThanOrEqual(ratio, -0.04)
    }

    func testNothingToAdjust_whenSwipesAreCentered() {
        let m: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = (0..<4).map { _ in
            (.init(key: .ㄷ, vowel: .ㅜ), sample(.ㄷ, vowel: .ㅜ, directions: [.down], angle: 270))
        }
        XCTAssertTrue(GestureCalibrator.compute(m).keys.isEmpty)
    }

    // MARK: 키보드 반영

    func testCalibrateEdit_replacesEarlierValues_andEachLineReverts() {
        let learner = GestureHabitLearner()
        for _ in 0..<GestureHabitLearner.stepThreshold {
            learner.record(GestureHabitObservation(key: "ㅂ", axis: .angle, sign: 1))
        }
        learner.record(GestureHabitObservation(key: "ㅅ", axis: .angle, sign: 1))
        XCTAssertEqual(learner.model.keys["ㅂ"]?.rotationDeg, -2)

        var g = GestureHabitAdjustment.zero
        g.set(.angle, to: 6); g.set(.curve, to: 4)
        learner.apply(edits: [GestureHabitEditRequest(id: 1, edit: .calibrate(keys: ["ㄱ": g]))])

        XCTAssertNil(learner.model.keys["ㅂ"])                  // 앞 값 지움 (7가)
        XCTAssertTrue(learner.model.counters.isEmpty)           // 쌓이던 오타도
        XCTAssertEqual(learner.model.keys["ㄱ"], g)
        XCTAssertEqual(learner.model.events.count, 2)
        XCTAssertTrue(learner.model.events.allSatisfy { $0.fromCalibration == true })
        XCTAssertEqual(learner.model.appliedEditId, 1)

        let curveEvent = try! XCTUnwrap(learner.model.events.first { $0.knob == .curve })
        learner.apply(edits: [GestureHabitEditRequest(id: 2, edit: .revert(eventId: curveEvent.id))])
        XCTAssertEqual(learner.model.keys["ㄱ"]?.curveDeg, 0)
        XCTAssertEqual(learner.model.keys["ㄱ"]?.rotationDeg, 6)
    }

    func testCalibrateEdit_roundTripsThroughJSON() throws {
        var g = GestureHabitAdjustment.zero
        g.set(.minLength, to: 0.04)
        let request = GestureHabitEditRequest(id: 3, edit: .calibrate(keys: ["ㅎ": g]))
        let decoded = try JSONDecoder().decode(GestureHabitEditRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded, request)
    }

    // MARK: 뷰모델

    func testViewModel_reportsMeasuredSampleOnTapAndSwipe() throws {
        let saved = KeyboardSettings.shared.autoSpaceOnPauseEnabled
        KeyboardSettings.shared.autoSpaceOnPauseEnabled = false
        defer { KeyboardSettings.shared.autoSpaceOnPauseEnabled = saved }

        let vm = KeyboardViewModel(predictionEngine: PredictionEngine(), gestureHabitLearner: GestureHabitLearner())
        let delegate = CalibrationTextDelegate()
        vm.delegate = delegate
        var received: [GestureCalibrationSample] = []
        vm.onConsonantGestureMeasured = { received.append($0) }

        let layout = KeyboardSettings.shared.layoutCustomization
        var giyeok: (Int, Int)?
        for row in 0..<4 { for column in 0..<8 {
            if case .consonant(.ㄱ)? = KeyboardMetrics.keyContent(at: row, column: column, mode: .korean, layout: layout) {
                giyeok = (row, column)
            }
        } }
        let (row, column) = try XCTUnwrap(giyeok)

        let start = CGPoint(x: 150, y: 150)
        vm.gestureStarted(row: row, column: column, at: start)
        for i in 1...10 {
            vm.gestureMoved(row: row, column: column, to: CGPoint(x: start.x + 6 * CGFloat(i), y: start.y))
        }
        vm.gestureEnded(row: row, column: column)
        vm.gestureStarted(row: row, column: column, at: start)
        vm.gestureEnded(row: row, column: column)

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.key, .ㄱ)
        XCTAssertEqual(received.first?.vowel, .ㅏ)
        XCTAssertEqual(received.first?.netVector.dx ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(received.last?.vowel, nil)
        XCTAssertEqual(delegate.text, "각")
    }
}

private final class CalibrationTextDelegate: KeyboardViewModelDelegate {
    var text = ""
    func insertText(_ s: String) { text += s }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func updateComposingText(from previous: String, to current: String) {
        text.removeLast(min(previous.count, text.count))
        text += current
    }
    func switchToNextKeyboard() {}
    func triggerHapticFeedback() {}
    func moveCursor(by offset: Int) {}
    func textBeforeCursor() -> String? { text.isEmpty ? nil : text }
    func textAfterCursor() -> String? { nil }
}
