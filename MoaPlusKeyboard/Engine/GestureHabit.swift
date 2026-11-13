import Foundation
import CoreGraphics

// MARK: - 긋기 버릇 맞추기 (개선 방안 13번, 사용자 결정 2026-11-13)
//
// 긋기 방향이 틀려 모음이 잘못 들어간 오타를 자음 키마다 세어, 같은 키 · 같은 종류 · 같은 쪽 오타가
// `stepThreshold`(5) 번 쌓이면 그 키의 판정 손잡이를 한 걸음 돌린다. 친 글은 남기지 않는다 — 비교하려고
// 메모리에 잠깐 든 글자는 저장하지 않고, 파일에는 키 · 손잡이 · 숫자만 쓴다.
//
// 손잡이 넷 (`GestureHabitKnob`):
// - 각도: 그 키의 방향 구역을 돌린다. 2°씩 ±10°.
// - 길이: 되돌림 · 방향 전환 문턱을 키폭의 2%씩 ±8%. + = 둘째 획이 덜 생김.
// - 휨: 휜 획을 한 획으로 합치는 꺾임 한도를 2°씩 0~10° 넓힌다.
// - 최소 길이: 탭이 아니라 긋기로 보는 길이를 키폭의 2%씩 ±8%. − = 짧아도 긋기.
//
// 세는 오타: 지운 글(10글자까지)과 다시 친 글이 **딱 한 글자** 다르고, 그 글자가 같은 자음 키에서 모음만
// 달라졌을 때(받침 같음). 다른 자음 키로 다시 쳤으면 자음 오타라 세지 않는다. 모음 키는 맞추지 않는다.

/// 한 자음 키에 맞춘 값. 모두 0 이면 맞추지 않은 것과 같다.
struct GestureHabitAdjustment: Codable, Equatable {
    /// 방향 구역 회전(도). 판정 각도 = 실제 각도 − 회전 (`GestureDirection.from` 과 같은 규약).
    var rotationDeg: Double = 0
    /// 되돌림 · 방향 전환 문턱에 더할 키폭 비율.
    var lengthRatio: Double = 0
    /// 휜 획 합치기 꺾임 한도에 더할 각도(도).
    var curveDeg: Double = 0
    /// 첫 획(탭/긋기 경계) 문턱에 더할 키폭 비율.
    var minLengthRatio: Double = 0

    static let zero = GestureHabitAdjustment()

    var isZero: Bool { self == .zero }

    func value(of knob: GestureHabitKnob) -> Double {
        switch knob {
        case .angle: return rotationDeg
        case .length: return lengthRatio
        case .curve: return curveDeg
        case .minLength: return minLengthRatio
        }
    }

    mutating func set(_ knob: GestureHabitKnob, to value: Double) {
        let clamped = min(max(value, knob.range.lowerBound), knob.range.upperBound)
        // 2% · 2° 걸음을 여러 번 더하고 빼도 부동소수 찌꺼기가 남지 않게 걸음 단위로 맞춘다.
        let rounded = (clamped / knob.step).rounded() * knob.step
        switch knob {
        case .angle: rotationDeg = rounded
        case .length: lengthRatio = rounded
        case .curve: curveDeg = rounded
        case .minLength: minLengthRatio = rounded
        }
    }
}

enum GestureHabitKnob: String, Codable, CaseIterable {
    case angle, length, curve, minLength

    /// 한 걸음 (사용자 결정 2026-11-13: 각도 2° · 길이 키폭 2% · 휨 2°).
    var step: Double {
        switch self {
        case .angle, .curve: return 2
        case .length, .minLength: return 0.02
        }
    }

    /// 맞출 수 있는 범위 (각도 ±10° · 길이 ±8% · 휨 0~10°).
    var range: ClosedRange<Double> {
        switch self {
        case .angle: return -10...10
        case .length, .minLength: return -0.08...0.08
        case .curve: return 0...10
        }
    }

    var displayName: String {
        switch self {
        case .angle: return "각도"
        case .length: return "길이"
        case .curve: return "휨"
        case .minLength: return "최소 길이"
        }
    }

    /// 사람이 읽는 값 — 「−2°」 「+4%」.
    func formatted(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        switch self {
        case .angle, .curve: return "\(sign)\(Int(abs(value).rounded()))°"
        case .length, .minLength: return "\(sign)\(Int((abs(value) * 100).rounded()))%"
        }
    }
}

/// 맞춘 일 하나 — 앱 「입력 기록 보드」에 보여 주고 되돌린다.
struct GestureHabitEvent: Codable, Equatable, Identifiable {
    let id: Int
    let date: Date
    /// 자음 키 (「ㄱ」).
    let key: String
    let knob: GestureHabitKnob
    /// 이번에 실제로 바뀐 양 (상한에 걸려 덜 바뀌었으면 그만큼).
    let delta: Double
    var reverted: Bool = false
}

struct GestureHabitModel: Codable, Equatable {
    static let currentVersion = 1
    /// 남겨 둘 맞춘 일 수.
    static let maxEvents = 100

    var version: Int = GestureHabitModel.currentVersion
    /// 자음 키(「ㄱ」) → 맞춘 값.
    var keys: [String: GestureHabitAdjustment] = [:]
    /// 「ㄱ|angle|+」 → 쌓인 오타 수.
    var counters: [String: Int] = [:]
    var events: [GestureHabitEvent] = []
    var nextEventId: Int = 1
    /// 앱 편집 요청(되돌리기 · 처음으로) 가운데 반영한 마지막 번호.
    var appliedEditId: Int = 0
    /// 지금까지 센 오타 쌍 (개발자 리포트용).
    var observedCount: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? GestureHabitModel.currentVersion
        keys = try c.decodeIfPresent([String: GestureHabitAdjustment].self, forKey: .keys) ?? [:]
        counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
        events = try c.decodeIfPresent([GestureHabitEvent].self, forKey: .events) ?? []
        nextEventId = try c.decodeIfPresent(Int.self, forKey: .nextEventId) ?? 1
        appliedEditId = try c.decodeIfPresent(Int.self, forKey: .appliedEditId) ?? 0
        observedCount = try c.decodeIfPresent(Int.self, forKey: .observedCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case version, keys, counters, events, nextEventId, appliedEditId, observedCount
    }

    func adjustment(for key: String) -> GestureHabitAdjustment {
        keys[key] ?? .zero
    }

    /// 개발자 리포트 「버릇 맞추기」 줄. 키 · 숫자만 담는다.
    var diagnosticLine: String {
        let adjusted = keys.keys.sorted().compactMap { key -> String? in
            let a = adjustment(for: key)
            guard !a.isZero else { return nil }
            let parts = GestureHabitKnob.allCases.compactMap { knob -> String? in
                let v = a.value(of: knob)
                return v == 0 ? nil : "\(knob.displayName) \(knob.formatted(v))"
            }
            return "\(key)(\(parts.joined(separator: " · ")))"
        }
        let counted = counters.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return "센 오타 \(observedCount)번 / 맞춘 키 \(adjusted.isEmpty ? "없음" : adjusted.joined(separator: ", "))"
            + " / 쌓이는 중 \(counted.isEmpty ? "없음" : counted.joined(separator: ", "))"
    }
}

// MARK: - 편집 요청 (앱 → 키보드)

enum GestureHabitEdit: Codable, Equatable {
    case revert(eventId: Int)
    case resetAll
}

struct GestureHabitEditRequest: Codable, Equatable {
    let id: Int
    let edit: GestureHabitEdit
}

// MARK: - 긋기 한 번의 숫자

/// 자음 키 긋기(또는 탭) 한 번. 오타를 가르는 데 필요한 숫자만 든다.
struct GestureHabitSample: Equatable {
    let key: Choseong
    /// 들어간 모음. 탭이면(또는 무효 긋기면) nil.
    let vowel: Jungseong?
    /// 확정된 획 방향.
    let directions: [GestureDirection]
    /// 누른 자리에서 가장 멀리 간 거리(pt).
    let maxDisplacement: CGFloat
    /// 그때의 첫 획 문턱(pt).
    let swipeThreshold: CGFloat

    var isTap: Bool { directions.isEmpty }
}

/// 틀린 긋기와 다시 그은 긋기를 비교해 나온 한 걸음 후보.
struct GestureHabitObservation: Equatable {
    enum Axis: String {
        /// 방향이 한 칸(45°) 어긋남. sign: +1 = 다시 그은 방향이 반시계 쪽.
        case angle
        /// 획 수가 다름. sign: +1 = 틀린 쪽 획이 더 많음(획이 덜 생기게).
        case strokes
        /// 탭 ↔ 긋기. sign: −1 = 긋기가 탭이 됨(문턱 내림), +1 = 탭이 긋기가 됨(문턱 올림).
        case minLength
    }
    let key: String
    let axis: Axis
    let sign: Int
}

// MARK: - 오타 가르기 · 맞추기

final class GestureHabitLearner {
    /// 같은 키 · 같은 종류 · 같은 쪽 오타가 이만큼 쌓이면 한 걸음 (사용자 결정).
    static let stepThreshold = 5
    /// 탭이 됐지만 긋기를 하려던 것으로 볼 최소 이동 (첫 획 문턱 대비).
    static let attemptedSwipeRatio: CGFloat = 0.4
    /// 긋기가 됐지만 탭을 하려던 것으로 볼 최대 길이 (첫 획 문턱 대비).
    static let accidentalSwipeRatio: CGFloat = 1.3

    private(set) var model: GestureHabitModel
    var now: () -> Date = Date.init

    init(model: GestureHabitModel = GestureHabitModel()) {
        self.model = model
    }

    func adjustment(for key: Choseong) -> GestureHabitAdjustment {
        model.adjustment(for: String(key.compatibilityCharacter))
    }

    /// 틀린 것과 다시 친 것을 비교한다. 같은 키가 아니거나 종류를 가를 수 없으면 nil.
    static func classify(wrong: GestureHabitSample, correct: GestureHabitSample) -> GestureHabitObservation? {
        guard wrong.key == correct.key else { return nil }
        let key = String(wrong.key.compatibilityCharacter)

        switch (wrong.isTap, correct.isTap) {
        case (true, false):
            // 긋는다고 그었는데 짧아서 탭(자음만)이 됐다.
            guard correct.vowel != nil,
                  wrong.maxDisplacement >= wrong.swipeThreshold * attemptedSwipeRatio else { return nil }
            return GestureHabitObservation(key: key, axis: .minLength, sign: -1)
        case (false, true):
            // 탭하려다 살짝 밀려 모음이 들어갔다.
            guard wrong.vowel != nil, wrong.directions.count == 1,
                  wrong.maxDisplacement < wrong.swipeThreshold * accidentalSwipeRatio,
                  correct.maxDisplacement < correct.swipeThreshold * attemptedSwipeRatio else { return nil }
            return GestureHabitObservation(key: key, axis: .minLength, sign: 1)
        case (true, true):
            return nil
        case (false, false):
            break
        }

        guard let wrongVowel = wrong.vowel, let correctVowel = correct.vowel, wrongVowel != correctVowel else { return nil }
        if wrong.directions.count != correct.directions.count {
            return GestureHabitObservation(key: key, axis: .strokes,
                                           sign: wrong.directions.count > correct.directions.count ? 1 : -1)
        }
        // 획 수가 같으면 다른 획이 딱 하나, 그것도 한 칸(45°) 어긋났을 때만 각도 오타로 본다.
        let differing = zip(wrong.directions, correct.directions).filter { $0.0 != $0.1 }
        guard differing.count == 1, let (w, c) = differing.first, w.isAdjacentTo(c) else { return nil }
        let signed = signedDegrees(from: w, to: c)
        guard abs(abs(signed) - 45) < 0.5 else { return nil }
        return GestureHabitObservation(key: key, axis: .angle, sign: signed > 0 ? 1 : -1)
    }

    /// 오타 하나를 센다. 쌓여서 한 걸음 맞췄으면 그 일을 돌려준다.
    @discardableResult
    func record(_ observation: GestureHabitObservation) -> GestureHabitEvent? {
        model.observedCount += 1
        let counterKey = "\(observation.key)|\(observation.axis.rawValue)|\(observation.sign > 0 ? "+" : "-")"
        let count = (model.counters[counterKey] ?? 0) + 1
        guard count >= Self.stepThreshold else {
            model.counters[counterKey] = count
            return nil
        }
        model.counters[counterKey] = nil

        var adjustment = model.adjustment(for: observation.key)
        guard let (knob, target) = Self.nextStep(for: observation, from: adjustment) else { return nil }
        let before = adjustment.value(of: knob)
        adjustment.set(knob, to: target)
        let delta = adjustment.value(of: knob) - before
        guard delta != 0 else { return nil }
        model.keys[observation.key] = adjustment
        let event = GestureHabitEvent(id: model.nextEventId, date: now(), key: observation.key,
                                      knob: knob, delta: delta)
        model.nextEventId += 1
        model.events.append(event)
        if model.events.count > GestureHabitModel.maxEvents {
            model.events.removeFirst(model.events.count - GestureHabitModel.maxEvents)
        }
        return event
    }

    /// 어느 손잡이를 어디로 돌릴지. 상한에 닿아 더 못 돌리면 nil.
    static func nextStep(for observation: GestureHabitObservation,
                         from adjustment: GestureHabitAdjustment) -> (GestureHabitKnob, Double)? {
        func move(_ knob: GestureHabitKnob, by steps: Double) -> (GestureHabitKnob, Double)? {
            let current = adjustment.value(of: knob)
            let target = current + steps * knob.step
            guard knob.range.contains(target) else { return nil }
            return (knob, target)
        }
        switch observation.axis {
        case .angle:
            // 다시 그은 방향이 반시계 쪽이면 판정 각도를 키워야 한다 = 회전을 줄인다.
            return move(.angle, by: observation.sign > 0 ? -1 : 1)
        case .minLength:
            return move(.minLength, by: Double(observation.sign))
        case .strokes:
            let length = adjustment.lengthRatio
            let curve = adjustment.curveDeg
            if observation.sign > 0 {
                // 획이 더 생김 → 먼저 내려 둔 길이를 되돌리고, 다음은 휜 획을 더 합치고, 그다음 길이를 올린다.
                if length < 0 { return move(.length, by: 1) }
                if curve < GestureHabitKnob.curve.range.upperBound { return move(.curve, by: 1) }
                return move(.length, by: 1)
            } else {
                // 획이 모자람 → 먼저 넓혀 둔 휨을 되돌리고, 그다음 길이를 내린다.
                if curve > 0 { return move(.curve, by: -1) }
                return move(.length, by: -1)
            }
        }
    }

    /// 앱이 남긴 요청을 반영한다. 바뀐 것이 있으면 true.
    @discardableResult
    func apply(edits: [GestureHabitEditRequest]) -> Bool {
        var changed = false
        for request in edits.sorted(by: { $0.id < $1.id }) where request.id > model.appliedEditId {
            switch request.edit {
            case .resetAll:
                let applied = request.id
                model = GestureHabitModel()
                model.appliedEditId = applied
            case .revert(let eventId):
                if let index = model.events.firstIndex(where: { $0.id == eventId && !$0.reverted }) {
                    let event = model.events[index]
                    var adjustment = model.adjustment(for: event.key)
                    adjustment.set(event.knob, to: adjustment.value(of: event.knob) - event.delta)
                    model.keys[event.key] = adjustment.isZero ? nil : adjustment
                    model.events[index].reverted = true
                    // 되돌린 쪽으로 쌓이던 오타도 비운다 — 바로 다시 맞추지 않게.
                    model.counters = model.counters.filter { !$0.key.hasPrefix("\(event.key)|") }
                }
                model.appliedEditId = request.id
            }
            changed = true
        }
        return changed
    }

    /// 두 방향 사이 각도(도, 반시계 +, −180~180).
    static func signedDegrees(from a: GestureDirection, to b: GestureDirection) -> Double {
        let diff = angle(of: b) - angle(of: a)
        return (diff + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private static func angle(of direction: GestureDirection) -> Double {
        switch direction {
        case .right: return 0
        case .upRight: return 45
        case .up: return 90
        case .upLeft: return 135
        case .left: return 180
        case .downLeft: return 225
        case .down: return 270
        case .downRight: return 315
        }
    }
}

// MARK: - 지운 글 · 다시 친 글 짝짓기

/// 최근 자음 키 긋기가 문맥의 몇 번째 글자를 만들었는지 들고 있다가, 지우고 다시 친 글을 맞대어
/// 오타 쌍(틀린 긋기, 다시 그은 긋기)을 찾는다. 글자는 메모리에만 있고 저장하지 않는다.
final class GestureHabitTracker {
    /// 이만큼 넘게 지웠으면 고쳐 쓴 글로 보고 세지 않는다 (사용자 결정 1가: 띄어쓰기 포함 10글자).
    static let maxDeletedCharacters = 10
    static let maxRecords = 40

    private struct Record {
        let seq: Int
        let sample: GestureHabitSample
        /// 문맥(커서 앞 글)에서 이 긋기가 만든 글자의 자리. 다음 갱신 때 정해진다.
        var index: Int?
    }

    private struct Episode {
        let snapshot: [Character]
        /// 이 번호 이상인 기록 = 지운 뒤 다시 친 것.
        let startSeq: Int
        var awaitingPostDeleteRead = true
        var afterDelete: [Character] = []
        var prefixLength: Int?
        var deleted: [Character] = []
    }

    private var records: [Record] = []
    private var nextSeq = 0
    private var episode: Episode?

    func reset() {
        records.removeAll()
        episode = nil
    }

    /// 자음 키 긋기 · 탭 하나를 남긴다. 만든 글자의 자리는 다음 `tick` 에서 정한다.
    func note(_ sample: GestureHabitSample) {
        records.append(Record(seq: nextSeq, sample: sample, index: nil))
        nextSeq += 1
        if records.count > Self.maxRecords { records.removeFirst(records.count - Self.maxRecords) }
    }

    /// 지우기 직전에 부른다 (백스페이스 · 단어 지우기). 연달아 지우면 처음 것만 기준이 된다.
    func noteDeletion(before: String?) {
        if var current = episode, current.prefixLength == nil {
            current.awaitingPostDeleteRead = true
            episode = current
            return
        }
        // 빈 입력란은 문맥이 nil 로 온다 — 빈 글로 본다(시큐어 필드도 nil 이지만 기록이 자리를 못 얻어 짝이 안 생긴다).
        episode = Episode(snapshot: Array(before ?? ""), startSeq: nextSeq)
    }

    /// 문맥이 바뀐 뒤(다음 런루프 틱) 부른다. 오타 쌍이 끝나면 (틀린 것, 다시 친 것)을 돌려준다.
    /// - Parameter composerIdle: 조합 중인 글자가 없음 — 다시 친 글이 지운 글과 길이가 같을 때 끝났는지 본다.
    func tick(before: String?, composerIdle: Bool) -> (wrong: GestureHabitSample, correct: GestureHabitSample)? {
        let chars = Array(before ?? "")
        resolvePendingRecords(in: chars)

        guard var current = episode else { return nil }
        if current.prefixLength == nil {
            if current.awaitingPostDeleteRead {
                current.awaitingPostDeleteRead = false
                current.afterDelete = chars
                episode = current
                return nil
            }
            guard chars != current.afterDelete else { return nil }
            // 지우기를 멈추고 다시 치기 시작했다 — 지운 글을 정한다.
            let p = Self.commonPrefixLength(current.snapshot, current.afterDelete)
            let deleted = Array(current.snapshot[p...])
            guard !deleted.isEmpty, deleted.count <= Self.maxDeletedCharacters else { episode = nil; return nil }
            current.prefixLength = p
            current.deleted = deleted
            episode = current
        }

        guard let p = current.prefixLength else { return nil }
        guard chars.count >= p, Array(chars[..<p]) == Array(current.snapshot[..<p]) else { episode = nil; return nil }
        let region = Array(chars[p...])
        let deleted = current.deleted
        let finished = region.count > deleted.count || (region.count == deleted.count && composerIdle)
        guard finished else { return nil }
        episode = nil
        return pair(deleted: deleted, retyped: Array(region.prefix(deleted.count)),
                    offset: p, startSeq: current.startSeq)
    }

    // MARK: 내부

    private func resolvePendingRecords(in chars: [Character]) {
        guard records.contains(where: { $0.index == nil }) else { return }
        records = records.compactMap { record in
            guard record.index == nil else { return record }
            guard let last = chars.last, Self.character(last, matches: record.sample) else { return nil }
            var resolved = record
            resolved.index = chars.count - 1
            return resolved
        }
    }

    private func pair(deleted: [Character], retyped: [Character], offset: Int,
                      startSeq: Int) -> (wrong: GestureHabitSample, correct: GestureHabitSample)? {
        let differing = zip(deleted, retyped).enumerated().filter { $0.element.0 != $0.element.1 }
        guard differing.count == 1, let diff = differing.first else { return nil }
        let (d, r) = diff.element
        guard Self.isVowelOnlyChange(from: d, to: r) else { return nil }
        let index = offset + diff.offset
        guard let wrong = records.last(where: { $0.seq < startSeq && $0.index == index }),
              let correct = records.last(where: { $0.seq >= startSeq && $0.index == index }),
              Self.character(d, matches: wrong.sample),
              Self.character(r, matches: correct.sample) else { return nil }
        return (wrong.sample, correct.sample)
    }

    /// 같은 자음, 같은 받침, 모음만 다름 — 또는 낱자음 ↔ 받침 없는 글자(탭 ↔ 긋기).
    static func isVowelOnlyChange(from d: Character, to r: Character) -> Bool {
        let ds = HangulConstants.decomposeSyllable(d)
        let rs = HangulConstants.decomposeSyllable(r)
        switch (ds, rs) {
        case let (a?, b?):
            return a.0 == b.0 && a.2 == b.2 && a.1 != b.1
        case let (nil, b?):
            return b.2 == Jongseong.none && d == b.0.compatibilityCharacter
        case let (a?, nil):
            return a.2 == Jongseong.none && r == a.0.compatibilityCharacter
        default:
            return false
        }
    }

    /// 이 글자가 그 긋기로 만들어질 수 있는 글자인지 (받침은 뒤에 붙을 수 있어 보지 않는다).
    static func character(_ char: Character, matches sample: GestureHabitSample) -> Bool {
        if let vowel = sample.vowel {
            guard let (cho, jung, _) = HangulConstants.decomposeSyllable(char) else { return false }
            return cho == sample.key && jung == vowel
        }
        return char == sample.key.compatibilityCharacter
    }

    static func commonPrefixLength(_ a: [Character], _ b: [Character]) -> Int {
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        return i
    }
}

// MARK: - 저장

/// 맞춘 값 파일. 학습 데이터(`PredictionStore`)와 같은 자리 규칙: App Group 우선, 못 쓰면 키보드 로컬.
enum GestureHabitStore {
    static let fileName = "gesture-habit.json"
    static let editsFileName = "gesture-habit-edits.json"

    private static let ioQueue = DispatchQueue(label: "MoaPlus.GestureHabitStore", qos: .utility)

    static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.appGroupId)?
            .appendingPathComponent(fileName)
    }

    static var localFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GestureHabit", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static var editsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.appGroupId)?
            .appendingPathComponent(editsFileName)
    }

    /// 저장된 값. 둘 다 있으면 오타를 더 많이 센 쪽.
    static func load() -> GestureHabitModel {
        let models = [sharedFileURL, localFileURL].compactMap { url -> GestureHabitModel? in
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(GestureHabitModel.self, from: data)
        }
        return models.max(by: { $0.observedCount < $1.observedCount }) ?? GestureHabitModel()
    }

    /// 앱 화면용 — App Group 파일만 읽는다(키보드 로컬 파일은 앱이 못 본다).
    static func loadShared() -> GestureHabitModel? {
        guard let url = sharedFileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GestureHabitModel.self, from: data)
    }

    static func save(_ model: GestureHabitModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        ioQueue.async {
            if let shared = sharedFileURL, write(data, to: shared) { return }
            if let local = localFileURL { _ = write(data, to: local) }
        }
    }

    static func loadEdits() -> [GestureHabitEditRequest] {
        guard let url = editsFileURL,
              let data = try? Data(contentsOf: url),
              let edits = try? JSONDecoder().decode([GestureHabitEditRequest].self, from: data) else { return [] }
        return edits
    }

    /// 앱이 요청 하나를 남긴다. 번호 = 쌓인 요청 · 키보드가 반영한 번호 중 큰 것 + 1.
    @discardableResult
    static func appendEdit(_ edit: GestureHabitEdit) -> Bool {
        guard let url = editsFileURL else { return false }
        let applied = loadShared()?.appliedEditId ?? 0
        var edits = loadEdits()
        let nextId = max(edits.map(\.id).max() ?? 0, applied) + 1
        edits.removeAll { $0.id <= applied }
        edits.append(GestureHabitEditRequest(id: nextId, edit: edit))
        guard let data = try? JSONEncoder().encode(edits) else { return false }
        return write(data, to: url)
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
