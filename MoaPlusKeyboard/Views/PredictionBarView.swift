import SwiftUI

/// 학습한 단어 추천 바. 키보드 맨 위, 약어 후보 바와 같은 자리에 같은 높이로 그린다.
///
/// 후보가 없어도 바는 비워 둔 채 자리를 지킨다 — 글자마다 바가 생겼다 사라지면 키보드
/// 높이가 계속 출렁여 손가락 아래의 키가 움직인다 (iOS 기본 키보드의 추천 막대와 같은 방식).
///
/// - 탭: 입력 중인 단어를 이 단어로 바꾸고 스페이스를 붙인다.
/// - 길게 누르기: 이 단어를 학습 데이터에서 지운다 (잘못 학습한 오타 정리).
/// - 칸 폭: 단어 길이에 맞춘다 (`PredictionBarLayout`, 사용자 결정 2026-11-13). 칸을 똑같이 나누면
///   4칸에서 「감정평가법인」처럼 긴 단어가 잘린다.
struct PredictionBarView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    let onForget: (String) -> Void

    var body: some View {
        Group {
            if suggestions.isEmpty {
                Spacer(minLength: 0)
            } else {
                PredictionBarLayout {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.system(size: 15, weight: index == 0 ? .semibold : .regular))
                            .foregroundColor(Color(.label))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, PredictionBarLayout.textPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .leading) {
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(width: 0.5, height: KeyboardMetrics.abbreviationCandidateBarHeight * 0.5)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(word) }
                            .onLongPressGesture(minimumDuration: 0.6) { onForget(word) }
                            .accessibilityLabel(Text(word))
                            .accessibilityHint(Text("두 번 탭하면 입력합니다"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: KeyboardMetrics.abbreviationCandidateBarHeight)
        .frame(maxWidth: .infinity)
    }
}

/// 추천 칸을 단어 길이에 맞춰 나누는 배치.
///
/// - 다 들어가면: 단어마다 제 폭을 주고 남는 폭을 칸 수로 똑같이 나눠 더한다.
/// - 모자라면: 가장 긴 칸부터 줄인다 — 모든 칸을 상한 `c` 로 자르되 합이 바 폭이 되는 `c` 를 찾는다.
///   짧은 단어는 그대로 다 보이고, 긴 단어만 끝이 「…」 로 잘린다.
struct PredictionBarLayout: Layout {
    /// 칸 안쪽 좌우 여백 (한쪽).
    static let textPadding: CGFloat = 6

    /// 칸 폭 계산. `natural` = 단어마다 여백까지 포함한 제 폭, `available` = 바 폭.
    static func widths(natural: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        let space = max(available, 0)
        let total = natural.reduce(0, +)
        if total <= space {
            let extra = (space - total) / CGFloat(natural.count)
            return natural.map { $0 + extra }
        }
        // 상한 c 찾기: 짧은 칸부터 그대로 두고, 남은 폭을 나머지 칸이 똑같이 나눈다.
        let sorted = natural.sorted()
        var remaining = space
        var cap = space / CGFloat(natural.count)
        for (i, width) in sorted.enumerated() {
            let share = remaining / CGFloat(sorted.count - i)
            if width <= share {
                remaining -= width
            } else {
                cap = share
                break
            }
        }
        return natural.map { min($0, cap) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let height = proposal.height ?? subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let natural = subviews.map { ceil($0.sizeThatFits(.unspecified).width) }
        let widths = Self.widths(natural: natural, available: bounds.width)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
