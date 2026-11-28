import XCTest
import CoreGraphics
@testable import MoaPlusKeyboard

/// 6방향 60° 균등 프리셋 (사용자 메일 제안) + 프리셋 피커가 섹터를 실제로 적용하는지.
///
/// 분류기는 바꾸지 않고 섹터 데이터(비대칭 좌우 폭)만으로 60° 타일링을 만든다.
/// 이 가드가 깨지면 `GestureDirection.from` 의 STEP1/STEP2 우선순위가 바뀐 것이다.
final class SixWaySectorTests: XCTestCase {

    // MARK: - 전수 스윕

    /// 0.25°, 1.25°, … 359.25° — 6방향 경계(정수 각도)와 8방향 경계(x.5°)를 모두 피해
    /// 섹터마다 정확히 60개(6방향) / 45개(8방향)가 나와야 한다.
    private func sweep(_ sectors: [DirectionSector], fillGap: Bool = true) -> [GestureDirection: Int] {
        var counts: [GestureDirection: Int] = [:]
        for k in 0..<360 {
            let deg = Double(k) + 0.25
            let rad = deg * .pi / 180
            // iOS 좌표계: y 가 아래로 증가 → 위쪽 성분은 음수.
            let v = CGVector(dx: cos(rad) * 100, dy: -sin(rad) * 100)
            guard let d = GestureDirection.from(vector: v, sectors: sectors, rotationOffset: 0,
                                                threshold: 1, fillGap: fillGap) else { continue }
            counts[d, default: 0] += 1
        }
        return counts
    }

    func test_sixWayRight_tilesSixSixtyDegreeSectors() {
        for fillGap in [true, false] {
            let c = sweep(DirectionSector.sixWayRightSectors, fillGap: fillGap)
            for d in [GestureDirection.right, .upRight, .up, .left, .downLeft, .down] {
                XCTAssertEqual(c[d], 60, "\(d) 는 60° (fillGap=\(fillGap))")
            }
            XCTAssertNil(c[.upLeft], "↖ 는 꺼짐")
            XCTAssertNil(c[.downRight], "↘ 는 꺼짐")
        }
    }

    func test_sixWayLeft_tilesSixSixtyDegreeSectors() {
        for fillGap in [true, false] {
            let c = sweep(DirectionSector.sixWayLeftSectors, fillGap: fillGap)
            for d in [GestureDirection.right, .upLeft, .up, .left, .downRight, .down] {
                XCTAssertEqual(c[d], 60, "\(d) 는 60° (fillGap=\(fillGap))")
            }
            XCTAssertNil(c[.upRight], "↗ 는 꺼짐")
            XCTAssertNil(c[.downLeft], "↙ 는 꺼짐")
        }
    }

    /// 열별 ㅣ/ㅡ 보정은 ↖(3)·↘(7) 에도 폭을 더한다. 끈 대각선이 되살아나지 않아야 한다.
    func test_sixWayRight_columnDiagonalDeltasDoNotReviveDisabledDiagonals() {
        let widened = DirectionSector.sixWayRightSectors.applyingDiagonalDeltas(iDelta: 10, euDelta: 10)
        let c = sweep(widened)
        XCTAssertNil(c[.upLeft])
        XCTAssertNil(c[.downRight])
        // 그림(구역 보기 · 앱 원그림)도 같은 배열을 쓴다 — 끈 대각선은 폭 0 그대로, 산 대각선만 넓어짐.
        XCTAssertEqual(widened[3].leftHalfWidth + widened[3].rightHalfWidth, 0)
        XCTAssertEqual(widened[7].leftHalfWidth + widened[7].rightHalfWidth, 0)
        XCTAssertEqual(widened[1].leftHalfWidth, 40)
        XCTAssertEqual(widened[5].rightHalfWidth, 40)
    }

    /// 기본 8방향 배치는 바뀌지 않는다 (회귀 가드).
    func test_defaultSectors_stillEightFortyFive() {
        let c = sweep(DirectionSector.defaultSectors)
        for d in GestureDirection.allCases {
            XCTAssertEqual(c[d], 45, "\(d)")
        }
    }

    // MARK: - 프리셋 적용

    func test_applyingPreset_writesSectorsAndKeepsOtherFields() {
        var p = SwipeProfile.bothHands
        p.swipeLength = .long
        p.upLeftMapping = .vowelO   // 끈 쪽 대각선 — 그대로 남아야 한다
        p.axisRotation = 5
        p.gapFillNearest = false

        let six = p.applyingPreset(.sixWayRight)
        XCTAssertEqual(six.mode, .sixWayRight)
        XCTAssertEqual(six.sectors, DirectionSector.sixWayRightSectors)
        XCTAssertEqual(six.swipeLength, .long)
        XCTAssertEqual(six.upLeftMapping, .vowelO)
        XCTAssertEqual(six.axisRotation, 5)
        XCTAssertFalse(six.gapFillNearest)
    }

    /// v2.2.2 까지 오른손/왼손 프리셋은 라벨만 바꾸고 섹터는 기본값 그대로였다.
    func test_applyingPreset_rightAndLeftActuallyChangeSectors() {
        XCTAssertEqual(SwipeProfile.bothHands.applyingPreset(.right).sectors, SwipeProfile.rightHand.sectors)
        XCTAssertEqual(SwipeProfile.bothHands.applyingPreset(.left).sectors, SwipeProfile.leftHand.sectors)
        XCTAssertNotEqual(SwipeProfile.rightHand.sectors, DirectionSector.defaultSectors)
    }

    func test_applyingPreset_bothRestoresDefault_customKeepsCurrent() {
        let six = SwipeProfile.bothHands.applyingPreset(.sixWayLeft)
        XCTAssertEqual(six.applyingPreset(.both).sectors, DirectionSector.defaultSectors)
        XCTAssertEqual(six.applyingPreset(.custom).sectors, DirectionSector.sixWayLeftSectors)
        XCTAssertEqual(six.applyingPreset(.custom).mode, .custom)
    }

    /// 대각선을 ㅗ/ㅜ 로 바꿔 둔 사용자(메일 제보 스크린샷)도 6방향을 고르면 이름대로
    /// 살아 있는 대각선이 ㅣ/ㅡ 가 되어야 한다.
    func test_applyingPreset_sixWayForcesLiveDiagonalPairToIEu() {
        var p = SwipeProfile.bothHands
        p.upLeftMapping = .normalizeUp
        p.upRightMapping = .vowelA
        p.downLeftMapping = .vowelU
        p.downRightMapping = .normalizeDown

        let right = p.applyingPreset(.sixWayRight)
        XCTAssertEqual(right.upRightMapping, .vowelI)
        XCTAssertEqual(right.downLeftMapping, .vowelEu)
        XCTAssertEqual(right.upLeftMapping, .normalizeUp, "끈 쪽은 유지")

        let left = p.applyingPreset(.sixWayLeft)
        XCTAssertEqual(left.upLeftMapping, .vowelI)
        XCTAssertEqual(left.downRightMapping, .vowelEu)
        XCTAssertEqual(left.upRightMapping, .vowelA, "끈 쪽은 유지")
    }

    func test_sixWayMode_roundTripsThroughJSON() throws {
        let p = SwipeProfile.bothHands.applyingPreset(.sixWayRight)
        let decoded = try JSONDecoder().decode(SwipeProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    // MARK: - E2E (분석기 + 리졸버)

    /// 꼭짓점 사이를 4pt 간격으로 채워 분석기에 넣고 모음을 돌려준다.
    private func vowel(_ mode: SwipeMode, strokes: [(dx: CGFloat, dy: CGFloat)],
                       from base: SwipeProfile = .bothHands) -> Jungseong? {
        var settings = GestureSettings.default
        settings.swipeProfile = base.applyingPreset(mode)
        let analyzer = GestureAnalyzer(settings: settings, columnId: 2)
        var p = CGPoint(x: 200, y: 200)
        analyzer.addPoint(p)
        for s in strokes {
            let steps = max(1, Int((hypot(s.dx, s.dy) / 4).rounded()))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                analyzer.addPoint(CGPoint(x: p.x + s.dx * t, y: p.y + s.dy * t))
            }
            p = CGPoint(x: p.x + s.dx, y: p.y + s.dy)
        }
        let detail = analyzer.finalizeGestureDetailed()
        let resolver = VowelResolver()
        resolver.swipeProfile = settings.swipeProfile
        return resolver.resolve(directions: detail.directions,
                                firstStrokeCardinal: detail.firstStrokeCardinal).vowel
    }

    /// 각도(수학 좌표) → 획 벡터.
    private func stroke(_ deg: Double, _ len: CGFloat = 60) -> (dx: CGFloat, dy: CGFloat) {
        let r = deg * .pi / 180
        return (len * CGFloat(cos(r)), -len * CGFloat(sin(r)))
    }

    func test_e2e_sixWayRight_widerIAndO() {
        // 70°: ↗(ㅣ) 범위(15~75°) 안쪽.
        XCTAssertEqual(vowel(.sixWayRight, strokes: [stroke(70)]), .ㅣ)
        // 128°: 8방향이면 ↖(ㅣ) 이지만 6방향 오른손형에서는 ↑(ㅗ) 범위(75~135°).
        XCTAssertEqual(vowel(.sixWayRight, strokes: [stroke(128)]), .ㅗ)
        // 320°: 8방향이면 ↘(ㅡ) 이지만 6방향 오른손형에서는 →(ㅏ) 범위(315~15°).
        XCTAssertEqual(vowel(.sixWayRight, strokes: [stroke(320)]), .ㅏ)
    }

    func test_e2e_sixWayLeft_mirror() {
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(110)]), .ㅣ)
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(52)]), .ㅗ)
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(290)]), .ㅡ)
    }

    /// 제보자 요청: "6방향으로 줄이더라도 복모음 조합은 유지".
    func test_e2e_compoundVowelsSurviveBothSixWayPresets() {
        for mode in [SwipeMode.sixWayRight, .sixWayLeft] {
            XCTAssertEqual(vowel(mode, strokes: [stroke(90, 40), stroke(0, 40)]), .ㅘ, "↑→ \(mode)")
            XCTAssertEqual(vowel(mode, strokes: [stroke(270, 40), stroke(180, 40)]), .ㅝ, "↓← \(mode)")
            XCTAssertEqual(vowel(mode, strokes: [stroke(0, 40), stroke(180, 40)]), .ㅐ, "→← \(mode)")
            XCTAssertEqual(vowel(mode, strokes: [stroke(180, 40), stroke(0, 40)]), .ㅔ, "←→ \(mode)")
            XCTAssertEqual(vowel(mode, strokes: [stroke(90, 40), stroke(270, 40)]), .ㅚ, "↑↓ \(mode)")
        }
    }

    /// 제보자 설정(↖ㅗ ↘ㅜ)에서 왼손형을 골라도 ㅣ·ㅡ·ㅢ 가 살아 있어야 한다.
    func test_e2e_sixWayLeft_fromReporterMappings() {
        var base = SwipeProfile.bothHands
        base.upLeftMapping = .normalizeUp
        base.downRightMapping = .normalizeDown
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(135)], from: base), .ㅣ)
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(315)], from: base), .ㅡ)
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(315, 40), stroke(135, 40)], from: base), .ㅢ)
    }

    /// ㅢ 는 남은 대각선 쌍의 왕복으로 들어간다 — 오른손형 ↙↗, 왼손형 ↘↖.
    func test_e2e_euiThroughRemainingDiagonalPair() {
        XCTAssertEqual(vowel(.sixWayRight, strokes: [stroke(225, 40), stroke(45, 40)]), .ㅢ)
        XCTAssertEqual(vowel(.sixWayLeft, strokes: [stroke(315, 40), stroke(135, 40)]), .ㅢ)
    }

    // MARK: - 6방향 (↖ㅗ ↘ㅜ) — 새모아 2026-11-28

    /// 수학 각도(도) → 기대 모음. ㅏ 330~30 · ㅣ 30~90 · ㅗ 90~150 · ㅓ 150~210 · ㅡ 210~270 · ㅜ 270~330.
    private func tiltedExpected(_ deg: Double) -> GestureDirection {
        switch deg {
        case 30..<90: return .upRight
        case 90..<150: return .up
        case 150..<210: return .left
        case 210..<270: return .downLeft
        case 270..<330: return .down
        default: return .right
        }
    }

    /// 1° 간격 전수: 구역이 60° 씩, 15° 돌아간 자리에 있어야 한다. 회전은 `effectiveAxisRotation` 한 곳에서 온다.
    func test_sixWayRightTilted_tilesSixSectorsRotatedFifteen() {
        let profile = SwipeProfile.bothHands.applyingPreset(.sixWayRightTilted)
        XCTAssertEqual(profile.sectors, DirectionSector.sixWayRightSectors)
        XCTAssertEqual(profile.axisRotation, 0, "저장값은 사용자 몫만")
        XCTAssertEqual(profile.effectiveAxisRotation, 15)
        for fillGap in [true, false] {
            for k in 0..<360 {
                let deg = Double(k) + 0.25
                let rad = deg * .pi / 180
                let v = CGVector(dx: cos(rad) * 100, dy: -sin(rad) * 100)
                let d = GestureDirection.from(vector: v, sectors: profile.sectors,
                                              rotationOffset: profile.effectiveAxisRotation,
                                              threshold: 1, fillGap: fillGap)
                XCTAssertEqual(d, tiltedExpected(deg), "\(deg)° (fillGap=\(fillGap))")
            }
        }
    }

    func test_sixWayRightTilted_rotationRules() {
        var p = SwipeProfile.bothHands
        p.axisRotation = 3
        let tilted = p.applyingPreset(.sixWayRightTilted)
        XCTAssertEqual(tilted.effectiveAxisRotation, 18, "사용자 회전 위에 더함")
        XCTAssertEqual(tilted.upRightMapping, .vowelI)
        XCTAssertEqual(tilted.downLeftMapping, .vowelEu)

        var four = tilted
        four.fourWayMode = true
        XCTAssertEqual(four.effectiveAxisRotation, 0, "4방향 전용이면 회전 없음")

        // 다른 프리셋으로 가면 프리셋 회전은 사라지고 사용자 몫만 남는다.
        XCTAssertEqual(tilted.applyingPreset(.both).effectiveAxisRotation, 3)
        XCTAssertEqual(tilted.applyingPreset(.sixWayRight).effectiveAxisRotation, 3)

        // 직접 설정으로 가면 프리셋 회전을 저장값으로 옮겨 구역이 그대로다.
        let custom = tilted.applyingPreset(.custom)
        XCTAssertEqual(custom.mode, .custom)
        XCTAssertEqual(custom.axisRotation, 18)
        XCTAssertEqual(custom.effectiveAxisRotation, 18)
        XCTAssertEqual(custom.sectors, DirectionSector.sixWayRightSectors)
        // 이미 직접 설정이면 두 번 더하지 않는다.
        XCTAssertEqual(custom.applyingPreset(.custom).axisRotation, 18)
    }

    func test_sixWayRightTilted_roundTripsThroughJSON() throws {
        let p = SwipeProfile.bothHands.applyingPreset(.sixWayRightTilted)
        let decoded = try JSONDecoder().decode(SwipeProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.effectiveAxisRotation, 15)
    }

    /// 분석기 + 리졸버: 한 획 여섯 방향과 겹모음(지금 규칙 그대로 — ㅘ ↖→ · ㅝ ↘← · ㅚ ↖↘ · ㅟ ↘↖ · ㅛ ↖↘↖ · ㅠ ↘↖↘ · ㅢ ↙↗).
    func test_e2e_sixWayRightTilted_singleAndCompound() {
        let m = SwipeMode.sixWayRightTilted
        XCTAssertEqual(vowel(m, strokes: [stroke(0)]), .ㅏ)
        XCTAssertEqual(vowel(m, strokes: [stroke(60)]), .ㅣ)
        XCTAssertEqual(vowel(m, strokes: [stroke(120)]), .ㅗ, "↖ = ㅗ")
        XCTAssertEqual(vowel(m, strokes: [stroke(180)]), .ㅓ)
        XCTAssertEqual(vowel(m, strokes: [stroke(240)]), .ㅡ)
        XCTAssertEqual(vowel(m, strokes: [stroke(300)]), .ㅜ, "↘ = ㅜ")

        XCTAssertEqual(vowel(m, strokes: [stroke(120, 40), stroke(0, 40)]), .ㅘ, "↖→")
        XCTAssertEqual(vowel(m, strokes: [stroke(300, 40), stroke(180, 40)]), .ㅝ, "↘←")
        XCTAssertEqual(vowel(m, strokes: [stroke(120, 40), stroke(300, 40)]), .ㅚ, "↖↘")
        XCTAssertEqual(vowel(m, strokes: [stroke(300, 40), stroke(120, 40)]), .ㅟ, "↘↖")
        XCTAssertEqual(vowel(m, strokes: [stroke(120, 40), stroke(300, 40), stroke(120, 40)]), .ㅛ, "↖↘↖")
        XCTAssertEqual(vowel(m, strokes: [stroke(300, 40), stroke(120, 40), stroke(300, 40)]), .ㅠ, "↘↖↘")
        XCTAssertEqual(vowel(m, strokes: [stroke(0, 40), stroke(180, 40)]), .ㅐ, "→←")
        XCTAssertEqual(vowel(m, strokes: [stroke(180, 40), stroke(0, 40)]), .ㅔ, "←→")
        XCTAssertEqual(vowel(m, strokes: [stroke(240, 40), stroke(60, 40)]), .ㅢ, "↙↗")
    }

    // MARK: - 직접 설정 기억하기 — 새모아 2026-11-28 사용자 「나」

    private var myCustomSectors: [DirectionSector] {
        var s = DirectionSector.defaultSectors
        s[1].leftHalfWidth = 33; s[1].rightHalfWidth = 12   // ↗ 비대칭
        s[6].leftHalfWidth = 30                              // ↓ 넓힘
        return s
    }

    /// 직접 설정 → 프리셋 → 목록에서 「직접 설정」 = 예전 각도로 되살림 (프리셋 회전은 옮기지 않음).
    func test_customSectors_restoredAfterPresetRoundTrip() {
        var p = SwipeProfile.bothHands
        p.mode = .custom
        p.sectors = myCustomSectors
        p.axisRotation = 4

        let tilted = p.applyingPreset(.sixWayRightTilted)
        XCTAssertEqual(tilted.sectors, DirectionSector.sixWayRightSectors)
        XCTAssertEqual(tilted.savedCustomSectors, myCustomSectors, "떠날 때 보관")
        // 프리셋끼리 오가도 보관은 남는다.
        let other = tilted.applyingPreset(.both).applyingPreset(.sixWayLeft)
        XCTAssertEqual(other.savedCustomSectors, myCustomSectors)

        let back = other.applyingPreset(.custom)
        XCTAssertEqual(back.mode, .custom)
        XCTAssertEqual(back.sectors, myCustomSectors, "예전 직접 설정 각도로")
        XCTAssertEqual(back.axisRotation, 4, "프리셋 회전을 더하지 않음")
        XCTAssertNil(back.savedCustomSectors)
        XCTAssertEqual(tilted.applyingPreset(.custom).axisRotation, 4)
    }

    /// 프리셋 상태에서 편집기로 손대면 그 각도가 새 직접 설정 — 보관한 예전 각도는 버린다.
    func test_editingPreset_becomesNewCustom_andDropsSaved() {
        var p = SwipeProfile.bothHands
        p.mode = .custom
        p.sectors = myCustomSectors
        var tilted = p.applyingPreset(.sixWayRightTilted)
        tilted.sectors[0].leftHalfWidth = 20   // 편집기에서 → 폭을 만짐
        let edited = tilted.convertingToCustom()
        XCTAssertEqual(edited.mode, .custom)
        XCTAssertEqual(edited.sectors[0].leftHalfWidth, 20)
        XCTAssertEqual(edited.axisRotation, 15, "프리셋 회전을 저장값으로")
        XCTAssertNil(edited.savedCustomSectors)
        // 이미 직접 설정이면 아무것도 바꾸지 않는다.
        XCTAssertEqual(edited.convertingToCustom(), edited)
        XCTAssertEqual(edited.applyingPreset(.custom), edited)
    }

    func test_savedCustomSectors_roundTripsAndOldJSONDecodes() throws {
        var p = SwipeProfile.bothHands
        p.mode = .custom
        p.sectors = myCustomSectors
        let preset = p.applyingPreset(.sixWayRight)
        let decoded = try JSONDecoder().decode(SwipeProfile.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.savedCustomSectors, myCustomSectors)

        // 이 칸이 없던 예전 판 파일
        let old = #"{"mode":"custom","swipeLength":"short","axisRotation":2}"#.data(using: .utf8)!
        let oldDecoded = try JSONDecoder().decode(SwipeProfile.self, from: old)
        XCTAssertNil(oldDecoded.savedCustomSectors)
        XCTAssertEqual(oldDecoded.axisRotation, 2)
    }
}
