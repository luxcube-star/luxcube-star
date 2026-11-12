import Foundation

// MARK: - 학습형 단어 추천 엔진
//
// 사용자가 실제로 입력을 끝낸 단어(스페이스·엔터·문장부호로 끝난 단어)를 **기기 안에서만**
// 학습해 두 가지를 추천한다.
//
// 1. 단어 완성: 입력 중인 단어의 앞부분으로 시작하는, 전에 쓴 단어
//    ("안녀" → "안녕하세요", "감정" → "감정평가서")
// 2. 다음 단어: 방금 끝낸 단어 뒤에 자주 이어 쓴 단어 ("감사" 뒤 스페이스 → "드립니다").
//    앞 두 단어가 맞는 것을 먼저 띄운다 ("확인 후" 뒤 → "연락드리겠습니다", 개선 방안 8번)
// 3. 구절: 띄어 쓴 2~4단어 묶음을 단어와 따로 배워, 첫 단어를 치는 중에 한 후보로 띄운다
//    ("수고" → "수고 많으셨습니다", 개선 방안 10번 넓힘 · 사용자 결정 2026-11-13: 4칸 중 2칸까지 · 2번 쓴 뒤)
//
// 한글은 **자모 단위**로 비교한다. 모아키는 받침을 다음 글자의 초성으로 옮기기 전에
// 한 번 앞 글자에 붙였다가 떼므로("가" + ㄴ → "간" → "가나"), 음절 단위로 비교하면
// "간" 이 "가나다" 의 앞부분으로 인정되지 않는다. 자모로 풀면 "ㄱㅏㄴ" 이 "ㄱㅏㄴㅏㄷㅏ"
// 의 앞부분이라 입력 도중에도 후보가 끊기지 않는다.
//
// 이 파일은 UIKit 에 의존하지 않는다 — 저장은 `PredictionStore`, 화면은 `PredictionBarView`.

/// 학습한 단어 하나의 통계.
struct PredictionWordEntry: Codable, Equatable {
    /// 지금까지 입력을 끝낸 횟수. 줄지 않는다 — "몇 번 써야 추천하나"(`minUsesToSuggest`)에 쓴다.
    var count: Int
    /// 마지막으로 쓴 시점. 실제 시각이 아니라 `PredictionModel.tick` 값이다 (시계를 안 써
    /// 테스트가 결정적이고, 기기 시간을 바꿔도 순서가 흐트러지지 않는다).
    var lastUsed: Int
    /// 순위 점수. `lastUsed` 시점의 값이며, 그 뒤로 다른 단어를 `PredictionEngine.halfLife` 개
    /// 배울 때마다 절반이 된다(`PredictionEngine.decayedScore`). 쓸 때마다 1 을 더한다.
    var score: Double

    init(count: Int, lastUsed: Int, score: Double? = nil) {
        self.count = count
        self.lastUsed = lastUsed
        self.score = score ?? Double(count)
    }

    private enum CodingKeys: String, CodingKey { case count, lastUsed, score }

    /// 판 1 파일에는 `score` 가 없다 — 쓴 횟수를 그대로 점수로 이어받는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.init(count: count,
                  lastUsed: try c.decodeIfPresent(Int.self, forKey: .lastUsed) ?? 0,
                  score: try c.decodeIfPresent(Double.self, forKey: .score))
    }
}

/// 추천이 실제로 도움이 됐는지 재는 숫자. 친 글은 담지 않는다. 개발자 리포트의 "단어 추천" 줄.
struct PredictionStats: Codable, Equatable {
    /// 추천 바에 후보가 새로 나타난 횟수.
    var shown: Int = 0
    /// 추천을 눌러 고른 횟수.
    var accepted: Int = 0
    /// 추천을 골라 직접 치지 않아도 된 글자 수 (고른 단어 글자 수 − 이미 친 글자 수).
    var savedCharacters: Int = 0

    init() {}

    private enum CodingKeys: String, CodingKey { case shown, accepted, savedCharacters }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shown = try c.decodeIfPresent(Int.self, forKey: .shown) ?? 0
        accepted = try c.decodeIfPresent(Int.self, forKey: .accepted) ?? 0
        savedCharacters = try c.decodeIfPresent(Int.self, forKey: .savedCharacters) ?? 0
    }
}

/// 디스크에 저장되는 학습 결과 전체.
///
/// 판 2 (2026-11): 단어별 감쇠 점수(`score`)와 효과 측정(`stats`)을 더했다. 판 1 파일도 읽는다 —
/// 모든 키를 `decodeIfPresent` 로 읽으므로 키가 하나 없다고 통째로 버려지지 않는다.
/// 판 3 (2026-11-12): 직접 넣은 단어(`manualWords`) · 편집 번호(`appliedEditId`) · 조사 증거(`stemEvidence`).
/// 판 4 (2026-11-13): 앞 두 단어(`trigrams`) · 구절(`phrases`) · 직접 넣은 구절(`manualPhrases`).
struct PredictionModel: Codable, Equatable {
    static let currentVersion = 4

    var version: Int = PredictionModel.currentVersion
    /// 표시용 원형(입력한 그대로) → 통계.
    var words: [String: PredictionWordEntry] = [:]
    /// 앞 단어(소문자 정규화) → 뒤 단어(원형) → 이어 쓴 횟수.
    var bigrams: [String: [String: Int]] = [:]
    /// 학습할 때마다 1씩 오르는 논리 시계.
    var tick: Int = 0
    /// 메인 앱의 "학습 데이터 지우기" 요청 중 마지막으로 반영한 것.
    /// `KeyboardSettings.predictionResetToken` 과 다르면 키보드가 학습 데이터를 비운다.
    var appliedResetToken: String = ""
    /// 효과 측정. 학습 데이터를 지우면 함께 0 이 된다.
    var stats = PredictionStats()
    /// 메인 앱 「학습한 단어」 화면에서 사용자가 직접 넣거나 고친 단어(소문자 정규형).
    /// 이 단어들은 저절로 배우기 규칙(`isLearnable`)과 상관없이 남고, 칠 때 숫자·기호까지 단어로 읽는다
    /// (사용자 결정 2026-11-12: 넣은 단어는 규칙 적용 안 함 · 숫자·기호는 넣은 단어만).
    var manualWords: Set<String> = []
    /// 메인 앱의 편집 요청(`PredictionEditRequest`) 중 마지막으로 반영한 번호.
    var appliedEditId: Int = 0
    /// 조사 나눠 배우기의 증거: 앞부분(소문자 정규형) → 그 뒤에 붙어 나온 조사들.
    /// 서로 다른 조사로 두 번 이상 나오면 앞부분을 단어로 친다 (`PredictionEngine.creditStem`).
    var stemEvidence: [String: [String]] = [:]
    /// 앞 두 단어(각각 소문자 정규형, 공백 하나로 이음) → 뒤 단어(원형) → 이어 쓴 횟수.
    var trigrams: [String: [String: Int]] = [:]
    /// 구절(원형, 단어 사이 공백 하나, 2~4단어) → 통계. 단어(`words`)와 따로 센다.
    var phrases: [String: PredictionWordEntry] = [:]
    /// 앱 「학습 내용」 화면에서 직접 넣거나 고친 구절(소문자 정규형).
    var manualPhrases: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, words, bigrams, tick, appliedResetToken, stats, manualWords, appliedEditId, stemEvidence
        case trigrams, phrases, manualPhrases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        words = try c.decodeIfPresent([String: PredictionWordEntry].self, forKey: .words) ?? [:]
        bigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .bigrams) ?? [:]
        tick = try c.decodeIfPresent(Int.self, forKey: .tick) ?? 0
        appliedResetToken = try c.decodeIfPresent(String.self, forKey: .appliedResetToken) ?? ""
        stats = try c.decodeIfPresent(PredictionStats.self, forKey: .stats) ?? PredictionStats()
        manualWords = try c.decodeIfPresent(Set<String>.self, forKey: .manualWords) ?? []
        appliedEditId = try c.decodeIfPresent(Int.self, forKey: .appliedEditId) ?? 0
        stemEvidence = try c.decodeIfPresent([String: [String]].self, forKey: .stemEvidence) ?? [:]
        trigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .trigrams) ?? [:]
        phrases = try c.decodeIfPresent([String: PredictionWordEntry].self, forKey: .phrases) ?? [:]
        manualPhrases = try c.decodeIfPresent(Set<String>.self, forKey: .manualPhrases) ?? []
    }
}

/// 메인 앱 「학습한 단어」 화면의 편집 하나.
///
/// 앱은 학습 파일을 직접 고치지 않는다 — 키보드는 학습 데이터를 메모리에 들고 있다가 통째로 덮어써
/// 앱이 고친 것이 지워지기 때문이다. 앱은 요청만 공유 폴더에 남기고(`PredictionStore.appendEdit`),
/// 키보드가 뜰 때 반영해 저장한다(`PredictionEngine.apply(edits:)`). "학습 데이터 지우기"의
/// `predictionResetToken` 과 같은 방식이다.
enum PredictionEdit: Codable, Equatable {
    /// 단어를 넣는다. 넣자마자 추천에 나온다(두 번 쓴 것으로 친다).
    case add(String)
    /// 단어를 잊는다 (추천 바에서 길게 누른 것과 같다).
    case delete(String)
    /// 단어 글자를 고친다. 쓴 횟수·순위·이어 쓴 짝을 이어받는다.
    case rename(from: String, to: String)
    /// 구절을 넣는다. 넣자마자 추천에 나온다.
    case addPhrase(String)
    /// 구절을 잊는다.
    case deletePhrase(String)
    /// 구절 글자를 고친다. 쓴 횟수 · 순위를 이어받는다.
    case renamePhrase(from: String, to: String)
}

struct PredictionEditRequest: Codable, Equatable {
    /// 1 부터 오르는 번호. 키보드는 `PredictionModel.appliedEditId` 보다 큰 것만 반영한다.
    var id: Int
    var edit: PredictionEdit
}

final class PredictionEngine {

    // MARK: Limits

    /// 기억할 최대 단어 수. 넘으면 오래되고 드물게 쓴 단어부터 정리한다.
    static let maxWords = 5000
    /// 한 단어 뒤에 기억할 다음 단어 수.
    static let maxNextWordsPerWord = 20
    /// 이보다 긴 토큰은 단어가 아니라 붙여넣은 문장·주소 등으로 보고 학습하지 않는다.
    static let maxWordLength = 30
    /// 추천 바에 보여 줄 후보 수. (사용자 결정 2026-11-13: 3 → 4, 칸 폭은 단어 길이에 맞춤 — `PredictionBarLayout`)
    static let defaultLimit = 4
    /// 이만큼 써 본 단어만 추천한다. 한 번 잘못 친 오타가 추천에 뜨지 않게 한다 — 배우기는
    /// 처음부터 하고 보여 주기만 미룬다 (Grammarly 키보드의 "trust-but-verify" 와 같은 생각).
    static let minUsesToSuggest = 2
    /// 반감기: 한 단어를 안 쓴 채 다른 단어를 이만큼 배우면 그 단어 점수가 절반이 된다.
    /// 시계가 아니라 친 단어 수로 세므로 며칠 쉬어도 잊지 않는다. (사용자 결정 2026-11-11: 3,000)
    static let halfLife: Double = 3000
    /// 구절은 몇 단어까지 (2~4).
    static let maxPhraseWords = 4
    /// 구절 전체 글자 수 상한 (띄어쓰기 포함).
    static let maxPhraseLength = 60
    /// 기억할 최대 구절 수. 넘으면 오래되고 드물게 쓴 구절부터 정리한다(직접 넣은 것은 남김).
    static let maxPhrases = 2000
    /// 추천 칸 중 구절이 쓸 수 있는 칸 수 (사용자 결정 2026-11-13: 2).
    static let maxPhraseSuggestions = 2
    /// 앞 두 단어 묶음 하나 뒤에 기억할 다음 단어 수.
    static let maxNextWordsPerPair = 10
    /// 기억할 앞 두 단어 묶음 수.
    static let maxWordPairs = 3000

    private(set) var model: PredictionModel

    /// 구절 → 비교용 키. 디스크에 저장하지 않는다.
    private var phraseKeyCache: [String: String] = [:]
    /// 구절 소문자 정규형 → 저장된 원형.
    private var phraseIndex: [String: String] = [:]

    /// 단어 → 비교용 키(자모 분해 + 소문자). 디스크에 저장하지 않고 메모리에서만 쓴다.
    private var keyCache: [String: String] = [:]
    /// 소문자 정규형 → 저장된 원형. 대소문자만 다른 단어를 찾을 때 전체를 훑지 않으려고 둔다.
    private var canonicalIndex: [String: String] = [:]

    init(model: PredictionModel = PredictionModel()) {
        var model = model
        // 판 1 에서는 배웠지만 지금 규칙으로는 배우지 않을 단어(낱자모가 든 "안ㄴ"·"ㅇㅋ" 등)를 비운다.
        // 사용자가 직접 넣은 단어는 남긴다.
        let manual = model.manualWords
        let unlearnable = model.words.keys.filter {
            !Self.isLearnable($0) && !manual.contains(Self.normalized($0))
        }
        if !unlearnable.isEmpty {
            let removed = Set(unlearnable)
            for word in removed { model.words.removeValue(forKey: word) }
            let removedNormalized = Set(removed.map(Self.normalized))
            var bigrams: [String: [String: Int]] = [:]
            for (from, next) in model.bigrams where !removedNormalized.contains(from) {
                let kept = next.filter { !removed.contains($0.key) }
                if !kept.isEmpty { bigrams[from] = kept }
            }
            model.bigrams = bigrams
        }
        let needsStemBackfill = model.version < 3
        let needsPhraseBackfill = model.version < 4
        model.version = PredictionModel.currentVersion
        self.model = model
        rebuildKeyCache()
        if needsStemBackfill { backfillStems() }
        if needsPhraseBackfill { backfillPhrases() }
    }

    /// 판 4 를 처음 읽을 때 한 번: 이미 기억한 단어 짝 중 두 번 넘게 이어 쓴 것을 두 단어 구절로 옮긴다.
    /// 단어 짝 횟수가 곧 그 두 단어를 띄어 이어 쓴 횟수라, 지난 기록에서도 구절 추천이 바로 나온다.
    private func backfillPhrases() {
        let tick = model.tick
        for (from, next) in model.bigrams {
            let head = canonicalIndex[from] ?? from
            for (word, n) in next where n >= Self.minUsesToSuggest {
                let phrase = head + " " + word
                guard phrase.count <= Self.maxPhraseLength, phraseIndex[Self.normalized(phrase)] == nil else { continue }
                model.phrases[phrase] = PredictionWordEntry(count: n, lastUsed: tick, score: Double(n))
                phraseKeyCache[phrase] = Self.matchKey(for: phrase)
                phraseIndex[Self.normalized(phrase)] = phrase
            }
        }
        prunePhrasesIfNeeded()
    }

    /// 판 3 을 처음 읽을 때 한 번: 이미 배운 조사 붙은 꼴("감정평가를" · "감정평가의")에서도 앞부분을 센다.
    /// 증거 규칙은 새로 배울 때와 같다(앞부분이 따로 있거나 조사가 두 가지 이상). 센 양은 조사 붙은 꼴들의
    /// 쓴 횟수 합 — 그때마다 앞부분도 한 번 쓴 것으로 치는 규칙(사용자 결정 1가)을 지난 기록에 적용한 것.
    private func backfillStems() {
        var groups: [String: (stem: String, josa: Set<String>, count: Int, score: Double, lastUsed: Int)] = [:]
        let tick = model.tick
        for (word, entry) in model.words {
            guard let (stem, josa) = Self.josaSplit(word) else { continue }
            let key = Self.normalized(stem)
            var g = groups[key] ?? (stem, [], 0, 0, 0)
            g.josa.insert(josa)
            g.count += entry.count
            g.score += Self.decayedScore(entry, at: tick)
            g.lastUsed = max(g.lastUsed, entry.lastUsed)
            groups[key] = g
        }
        for (key, g) in groups {
            model.stemEvidence[key] = g.josa.sorted()
            let stored = canonicalIndex[key] ?? g.stem
            let existing = model.words[stored]
            guard existing != nil || g.josa.count >= 2 else { continue }
            var entry = existing ?? PredictionWordEntry(count: 0, lastUsed: g.lastUsed, score: 0)
            entry.score = Self.decayedScore(entry, at: tick) + g.score
            entry.count += g.count
            entry.lastUsed = max(entry.lastUsed, g.lastUsed)
            model.words[stored] = entry
            keyCache[stored] = Self.matchKey(for: stored)
            canonicalIndex[key] = stored
        }
        pruneStemEvidenceIfNeeded()
    }

    // MARK: - Learning

    /// 입력을 끝낸 단어 하나를 학습한다. 학습했으면 `true`.
    ///
    /// - Parameters:
    ///   - word: 입력을 끝낸 단어 (구분자 제외)
    ///   - previous: 같은 문장에서 바로 앞에 쓴 단어. 없으면 `nil`
    ///   - precedingWords: 같은 문장에서 이 단어 앞에 띄어 쓴 단어들 (먼 것 → 가까운 것, 마지막 = `previous`).
    ///     앞 두 단어 · 구절을 배우는 데 쓴다. 비어 있으면 `previous` 하나만 있는 것으로 본다.
    @discardableResult
    func learn(word: String, previous: String?, precedingWords: [String] = []) -> Bool {
        guard Self.isLearnable(word) || isManual(word) else { return false }
        model.tick += 1

        let stored = canonicalForm(of: word)
        var entry = model.words[stored] ?? PredictionWordEntry(count: 0, lastUsed: model.tick, score: 0)
        entry.score = Self.decayedScore(entry, at: model.tick) + 1
        entry.count += 1
        entry.lastUsed = model.tick
        model.words[stored] = entry
        keyCache[stored] = Self.matchKey(for: stored)
        canonicalIndex[Self.normalized(stored)] = stored

        if let previous, Self.isLearnable(previous) || isManual(previous) {
            let from = Self.normalized(previous)
            var next = model.bigrams[from] ?? [:]
            next[stored, default: 0] += 1
            if next.count > Self.maxNextWordsPerWord,
               let weakest = next.min(by: { lhs, rhs in
                   lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
               }) {
                next.removeValue(forKey: weakest.key)
            }
            model.bigrams[from] = next
        }

        learnContext(of: stored, precedingWords: precedingWords.isEmpty ? [previous].compactMap { $0 } : precedingWords)
        creditStem(of: stored)
        pruneIfNeeded()
        return true
    }

    // MARK: - 앞 두 단어 · 구절 (개선 방안 8번 · 10번 넓힘, 2026-11-13 사용자 결정)

    /// 앞 단어들 가운데 배워도 되는 것만, 가까운 쪽부터 끊기지 않게 이어진 것 (먼 것 → 가까운 것, 3개까지).
    private func learnableChain(_ words: [String]) -> [String] {
        var chain: [String] = []
        for w in words.reversed() {
            guard chain.count < Self.maxPhraseWords - 1, Self.isLearnable(w) || isManual(w) else { break }
            chain.insert(canonicalForm(of: w), at: 0)
        }
        return chain
    }

    private func learnContext(of stored: String, precedingWords: [String]) {
        let chain = learnableChain(precedingWords)
        guard !chain.isEmpty else { return }

        if chain.count >= 2 {
            let pair = Self.pairKey(chain[chain.count - 2], chain[chain.count - 1])
            var next = model.trigrams[pair] ?? [:]
            next[stored, default: 0] += 1
            if next.count > Self.maxNextWordsPerPair,
               let weakest = next.min(by: { lhs, rhs in
                   lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
               }) {
                next.removeValue(forKey: weakest.key)
            }
            model.trigrams[pair] = next
            pruneWordPairsIfNeeded()
        }

        for n in 1...chain.count {
            let phrase = (chain.suffix(n) + [stored]).joined(separator: " ")
            guard phrase.count <= Self.maxPhraseLength else { break }
            bumpPhrase(phrase)
        }
        prunePhrasesIfNeeded()
    }

    private func bumpPhrase(_ phrase: String) {
        let key = Self.normalized(phrase)
        let stored = phraseIndex[key] ?? phrase
        var entry = model.phrases[stored] ?? PredictionWordEntry(count: 0, lastUsed: model.tick, score: 0)
        entry.score = Self.decayedScore(entry, at: model.tick) + 1
        entry.count += 1
        entry.lastUsed = model.tick
        model.phrases[stored] = entry
        phraseKeyCache[stored] = Self.matchKey(for: stored)
        phraseIndex[key] = stored
    }

    static func pairKey(_ first: String, _ second: String) -> String {
        normalized(first) + " " + normalized(second)
    }

    private func pruneWordPairsIfNeeded() {
        guard model.trigrams.count > Self.maxWordPairs else { return }
        let target = Self.maxWordPairs * 9 / 10
        let ranked = model.trigrams.sorted { lhs, rhs in
            let l = lhs.value.values.reduce(0, +), r = rhs.value.values.reduce(0, +)
            return l != r ? l < r : lhs.key < rhs.key
        }
        for (key, _) in ranked.prefix(model.trigrams.count - target) {
            model.trigrams.removeValue(forKey: key)
        }
    }

    private func prunePhrasesIfNeeded() {
        guard model.phrases.count > Self.maxPhrases else { return }
        let target = Self.maxPhrases * 9 / 10
        let tick = model.tick
        let ranked = model.phrases
            .filter { !model.manualPhrases.contains(Self.normalized($0.key)) }
            .sorted { lhs, rhs in
                let l = Self.decayedScore(lhs.value, at: tick), r = Self.decayedScore(rhs.value, at: tick)
                return l != r ? l < r : lhs.key < rhs.key
            }
        for (phrase, _) in ranked.prefix(max(0, model.phrases.count - target)) {
            removePhrase(stored: phrase)
        }
    }

    private func removePhrase(stored: String) {
        model.phrases.removeValue(forKey: stored)
        phraseKeyCache.removeValue(forKey: stored)
        let key = Self.normalized(stored)
        phraseIndex.removeValue(forKey: key)
        model.manualPhrases.remove(key)
    }

    /// 구절 하나를 잊는다 (추천 바에서 길게 누르거나 앱에서 지움).
    func forget(phrase: String) {
        let key = Self.normalized(Self.normalizedPhraseSpacing(phrase))
        if let stored = phraseIndex[key] { removePhrase(stored: stored) }
        model.manualPhrases.remove(key)
    }

    /// 사용자가 직접 넣거나 고친 구절인지.
    func isManualPhrase(_ phrase: String) -> Bool {
        model.manualPhrases.contains(Self.normalized(phrase))
    }

    /// 단어 사이 공백을 하나로 맞춘다.
    static func normalizedPhraseSpacing(_ phrase: String) -> String {
        phrase.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// 직접 넣을 수 없는 구절이면 그 까닭. 넣을 수 있으면 `nil`.
    static func phraseProblem(_ phrase: String) -> String? {
        let words = phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.isEmpty { return "구절을 입력해 주세요." }
        guard (2...maxPhraseWords).contains(words.count) else {
            return "두 단어에서 \(maxPhraseWords) 단어까지 넣을 수 있습니다. 단어 사이는 띄어 주세요."
        }
        if words.joined(separator: " ").count > maxPhraseLength { return "\(maxPhraseLength)자까지 넣을 수 있습니다." }
        for word in words {
            if let bad = word.first(where: { !isManualWordCharacter($0) }) {
                return "「\(bad)」는 구절 안에 넣을 수 없습니다. 문장부호(. , ? ! ; :)·괄호·따옴표는 단어가 끝났다는 신호로 쓰입니다."
            }
        }
        return nil
    }

    private func addManualPhrase(_ phrase: String) {
        guard Self.phraseProblem(phrase) == nil else { return }
        let spaced = Self.normalizedPhraseSpacing(phrase)
        let key = Self.normalized(spaced)
        let stored = phraseIndex[key] ?? spaced
        var entry = model.phrases[stored] ?? PredictionWordEntry(count: 0, lastUsed: model.tick, score: 0)
        entry.score = max(Self.decayedScore(entry, at: model.tick), Double(Self.minUsesToSuggest))
        entry.count = max(entry.count, Self.minUsesToSuggest)
        entry.lastUsed = model.tick
        model.phrases[stored] = entry
        phraseKeyCache[stored] = Self.matchKey(for: stored)
        phraseIndex[key] = stored
        model.manualPhrases.insert(key)
        prunePhrasesIfNeeded()
    }

    private func renamePhrase(from old: String, to new: String) {
        guard Self.phraseProblem(new) == nil,
              let oldStored = phraseIndex[Self.normalized(Self.normalizedPhraseSpacing(old))],
              let oldEntry = model.phrases[oldStored] else { return }
        let spaced = Self.normalizedPhraseSpacing(new)
        removePhrase(stored: oldStored)
        let newKey = Self.normalized(spaced)
        let newStored = phraseIndex[newKey] ?? spaced
        var entry = oldEntry
        if let existing = model.phrases[newStored] {
            let tick = model.tick
            entry.count += existing.count
            entry.score = Self.decayedScore(oldEntry, at: tick) + Self.decayedScore(existing, at: tick)
            entry.lastUsed = tick
        }
        model.phrases[newStored] = entry
        phraseKeyCache[newStored] = Self.matchKey(for: newStored)
        phraseIndex[newKey] = newStored
        model.manualPhrases.insert(newKey)
    }

    /// 앱 화면에 보여 줄 구절 목록 (원형, 쓴 횟수, 지금 순위 점수, 직접 넣었는지).
    var phraseList: [(phrase: String, count: Int, score: Double, isManual: Bool)] {
        let tick = model.tick
        return model.phrases.map { phrase, entry in
            (phrase, entry.count, Self.decayedScore(entry, at: tick), isManualPhrase(phrase))
        }
    }

    // MARK: - 조사 나눠 배우기 (개선 방안 6번, 2026-11-12 사용자 결정)
    //
    // "감정평가를" 을 쓰면 "감정평가를" 을 그대로 배우고, 앞부분 "감정평가" 도 한 번 쓴 것으로 센다(1가).
    // 잘못 나누지 않도록 — 조사 목록에 있는 것만 · 받침이 맞을 때만("나이" 는 나+이 아님) · 앞부분 두 글자
    // 이상 — 이고, 증거가 있을 때만 센다(2가): 앞부분을 따로 쓴 적이 있거나, 서로 다른 조사로 두 번 이상
    // 나왔을 때("감정평가를" · "감정평가의"). "고양이"(고양+이)처럼 우연히 조사 꼴로 끝나는 말을 거른다.
    // 앞부분을 고른 뒤 조사를 추천하는 일은 하지 않는다(3가).

    /// 받침이 있을 때만 붙는 조사 · 없을 때만 붙는 조사 · 어느 쪽에나 붙는 조사.
    /// "로" 는 받침 없거나 ㄹ 받침 뒤, "으로" 는 ㄹ 아닌 받침 뒤 (`josaFits`).
    static let josaAfterFinal: [String] = ["으로는", "이라도", "으로", "이나", "이랑", "을", "은", "이", "과"]
    static let josaAfterNoFinal: [String] = ["로는", "라도", "로", "나", "랑", "를", "는", "가", "와"]
    static let josaAny: [String] = [
        "에서는", "에게는", "에서", "에게", "에는", "에도", "께서", "한테", "까지", "부터", "보다", "처럼",
        "마다", "조차", "밖에", "하고", "의", "에", "께", "도", "만",
    ]
    /// 긴 조사부터 맞춘다 — "에서" 를 "에" 로 자르지 않게.
    private static let josaByLength: [String] =
        (josaAfterFinal + josaAfterNoFinal + josaAny).sorted { $0.count > $1.count }
    /// 증거로 기억할 앞부분 수. 넘으면 절반을 비운다.
    static let maxStemEvidence = 3000

    /// 조사가 붙은 꼴이면 (앞부분, 조사). 받침이 맞지 않거나 앞부분이 두 글자보다 짧으면 `nil`.
    /// 끝에 맞는 가장 긴 조사 하나만 본다 — 그것이 맞지 않으면 더 짧은 조사로 다시 자르지 않는다
    /// ("책이라도" 를 "책이" + 라도, "책으로" 를 "책으" + 로 로 자르지 않게).
    static func josaSplit(_ word: String) -> (stem: String, josa: String)? {
        guard let josa = josaByLength.first(where: { word.hasSuffix($0) }) else { return nil }
        let stem = String(word.dropLast(josa.count))
        guard stem.count >= 2, isLearnable(stem),
              let last = stem.unicodeScalars.last,
              (0xAC00...0xD7A3).contains(last.value) else { return nil }
        let final = Int(last.value - 0xAC00) % 28
        return josaFits(josa, final: final) ? (stem, josa) : nil
    }

    /// 앞 글자 받침(`final`, 0 = 없음, 8 = ㄹ)과 조사가 맞는지.
    private static func josaFits(_ josa: String, final: Int) -> Bool {
        let hasFinal = final != 0
        let isRieul = final == 8
        switch josa {
        case "로", "로는": return !hasFinal || isRieul
        case "으로", "으로는": return hasFinal && !isRieul
        default:
            if josaAfterFinal.contains(josa) { return hasFinal }
            if josaAfterNoFinal.contains(josa) { return !hasFinal }
            return true
        }
    }

    /// 방금 배운 단어가 조사 붙은 꼴이고 증거가 있으면 앞부분도 한 번 쓴 것으로 센다.
    private func creditStem(of word: String) {
        guard let (stem, josa) = Self.josaSplit(word) else { return }
        let key = Self.normalized(stem)
        var seen = model.stemEvidence[key] ?? []
        if !seen.contains(josa) {
            seen.append(josa)
            model.stemEvidence[key] = seen
        }
        let storedStem = canonicalForm(of: stem)
        guard model.words[storedStem] != nil || seen.count >= 2 else {
            pruneStemEvidenceIfNeeded()
            return
        }
        var entry = model.words[storedStem] ?? PredictionWordEntry(count: 0, lastUsed: model.tick, score: 0)
        entry.score = Self.decayedScore(entry, at: model.tick) + 1
        entry.count += 1
        entry.lastUsed = model.tick
        model.words[storedStem] = entry
        keyCache[storedStem] = Self.matchKey(for: storedStem)
        canonicalIndex[key] = storedStem
        pruneStemEvidenceIfNeeded()
    }

    private func pruneStemEvidenceIfNeeded() {
        guard model.stemEvidence.count > Self.maxStemEvidence else { return }
        // 이미 단어로 배운 앞부분은 증거가 더 필요 없으니 먼저 비우고, 그래도 많으면 절반을 비운다.
        model.stemEvidence = model.stemEvidence.filter { canonicalIndex[$0.key] == nil }
        if model.stemEvidence.count > Self.maxStemEvidence {
            let keep = Set(model.stemEvidence.keys.sorted().suffix(Self.maxStemEvidence / 2))
            model.stemEvidence = model.stemEvidence.filter { keep.contains($0.key) }
        }
    }

    /// 단어 하나를 완전히 잊는다 (추천 바에서 길게 눌러 삭제).
    func forget(word: String) {
        let key = Self.normalized(word)
        if let stored = canonicalIndex.removeValue(forKey: key) {
            model.words.removeValue(forKey: stored)
            keyCache.removeValue(forKey: stored)
            for (from, var next) in model.bigrams where next[stored] != nil {
                next.removeValue(forKey: stored)
                model.bigrams[from] = next.isEmpty ? nil : next
            }
        }
        model.bigrams.removeValue(forKey: key)
        // 앞 두 단어 · 구절에서도 지운다 — 오타로 지운 단어가 구절 후보로 남지 않게.
        for (pair, var next) in model.trigrams {
            if pair.split(separator: " ").contains(where: { String($0) == key }) {
                model.trigrams.removeValue(forKey: pair)
                continue
            }
            if next.keys.contains(where: { Self.normalized($0) == key }) {
                next = next.filter { Self.normalized($0.key) != key }
                model.trigrams[pair] = next.isEmpty ? nil : next
            }
        }
        for phrase in model.phrases.keys
        where !isManualPhrase(phrase) && phrase.split(separator: " ").contains(where: { Self.normalized(String($0)) == key }) {
            removePhrase(stored: phrase)
        }
        model.manualWords.remove(key)
        // 지운 단어가 조사 앞부분으로 곧바로 되살아나지 않게 증거도 지운다.
        model.stemEvidence.removeValue(forKey: key)
    }

    /// 학습 데이터를 모두 지운다. 마지막으로 반영한 초기화 토큰은 남긴다.
    /// 편집 번호(`appliedEditId`)는 0 으로 돌린다 — 앱이 지우기와 함께 편집 요청 파일도 지우므로
    /// 다음 요청은 1 번부터 다시 온다.
    func reset(appliedResetToken: String? = nil) {
        let token = appliedResetToken ?? model.appliedResetToken
        model = PredictionModel()
        model.appliedResetToken = token
        keyCache = [:]
        canonicalIndex = [:]
        phraseKeyCache = [:]
        phraseIndex = [:]
    }

    // MARK: - 직접 넣은 단어 (메인 앱 「학습한 단어」 화면)

    /// 사용자가 직접 넣거나 고친 단어인지.
    func isManual(_ word: String) -> Bool {
        model.manualWords.contains(Self.normalized(word))
    }

    /// 앱의 편집 요청 중 아직 반영하지 않은 것을 번호 순서대로 반영한다. 바뀐 게 있으면 `true`.
    @discardableResult
    func apply(edits: [PredictionEditRequest]) -> Bool {
        let pending = edits.filter { $0.id > model.appliedEditId }.sorted { $0.id < $1.id }
        guard let last = pending.last else { return false }
        for request in pending {
            switch request.edit {
            case .add(let word): addManual(word)
            case .delete(let word): forget(word: word)
            case .rename(let from, let to): rename(from: from, to: to)
            case .addPhrase(let phrase): addManualPhrase(phrase)
            case .deletePhrase(let phrase): forget(phrase: phrase)
            case .renamePhrase(let from, let to): renamePhrase(from: from, to: to)
            }
        }
        model.appliedEditId = last.id
        return true
    }

    /// 단어를 직접 넣는다. 이미 있으면 직접 넣은 단어로 표시하고, 추천에 나오도록 쓴 횟수를 채운다.
    private func addManual(_ word: String) {
        guard Self.manualWordProblem(word) == nil else { return }
        let stored = canonicalForm(of: word)
        var entry = model.words[stored] ?? PredictionWordEntry(count: 0, lastUsed: model.tick, score: 0)
        entry.score = max(Self.decayedScore(entry, at: model.tick), Double(Self.minUsesToSuggest))
        entry.count = max(entry.count, Self.minUsesToSuggest)
        entry.lastUsed = model.tick
        model.words[stored] = entry
        keyCache[stored] = Self.matchKey(for: stored)
        canonicalIndex[Self.normalized(stored)] = stored
        model.manualWords.insert(Self.normalized(stored))
        pruneIfNeeded()
    }

    /// 단어 글자를 고친다. 쓴 횟수·순위·이어 쓴 짝을 새 글자로 옮긴다. 새 글자가 이미 있으면 합친다.
    private func rename(from old: String, to new: String) {
        guard Self.manualWordProblem(new) == nil,
              let oldStored = canonicalIndex[Self.normalized(old)],
              let oldEntry = model.words[oldStored] else { return }
        let oldKey = Self.normalized(oldStored)
        let newKey = Self.normalized(new)

        // 1. 단어 통계: 옛 단어를 빼고 새 단어에 넣는다(있으면 합친다).
        model.words.removeValue(forKey: oldStored)
        keyCache.removeValue(forKey: oldStored)
        canonicalIndex.removeValue(forKey: oldKey)
        let newStored = canonicalIndex[newKey] ?? new
        var entry = oldEntry
        if let existing = model.words[newStored] {
            let tick = model.tick
            entry.count += existing.count
            entry.score = Self.decayedScore(oldEntry, at: tick) + Self.decayedScore(existing, at: tick)
            entry.lastUsed = tick
        }
        model.words[newStored] = entry
        keyCache[newStored] = Self.matchKey(for: newStored)
        canonicalIndex[newKey] = newStored

        // 2. 이어 쓴 짝: 뒤 단어 자리와 앞 단어 자리 모두 옮긴다.
        for (from, var next) in model.bigrams {
            guard let n = next.removeValue(forKey: oldStored) else { continue }
            next[newStored, default: 0] += n
            model.bigrams[from] = next
        }
        if oldKey != newKey, let moved = model.bigrams.removeValue(forKey: oldKey) {
            var merged = model.bigrams[newKey] ?? [:]
            for (word, n) in moved { merged[word, default: 0] += n }
            model.bigrams[newKey] = merged
        }

        // 3. 직접 고친 단어는 규칙과 상관없이 남긴다.
        model.manualWords.remove(oldKey)
        model.manualWords.insert(newKey)
    }

    /// 앱 화면에 보여 줄 단어 목록 (원형, 쓴 횟수, 지금 순위 점수, 직접 넣었는지).
    var wordList: [(word: String, count: Int, score: Double, isManual: Bool)] {
        let tick = model.tick
        return model.words.map { word, entry in
            (word, entry.count, Self.decayedScore(entry, at: tick), isManual(word))
        }
    }

    /// `word` 뒤에 이어 쓴 단어와 횟수 (많은 순).
    func followers(of word: String) -> [(word: String, count: Int)] {
        (model.bigrams[Self.normalized(word)] ?? [:])
            .map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    /// 직접 넣을 수 없는 단어면 그 까닭(화면에 그대로 보여 줌). 넣을 수 있으면 `nil`.
    static func manualWordProblem(_ word: String) -> String? {
        if word.isEmpty { return "단어를 입력해 주세요." }
        if word.count > maxWordLength { return "\(maxWordLength)자까지 넣을 수 있습니다." }
        if word.contains(where: { $0.isWhitespace }) {
            return "띄어쓰기는 넣을 수 없습니다. 한 단어씩 넣어 주세요."
        }
        if let bad = word.first(where: { !isManualWordCharacter($0) }) {
            return "「\(bad)」는 단어 안에 넣을 수 없습니다. 문장부호(. , ? ! ; :)·괄호·따옴표는 단어가 끝났다는 신호로 쓰입니다."
        }
        return nil
    }

    // MARK: - Stats (효과 측정)

    /// 추천 바에 후보가 새로 나타났다.
    func recordShown() {
        model.stats.shown += 1
    }

    /// 추천을 골랐다. `typed` = 그때까지 친 앞부분.
    func recordAccepted(word: String, typed: String) {
        model.stats.accepted += 1
        model.stats.savedCharacters += max(0, word.count - typed.count)
    }

    /// 지금 추천에 나올 수 있는 단어 수 (`minUsesToSuggest` 번 이상 쓴 단어).
    var suggestableWordCount: Int {
        model.words.values.reduce(0) { $0 + ($1.count >= Self.minUsesToSuggest ? 1 : 0) }
    }

    /// 개발자 리포트 한 줄. 숫자만 담고 단어는 담지 않는다.
    var diagnosticLine: String {
        let s = model.stats
        return "배운 단어 \(model.words.count)개(추천 가능 \(suggestableWordCount)개) / 구절 \(model.phrases.count)개 / 추천 보여 줌 \(s.shown)번 / 고름 \(s.accepted)번 / 아낀 글자 \(s.savedCharacters)자"
    }

    // MARK: - Suggestions

    /// 추천 후보.
    ///
    /// - `prefix` 가 비어 있으면(방금 스페이스를 친 상태) `previous` 뒤에 자주 쓴 단어.
    /// - 아니면 `prefix` 로 시작하는 단어. 같은 점수면 `previous` 뒤에 이어 쓴 적이 있는 쪽이 앞선다.
    ///
    /// 입력 중인 단어와 똑같은 단어는 후보에서 뺀다 — 눌러도 바뀌는 게 없다.
    ///
    /// `beforePrevious` = `previous` 바로 앞 단어. 둘 다 있으면 그 두 단어 뒤에 이어 쓴 단어를 먼저 띄운다.
    /// 입력 중인 단어로 시작하는 구절은 `maxPhraseSuggestions` 칸까지 단어 뒤에 붙인다.
    func suggestions(prefix: String, previous: String?, beforePrevious: String? = nil,
                     limit: Int = PredictionEngine.defaultLimit) -> [String] {
        guard limit > 0 else { return [] }
        let followers = previous.flatMap { model.bigrams[Self.normalized($0)] } ?? [:]
        let pairFollowers: [String: Int] = {
            guard let previous, let beforePrevious else { return [:] }
            return model.trigrams[Self.pairKey(beforePrevious, previous)] ?? [:]
        }()

        if prefix.isEmpty {
            func ranked(_ source: [String: Int], weight: Double) -> [String] {
                source
                    .compactMap { follower -> (String, Double)? in
                        guard let entry = model.words[follower.key],
                              entry.count >= Self.minUsesToSuggest else { return nil }
                        return (follower.key, Double(follower.value) * weight + freshness(of: entry))
                    }
                    .sorted(by: Self.byScoreThenWord)
                    .map { $0.0 }
            }
            var result: [String] = []
            for word in ranked(pairFollowers, weight: 1) + ranked(followers, weight: 1)
            where !result.contains(word) {
                result.append(word)
                if result.count == limit { break }
            }
            return result
        }

        // 문장부호 등 단어가 될 수 없는 글자가 끼어 있으면 추천하지 않는다.
        // 숫자·기호가 든 앞부분은 직접 넣은 단어만 후보로 삼는다.
        let manualOnly = !prefix.allSatisfy(Self.isWordCharacter)
        guard !manualOnly || prefix.allSatisfy(Self.isManualWordCharacter) else { return [] }
        let prefixKey = Self.matchKey(for: prefix)
        guard !prefixKey.isEmpty else { return [] }
        let typed = Self.normalized(prefix)

        var scored: [(String, Double)] = []
        for (word, entry) in model.words {
            guard entry.count >= Self.minUsesToSuggest,
                  !manualOnly || isManual(word),
                  let key = keyCache[word], key.count > prefixKey.count,
                  key.hasPrefix(prefixKey),
                  Self.normalized(word) != typed else { continue }
            let followBonus = Double(followers[word] ?? 0) * 3 + Double(pairFollowers[word] ?? 0) * 5
            scored.append((word, Self.decayedScore(entry, at: model.tick) + followBonus))
        }

        var phraseScored: [(String, Double)] = []
        for (phrase, entry) in model.phrases {
            guard entry.count >= Self.minUsesToSuggest,
                  !manualOnly || isManualPhrase(phrase),
                  let key = phraseKeyCache[phrase], key.count > prefixKey.count,
                  key.hasPrefix(prefixKey) else { continue }
            let followBonus = Double(followers[phrase.split(separator: " ").first.map(String.init) ?? ""] ?? 0)
            phraseScored.append((phrase, Self.decayedScore(entry, at: model.tick) + followBonus))
        }
        let phrases = phraseScored
            .sorted(by: Self.byScoreThenWord)
            .prefix(min(Self.maxPhraseSuggestions, limit))
        let words = scored
            .sorted(by: Self.byScoreThenWord)
            .prefix(limit - phrases.count)
        return (Array(words) + Array(phrases)).map { Self.matchingCase(of: $0.0, to: prefix) }
    }

    /// `rest` 끝에서부터 띄어 쓴 단어들을 거꾸로 읽는다 (먼 것 → 가까운 것, `max` 개까지).
    /// 문장부호 · 줄바꿈을 만나면 멈춘다 — 문장이 바뀌면 앞 단어로 치지 않는다.
    func precedingWords(in rest: Substring, max: Int) -> [String] {
        var words: [String] = []
        var rest = rest
        while words.count < max, let word = manualAwarePreviousWord(in: rest) {
            words.insert(word, at: 0)
            let gap = rest.reversed().prefix(while: { !Self.isManualWordCharacter($0) }).count
            rest = rest.dropLast(gap).dropLast(word.count)
        }
        return words
    }

    // MARK: - Context parsing (직접 넣은 단어까지 보는 판)
    //
    // 저절로 배우기는 지금처럼 글자만 단어로 읽는다(아래 static 판). 직접 넣은 단어에는 숫자·기호가
    // 들어갈 수 있으므로("3층", "A-4"), 넓게 읽은 토큰이 직접 넣은 단어(또는 그 앞부분)일 때만 넓은
    // 쪽을 쓴다. 그 밖에는 static 판과 결과가 같다 — 전화번호·인증번호는 여전히 배우지 않는다.

    /// 추천에 쓸 (앞 단어, 입력 중인 단어). 입력 중인 단어가 숫자·기호를 품은 직접 넣은 단어의
    /// 앞부분이면 그 넓은 토큰을, 아니면 `currentContext(in:)` 과 같다. 추천을 고를 때 지울 길이도 이것.
    func suggestionContext(in before: String) -> (previous: String?, current: String) {
        let narrow = Self.currentContext(in: before)
        let broad = Self.trailingToken(of: Substring(before), where: Self.isManualWordCharacter)
        guard broad.count > narrow.current.count, hasManualWord(withPrefix: broad) else { return narrow }
        let rest = before.dropLast(broad.count)
        return (manualAwarePreviousWord(in: rest), broad)
    }

    /// 방금 끝낸 단어. 넓게 읽은 토큰이 직접 넣은 단어면 그것을, 아니면 `completedWord(in:)` 과 같다.
    func completedWordConsideringManual(in before: String) -> (word: String, previous: String?, signature: String)? {
        if let last = before.last, !Self.isManualWordCharacter(last) {
            let trimmed = String(before.reversed().drop(while: { !Self.isManualWordCharacter($0) }).reversed())
            let broad = Self.trailingToken(of: Substring(trimmed), where: Self.isManualWordCharacter)
            if !broad.isEmpty, isManual(broad) {
                let rest = trimmed.dropLast(broad.count)
                return (broad, manualAwarePreviousWord(in: rest), trimmed)
            }
        }
        return Self.completedWord(in: before)
    }

    private func manualAwarePreviousWord(in rest: Substring) -> String? {
        let gap = rest.reversed().prefix(while: { !Self.isManualWordCharacter($0) })
        if !gap.isEmpty, gap.allSatisfy({ $0 == " " }) {
            let broad = Self.trailingToken(of: rest.dropLast(gap.count), where: Self.isManualWordCharacter)
            if !broad.isEmpty, isManual(broad) { return broad }
        }
        return Self.previousWord(in: rest)
    }

    private func hasManualWord(withPrefix prefix: String) -> Bool {
        let key = Self.matchKey(for: prefix)
        return model.manualWords.contains { manual in
            guard let stored = canonicalIndex[manual], let storedKey = keyCache[stored] else { return false }
            return storedKey.hasPrefix(key) && storedKey.count > key.count
        }
    }

    private static func trailingToken(of text: Substring, where isPart: (Character) -> Bool) -> String {
        String(text.reversed().prefix(while: isPart).reversed())
    }

    // MARK: - Context parsing

    /// 커서 앞 문맥에서 (앞 단어, 입력 중인 단어)를 뽑는다.
    ///
    /// - "오늘 감정" → ("오늘", "감정")
    /// - "오늘 감정 " → ("감정", "")  ← 다음 단어 추천 상태
    /// - "끝. 다음" → (nil, "다음")    ← 문장이 바뀌면 앞 단어로 치지 않는다
    static func currentContext(in before: String) -> (previous: String?, current: String) {
        let current = String(before.reversed().prefix(while: isWordCharacter).reversed())
        let rest = before.dropLast(current.count)
        return (previousWord(in: rest), current)
    }

    /// 방금 입력을 끝낸 단어. 문맥이 구분자(공백·문장부호)로 끝나지 않으면 `nil`.
    ///
    /// `signature` 는 이 단어까지의 문맥으로, 같은 단어를 두 번 학습하지 않는 데 쓴다
    /// ("안녕 " 에서 스페이스를 한 번 더 쳐 "안녕. " 이 돼도 둘 다 같은 서명이다).
    static func completedWord(in before: String) -> (word: String, previous: String?, signature: String)? {
        guard let last = before.last, !isWordCharacter(last) else { return nil }
        let trimmed = before.reversed().drop(while: { !isWordCharacter($0) }).reversed()
        let trimmedString = String(trimmed)
        let word = String(trimmedString.reversed().prefix(while: isWordCharacter).reversed())
        guard !word.isEmpty else { return nil }
        let rest = trimmedString.dropLast(word.count)
        return (word, previousWord(in: rest), trimmedString)
    }

    /// `rest` 끝의 단어. 사이에 공백만 있을 때만 앞 단어로 인정한다.
    fileprivate static func previousWord(in rest: Substring) -> String? {
        let gap = rest.reversed().prefix(while: { !isWordCharacter($0) })
        guard !gap.isEmpty, gap.allSatisfy({ $0 == " " }) else { return nil }
        let beforeGap = rest.dropLast(gap.count)
        let word = String(beforeGap.reversed().prefix(while: isWordCharacter).reversed())
        return word.isEmpty ? nil : word
    }

    // MARK: - Rules

    /// 직접 넣은 단어 안에 들어갈 수 있는 기호. 띄어쓰기와 문장부호(. , ? ! ; :)·괄호·따옴표는
    /// 단어가 끝났다는 신호(학습 · 저절로 띈 뒤 붙이기 · 단축어)로 쓰이므로 뺀다 (사용자 결정 2026-11-12).
    static let manualWordSymbols: Set<Character> = [
        "-", "_", "/", "&", "@", "#", "%", "+", "=", "*", "~", "^", "$", "|", "\\",
        "₩", "€", "£", "¥", "°", "·",
    ]

    /// 직접 넣은 단어를 이루는 글자: 단어 글자 + 숫자 + `manualWordSymbols`.
    static func isManualWordCharacter(_ character: Character) -> Bool {
        isWordCharacter(character) || character.isNumber || manualWordSymbols.contains(character)
    }

    /// 단어를 이루는 글자: 한글(음절·자모), 영문 등 문자와 아포스트로피(don't).
    /// 숫자는 단어로 치지 않는다 — 전화번호·카드번호·인증번호를 학습하지 않기 위해서다.
    static func isWordCharacter(_ character: Character) -> Bool {
        if character == "'" { return true }
        return character.isLetter
    }

    /// 학습해도 되는 단어인지.
    static func isLearnable(_ word: String) -> Bool {
        guard !word.isEmpty, word.count <= maxWordLength else { return false }
        guard word.allSatisfy(isWordCharacter) else { return false }
        // 천지인 조합 중 표시("ㅇㆍㆍ")는 완성된 글자가 아니다.
        guard !word.contains("ㆍ") else { return false }
        // 아포스트로피만 있는 토큰은 단어가 아니다.
        guard word.contains(where: { $0 != "'" }) else { return false }
        // 낱자모가 든 단어는 배우지 않는다 — "안ㄴ" 처럼 덜 끝난 글자가 섞인 오타와
        // "ㅇㅋ"·"ㅎㅎ" 처럼 자모만 쓴 말 둘 다 (사용자 결정 2026-11-11).
        guard !word.unicodeScalars.contains(where: isStandaloneJamo) else { return false }
        return true
    }

    /// 음절로 묶이지 않은 한글 자모 (호환 자모 U+3131–318E, 첫가끝 자모 U+1100–11FF).
    private static func isStandaloneJamo(_ scalar: Unicode.Scalar) -> Bool {
        (0x3131...0x318E).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
    }

    // MARK: - Helpers

    /// 영문은 대소문자를 구분하지 않고 한 단어로 센다. 저장 형태는 처음 학습한 철자를 따르되,
    /// 문장 첫머리 자동 대문자("Thanks")는 소문자 형태가 있으면 그쪽으로 합친다.
    private func canonicalForm(of word: String) -> String {
        canonicalIndex[Self.normalized(word)] ?? word
    }

    /// `tick` 시점의 점수: 마지막으로 쓴 뒤 배운 단어 수만큼 반감기로 줄인 값.
    static func decayedScore(_ entry: PredictionWordEntry, at tick: Int) -> Double {
        let age = Double(max(0, tick - entry.lastUsed))
        return entry.score * pow(0.5, age / halfLife)
    }

    /// 0~1. 방금 쓴 단어는 1, 반감기만큼 지나면 0.5. 다음 단어 후보의 동점 가르기에 쓴다.
    private func freshness(of entry: PredictionWordEntry) -> Double {
        let age = Double(max(0, model.tick - entry.lastUsed))
        return pow(0.5, age / Self.halfLife)
    }

    private static func byScoreThenWord(_ lhs: (String, Double), _ rhs: (String, Double)) -> Bool {
        lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0 < rhs.0
    }

    private func pruneIfNeeded() {
        guard model.words.count > Self.maxWords else { return }
        // 한 번에 10% 를 비워 매 학습마다 정렬하지 않게 한다.
        let target = Self.maxWords * 9 / 10
        let tick = model.tick
        let ranked = model.words.sorted { lhs, rhs in
            let l = Self.decayedScore(lhs.value, at: tick)
            let r = Self.decayedScore(rhs.value, at: tick)
            return l != r ? l < r : lhs.key < rhs.key
        }
        let removed = Set(ranked.prefix(model.words.count - target).map { $0.key })
        for word in removed {
            model.words.removeValue(forKey: word)
            keyCache.removeValue(forKey: word)
            canonicalIndex.removeValue(forKey: Self.normalized(word))
        }
        let removedNormalized = Set(removed.map(Self.normalized))
        var bigrams: [String: [String: Int]] = [:]
        for (from, next) in model.bigrams where !removedNormalized.contains(from) {
            let kept = next.filter { !removed.contains($0.key) }
            if !kept.isEmpty { bigrams[from] = kept }
        }
        model.bigrams = bigrams
        for (pair, next) in model.trigrams {
            let kept = next.filter { !removed.contains($0.key) }
            model.trigrams[pair] = kept.isEmpty ? nil : kept
        }
    }

    private func rebuildKeyCache() {
        phraseKeyCache = Dictionary(uniqueKeysWithValues: model.phrases.keys.map { ($0, Self.matchKey(for: $0)) })
        phraseIndex = Dictionary(model.phrases.keys.sorted().map { (Self.normalized($0), $0) },
                                 uniquingKeysWith: { first, _ in first })
        keyCache = Dictionary(uniqueKeysWithValues: model.words.keys.map { ($0, Self.matchKey(for: $0)) })
        // 저장 파일이 손으로 고쳐져 대소문자만 다른 단어가 둘 있어도 죽지 않게 먼저 것을 남긴다.
        canonicalIndex = Dictionary(model.words.keys.sorted().map { (Self.normalized($0), $0) },
                                    uniquingKeysWith: { first, _ in first })
    }

    static func normalized(_ word: String) -> String {
        word.lowercased()
    }

    /// 입력이 대문자로 시작하면 후보도 첫 글자를 대문자로 맞춘다 ("Th" → "Thanks").
    static func matchingCase(of word: String, to prefix: String) -> String {
        guard let first = prefix.first, first.isUppercase,
              let wordFirst = word.first, wordFirst.isLowercase else { return word }
        return wordFirst.uppercased() + word.dropFirst()
    }

    // MARK: - Hangul jamo key

    /// 비교용 키: 한글 음절은 자모로 풀고(겹받침·이중모음도 낱자로), 나머지는 소문자로.
    static func matchKey(for text: String) -> String {
        var result = ""
        result.unicodeScalars.reserveCapacity(text.unicodeScalars.count * 3)
        for scalar in text.lowercased().unicodeScalars {
            let value = scalar.value
            if value >= 0xAC00 && value <= 0xD7A3 {
                let index = Int(value - 0xAC00)
                let cho = index / (21 * 28)
                let jung = (index % (21 * 28)) / 28
                let jong = index % 28
                result += choseongJamo[cho]
                result += jungseongJamo[jung]
                result += jongseongJamo[jong]
            } else if let split = compatibilitySplit[Character(scalar)] {
                result += split
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 초성 19자 (호환 자모).
    private static let choseongJamo: [String] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 중성 21자. 이중모음은 낱자로 푼다 (ㅘ = ㅗㅏ).
    private static let jungseongJamo: [String] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ",
        "ㅗㅐ", "ㅗㅣ", "ㅛ", "ㅜ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅠ", "ㅡ", "ㅡㅣ",
        "ㅣ",
    ]

    /// 종성 28자(없음 포함). 겹받침은 낱자로 푼다 (ㄺ = ㄹㄱ).
    private static let jongseongJamo: [String] = [
        "", "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ",
        "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ", "ㄹㅍ", "ㄹㅎ", "ㅁ", "ㅂ", "ㅂㅅ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 단독으로 입력된 호환 자모 중 낱자로 풀어야 하는 것 (음절 분해와 같은 규칙).
    private static let compatibilitySplit: [Character: String] = [
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ",
        "ㄼ": "ㄹㅂ", "ㄽ": "ㄹㅅ", "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ",
        "ㅄ": "ㅂㅅ", "ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ",
        "ㅞ": "ㅜㅔ", "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ",
    ]
}
