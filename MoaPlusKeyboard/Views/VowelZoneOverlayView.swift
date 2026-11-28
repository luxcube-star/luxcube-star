import SwiftUI

// MARK: - 누를 때 ㅣ · ㅜ · ㅓ 구역 보기 (새모아 개선 방안 14번, 2026-11-27 사용자 「구현해」)
//
// 자음 키를 누르는 동안 누른 자리를 가운데로 ㅣ · ㅜ · ㅓ 세 구역만 반투명 부채꼴로 그린다(반지름 = 키 폭 × 설정 배율).
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

    /// 반지름 배율(키 몇 칸) — 설정 슬라이더 범위 · 기본값. 처음엔 1칸 고정이었는데 손가락에 가려 작다는
    /// 사용자 제보로 고르게 했다(2026-11-27 1다 · 2가).
    static let radiusScaleRange: ClosedRange<Double> = 1.0...3.0
    static let radiusScaleStep: Double = 0.5
    static let defaultRadiusScale: Double = 2.0

    /// 부채꼴 반지름 = 키 한 칸 폭 × 배율(범위 밖·NaN 은 잘라 씀).
    static func radius(keyWidth: CGFloat, scale: Double = defaultRadiusScale) -> CGFloat {
        let s = scale.isFinite ? min(max(scale, radiusScaleRange.lowerBound), radiusScaleRange.upperBound)
                               : defaultRadiusScale
        return max(keyWidth, 30) * CGFloat(s)
    }
}

/// 구역 보기 진단 (새모아 2026-11-28). 실기기에서 앱 스위치는 켜짐인데 키보드는 꺼짐을 들고 있어 구역이 안 뜨다가,
/// 앱에서 껐다 켜자 돌아왔다. 키보드가 **들고 있던 값**과 누른 순간 **저장소에서 바로 읽은 값**을 견준다 —
/// 어긋나면 다시 읽기를 놓친 것, 둘 다 꺼짐이면 저장소가 낡은 값을 준 것. 글자는 담지 않는다.
struct VowelZoneDiagnostics {
    let since: Date
    private(set) var presses = 0
    private(set) var shown = 0
    private(set) var mismatches = 0
    private(set) var lastMismatchAt: Date?
    private(set) var lastHeld: Bool?
    /// 마지막 누름 때 저장소 값. 값이 없으면 nil(기본 꺼짐으로 침).
    private(set) var lastStored: Bool?

    init(since: Date = Date()) { self.since = since }

    /// 한글 자음 키 누름 하나. 어긋났으면 true.
    @discardableResult
    mutating func recordPress(held: Bool, stored: Bool?, at date: Date = Date()) -> Bool {
        presses += 1
        if held { shown += 1 }
        lastHeld = held
        lastStored = stored
        let mismatch = (stored ?? false) != held
        if mismatch {
            mismatches += 1
            lastMismatchAt = date
        }
        return mismatch
    }

    func line(lastLoad: (at: Date, reason: String, vowelZone: Bool)?, notices: Int, dropped: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss"
        let t = DateFormatter()
        t.dateFormat = "HH:mm:ss"
        func onOff(_ v: Bool?) -> String { v.map { $0 ? "켜짐" : "꺼짐" } ?? "-" }
        var parts = ["\(f.string(from: since)) 부터", "자음 누름 \(presses)", "구역 띄움 \(shown)"]
        // 타입을 단계마다 드러낸다 — 한 식으로 묶으면 CI 컴파일러가 타입 추론 시간 초과(EarlyTouch.swift 와 같은 까닭).
        let storedText: String = presses == 0 ? "-" : (lastStored == nil ? "없음" : onOff(lastStored))
        parts.append("마지막 누름 때 키보드 값 \(onOff(lastHeld)) · 저장소 값 \(storedText)")
        var mismatchText = "어긋남 \(mismatches)"
        if let lastMismatchAt { mismatchText += " (마지막 \(t.string(from: lastMismatchAt)))" }
        parts.append(mismatchText)
        if let lastLoad {
            parts.append("설정 다시 읽음 \(f.string(from: lastLoad.at)) \(lastLoad.reason) · 그때 읽은 값 \(onOff(lastLoad.vowelZone))")
        } else {
            parts.append("설정 다시 읽음 -")
        }
        parts.append("앱 알림 받음 \(notices) · 겹쳐 버림 \(dropped)")
        return parts.joined(separator: " · ")
    }
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
