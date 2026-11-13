import SwiftUI
import Combine

// MARK: - 처음 맞추기 (개선 방안 15번, 사용자 결정 2026-11-13: 1~9 모두 가)
//
// 정해 준 문장을 진짜 키보드 그림으로 치게 하고, 자음 키 긋기 · 탭마다 숫자를 받아 버릇을 잰다
// (`GestureCalibrator`). 다 치면 잰 값을 보여 주고, 「넣기」를 눌러야 `GestureHabitEdit.calibrate`
// 요청을 남긴다 — 앱은 맞춘 값 파일을 직접 고치지 않는다(키보드가 다음에 뜰 때 반영).

/// 친 글을 화면에만 담는 입력 대리자. 친 글로 단어를 배우지 않는다(`hostAllowsLearning` false).
final class GestureCalibrationKeyboardDelegate: ObservableObject, KeyboardViewModelDelegate {
    @Published var typedText: String = ""

    func insertText(_ text: String) { typedText.append(text) }

    func deleteBackward() {
        if !typedText.isEmpty { typedText.removeLast() }
    }

    func updateComposingText(from previous: String, to current: String) {
        var remaining = previous.count
        while remaining > 0, !typedText.isEmpty {
            typedText.removeLast()
            remaining -= 1
        }
        if !current.isEmpty { typedText.append(current) }
    }

    func switchToNextKeyboard() {}
    func triggerHapticFeedback() {}
    func moveCursor(by offset: Int) { _ = offset }
    /// 연습 문장을 추천 학습에 넣지 않는다 (저절로 띄기도 함께 꺼진다).
    func hostAllowsLearning() -> Bool { false }
}

final class GestureCalibrationModel: ObservableObject {
    enum Stage { case intro, typing, result }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var sentenceIndex = 0
    @Published private(set) var sentenceMeasured = 0
    @Published private(set) var result: GestureCalibrationResult?
    @Published private(set) var applied = false
    @Published private(set) var applyFailed = false
    /// 문장을 넘기거나 다시 칠 때 키보드(조합 상태)를 새로 만든다.
    @Published private(set) var keyboardToken = 0

    let sentences = GestureCalibrationScript.sentences
    private let calibrator = GestureCalibrator()

    var currentSentence: String { sentences[min(sentenceIndex, sentences.count - 1)] }
    var isLastSentence: Bool { sentenceIndex >= sentences.count - 1 }

    func start() {
        stage = .typing
        sentenceIndex = 0
        applied = false
        applyFailed = false
        calibrator.begin(sentence: currentSentence)
        refresh()
    }

    func ingest(_ sample: GestureCalibrationSample) {
        guard stage == .typing else { return }
        calibrator.ingest(sample)
        refresh()
    }

    func restartSentence() {
        calibrator.restartSentence()
        keyboardToken += 1
        refresh()
    }

    func nextSentence() {
        if isLastSentence {
            result = calibrator.result()
            stage = .result
            return
        }
        sentenceIndex += 1
        calibrator.begin(sentence: currentSentence)
        keyboardToken += 1
        refresh()
    }

    /// 여기까지 친 것으로 끝낸다.
    func finishEarly() {
        result = calibrator.result()
        stage = .result
    }

    func apply() {
        guard let result else { return }
        if GestureHabitStore.appendEdit(.calibrate(keys: result.keys)) {
            applied = true
        } else {
            applyFailed = true
        }
    }

    private func refresh() {
        sentenceMeasured = calibrator.sentenceMeasuredCount
    }
}

struct GestureCalibrationView: View {
    @StateObject private var model = GestureCalibrationModel()
    @StateObject private var inputDelegate = GestureCalibrationKeyboardDelegate()
    @ObservedObject private var settings = KeyboardSettings.shared

    var body: some View {
        Group {
            if model.stage == .typing {
                // 키보드는 실제 키보드와 같은 자리 · 크기로 — 화면 맨 아래, 폭 가득 (사용자 결정 2026-11-13 1가).
                VStack(spacing: 0) {
                    ScrollView {
                        typing.padding()
                    }
                    KeyboardPreviewView(
                        liveInputDelegate: inputDelegate,
                        gestureHabitPersistence: .off,
                        onConsonantMeasured: { sample in model.ingest(sample) },
                        matchesRealKeyboardSize: true
                    )
                    .id(model.keyboardToken)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.stage == .intro { intro } else { resultView }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("처음 맞추기")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 시작

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("문장 \(model.sentences.count)개를 아래 키보드로 쳐 주십시오. 치는 동안 자음 키마다 긋는 각도와, 손 전체의 되돌림 길이 · 휨 · 누를 때 미끄러지는 거리를 잽니다.")
            Text("평소처럼 치시면 됩니다. 틀려도 지우지 말고 그대로 이어 치십시오 — 틀린 긋기도 버릇을 재는 데 씁니다.")
            Text("다 치면 잰 값을 보여 드리고, 「넣기」를 누르셔야 넣습니다. 넣으면 「새모아가 맞춘 것」의 앞 값은 지워지고 이 값으로 바뀝니다. 그 뒤는 「스스로 맞추기」가 이어서 고칩니다.")
            Text("친 글은 남기지 않고, 단어 추천에도 배우지 않습니다.")
                .foregroundColor(.secondary)
            Button {
                inputDelegate.typedText = ""
                model.start()
            } label: {
                Text("시작").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.callout)
    }

    // MARK: 치기

    private var typing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("문장 \(model.sentenceIndex + 1) / \(model.sentences.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("잰 입력 \(model.sentenceMeasured)번")
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(model.currentSentence)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            Text(inputDelegate.typedText.isEmpty ? " " : inputDelegate.typedText)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
            Text("틀려도 지우지 말고 그대로 이어 치십시오. 아래 키보드는 실제 키보드와 같은 자리 · 크기입니다.")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                Button("이 문장 다시") {
                    inputDelegate.typedText = ""
                    model.restartSentence()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(model.isLastSentence ? "다 쳤음" : "다음 문장") {
                    inputDelegate.typedText = ""
                    model.nextSentence()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.sentenceMeasured == 0)
            }
            if model.sentenceIndex > 0 {
                Button("여기까지 친 것으로 끝내기") {
                    inputDelegate.typedText = ""
                    model.finishEarly()
                }
                .font(.footnote)
            }
        }
    }

    // MARK: 결과

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = model.result {
                Text("잰 입력 \(result.measuredCount)번 · 정해 준 것과 다르게 들어간 것 \(result.mismatchCount)번")
                    .font(.subheadline)
                if result.keys.isEmpty {
                    Text("맞출 것이 없습니다. 지금 판정이 긋는 버릇과 잘 맞습니다.")
                } else {
                    handWideCard(result)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("키마다 각도").font(.subheadline.weight(.semibold))
                        ForEach(Choseong.allCases.map { String($0.compatibilityCharacter) }, id: \.self) { key in
                            angleRow(key: key, result: result)
                        }
                        Text("각도는 그 키에서 한 획 모음을 \(GestureCalibrator.minAngleSamples)번 넘게 그었을 때만 넣습니다.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                }

                if model.applied {
                    Text("넣기를 남겼습니다. 키보드를 열면 반영되고, 「새모아가 맞춘 것」에 줄마다 보입니다.")
                        .foregroundColor(.green)
                } else if model.applyFailed {
                    Text("넣기를 남기지 못했습니다. 앱 그룹 저장소에 쓸 수 없습니다.")
                        .foregroundColor(.red)
                } else if !result.keys.isEmpty {
                    if !settings.gestureHabitEnabled {
                        Text("「스스로 맞추기」가 꺼져 있어, 넣어도 켜기 전에는 쓰지 않습니다.")
                            .font(.footnote).foregroundColor(.orange)
                    }
                    Text("넣으면 앞서 맞춘 값과 쌓이던 오타는 지워지고 이 값으로 바뀝니다.")
                        .font(.footnote).foregroundColor(.secondary)
                    Button {
                        model.apply()
                    } label: {
                        Text("넣기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("처음부터 다시 재기") {
                    inputDelegate.typedText = ""
                    model.start()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func handWideCard(_ result: GestureCalibrationResult) -> some View {
        let clamped = result.clamped[GestureCalibrationResult.handWideLabel] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text("손 전체 (19키에 같게)").font(.subheadline.weight(.semibold))
            ForEach([GestureHabitKnob.length, .curve, .minLength], id: \.self) { knob in
                HStack {
                    Text(knob.displayName)
                    Spacer()
                    let value = result.handWide.value(of: knob)
                    Text(value == 0 ? "그대로" : knob.formatted(value))
                        .foregroundColor(value == 0 ? .secondary : .primary)
                    if clamped.contains(knob) {
                        Text("한도에 닿음").font(.caption2).foregroundColor(.orange)
                    }
                }
                .font(.callout)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func angleRow(key: String, result: GestureCalibrationResult) -> some View {
        let count = result.angleSampleCounts[key] ?? 0
        let value = result.keys[key]?.rotationDeg ?? 0
        let clamped = result.clamped[key]?.contains(.angle) ?? false
        return HStack {
            Text("\(key) 키")
            Spacer()
            if count < GestureCalibrator.minAngleSamples {
                Text("모자람 (\(count)번)").foregroundColor(.secondary)
            } else {
                Text(value == 0 ? "그대로" : GestureHabitKnob.angle.formatted(value))
                    .foregroundColor(value == 0 ? .secondary : .primary)
                if clamped {
                    Text("한도에 닿음").font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .font(.callout)
    }
}
