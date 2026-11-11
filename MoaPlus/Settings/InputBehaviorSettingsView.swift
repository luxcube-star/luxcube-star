// InputBehaviorSettingsView.swift
// MoaPlus

import SwiftUI

struct InputBehaviorSettingsView: View {
    @ObservedObject private var settings = KeyboardSettings.shared
    @State private var isConfirmingPredictionReset = false
    @State private var didResetPrediction = false

    var body: some View {
        List {
            Section {
                Toggle("단어 추천 바", isOn: $settings.predictionEnabled)
                Toggle("입력한 단어 학습", isOn: $settings.predictionLearningEnabled)
                NavigationLink("학습한 단어") { PredictionWordsView() }
                Button(role: .destructive) {
                    isConfirmingPredictionReset = true
                } label: {
                    Text(didResetPrediction ? "학습 데이터를 지웠습니다" : "학습 데이터 지우기")
                }
                .disabled(didResetPrediction)
            } header: {
                Text("단어 추천")
            } footer: {
                Text("자주 쓰는 단어를 학습해 키보드 위에 추천합니다. 입력 중인 단어를 완성하거나(예: \"감정\" → \"감정평가서\"), 스페이스를 친 뒤 다음에 이어 쓸 단어를 보여 줍니다. 추천 단어를 탭하면 입력되고, 길게 누르면 그 단어를 잊습니다.\n\n학습 데이터는 이 기기 안에만 저장되며 외부로 전송되지 않습니다. 숫자가 들어간 단어와 이메일·주소·전화번호·비밀번호·인증번호 입력란의 내용은 학습하지 않습니다. 「학습한 단어」에서 배운 단어를 보고 고칠 수 있고, 숫자나 기호가 든 단어(예: 3층)는 직접 넣으면 추천합니다.")
            }
            .confirmationDialog("학습한 단어를 모두 지울까요?", isPresented: $isConfirmingPredictionReset, titleVisibility: .visible) {
                Button("모두 지우기", role: .destructive) { resetPrediction() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("키보드의 \"전체 접근 허용\"이 꺼져 있으면 키보드가 이 요청을 받지 못할 수 있습니다. 그때는 추천 단어를 길게 눌러 하나씩 지워 주세요.")
            }

            Section {
                Toggle("괄호 자동 닫기", isOn: $settings.autoBracketEnabled)
            } footer: {
                Text("( [ { 등 여는 괄호 입력 시 닫는 괄호를 자동 삽입하고 커서를 가운데에 놓습니다.")
            }

            Section {
                Toggle("더블 스페이스로 마침표 입력", isOn: $settings.periodOnDoubleSpaceEnabled)
            } footer: {
                Text("글자 뒤에서 스페이스를 두 번 누르면 마침표와 공백(. )으로 바꿉니다.")
            }

            Section {
                Toggle("잠시 멈추면 저절로 띄기", isOn: $settings.autoSpaceOnPauseEnabled)
            } footer: {
                Text("한글을 치다가 1초 동안 멈추면 한 칸 띄웁니다. 바로 뒤에 . , ? ! 를 치면 그 칸을 지우고 붙입니다. 백스페이스를 누르면 스페이스·엔터를 직접 치거나 추천 단어를 고를 때까지 쉽니다. 글 가운데와 이메일·주소·전화번호·비밀번호 입력란에서는 띄우지 않습니다.")
            }

            Section {
                Toggle("영문 문장 첫 글자 대문자", isOn: $settings.englishAutoCapitalizeEnabled)
                Toggle("영문 키 길게 눌러 대문자", isOn: $settings.englishLongPressUppercaseEnabled)
            } header: {
                Text("영문")
            } footer: {
                Text("문장 첫 글자 대문자를 켜면 문장이 시작될 때(빈 칸이거나 . ! ? 뒤) 시프트가 자동으로 켜집니다. 이메일·비밀번호처럼 대문자를 원하지 않는 입력란에서는 동작하지 않습니다. 길게 눌러 대문자는 시프트를 누르지 않고도 q~m 키를 꾹 눌러 대문자를 입력합니다.")
            }

            Section {
                Toggle("스페이스 드래그로 커서 이동", isOn: $settings.cursorMoveBySpaceDragEnabled)
                if settings.cursorMoveBySpaceDragEnabled {
                    Picker("연속 이동 속도", selection: $settings.cursorRepeatSpeed) {
                        Text("느림").tag(0)
                        Text("보통").tag(1)
                        Text("빠름").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("스페이스바를 길게 누른 채 드래그하면 커서가 좌우로 이동합니다. 바 양쪽 끝(15%)까지 밀고 유지하면 그 방향으로 연속 이동하며, 속도는 위에서 조절합니다.")
            }

            Section {
                Toggle("마지막 모드 기억", isOn: $settings.rememberLastKeyboardMode)
            } footer: {
                Text("키보드를 닫았다 다시 열 때 마지막으로 쓴 한글/영문 모드를 유지합니다. 끄면 항상 한글로 시작합니다.")
            }
        }
        .navigationTitle("입력 동작")
    }

    /// 앱이 지울 수 있는 파일(공유 컨테이너)은 바로 지우고, 키보드 쪽 파일은 토큰을 바꿔
    /// 키보드가 다음에 뜰 때 스스로 비우게 한다.
    private func resetPrediction() {
        PredictionStore.deleteAll()
        settings.predictionResetToken = UUID().uuidString
        didResetPrediction = true
    }
}

#Preview {
    NavigationStack {
        InputBehaviorSettingsView()
    }
}
