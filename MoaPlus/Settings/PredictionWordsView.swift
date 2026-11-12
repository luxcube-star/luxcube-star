// PredictionWordsView.swift
// MoaPlus
//
// 「학습 내용」 — 단어 추천이 배운 단어와 구절을 따로 보고, 지우고, 고치고, 넣는다
// (새모아, 2026-11-12 사용자 결정 「학습한 단어」 → 2026-11-13 구절을 더하며 이름을 「학습 내용」으로).
//
// 앱은 학습 파일을 직접 고치지 않는다. 키보드가 학습 데이터를 메모리에 들고 있다가 통째로 덮어써서
// 앱이 고친 것이 지워지기 때문이다. 대신 편집 요청을 공유 폴더에 남기고(`PredictionStore.appendEdit`),
// 키보드가 다음에 뜰 때 반영한다. 화면은 저장된 학습 데이터에 아직 반영 안 된 요청까지 얹어 보여 준다.

import Combine
import SwiftUI

/// 화면에 보여 줄 학습 데이터. 저장된 학습 파일 + 아직 키보드가 반영하지 않은 편집 요청.
@MainActor
final class PredictionWordsModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let word: String
        let count: Int
        let score: Double
        let isManual: Bool
        var id: String { word }
    }

    /// 단어와 구절은 따로 배우고 따로 보여 준다 (사용자 결정 2026-11-13).
    enum Kind: String, CaseIterable, Identifiable {
        case word = "단어"
        case phrase = "구절"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case frequent = "많이 쓴 순"
        case alphabetical = "가나다 순"
        var id: String { rawValue }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var phraseRows: [Row] = []
    /// 공유 폴더에 학습 파일이 있는지. 없으면 키보드의 "전체 접근 허용"이 꺼져 있을 수 있다.
    @Published private(set) var hasSharedFile = false
    @Published private(set) var canWriteEdits = true

    private var engine = PredictionEngine()

    func reload() {
        let sharedURL = PredictionStore.sharedFileURL
        hasSharedFile = sharedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        canWriteEdits = PredictionStore.editsFileURL != nil
        engine = PredictionEngine(model: PredictionStore.load().model)
        engine.apply(edits: PredictionStore.loadEdits())
        refreshRows()
    }

    /// 편집을 요청으로 남기고, 화면에도 바로 반영한다. 남기지 못했으면 `false`.
    @discardableResult
    func perform(_ edit: PredictionEdit) -> Bool {
        guard PredictionStore.appendEdit(edit) else { return false }
        reload()
        return true
    }

    func followers(of word: String) -> [(word: String, count: Int)] {
        engine.followers(of: word)
    }

    func rows(of kind: Kind) -> [Row] {
        kind == .word ? rows : phraseRows
    }

    func sortedRows(_ kind: Kind, _ order: SortOrder, matching query: String) -> [Row] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let source = rows(of: kind)
        let filtered = trimmed.isEmpty ? source : source.filter {
            $0.word.localizedCaseInsensitiveContains(trimmed)
                || PredictionEngine.matchKey(for: $0.word).hasPrefix(PredictionEngine.matchKey(for: trimmed))
        }
        switch order {
        case .frequent:
            return filtered.sorted { $0.score != $1.score ? $0.score > $1.score : $0.word < $1.word }
        case .alphabetical:
            return filtered.sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending }
        }
    }

    private func refreshRows() {
        rows = engine.wordList.map { Row(word: $0.word, count: $0.count, score: $0.score, isManual: $0.isManual) }
        phraseRows = engine.phraseList.map { Row(word: $0.phrase, count: $0.count, score: $0.score, isManual: $0.isManual) }
    }
}

struct PredictionWordsView: View {
    @StateObject private var model = PredictionWordsModel()
    @State private var kind: PredictionWordsModel.Kind = .word
    @State private var order: PredictionWordsModel.SortOrder = .frequent
    @State private var query = ""
    @State private var isAdding = false
    @State private var newWord = ""
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                Picker("종류", selection: $kind) {
                    ForEach(PredictionWordsModel.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("순서", selection: $order) {
                    ForEach(PredictionWordsModel.SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(footerText)
            }

            let shown = model.sortedRows(kind, order, matching: query)
            let noun = kind.rawValue
            Section {
                if shown.isEmpty {
                    let subject = kind == .word ? "단어가" : "구절이"
                    Text(query.isEmpty ? "아직 배운 \(subject) 없습니다." : "찾는 \(subject) 없습니다.")
                        .foregroundColor(.secondary)
                }
                ForEach(shown) { row in
                    NavigationLink {
                        PredictionWordDetailView(model: model, word: row.word, kind: kind)
                    } label: {
                        HStack {
                            Text(row.word)
                            if row.isManual {
                                Text("직접 넣음")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(row.count)번")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let item = shown[index].word
                        model.perform(kind == .word ? .delete(item) : .deletePhrase(item))
                    }
                }
            } header: {
                Text("\(noun) \(model.rows(of: kind).count)개")
            }
        }
        .searchable(text: $query, prompt: "\(kind.rawValue) 찾기")
        .navigationTitle("학습 내용")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newWord = ""
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("\(kind.rawValue) 넣기")
                .disabled(!model.canWriteEdits)
            }
        }
        .alert("\(kind.rawValue) 넣기", isPresented: $isAdding) {
            TextField(kind.rawValue, text: $newWord)
            Button("넣기") { add() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(kind == .word
                 ? "넣자마자 추천에 나옵니다. 숫자와 - _ / & @ # 같은 기호도 넣을 수 있습니다."
                 : "두 단어에서 네 단어까지 띄어 써서 넣습니다(예: 수고 많으셨습니다). 첫 단어를 치면 바로 추천에 나옵니다.")
        }
        .alert("넣을 수 없습니다", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
        .onAppear { model.reload() }
    }

    private var footerText: String {
        var text = kind == .word
            ? "고친 것은 키보드를 한 번 내렸다 올리면 추천에 반영됩니다. 왼쪽으로 밀면 지우고, 누르면 고칠 수 있습니다. 모든 기록은 이 기기 안에만 있습니다."
            : "띄어 쓴 2~4단어 묶음입니다. 두 번 넘게 쓴 구절을 첫 단어를 칠 때 추천합니다(추천 칸 4개 중 2개까지). 왼쪽으로 밀면 지우고, 누르면 고칠 수 있습니다. 모든 기록은 이 기기 안에만 있습니다."
        if !model.hasSharedFile {
            text += "\n\n키보드의 학습 기록을 찾지 못했습니다. 키보드를 아직 안 썼거나 \"전체 접근 허용\"이 꺼져 있으면 여기에 보이지 않고, 고친 것도 키보드에 전달되지 않습니다."
        }
        return text
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        let reason = kind == .word ? PredictionEngine.manualWordProblem(word) : PredictionEngine.phraseProblem(word)
        if let reason {
            problem = reason
        } else if !model.perform(kind == .word ? .add(word) : .addPhrase(word)) {
            problem = "저장하지 못했습니다. 키보드의 \"전체 접근 허용\"을 켜 주세요."
        }
    }
}

/// 단어(구절) 하나: 글자 고치기 · 뒤에 자주 쓴 단어 보기(단어만) · 지우기.
struct PredictionWordDetailView: View {
    @ObservedObject var model: PredictionWordsModel
    let word: String
    var kind: PredictionWordsModel.Kind = .word
    @Environment(\.dismiss) private var dismiss
    @State private var editedWord = ""
    @State private var problem: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            Section {
                TextField(kind.rawValue, text: $editedWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("고친 글자로 바꾸기") { rename() }
                    .disabled(editedWord.trimmingCharacters(in: .whitespaces) == word)
            } header: {
                Text("글자 고치기")
            } footer: {
                Text(kind == .word
                     ? "쓴 횟수와 순위, 앞뒤로 이어 쓴 짝을 그대로 이어받습니다. 고친 단어가 이미 있으면 합칩니다."
                     : "쓴 횟수와 순위를 그대로 이어받습니다. 고친 구절이 이미 있으면 합칩니다.")
            }

            if kind == .word {
            Section {
                let next = model.followers(of: word)
                if next.isEmpty {
                    Text("아직 없습니다.").foregroundColor(.secondary)
                }
                ForEach(next, id: \.word) { item in
                    HStack {
                        Text(item.word)
                        Spacer()
                        Text("\(item.count)번").font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("「\(word)」 뒤에 자주 쓴 단어")
            } footer: {
                Text("띄어쓰기 바로 뒤에 추천하는 단어입니다.")
            }
            }

            Section {
                Button("이 \(kind.rawValue) 지우기", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(word)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { editedWord = word }
        .confirmationDialog("「\(word)」를 지울까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                if model.perform(kind == .word ? .delete(word) : .deletePhrase(word)) { dismiss() } else { problem = saveFailure }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("바꿀 수 없습니다", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private let saveFailure = "저장하지 못했습니다. 키보드의 \"전체 접근 허용\"을 켜 주세요."

    private func rename() {
        let target = editedWord.trimmingCharacters(in: .whitespaces)
        let reason = kind == .word ? PredictionEngine.manualWordProblem(target) : PredictionEngine.phraseProblem(target)
        if let reason {
            problem = reason
        } else if model.perform(kind == .word ? .rename(from: word, to: target) : .renamePhrase(from: word, to: target)) {
            dismiss()
        } else {
            problem = saveFailure
        }
    }
}

#Preview {
    NavigationStack {
        PredictionWordsView()
    }
}
