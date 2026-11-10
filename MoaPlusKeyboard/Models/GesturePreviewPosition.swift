import CoreGraphics

/// 긋기 미리보기(완성될 글자)를 띄울 자리.
///
/// 키보드 익스텐션은 자기 영역 밖(호스트 앱 화면)에 그릴 수 없으므로, 손가락에 가장 덜 가려지는
/// 키보드 **맨 위쪽**에 고정하는 선택지를 둔다. `.auto` 는 원본 모아+ 동작(누른 키의 반대편).
enum GesturePreviewPosition: String, Codable, CaseIterable, Identifiable {
    /// 누른 키의 반대편 (두 엄지 입력 기준, 원본 동작)
    case auto
    /// 키보드 왼쪽 위 — 오른손으로 칠 때
    case topLeft
    /// 키보드 가운데 위
    case topCenter
    /// 키보드 오른쪽 위 — 왼손으로 칠 때
    case topRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "자동 (누른 키 반대편)"
        case .topLeft: return "오른손 (왼쪽 위)"
        case .topCenter: return "가운데 위"
        case .topRight: return "왼손 (오른쪽 위)"
        }
    }

    /// 고정 위치의 가로 기준 (키보드 폭 대비). `.auto` 는 `nil`.
    var fixedHorizontalFraction: CGFloat? {
        switch self {
        case .auto: return nil
        case .topLeft: return 0.2
        case .topCenter: return 0.5
        case .topRight: return 0.8
        }
    }
}
