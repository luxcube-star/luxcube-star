import SwiftUI

struct GestureOverlayView: View {
    let directions: [GestureDirection]
    let startPoint: CGPoint?
    let currentVowel: Jungseong?
    /// 완성될 글자 (예: ㅈ 키에서 ↑ → "조"). 없으면 모음만 보여 준다.
    var previewText: String? = nil
    /// 미리보기 자리. 기본은 원본 동작(누른 키 반대편).
    var position: GesturePreviewPosition = .auto

    var body: some View {
        GeometryReader { geometry in
            if let start = startPoint, !directions.isEmpty {
                ZStack {
                    VStack(spacing: 2) {
                        // 완성될 글자를 크게 — 사용자가 확인하려는 건 방향이 아니라 결과 글자다.
                        if let text = previewText ?? currentVowel.map({ String($0.compatibilityCharacter) }) {
                            Text(text)
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }

                        // 화살표가 많아도 한 줄·고정 폭으로 — 길어져서 미리보기
                        // 박스가 화면을 침범하지 않게 최근 8개만, 축소 허용.
                        Text(directions.suffix(8).map { $0.symbol }.joined())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(8)
                    .frame(maxWidth: 240)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.9))
                            .shadow(radius: 2)
                    )
                    .position(indicatorPosition(start: start, in: geometry.size))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func indicatorPosition(start: CGPoint, in size: CGSize) -> CGPoint {
        // 고정 자리: 키보드 맨 위. 엄지는 주로 아래쪽 키 위에 있어 맨 위가 가장 덜 가려진다.
        if let fraction = position.fixedHorizontalFraction {
            let boxHalfHeight: CGFloat = 40
            return CGPoint(
                x: max(60, min(size.width - 60, size.width * fraction)),
                y: min(boxHalfHeight + 2, size.height / 2)
            )
        }

        let overlayHeight: CGFloat = 80

        // Vertical: upper half → below, lower half → above (keep existing rule)
        let y: CGFloat
        if start.y < size.height * 0.45 {
            y = start.y + overlayHeight
        } else {
            y = start.y - overlayHeight
        }

        // Horizontal: render on the opposite half so the user's finger
        // never covers the preview. Left half touch → anchor at 75% width
        // (right half), right half touch → anchor at 25% width (left half).
        let isOnLeft = start.x < size.width / 2
        let x: CGFloat = isOnLeft ? size.width * 0.75 : size.width * 0.25

        return CGPoint(
            x: max(50, min(size.width - 50, x)),
            y: max(40, min(size.height - 40, y))
        )
    }
}

#Preview {
    ZStack {
        Color(.systemGray6)

        GestureOverlayView(
            directions: [.up, .right],
            startPoint: CGPoint(x: 150, y: 200),
            currentVowel: .ㅘ,
            previewText: "과",
            position: .topLeft
        )
    }
    .frame(width: 300, height: 300)
}
