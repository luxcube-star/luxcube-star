import SwiftUI

// MARK: - 누를 때 ㅣ · ㅜ · ㅓ 구역 보기 (새모아 개선 방안 14번, 2026-11-27 사용자 「구현해」)
//
// 자음 키를 누르는 동안 누른 자리를 가운데로 ㅣ · ㅜ · ㅓ 세 구역만 반투명 부채꼴로 그린다.
// 셋이 헷갈려 오타가 난다는 사용자 제보에서 나왔다(2026-11-13 정함 — 기본 끔 · 원은 키 두 개 폭쯤 ·
// 손 떼면 사라짐 · 모음 키 · 영문 · 숫자 키 제외 · 4방향 전용 모드는 ㅜ · ㅓ 만).
// 구역은 분석기와 **같은 식**으로 만든다 — 방향 설정 · 전체 회전 · 세로 줄 보정 · 그 줄의 ㅣ 폭 보정 ·
// 그 키의 버릇 각도(`GestureAnalyzer.effectiveSectors` · `effectiveRotationOffset`). 앱의
// `DirectionPieChart.keySlices` 와도 같은 식이다 — 한쪽을 바꾸면 같이 바꿀 것.
// 누름 시작은 조기 터치 경로(`EarlyTouch.swift`)로 오므로 아래쪽 줄도 바로 뜬다.

/// 누른 자음 키의 구역을 그릴 재료. `KeyboardViewModel.gestureStarted` 가 설정이 켜져 있고
/// 한글 자음 키일 때만 채운다.
struct VowelZoneInfo: Equatable {
    var columnId: Int
    var habitRotation: Double
}

enum VowelZoneGeometry {
    struct Zone: Equatable {
        /// 수학 각도(0° = 오른쪽, 반시계).
        var start: Double
        var end: Double
        var vowel: String
    }

    /// 보여 줄 모음. ㅣ 는 ↗ · ↖ 가운데 ㅣ 로 매핑된 대각선만.
    static func zones(settings: GestureSettings, info: VowelZoneInfo) -> [Zone] {
        let profile = settings.swipeProfile
        let rotation = settings.recognizerRotationOffset(forColumn: info.columnId) + info.habitRotation
        if profile.fourWayMode {
            // 4방향 전용: 90° 네 칸(← = ㅓ, ↓ = ㅜ). ㅣ 는 대각선이 없어 안 그린다.
            return [
                Zone(start: 180 - 45 + rotation, end: 180 + 45 + rotation, vowel: "ㅓ"),
                Zone(start: 270 - 45 + rotation, end: 270 + 45 + rotation, vowel: "ㅜ"),
            ]
        }
        var sectors = profile.sectors
        if info.columnId > 0 {
            sectors = sectors.applyingDiagonalDeltas(
                iDelta: settings.verticalIWidthDelta(forColumn: info.columnId),
                euDelta: settings.horizontalEuWidthDelta(forColumn: info.columnId))
        }
        // DirectionSector 순서: → ↗ ↑ ↖ ← ↙ ↓ ↘
        var wanted: [(index: Int, vowel: String)] = [(4, "ㅓ"), (6, "ㅜ")]
        if profile.upRightMapping == .vowelI { wanted.append((1, "ㅣ")) }
        if profile.upLeftMapping == .vowelI { wanted.append((3, "ㅣ")) }
        return wanted.compactMap { item in
            guard item.index < sectors.count else { return nil }
            let s = sectors[item.index]
            let start = s.centerAngle - s.rightHalfWidth + rotation
            let end = s.centerAngle + s.leftHalfWidth + rotation
            guard end - start > 0.5 else { return nil }   // 6방향 프리셋에서 끈 대각선(폭 0)
            return Zone(start: start, end: end, vowel: item.vowel)
        }
    }

    /// 부채꼴 반지름 = 키 한 칸 폭(원 지름 = 키 두 개 폭).
    static func radius(keyWidth: CGFloat) -> CGFloat { max(keyWidth, 30) }
}

struct VowelZoneOverlayView: View {
    let center: CGPoint
    let zones: [VowelZoneGeometry.Zone]
    let radius: CGFloat

    /// 앱 긋기 테스트 원그림(`DirectionPieChart.vowelColors`)과 같은 색.
    private static let colors: [String: Color] = [
        "ㅓ": Color(red: 1.0, green: 0.75, blue: 0.75),
        "ㅜ": Color(red: 0.70, green: 0.92, blue: 0.78),
        "ㅣ": Color(red: 0.72, green: 0.92, blue: 0.98),
    ]

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for zone in zones {
                    let color = Self.colors[zone.vowel] ?? .gray
                    var path = Path()
                    path.move(to: center)
                    let steps = 24
                    for step in 0...steps {
                        let deg = zone.start + (zone.end - zone.start) * Double(step) / Double(steps)
                        let rad = deg * .pi / 180
                        // 수학 각도 → 화면: y 를 뒤집는다.
                        path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(rad)),
                                                 y: center.y - radius * CGFloat(sin(rad))))
                    }
                    path.closeSubpath()
                    context.fill(path, with: .color(color.opacity(0.45)))
                    context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1)
                }
            }
            ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                let mid = (zone.start + zone.end) / 2 * .pi / 180
                Text(zone.vowel)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.black.opacity(0.75))
                    .position(x: center.x + radius * 0.68 * CGFloat(cos(mid)),
                              y: center.y - radius * 0.68 * CGFloat(sin(mid)))
            }
        }
        .allowsHitTesting(false)
    }
}
