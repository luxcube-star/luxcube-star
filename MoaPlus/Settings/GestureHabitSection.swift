import SwiftUI
import Combine

/// 「입력 기록 보드」의 「새모아가 맞춘 것」 칸 (긋기 버릇 맞추기, 개선 방안 13번).
///
/// 앱은 맞춘 값 파일을 **직접 고치지 않는다** — 키보드가 값을 메모리에 들고 있다가 덮어쓴다.
/// 되돌리기 · 처음으로는 `GestureHabitStore.appendEdit` 로 요청을 남기고, 키보드가 다음에 뜰 때 반영한다
/// (「학습 내용」 화면과 같은 방식).
final class GestureHabitBoardModel: ObservableObject {
    @Published private(set) var model: GestureHabitModel?
    /// 남겼지만 키보드가 아직 반영하지 않은 요청.
    @Published private(set) var pendingReverts: Set<Int> = []
    @Published private(set) var pendingReset = false
    /// 처음 맞추기(15번) 결과를 남겼지만 키보드가 아직 반영하지 않음.
    @Published private(set) var pendingCalibration = false

    func reload() {
        model = GestureHabitStore.loadShared()
        let applied = model?.appliedEditId ?? 0
        let pending = GestureHabitStore.loadEdits().filter { $0.id > applied }
        pendingReverts = Set(pending.compactMap {
            if case .revert(let id) = $0.edit { return id }
            return nil
        })
        pendingReset = pending.contains { $0.edit == .resetAll }
        pendingCalibration = pending.contains {
            if case .calibrate = $0.edit { return true }
            return false
        }
    }

    /// 아직 되돌리지 않은 맞춘 일, 새것부터.
    var activeEvents: [GestureHabitEvent] {
        (model?.events ?? []).filter { !$0.reverted }.reversed()
    }

    func revert(_ event: GestureHabitEvent) {
        if GestureHabitStore.appendEdit(.revert(eventId: event.id)) { pendingReverts.insert(event.id) }
    }

    func resetAll() {
        if GestureHabitStore.appendEdit(.resetAll) { pendingReset = true }
    }
}

struct GestureHabitSection: View {
    @ObservedObject var settings: KeyboardSettings
    @StateObject private var board = GestureHabitBoardModel()
    @State private var confirmingReset = false

    var body: some View {
        Section {
            Toggle("스스로 맞추기", isOn: $settings.gestureHabitEnabled)
            if let model = board.model {
                HStack {
                    Text("센 오타")
                    Spacer()
                    Text("\(model.observedCount)번").foregroundColor(.secondary)
                }
            }
            NavigationLink("처음 맞추기 — 문장을 쳐서 버릇 재기") {
                GestureCalibrationView()
            }
            if board.pendingCalibration {
                Text("처음 맞추기 결과를 남겼습니다. 키보드를 열면 반영됩니다.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if board.pendingReset {
                Text("처음으로 되돌리기를 남겼습니다. 키보드를 열면 반영됩니다.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            ForEach(board.activeEvents) { event in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.key) 키 · \(event.knob.displayName) \(event.knob.formatted(event.delta))"
                             + (event.fromCalibration == true ? " (처음 맞추기)" : ""))
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if board.pendingReverts.contains(event.id) || board.pendingReset || board.pendingCalibration {
                        Text("키보드를 열면 되돌림").font(.caption).foregroundColor(.secondary)
                    } else {
                        Button("되돌리기") { board.revert(event) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            if !(board.model?.events.isEmpty ?? true) || !(board.model?.counters.isEmpty ?? true) {
                Button("처음으로", role: .destructive) { confirmingReset = true }
                    .disabled(board.pendingReset)
            }
        } header: {
            Text("새모아가 맞춘 것")
        } footer: {
            Text("같은 자음 키에서 모음이 잘못 들어가 지우고 다시 그은 일이 5번 쌓이면, 그 키의 긋기 각도(2°씩 10°까지) · 길이 · 휨 · 최소 길이를 스스로 조금씩 맞춥니다. 친 글은 남기지 않고 키 · 숫자만 이 기기에 둡니다. 「처음 맞추기」는 정해 준 문장을 치게 해 처음 값을 잽니다. 전체 접근 허용이 꺼져 있으면 키보드 안에서는 맞춰지지만 여기에는 보이지 않고, 처음 맞추기 결과도 키보드에 닿지 않습니다.")
        }
        .onAppear { board.reload() }
        .confirmationDialog("맞춘 것을 모두 처음으로 되돌릴까요?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("처음으로", role: .destructive) { board.resetAll() }
            Button("취소", role: .cancel) {}
        }
    }
}
