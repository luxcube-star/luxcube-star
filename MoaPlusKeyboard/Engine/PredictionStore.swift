import Foundation

/// 학습 데이터(`PredictionModel`)를 기기 안의 파일로 저장한다. 네트워크는 쓰지 않는다.
///
/// 저장 위치는 두 곳을 차례로 시도한다.
/// 1. App Group 공유 컨테이너 — 메인 앱이 "학습 데이터 지우기"로 직접 지울 수 있다.
///    키보드의 "전체 접근 허용"이 꺼져 있으면 키보드가 여기에 쓰지 못한다.
/// 2. 키보드 자신의 Application Support — 전체 접근 없이도 쓸 수 있는 곳.
///    메인 앱은 이 파일에 손댈 수 없으므로 지우기 요청은 `KeyboardSettings.predictionResetToken`
///    으로 전달하고, 토큰을 읽을 수 없는 환경에서는 추천 바에서 단어를 길게 눌러 지운다.
enum PredictionStore {
    static let fileName = "prediction-model.json"

    private static let ioQueue = DispatchQueue(label: "MoaPlus.PredictionStore", qos: .utility)

    /// App Group 컨테이너 안의 파일 위치. App Group 을 쓸 수 없으면 `nil`.
    static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.appGroupId)?
            .appendingPathComponent(fileName)
    }

    /// 이 프로세스 전용 Application Support 안의 파일 위치.
    static var localFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Prediction", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// 저장된 학습 데이터. 둘 다 있으면 더 많이 학습한(`tick` 이 큰) 쪽을 쓴다 —
    /// 전체 접근을 켰다 껐다 하면 두 곳에 따로 쌓일 수 있다.
    ///
    /// `isWritable` 이 `false` 면 로컬 파일은 있는데 읽지 못한 것이다(기기 보호 등). 이때
    /// 저장하면 빈 학습 데이터로 기존 파일을 덮어쓰게 되므로 호출하는 쪽은 저장을 건너뛰어야 한다.
    /// - 공유 파일을 못 읽는 것은 대개 "전체 접근 허용"이 꺼진 경우라 저장을 막지 않는다
    ///   (어차피 공유 쪽에는 쓰지 못하고 로컬에 쓴다).
    /// - 내용이 깨져 해석하지 못한 파일은 덮어써도 되므로 막지 않는다.
    static func load() -> (model: PredictionModel, isWritable: Bool) {
        var models: [PredictionModel] = []
        var isWritable = true
        for (url, isLocal) in [(sharedFileURL, false), (localFileURL, true)] {
            guard let url else { continue }
            switch read(url) {
            case .missing, .corrupted: break
            case .unreadable: if isLocal { isWritable = false }
            case .loaded(let model): models.append(model)
            }
        }
        return (models.max(by: { $0.tick < $1.tick }) ?? PredictionModel(), isWritable)
    }

    /// 백그라운드에서 저장한다. App Group 에 못 쓰면 로컬에 쓴다.
    static func save(_ model: PredictionModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        ioQueue.async {
            if let shared = sharedFileURL, write(data, to: shared) { return }
            if let local = localFileURL { _ = write(data, to: local) }
        }
    }

    /// 접근할 수 있는 저장 파일을 모두 지운다 (메인 앱의 "학습 데이터 지우기").
    /// 아직 키보드가 반영하지 않은 편집 요청도 함께 지운다 — 키보드는 지우기를 반영하며 편집 번호를
    /// 0 으로 돌리므로 다음 요청은 1 번부터 다시 쓴다.
    static func deleteAll() {
        for url in [sharedFileURL, localFileURL, editsFileURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 편집 요청 (메인 앱 「학습한 단어」 화면 → 키보드)

    static let editsFileName = "prediction-edits.json"

    /// 편집 요청 파일. 앱과 키보드가 함께 보는 App Group 에만 둔다 — 키보드의 "전체 접근 허용"이
    /// 꺼져 있으면 키보드가 읽지 못한다.
    static var editsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.appGroupId)?
            .appendingPathComponent(editsFileName)
    }

    /// 쌓인 편집 요청. 없거나 읽지 못하면 빈 배열.
    static func loadEdits() -> [PredictionEditRequest] {
        guard let url = editsFileURL,
              let data = try? Data(contentsOf: url),
              let edits = try? JSONDecoder().decode([PredictionEditRequest].self, from: data) else { return [] }
        return edits
    }

    /// 앱이 편집 요청 하나를 남긴다. 번호는 쌓인 요청과 키보드가 저장해 둔 반영 번호 중 큰 것 + 1.
    /// 키보드가 이미 반영해 저장한 요청은 이때 걸러 파일이 끝없이 커지지 않게 한다.
    /// - Returns: 저장했으면 `true` (App Group 을 쓸 수 없으면 `false`).
    @discardableResult
    static func appendEdit(_ edit: PredictionEdit) -> Bool {
        guard let url = editsFileURL else { return false }
        let applied: Int = {
            guard let shared = sharedFileURL, case .loaded(let model) = read(shared) else { return 0 }
            return model.appliedEditId
        }()
        var edits = loadEdits()
        let nextId = max(edits.map(\.id).max() ?? 0, applied) + 1
        edits.removeAll { $0.id <= applied }
        edits.append(PredictionEditRequest(id: nextId, edit: edit))
        guard let data = try? JSONEncoder().encode(edits) else { return false }
        return write(data, to: url)
    }

    private enum ReadResult {
        case missing
        case unreadable
        case corrupted
        case loaded(PredictionModel)
    }

    private static func read(_ url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let model = try? JSONDecoder().decode(PredictionModel.self, from: data),
              model.version <= PredictionModel.currentVersion else { return .corrupted }
        return .loaded(model)
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 학습 데이터는 개인 입력 기록이므로 기기를 켠 뒤 처음 잠금을 풀기 전에는
            // 읽을 수 없게 한다. 그 사이 읽기에 실패하면 `load()` 가 저장을 막는다.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
