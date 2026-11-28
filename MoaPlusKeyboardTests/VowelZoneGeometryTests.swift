import XCTest
import CoreGraphics
@testable import MoaPlusKeyboard

/// 누를 때 ㅣ · ㅜ · ㅓ 구역 보기 (새모아 개선 방안 14번). 그리는 구역이 분석기가 실제로 가르는 구역과
/// 같아야 한다 — 그린 구역의 가운데 방향으로 그으면 분석기도 그 모음 방향이라고 판정해야 한다.
final class VowelZoneGeometryTests: XCTestCase {

    private func direction(of zone: VowelZoneGeometry.Zone, settings: GestureSettings, column: Int,
                           habit: Double) -> GestureDirection? {
        let mid = (zone.start + zone.end) / 2 * .pi / 180
        // 화면 좌표: 위가 −y
        let vector = CGVector(dx: cos(mid) * 80, dy: -sin(mid) * 80)
        var sectors = settings.swipeProfile.sectors
        if column > 0 {
            sectors = sectors.applyingDiagonalDeltas(
                iDelta: settings.verticalIWidthDelta(forColumn: column),
                euDelta: settings.horizontalEuWidthDelta(forColumn: column))
        }
        return GestureDirection.from(
            vector: vector, sectors: sectors,
            rotationOffset: settings.recognizerRotationOffset(forColumn: column) + habit,
            threshold: 10, fourWay: settings.swipeProfile.fourWayMode)
    }

    func test_defaultProfile_showsEoUAndBothI_matchingRecognizer() {
        let settings = GestureSettings()
        for column in 1...5 {
            for habit in [0.0, 8.0, -6.0] {
                let zones = VowelZoneGeometry.zones(settings: settings,
                                                    info: VowelZoneInfo(columnId: column, habitRotation: habit))
                XCTAssertEqual(zones.map(\.vowel).sorted(), ["ㅓ", "ㅜ", "ㅣ", "ㅣ"], "열 \(column)")
                for zone in zones {
                    let d = direction(of: zone, settings: settings, column: column, habit: habit)
                    switch zone.vowel {
                    case "ㅓ": XCTAssertEqual(d, .left, "열 \(column) 버릇 \(habit)")
                    case "ㅜ": XCTAssertEqual(d, .down, "열 \(column) 버릇 \(habit)")
                    default: XCTAssertTrue(d == .upRight || d == .upLeft, "열 \(column) 버릇 \(habit) → \(String(describing: d))")
                    }
                }
            }
        }
    }

    /// 6방향 (↖ㅗ ↘ㅜ, 새모아 2026-11-28): 프리셋 회전 15° 가 구역 그림에도 들어가야 한다 — ㅜ 구역 가운데 ≈ 300°.
    func test_sixWayRightTilted_zonesFollowPresetRotation() {
        var settings = GestureSettings()
        settings.swipeProfile = settings.swipeProfile.applyingPreset(.sixWayRightTilted)
        for column in 1...5 {
            let zones = VowelZoneGeometry.zones(settings: settings,
                                                info: VowelZoneInfo(columnId: column, habitRotation: 0))
            XCTAssertEqual(zones.map(\.vowel).sorted(), ["ㅓ", "ㅜ", "ㅣ"], "열 \(column)")
            for zone in zones {
                let d = direction(of: zone, settings: settings, column: column, habit: 0)
                switch zone.vowel {
                case "ㅓ": XCTAssertEqual(d, .left, "열 \(column)")
                case "ㅜ":
                    XCTAssertEqual(d, .down, "열 \(column)")
                    let mid = (zone.start + zone.end) / 2
                    let rot = settings.recognizerRotationOffset(forColumn: column)
                    XCTAssertEqual(mid - rot, 285, accuracy: 0.001, "열 \(column) — 6방향 ↓ 구역 가운데 285° + 회전")
                default: XCTAssertEqual(d, .upRight, "열 \(column)")
                }
            }
        }
    }

    func test_fourWay_showsOnlyEoAndU() {
        var settings = GestureSettings()
        settings.swipeProfile.fourWayMode = true
        let zones = VowelZoneGeometry.zones(settings: settings, info: VowelZoneInfo(columnId: 3, habitRotation: 0))
        XCTAssertEqual(zones.map(\.vowel), ["ㅓ", "ㅜ"])
        XCTAssertEqual(zones[0].end - zones[0].start, 90, accuracy: 0.001)
    }

    func test_diagonalNotMappedToI_isNotShownAsI() {
        var settings = GestureSettings()
        settings.swipeProfile.upLeftMapping = .disabled
        let zones = VowelZoneGeometry.zones(settings: settings, info: VowelZoneInfo(columnId: 3, habitRotation: 0))
        XCTAssertEqual(zones.filter { $0.vowel == "ㅣ" }.count, 1)
    }

    func test_radius_scalesWithKeyWidth_andClampsToRange() {
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 60), 120, accuracy: 0.001)   // 기본 2칸
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 60, scale: 1.5), 90, accuracy: 0.001)
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 60, scale: 0.2), 60, accuracy: 0.001)
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 60, scale: 9), 180, accuracy: 0.001)
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 60, scale: .nan), 120, accuracy: 0.001)
        XCTAssertEqual(VowelZoneGeometry.radius(keyWidth: 10, scale: 1), 30, accuracy: 0.001)  // 아주 좁은 키 하한
    }
}
