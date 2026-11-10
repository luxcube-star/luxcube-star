import SwiftUI

/// 학습한 단어 추천 바. 키보드 맨 위, 약어 후보 바와 같은 자리에 같은 높이로 그린다.
///
/// 후보가 없어도 바는 비워 둔 채 자리를 지킨다 — 글자마다 바가 생겼다 사라지면 키보드
/// 높이가 계속 출렁여 손가락 아래의 키가 움직인다 (iOS 기본 키보드의 추천 막대와 같은 방식).
///
/// - 탭: 입력 중인 단어를 이 단어로 바꾸고 스페이스를 붙인다.
/// - 길게 누르기: 이 단어를 학습 데이터에서 지운다 (잘못 학습한 오타 정리).
struct PredictionBarView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    let onForget: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, word in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5, height: KeyboardMetrics.abbreviationCandidateBarHeight * 0.5)
                }
                Text(word)
                    .font(.system(size: 15, weight: index == 0 ? .semibold : .regular))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(word) }
                    .onLongPressGesture(minimumDuration: 0.6) { onForget(word) }
                    .accessibilityLabel(Text(word))
                    .accessibilityHint(Text("두 번 탭하면 입력합니다"))
                    .accessibilityAddTraits(.isButton)
            }
            if suggestions.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: KeyboardMetrics.abbreviationCandidateBarHeight)
        .frame(maxWidth: .infinity)
    }
}
