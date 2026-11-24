import XCTest
import SwiftUI
@testable import MoaPlusKeyboard

/// 기능 행의 자식 폭 합 == 사용 가능 폭 불변식.
/// 자식을 추가하면 간격(gap) 개수도 함께 늘어나야 하는데, 이를 놓치면 가장
/// 오른쪽 키(⏎)가 넘쳐 잘린다. v1.9 지구본 키 추가가 바로 그 위험이라
/// 모든 바디 × 지구본 on/off × 내림 키 on/off(이슈 #51) 조합을 고정한다.
final class FunctionRowWidthTests: XCTestCase {

    private static let globeDismissCombos = [(false, false), (true, false), (false, true), (true, true)]

    private func row(mode: KeyboardMode,
                     showGlobeKey: Bool,
                     showDismissKey: Bool = false,
                     slotA: SlotAPreset = .vowel,
                     koreanPunctuationEnabled: Bool = true,
                     englishPunctuationEnabled: Bool = true,
                     bimanual: Bool = false,
                     compactReturn: Bool = false,
                     totalWidth: CGFloat = 393) -> FunctionRowView {
        var customization = LayoutCustomization()
        customization.slotA = slotA
        customization.koreanPunctuationEnabled = koreanPunctuationEnabled
        customization.englishPunctuationEnabled = englishPunctuationEnabled
        return FunctionRowView(
            totalWidth: totalWidth,
            mode: mode,
            onToggleSymbolPressed: {},
            onToggleLetterPressed: {},
            onSpacePressed: {},
            onPunctuation: { _ in },
            onReturnPressed: {},
            showGlobeKey: showGlobeKey,
            showDismissKey: showDismissKey,
            compactReturnKey: compactReturn,
            useBimanualLayout: bimanual,
            layoutCustomization: customization
        )
    }

    private func assertFits(_ view: FunctionRowView,
                            _ label: String,
                            kind: FunctionRowView.BodyKind,
                            file: StaticString = #filePath, line: UInt = #line) {
        // 의도한 바디를 실제로 렌더하는지 먼저 확인 — 조건이 바뀌어 다른 바디로
        // 새면 폭 검증은 통과하면서 정작 대상 바디는 미검증으로 남는다.
        XCTAssertEqual(view.activeBodyKind, kind,
                       "\(label): 기대와 다른 바디가 활성", file: file, line: line)
        XCTAssertEqual(view.occupiedWidth, view.availableWidth, accuracy: 0.5,
                       "\(label): 자식 폭 합이 사용 가능 폭과 다름 — 오른쪽 키가 잘린다",
                       file: file, line: line)
        XCTAssertGreaterThan(view.occupiedWidth, 0, "\(label): 폭이 0 이하", file: file, line: line)
    }

    func test_defaultLayout_fitsWithAndWithoutGlobe() {
        for (globe, dismiss) in Self.globeDismissCombos {
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss),
                       "default korean globe=\(globe) dismiss=\(dismiss)", kind: .default)
            assertFits(row(mode: .english, showGlobeKey: globe, showDismissKey: dismiss),
                       "default english globe=\(globe) dismiss=\(dismiss)", kind: .default)
        }
    }

    func test_symbolLayout_fitsWithAndWithoutGlobe() {
        for (globe, dismiss) in Self.globeDismissCombos {
            assertFits(row(mode: .symbolFromKorean, showGlobeKey: globe, showDismissKey: dismiss),
                       "symbol globe=\(globe) dismiss=\(dismiss)", kind: .symbol)
            assertFits(row(mode: .symbolFromEnglish, showGlobeKey: globe, showDismissKey: dismiss),
                       "symbol-en globe=\(globe) dismiss=\(dismiss)", kind: .symbol)
        }
    }

    /// 긴 스페이스 바디는 두 경로로 진입한다 — 한글 펑크 OFF, 그리고 확장형(A3).
    func test_longSpaceLayout_fitsWithAndWithoutGlobe() {
        for (globe, dismiss) in Self.globeDismissCombos {
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, koreanPunctuationEnabled: false),
                       "longSpace(펑크 OFF) globe=\(globe) dismiss=\(dismiss)", kind: .longSpace)
            assertFits(row(mode: .english, showGlobeKey: globe, showDismissKey: dismiss, englishPunctuationEnabled: false),
                       "longSpace(영문 펑크 OFF, 기본값) globe=\(globe) dismiss=\(dismiss)", kind: .longSpace)
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, slotA: .fullPackage),
                       "longSpace(확장형) globe=\(globe) dismiss=\(dismiss)", kind: .longSpace)
        }
    }

    func test_bimanualLayout_fitsWithAndWithoutGlobe() {
        for (globe, dismiss) in Self.globeDismissCombos {
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, bimanual: true, totalWidth: 1366),
                       "bimanual globe=\(globe) dismiss=\(dismiss)", kind: .bimanual)
            assertFits(row(mode: .symbolFromKorean, showGlobeKey: globe, showDismissKey: dismiss, bimanual: true, totalWidth: 1366),
                       "bimanual symbol globe=\(globe) dismiss=\(dismiss)", kind: .bimanual)
        }
    }

    /// 내림 키 = 자음 키 한 칸 (사용자 결정 2026-11-24). 스페이스바는 예전 몫(지구본의 0.8배 + 간격)만 내고
    /// 늘어난 몫은 엔터가 낸다 — 가장 좁은 아이폰(375pt, 지구본 표시)에서도 스페이스바가 한/영 키보다 넓어야 쓸 만하다.
    /// 한손 모드는 내림 키를 띠로 빼서 이 검사 밖.
    func test_dismissKeyGrowthComesFromReturn() {
        for width: CGFloat in [375, 393, 744, 1133] {
            let off = row(mode: .korean, showGlobeKey: true, totalWidth: width)
            let on = row(mode: .korean, showGlobeKey: true, showDismissKey: true, totalWidth: width)
            let tag = "width=\(width)"
            XCTAssertEqual(on.dismissWidth, on.letterToggleWidth, accuracy: 0.01, "내림 키 = 키 한 칸 \(tag)")
            XCTAssertGreaterThan(on.dismissGrowth, 0, tag)
            XCTAssertEqual(on.punctuationWidth, off.punctuationWidth, accuracy: 0.01, tag)
            XCTAssertEqual(on.symbolToggleWidth, off.symbolToggleWidth, accuracy: 0.01, tag)
            XCTAssertEqual(on.letterToggleWidth, off.letterToggleWidth, accuracy: 0.01, tag)
            XCTAssertEqual(off.returnWidth - on.returnWidth, on.dismissGrowth, accuracy: 0.01, "늘어난 몫은 엔터가 \(tag)")
            XCTAssertEqual(off.spaceWidth - on.spaceWidth,
                           on.legacyDismissWidth + KeyboardMetrics.keySpacing, accuracy: 0.01, "스페이스바는 예전 몫만 \(tag)")
            XCTAssertGreaterThan(on.spaceWidth, on.letterToggleWidth, "스페이스바가 너무 좁다 \(tag)")
        }
    }

    /// 「엔터 키 좁게」면 엔터가 이미 키 한 칸이라 더 줄이지 않고, 늘어난 몫까지 스페이스바가 낸다.
    func test_dismissKeyGrowth_compactReturnKeepsOneKey() {
        let off = row(mode: .korean, showGlobeKey: true, compactReturn: true, totalWidth: 375)
        let on = row(mode: .korean, showGlobeKey: true, showDismissKey: true, compactReturn: true, totalWidth: 375)
        XCTAssertEqual(on.returnWidth, on.letterToggleWidth, accuracy: 0.01)
        XCTAssertEqual(off.spaceWidth - on.spaceWidth, on.dismissWidth + KeyboardMetrics.keySpacing, accuracy: 0.01)
        assertFits(on, "compact + dismiss 375", kind: .default)
    }

    /// 아이패드 분리 배치: 그리드 키 폭을 넘기면 내림 키가 그 폭이다.
    func test_dismissKey_usesGridKeyWidthWhenGiven() {
        var view = row(mode: .korean, showGlobeKey: true, showDismissKey: true, totalWidth: 1133)
        view.gridKeyWidth = 108.7
        XCTAssertEqual(view.dismissWidth, 108.7, accuracy: 0.01)
        assertFits(view, "split grid key width", kind: .default)
    }

    /// 지구본을 켜면 스페이스 바만 줄어들어야 한다. 펑크 키까지 같이 줄면
    /// 기존 사용자의 특수문자 키 타격 지점이 바뀐다.
    func test_globeKeyShrinksOnlyTheSpaceBar() {
        let off = row(mode: .korean, showGlobeKey: false)
        let on = row(mode: .korean, showGlobeKey: true)
        XCTAssertEqual(on.punctuationWidth, off.punctuationWidth, accuracy: 0.01)
        XCTAssertEqual(on.symbolToggleWidth, off.symbolToggleWidth, accuracy: 0.01)
        XCTAssertEqual(on.letterToggleWidth, off.letterToggleWidth, accuracy: 0.01)
        XCTAssertEqual(on.returnWidth, off.returnWidth, accuracy: 0.01)
        XCTAssertLessThan(on.spaceWidth, off.spaceWidth)
        XCTAssertEqual(off.spaceWidth - on.spaceWidth,
                       on.globeWidth + KeyboardMetrics.keySpacing, accuracy: 0.01)
    }

    /// 엔터 키 좁게 (앱스토어 리뷰 "엔터키가 너무 커요"): 모든 바디에서 폭 합이 맞아야 한다.
    func test_compactReturn_fitsEveryBody() {
        for (globe, dismiss) in Self.globeDismissCombos {
            let tag = "compact globe=\(globe) dismiss=\(dismiss)"
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, compactReturn: true),
                       "default \(tag)", kind: .default)
            assertFits(row(mode: .symbolFromKorean, showGlobeKey: globe, showDismissKey: dismiss, compactReturn: true),
                       "symbol \(tag)", kind: .symbol)
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, slotA: .fullPackage, compactReturn: true),
                       "longSpace(확장형) \(tag)", kind: .longSpace)
            assertFits(row(mode: .korean, showGlobeKey: globe, showDismissKey: dismiss, bimanual: true,
                           compactReturn: true, totalWidth: 1366),
                       "bimanual \(tag)", kind: .bimanual)
        }
    }

    /// 줄인 만큼은 스페이스바로만 간다 — 펑크 키까지 커지면 그 키의 타격 지점이 바뀐다.
    func test_compactReturn_givesWidthOnlyToSpaceBar() {
        let off = row(mode: .korean, showGlobeKey: false)
        let on = row(mode: .korean, showGlobeKey: false, compactReturn: true)
        XCTAssertEqual(on.returnWidth, on.letterToggleWidth, accuracy: 0.01, "좁힌 ⏎ = 키 한 칸")
        XCTAssertLessThan(on.returnWidth, off.returnWidth)
        XCTAssertEqual(on.punctuationWidth, off.punctuationWidth, accuracy: 0.01)
        XCTAssertEqual(on.symbolToggleWidth, off.symbolToggleWidth, accuracy: 0.01)
        XCTAssertEqual(on.spaceWidth - off.spaceWidth, off.returnWidth - on.returnWidth, accuracy: 0.01)
    }

    // MARK: - 아이패드 숫자패드 왼쪽 배치 (사용자 결정 2026-11-21)

    /// `KeyboardView` 와 같은 식으로 분리 배치 값을 만든다 (iPad mini 가로 1133pt).
    private func splitMetrics(width: CGFloat = 1133) -> (numpad: CGFloat, moaki: CGFloat, center: CGFloat) {
        let sp = KeyboardMetrics.keySpacing
        let numpad = (width - sp * 3) * 0.31
        let moaki = (width - sp * 3) * 0.69
        return (numpad, moaki, KeyboardMetrics.centerKeyWidth(for: moaki, columnCount: 7, mode: .korean))
    }

    func test_iPadSplitLeft_returnStartsWherePaStarts_spaceEndsAtChieut() {
        let width: CGFloat = 1133
        let m = splitMetrics(width: width)
        let sp = KeyboardMetrics.keySpacing
        let x = KeyboardMetrics.iPadSplitReturnLeadingX(
            numpadWidth: m.numpad, moakiWidth: m.moaki, splitSpacing: sp, moakiCenterKeyWidth: m.center)
        // ㅊ(4번째 줄 3열) 오른쪽 끝 = 여백 + 넓힌 옆 칸 + 가운데 키 3개 + 간격 3 — 그 뒤 간격 하나가 ㅍ 왼쪽 끝.
        let side = KeyboardMetrics.keyWidth(for: 0, row: 3, centerKeyWidth: m.center, mode: .korean)
        let gridWidth = side * 2 + m.center * 5 + sp * 6
        let margin = max(sp, (m.moaki - gridWidth) / 2)
        let chieutRight = m.numpad + sp + margin + side + sp + (m.center + sp) * 2 + m.center
        XCTAssertEqual(x, chieutRight + sp, accuracy: 0.01)

        for (globe, dismiss) in Self.globeDismissCombos {
            for slotA in [SlotAPreset.fullPackage, .vowel] {
                var customization = LayoutCustomization()
                customization.slotA = slotA
                let view = FunctionRowView(
                    totalWidth: width, mode: .korean,
                    onToggleSymbolPressed: {}, onToggleLetterPressed: {}, onSpacePressed: {},
                    onPunctuation: { _ in }, onReturnPressed: {},
                    showGlobeKey: globe, showDismissKey: dismiss,
                    returnLeadingX: x, layoutCustomization: customization)
                let label = "split slotA=\(slotA) globe=\(globe) dismiss=\(dismiss)"
                assertFits(view, label, kind: slotA == .fullPackage ? .longSpace : .default)
                // 맞춘 엔터가 예전보다 넓어지는 자리(내림 키 없음 — 1133pt 에서 ㅍ ~ 행 끝이 예전 엔터보다 넓다)면
                // 예전 폭 그대로 (「엔터를 줄이고」, 사용자 결정 2026-11-21).
                let aligned = view.effectiveTotalWidth - view.dismissReservedWidth - x
                if dismiss { XCTAssertLessThan(aligned, view.baseReturnWidth, label) }
                guard aligned < view.baseReturnWidth else {
                    XCTAssertNil(view.alignedReturnWidth, label)
                    XCTAssertEqual(view.returnWidth, view.baseReturnWidth, label)
                    continue
                }
                XCTAssertNotNil(view.alignedReturnWidth, label)
                // 엔터 왼쪽 끝 = 행 끝 − 내림 키 몫 − 엔터 폭 = ㅍ 왼쪽 끝.
                let returnLeft = view.occupiedWidth - view.dismissReservedWidth - view.returnWidth
                XCTAssertEqual(returnLeft, x, accuracy: 0.5, label)
            }
        }
    }

    func test_returnLeadingX_ignoredWhenItWouldWidenOrInSymbolMode() {
        let base = row(mode: .korean, showGlobeKey: true, totalWidth: 1133)
        // 예전 엔터보다 넓어지는 자리면 쓰지 않는다.
        var wide = base
        wide.returnLeadingX = 10
        XCTAssertNil(wide.alignedReturnWidth)
        XCTAssertEqual(wide.returnWidth, base.baseReturnWidth)
        // 심볼 행은 다른 배치라 쓰지 않는다.
        var symbol = row(mode: .symbolFromKorean, showGlobeKey: true, totalWidth: 1133)
        symbol.returnLeadingX = 900
        XCTAssertNil(symbol.alignedReturnWidth)
    }
}

/// 기능행 키 눌림 표시 = 자음 키와 같은 반대쪽 키 색 (사용자 결정 2026-11-22 1나 · 2가).
/// 투명도만 낮추던 예전 방식으로 되돌리면 눌려도 티가 안 난다(아이패드 스페이스바 제보).
final class FunctionKeyPressFillTests: XCTestCase {
    func test_pressed_usesKeyColor_released_usesFunctionKeyColor() {
        let s = KeyboardSettings.shared
        XCTAssertEqual(FunctionKeyPressFill.fillColor(pressed: true, settings: s), s.resolvedKeyBackground)
        XCTAssertEqual(FunctionKeyPressFill.fillColor(pressed: false, settings: s), s.resolvedFunctionKeyBackground)
    }
}
