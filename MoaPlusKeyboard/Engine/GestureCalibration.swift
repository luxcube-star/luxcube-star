import Foundation
import CoreGraphics

// MARK: - 처음 맞추기 (개선 방안 15번, 사용자 결정 2026-11-13: 1~9 모두 가)
//
// 앱 화면에 정해 준 문장을 치게 하고, 자음 키 긋기 · 탭마다 숫자를 받아 버릇을 잰다. 무엇을 그으려 했는지
// 알고 있으므로 틀린 긋기도 그대로 잰다(3가). 잰 값은 13번(긋기 버릇 맞추기)과 같은 자리 · 같은 한도에
// 넣는다(5가 · 6가) — 앱은 보여 주기만 하고, 「넣기」를 누르면 `GestureHabitEdit.calibrate` 요청을 남겨
// 키보드가 다음에 뜰 때 앞 값을 지우고 이 값으로 바꾼다(4가 · 7가). 그 뒤는 13번이 이어서 고친다(8가).
//
// 무엇을 재나:
// - 각도: 키마다. 한 획 모음(ㅏ ㅓ ㅗ ㅜ ㅣ ㅡ)을 그은 실제 각도가 구역 한가운데서 벗어난 양의 가운데값.
// - 길이 · 휨 · 최소 길이: 손 전체에서 재어 19키에 같게 넣는다. 키마다 재려면 문장이 몇 배로 길어진다.
//   - 길이: 되돌아온 획(꺾임 135° 넘음)이 되돌림 문턱보다 짧거나 가까우면 내리고, 한 획 모음 끝에
//     되돌림 꼬리가 붙어 획이 더 생기면 올린다.
//   - 휨: 한 획 모음이 휘어서 두 조각으로 갈렸으면, 그 꺾임이 합쳐지도록 한도를 넓힌다.
//   - 최소 길이: 받침 탭이 긋기로 들어가면 올리고, 긋기가 짧아 탭이 되면 내린다.

/// 처음 맞추기 화면이 기대하는 입력 하나 — 자음 키와, 그어야 할 모음(받침 탭이면 nil).
struct GestureCalibrationTarget: Equatable {
    let key: Choseong
    let vowel: Jungseong?
}

/// 자음 키 긋기 · 탭 한 번을 잰 숫자. 버릇 맞추기는 끈 채(`.zero`) 잰다.
struct GestureCalibrationSample: Equatable {
    let key: Choseong
    /// 들어간 모음. 탭이면(또는 무효 긋기면) nil.
    let vowel: Jungseong?
    let directions: [GestureDirection]
    /// 누른 자리 → 뗀 자리 (화면 좌표, y 아래로 +).
    let netVector: CGVector
    /// 노이즈를 걷어 낸 획들 (화면 좌표).
    let strokeVectors: [CGVector]
    /// 누른 자리에서 가장 멀리 간 거리.
    let maxDisplacement: CGFloat
    /// 가장 멀리 간 자리 → 뗀 자리 거리 (되돌아온 길이).
    let returnDistance: CGFloat
    let keyWidth: CGFloat
    /// 그때의 첫 획 문턱 (탭/긋기 경계).
    let swipeThreshold: CGFloat
    /// 그때의 되돌림 문턱.
    let reversalThreshold: CGFloat
    /// 그 줄의 구역 회전 (전체 회전 + 줄 보정, 버릇 맞추기 뺌).
    let rotationOffset: Double
    /// 4방향 전용 모드였나 — 대각선(ㅣ ㅡ)은 각도 재기에서 뺀다.
    let fourWay: Bool
}

// MARK: - 문장

enum GestureCalibrationScript {
    /// 자음 키 19개가 모두 한 획 긋기(ㅏ ㅓ ㅗ ㅜ ㅣ ㅡ)를 3번 넘게 하고, 모음 21개가 다 들어가게 골랐다.
    /// 모두 입력 312번 (긋기 · 받침 탭). 근거: 사람마다 맞춘 터치 판정이 약 200번 입력으로 나아짐 (Weir 외 2012).
    static let sentences: [String] = [
        "아빠와 엄마는 토끼를 키웠다",
        "뜨거운 차를 쪼르륵 따라 마셨다",
        "씨앗을 심고 꽃이 피기를 기다린다",
        "파도 소리에 귀를 기울여 보자",
        "예쁜 의자 위에 쿠키를 놓았다",
        "왜 그렇게 외롭게 웃었니",
        "훨씬 더 큰 꿈을 꾸어도 좋다",
        "뭐든지 처음에는 서툴러도 괜찮다",
        "얘기를 듣다 보니 해가 졌다",
        "웨딩 사진을 찍으러 공원에 갔다",
        "쌀쌀한 바람이 뺨을 스치고 지나갔다",
        "짜장면 한 그릇과 탕수육을 시켰다",
        "저녁에 텃밭에서 호박을 땄다",
        "치킨과 피자를 먹으며 축구를 봤다",
        "여름 휴가는 바다로 떠나요",
        "뿌리 깊은 나무는 바람에 흔들리지 않는다",
        "새벽에 개가 짖어서 교실 유리창이 깨졌다",
    ]

    /// 문장을 칠 때 자음 키에서 일어날 입력 차례. 글자마다 첫소리 긋기, 받침은 낱자마다 탭.
    static func targets(for text: String) -> [GestureCalibrationTarget] {
        var result: [GestureCalibrationTarget] = []
        for char in text {
            guard let (cho, jung, jong) = HangulConstants.decomposeSyllable(char) else { continue }
            result.append(GestureCalibrationTarget(key: cho, vowel: jung))
            for keyChar in jongseongKeys(jong) {
                if let key = Choseong.allCases.first(where: { $0.compatibilityCharacter == keyChar }) {
                    result.append(GestureCalibrationTarget(key: key, vowel: nil))
                }
            }
        }
        return result
    }

    /// 받침을 누를 자음 키 차례 (겹받침은 둘).
    static func jongseongKeys(_ jong: Jongseong) -> [Character] {
        switch jong {
        case .none: return []
        case .ㄳ: return ["ㄱ", "ㅅ"]
        case .ㄵ: return ["ㄴ", "ㅈ"]
        case .ㄶ: return ["ㄴ", "ㅎ"]
        case .ㄺ: return ["ㄹ", "ㄱ"]
        case .ㄻ: return ["ㄹ", "ㅁ"]
        case .ㄼ: return ["ㄹ", "ㅂ"]
        case .ㄽ: return ["ㄹ", "ㅅ"]
        case .ㄾ: return ["ㄹ", "ㅌ"]
        case .ㄿ: return ["ㄹ", "ㅍ"]
        case .ㅀ: return ["ㄹ", "ㅎ"]
        case .ㅄ: return ["ㅂ", "ㅅ"]
        default: return jong.compatibilityCharacter.map { [$0] } ?? []
        }
    }
}

// MARK: - 재기

struct GestureCalibrationResult: Equatable {
    /// 자음 키(「ㄱ」) → 넣을 값. 0 인 키는 빠진다.
    var keys: [String: GestureHabitAdjustment] = [:]
    /// 한도에 닿아 잘린 손잡이 (「ㄱ」 → 손잡이들). 손 전체 값은 「전체」.
    var clamped: [String: Set<GestureHabitKnob>] = [:]
    /// 각도를 잰 키마다 쓴 긋기 수.
    var angleSampleCounts: [String: Int] = [:]
    /// 잰 입력 수 · 그 가운데 정해 준 것과 다르게 들어간 수.
    var measuredCount = 0
    var mismatchCount = 0
    /// 손 전체 값 (길이 · 휨 · 최소 길이).
    var handWide = GestureHabitAdjustment.zero

    static let handWideLabel = "전체"
}

final class GestureCalibrator {
    /// 각도를 넣으려면 그 키에서 한 획 긋기가 이만큼 있어야 한다.
    static let minAngleSamples = 3
    /// 길이를 정하려면 되돌아온 획이 이만큼 있어야 한다.
    static let minLengthSamples = 4
    /// 기대한 차례에서 이만큼 앞까지 같은 키를 찾는다 (한두 글자 건너뛰고 친 경우).
    static let lookahead = 3

    private(set) var measurements: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)] = []
    private var sentenceStart = 0
    private var expected: [GestureCalibrationTarget] = []
    private var cursor = 0

    /// 새 문장을 시작한다.
    func begin(sentence: String) {
        expected = GestureCalibrationScript.targets(for: sentence)
        cursor = 0
        sentenceStart = measurements.count
    }

    /// 이 문장에서 잰 것을 버리고 처음부터 (「이 문장 다시」).
    func restartSentence() {
        measurements.removeSubrange(sentenceStart...)
        cursor = 0
    }

    var sentenceMeasuredCount: Int { measurements.count - sentenceStart }

    /// 자음 키 입력 하나를 받는다. 기대한 차례에서 같은 키를 찾아 짝지운다 — 못 찾으면 버린다.
    @discardableResult
    func ingest(_ sample: GestureCalibrationSample) -> Bool {
        let end = min(cursor + Self.lookahead, expected.count)
        guard cursor < end,
              let index = (cursor..<end).first(where: { expected[$0].key == sample.key }) else { return false }
        measurements.append((expected[index], sample))
        cursor = index + 1
        return true
    }

    func result() -> GestureCalibrationResult {
        Self.compute(measurements)
    }

    // MARK: 셈

    static func compute(_ measurements: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)]) -> GestureCalibrationResult {
        var result = GestureCalibrationResult()
        result.measuredCount = measurements.count
        result.mismatchCount = measurements.filter { $0.target.vowel != $0.sample.vowel }.count

        // 손 전체 값 — 한도 안으로 잘라 넣는다.
        var hand = GestureHabitAdjustment.zero
        var handClamped = Set<GestureHabitKnob>()
        func put(_ knob: GestureHabitKnob, _ raw: Double?, into adjustment: inout GestureHabitAdjustment,
                 clamped: inout Set<GestureHabitKnob>) {
            guard let raw else { return }
            adjustment.set(knob, to: raw)
            if raw < knob.range.lowerBound - 1e-9 || raw > knob.range.upperBound + 1e-9 { clamped.insert(knob) }
        }
        put(.length, lengthAdjustment(measurements), into: &hand, clamped: &handClamped)
        put(.curve, curveAdjustment(measurements), into: &hand, clamped: &handClamped)
        put(.minLength, minLengthAdjustment(measurements), into: &hand, clamped: &handClamped)
        result.handWide = hand
        if !handClamped.isEmpty { result.clamped[GestureCalibrationResult.handWideLabel] = handClamped }

        // 각도 — 키마다.
        var angles: [String: [Double]] = [:]
        for (target, sample) in measurements {
            guard let vowel = target.vowel, let deviation = angleDeviation(vowel: vowel, sample: sample) else { continue }
            angles[String(target.key.compatibilityCharacter), default: []].append(deviation)
        }
        for key in Choseong.allCases.map({ String($0.compatibilityCharacter) }) {
            var adjustment = hand
            if let deviations = angles[key] {
                result.angleSampleCounts[key] = deviations.count
                if deviations.count >= minAngleSamples {
                    var clamped = Set<GestureHabitKnob>()
                    put(.angle, median(deviations), into: &adjustment, clamped: &clamped)
                    if !clamped.isEmpty { result.clamped[key] = clamped }
                }
            }
            if !adjustment.isZero { result.keys[key] = adjustment }
        }
        return result
    }

    /// 한 획 모음을 그은 각도가 구역 한가운데서 벗어난 양 (반시계 +). 판정 각도 = 실제 − 회전 이므로
    /// 이 값을 회전으로 넣으면 그은 각도가 구역 한가운데로 온다. 한 획 모음이 아니거나 너무 짧으면 nil.
    static func angleDeviation(vowel: Jungseong, sample: GestureCalibrationSample) -> Double? {
        let centers: [Double]
        switch vowel {
        case .ㅏ: centers = [0]
        case .ㅗ: centers = [90]
        case .ㅓ: centers = [180]
        case .ㅜ: centers = [270]
        case .ㅣ: centers = sample.fourWay ? [] : [45, 135]
        case .ㅡ: centers = sample.fourWay ? [] : [225, 315]
        default: centers = []
        }
        guard !centers.isEmpty else { return nil }
        let v = sample.netVector
        let length = sqrt(v.dx * v.dx + v.dy * v.dy)
        guard length >= sample.swipeThreshold, length > 0 else { return nil }
        let actual = atan2(Double(-v.dy), Double(v.dx)) * 180 / .pi
        let deviations = centers.map { wrap(actual - sample.rotationOffset - $0) }
        guard let best = deviations.min(by: { abs($0) < abs($1) }), abs(best) <= 45 else { return nil }
        return best
    }

    /// 여러 획 모음의 최소 획 수 (되돌림이 몇 번 있어야 하는지 가늠용).
    static func minimumStrokeCount(_ vowel: Jungseong) -> Int {
        switch vowel {
        case .ㅏ, .ㅓ, .ㅗ, .ㅜ, .ㅣ, .ㅡ: return 1
        case .ㅐ, .ㅔ, .ㅚ, .ㅟ, .ㅘ, .ㅝ, .ㅢ: return 2
        case .ㅛ, .ㅠ, .ㅑ, .ㅕ, .ㅙ, .ㅞ: return 3
        case .ㅒ, .ㅖ: return 4
        default: return 1
        }
    }

    /// 두 획이 되돌림인 모음 (→← · ↑↓ · ↙↗ 처럼 거꾸로 돌아옴).
    static func isTwoStrokeReversal(_ vowel: Jungseong) -> Bool {
        [.ㅐ, .ㅔ, .ㅚ, .ㅟ, .ㅢ].contains(vowel)
    }

    /// 길이(되돌림 · 방향 전환 문턱)에 더할 키폭 비율. 증거가 모자라거나 엇갈리면 nil.
    static func lengthAdjustment(_ measurements: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)]) -> Double? {
        var legs: [Double] = []          // 되돌아온 획 길이 / 키폭
        var thresholds: [Double] = []    // 되돌림 문턱 / 키폭
        var tails: [Double] = []         // 한 획 모음 끝에 붙은 되돌림 꼬리 / 키폭
        for (target, sample) in measurements {
            guard let vowel = target.vowel, sample.keyWidth > 0 else { continue }
            let kw = Double(sample.keyWidth)
            let needed = minimumStrokeCount(vowel)
            if needed >= 2 {
                thresholds.append(Double(sample.reversalThreshold) / kw)
                let reversals = reversalLegs(sample.strokeVectors)
                legs.append(contentsOf: reversals.map { Double($0) / kw })
                // 되돌림이 아예 안 잡혀 획이 모자랐으면, 되돌아온 거리로 짧은 획 길이를 대신한다.
                if isTwoStrokeReversal(vowel), reversals.isEmpty, sample.directions.count < needed,
                   sample.returnDistance > 0 {
                    legs.append(Double(sample.returnDistance) / kw)
                }
            } else if sample.directions.count >= 2, sample.vowel != vowel {
                tails.append(contentsOf: reversalLegs(sample.strokeVectors).map { Double($0) / kw })
            }
        }
        guard let threshold = median(thresholds) else { return nil }
        var lower: Double?
        if legs.count >= minLengthSamples, let short = percentile(legs, 0.2) {
            // 짧게 되돌아온 획(아래 20%)도 문턱의 1.25배는 되게.
            let desired = short / 1.25
            if desired < threshold { lower = desired - threshold }
        }
        var raise: Double?
        if tails.count >= 2, let longest = tails.max() {
            let desired = longest * 1.2
            if desired > threshold { raise = desired - threshold }
        }
        switch (lower, raise) {
        case (let l?, nil): return l
        case (nil, let r?): return r
        default: return nil
        }
    }

    /// 휜 획 합치기 한도에 더할 각도. 한 획 모음이 두 조각으로 갈린 일이 두 번 넘게 있어야 한다.
    static func curveAdjustment(_ measurements: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)]) -> Double? {
        var needs: [Double] = []
        for (target, sample) in measurements {
            guard let vowel = target.vowel, minimumStrokeCount(vowel) == 1,
                  sample.vowel != vowel, sample.strokeVectors.count == 2 else { continue }
            let first = sample.strokeVectors[0], second = sample.strokeVectors[1]
            let turn = turnDegrees(first, second)
            // 세로로 시작해 옆 대각선으로 휜 것은 35°, 그 밖은 45° 가 한도 (GestureAnalyzer).
            let verticalStart = sample.directions.first == .up || sample.directions.first == .down
            let limit = verticalStart ? 35.0 : 45.0
            let need = turn - limit + 1
            if need > 0, need <= GestureHabitKnob.curve.range.upperBound + 4 { needs.append(need) }
        }
        guard needs.count >= 2 else { return nil }
        // 하나 튄 값에 끌려가지 않게 두 번째로 큰 값.
        let sorted = needs.sorted(by: >)
        return (sorted[1] / GestureHabitKnob.curve.step).rounded(.up) * GestureHabitKnob.curve.step
    }

    /// 첫 획 문턱에 더할 키폭 비율.
    static func minLengthAdjustment(_ measurements: [(target: GestureCalibrationTarget, sample: GestureCalibrationSample)]) -> Double? {
        var slips: [Double] = []        // 받침 탭에서 미끄러진 거리 / 키폭
        var accidental: [Double] = []   // 탭이 긋기로 들어간 것
        var tooShort: [Double] = []     // 긋기가 탭이 된 것 (문턱의 40% 넘게 움직임)
        var thresholds: [Double] = []
        for (target, sample) in measurements where sample.keyWidth > 0 {
            let kw = Double(sample.keyWidth)
            let moved = Double(sample.maxDisplacement) / kw
            thresholds.append(Double(sample.swipeThreshold) / kw)
            if target.vowel == nil {
                slips.append(moved)
                if sample.vowel != nil { accidental.append(moved) }
            } else if sample.directions.isEmpty,
                      sample.maxDisplacement >= sample.swipeThreshold * GestureHabitLearner.attemptedSwipeRatio {
                tooShort.append(moved)
            }
        }
        guard let threshold = median(thresholds) else { return nil }
        if accidental.count >= 2, tooShort.isEmpty, let longest = slips.max() {
            let desired = longest * 1.1
            return desired > threshold ? desired - threshold : nil
        }
        if tooShort.count >= 2, accidental.isEmpty, let shortest = tooShort.min() {
            let desired = shortest * 0.9
            // 받침 탭이 긋기로 넘어가지 않게, 미끄러진 거리(위 10%)보다는 높게.
            let floor = (percentile(slips, 0.9) ?? 0) * 1.1
            guard desired < threshold, desired > floor else { return nil }
            return desired - threshold
        }
        return nil
    }

    // MARK: 도움

    /// 앞 획에서 135° 넘게 꺾여 되돌아온 획들의 길이.
    static func reversalLegs(_ vectors: [CGVector]) -> [CGFloat] {
        guard vectors.count >= 2 else { return [] }
        return (1..<vectors.count).compactMap { i in
            turnDegrees(vectors[i - 1], vectors[i]) > 135 ? hypot(vectors[i].dx, vectors[i].dy) : nil
        }
    }

    static func turnDegrees(_ a: CGVector, _ b: CGVector) -> Double {
        let la = hypot(a.dx, a.dy), lb = hypot(b.dx, b.dy)
        guard la > 0, lb > 0 else { return 0 }
        let cos = Double((a.dx * b.dx + a.dy * b.dy) / (la * lb))
        return acos(min(max(cos, -1), 1)) * 180 / .pi
    }

    static func wrap(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    static func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    /// 0~1 자리의 값 (선형 보간).
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
