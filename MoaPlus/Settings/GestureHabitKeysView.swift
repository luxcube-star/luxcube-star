import SwiftUI
import Combine

// MARK: - 키마다 그림으로 보기 (「새모아가 맞춘 것」, 사용자 결정 2026-11-15: 2나 · 3가 · 자리 1나 · 경계 2나)
//
// 맞춘 값이 있는 자음 키마다 작은 원을 그린다. 색 구역 = 키보드가 지금 그 키에서 가르는 구역(방향 설정 ·
// 전체 회전 · 세로 줄 보정 · 버릇 각도를 모두 더함). 점선 = 버릇 각도를 뺀 경계. 옆에 각도 · 길이 · 휨 ·
// 최소 길이를 글로. 보기만 한다 — 고치기 · 되돌리기는 「새모아가 맞춘 것」 줄에서.

struct GestureHabitKeysView: View {
    @ObservedObject private var settings = KeyboardSettings.shared
    @State private var model: GestureHabitModel?

    private var keysWithValues: [Choseong] {
        Choseong.allCases.filter { !(model?.adjustment(for: String($0.compatibilityCharacter)).isZero ?? true) }
    }

    var body: some View {
        List {
            if !settings.gestureHabitEnabled {
                Section {
                    Text("「스스로 맞추기」가 꺼져 있어, 지금 키보드는 점선(버릇 각도를 뺀 경계)대로 가릅니다.")
                        .font(.footnote).foregroundColor(.orange)
                }
            }
            if keysWithValues.isEmpty {
                Section {
                    Text("맞춘 값이 있는 키가 없습니다. 처음 맞추기를 넣었다면 키보드를 한 번 연 뒤 이 화면을 다시 여십시오.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach(keysWithValues, id: \.self) { key in
                        row(key)
                    }
                } footer: {
                    Text("색 구역은 지금 키보드가 그 키에서 가르는 구역입니다(방향별 좌/우 각도 · 세로 줄 보정 · 버릇 각도를 모두 더함). 점선은 버릇 각도를 뺀 경계입니다. 각도 − 는 시계 방향으로 돌린 것입니다. 고치거나 되돌리는 것은 「새모아가 맞춘 것」 줄에서 합니다.")
                }
            }
        }
        .navigationTitle("키마다 맞춘 값")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model = GestureHabitStore.loadShared() }
    }

    private func row(_ key: Choseong) -> some View {
        let adjustment = model?.adjustment(for: String(key.compatibilityCharacter)) ?? .zero
        let column = KeyboardMetrics.columnIndex(for: key)
        let habitRotation = settings.gestureHabitEnabled ? adjustment.rotationDeg : 0
        let reference = DirectionPieChart.keySlices(settings: settings, columnId: column, habitRotation: 0)
        return HStack(alignment: .center, spacing: 12) {
            DirectionPieChart(
                slices: DirectionPieChart.keySlices(settings: settings, columnId: column, habitRotation: habitRotation),
                referenceBoundaries: adjustment.rotationDeg == 0 ? [] : reference.map(\.mathStart)
            )
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(key.compatibilityCharacter)) 키").font(.headline)
                ForEach(GestureHabitKnob.allCases, id: \.self) { knob in
                    let value = adjustment.value(of: knob)
                    HStack {
                        Text(knob.displayName)
                        Spacer()
                        Text(value == 0 ? "그대로" : knob.formatted(value))
                            .foregroundColor(value == 0 ? .secondary : .primary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
