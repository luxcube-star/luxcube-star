import Foundation

// MARK: - 학습형 단어 추천 엔진
//
// 사용자가 실제로 입력을 끝낸 단어(스페이스·엔터·문장부호로 끝난 단어)를 **기기 안에서만**
// 학습해 두 가지를 추천한다.
//
// 1. 단어 완성: 입력 중인 단어의 앞부분으로 시작하는, 전에 쓴 단어
//    ("안녀" → "안녕하세요", "감정" → "감정평가서")
// 2. 다음 단어: 방금 끝낸 단어 뒤에 자주 이어 쓴 단어 ("감사" 뒤 스페이스 → "드립니다")
//
// 한글은 **자모 단위**로 비교한다. 모아키는 받침을 다음 글자의 초성으로 옮기기 전에
// 한 번 앞 글자에 붙였다가 떼므로("가" + ㄴ → "간" → "가나"), 음절 단위로 비교하면
// "간" 이 "가나다" 의 앞부분으로 인정되지 않는다. 자모로 풀면 "ㄱㅏㄴ" 이 "ㄱㅏㄴㅏㄷㅏ"
// 의 앞부분이라 입력 도중에도 후보가 끊기지 않는다.
//
// 이 파일은 UIKit 에 의존하지 않는다 — 저장은 `PredictionStore`, 화면은 `PredictionBarView`.

/// 학습한 단어 하나의 통계.
struct PredictionWordEntry: Codable, Equatable {
    /// 지금까지 입력을 끝낸 횟수.
    var count: Int
    /// 마지막으로 쓴 시점. 실제 시각이 아니라 `PredictionModel.tick` 값이다 (시계를 안 써
    /// 테스트가 결정적이고, 기기 시간을 바꿔도 순서가 흐트러지지 않는다).
    var lastUsed: Int
}

/// 디스크에 저장되는 학습 결과 전체.
struct PredictionModel: Codable, Equatable {
    static let currentVersion = 1

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
}

final class PredictionEngine {

    // MARK: Limits

    /// 기억할 최대 단어 수. 넘으면 오래되고 드물게 쓴 단어부터 정리한다.
    static let maxWords = 5000
    /// 한 단어 뒤에 기억할 다음 단어 수.
    static let maxNextWordsPerWord = 20
    /// 이보다 긴 토큰은 단어가 아니라 붙여넣은 문장·주소 등으로 보고 학습하지 않는다.
    static let maxWordLength = 30
    /// 추천 바에 보여 줄 후보 수.
    static let defaultLimit = 3

    private(set) var model: PredictionModel

    /// 단어 → 비교용 키(자모 분해 + 소문자). 디스크에 저장하지 않고 메모리에서만 쓴다.
    private var keyCache: [String: String] = [:]
    /// 소문자 정규형 → 저장된 원형. 대소문자만 다른 단어를 찾을 때 전체를 훑지 않으려고 둔다.
    private var canonicalIndex: [String: String] = [:]

    init(model: PredictionModel = PredictionModel()) {
        self.model = model
        rebuildKeyCache()
    }

    // MARK: - Learning

    /// 입력을 끝낸 단어 하나를 학습한다. 학습했으면 `true`.
    ///
    /// - Parameters:
    ///   - word: 입력을 끝낸 단어 (구분자 제외)
    ///   - previous: 같은 문장에서 바로 앞에 쓴 단어. 없으면 `nil`
    @discardableResult
    func learn(word: String, previous: String?) -> Bool {
        guard Self.isLearnable(word) else { return false }
        model.tick += 1

        let stored = canonicalForm(of: word)
        var entry = model.words[stored] ?? PredictionWordEntry(count: 0, lastUsed: 0)
        entry.count += 1
        entry.lastUsed = model.tick
        model.words[stored] = entry
        keyCache[stored] = Self.matchKey(for: stored)
        canonicalIndex[Self.normalized(stored)] = stored

        if let previous, Self.isLearnable(previous) {
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

        pruneIfNeeded()
        return true
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
    }

    /// 학습 데이터를 모두 지운다. 마지막으로 반영한 초기화 토큰은 남긴다.
    func reset(appliedResetToken: String? = nil) {
        let token = appliedResetToken ?? model.appliedResetToken
        model = PredictionModel()
        model.appliedResetToken = token
        keyCache = [:]
        canonicalIndex = [:]
    }

    // MARK: - Suggestions

    /// 추천 후보.
    ///
    /// - `prefix` 가 비어 있으면(방금 스페이스를 친 상태) `previous` 뒤에 자주 쓴 단어.
    /// - 아니면 `prefix` 로 시작하는 단어. 같은 점수면 `previous` 뒤에 이어 쓴 적이 있는 쪽이 앞선다.
    ///
    /// 입력 중인 단어와 똑같은 단어는 후보에서 뺀다 — 눌러도 바뀌는 게 없다.
    func suggestions(prefix: String, previous: String?, limit: Int = PredictionEngine.defaultLimit) -> [String] {
        guard limit > 0 else { return [] }
        let followers = previous.flatMap { model.bigrams[Self.normalized($0)] } ?? [:]

        if prefix.isEmpty {
            return followers
                .compactMap { follower -> (String, Double)? in
                    guard model.words[follower.key] != nil else { return nil }
                    return (follower.key, Double(follower.value) + recencyBonus(for: follower.key))
                }
                .sorted(by: Self.byScoreThenWord)
                .prefix(limit)
                .map { $0.0 }
        }

        // 문장부호 등 단어가 될 수 없는 글자가 끼어 있으면 추천하지 않는다.
        guard prefix.allSatisfy(Self.isWordCharacter) else { return [] }
        let prefixKey = Self.matchKey(for: prefix)
        guard !prefixKey.isEmpty else { return [] }
        let typed = Self.normalized(prefix)

        var scored: [(String, Double)] = []
        for (word, entry) in model.words {
            guard let key = keyCache[word], key.count > prefixKey.count,
                  key.hasPrefix(prefixKey),
                  Self.normalized(word) != typed else { continue }
            let followBonus = Double(followers[word] ?? 0) * 3
            scored.append((word, Double(entry.count) + followBonus + recencyBonus(for: word)))
        }
        return scored
            .sorted(by: Self.byScoreThenWord)
            .prefix(limit)
            .map { Self.matchingCase(of: $0.0, to: prefix) }
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
    private static func previousWord(in rest: Substring) -> String? {
        let gap = rest.reversed().prefix(while: { !isWordCharacter($0) })
        guard !gap.isEmpty, gap.allSatisfy({ $0 == " " }) else { return nil }
        let beforeGap = rest.dropLast(gap.count)
        let word = String(beforeGap.reversed().prefix(while: isWordCharacter).reversed())
        return word.isEmpty ? nil : word
    }

    // MARK: - Rules

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
        return true
    }

    // MARK: - Helpers

    /// 영문은 대소문자를 구분하지 않고 한 단어로 센다. 저장 형태는 처음 학습한 철자를 따르되,
    /// 문장 첫머리 자동 대문자("Thanks")는 소문자 형태가 있으면 그쪽으로 합친다.
    private func canonicalForm(of word: String) -> String {
        canonicalIndex[Self.normalized(word)] ?? word
    }

    private func recencyBonus(for word: String) -> Double {
        guard let entry = model.words[word] else { return 0 }
        let age = Double(model.tick - entry.lastUsed)
        return max(0, 1 - age / 1000)
    }

    private static func byScoreThenWord(_ lhs: (String, Double), _ rhs: (String, Double)) -> Bool {
        lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0 < rhs.0
    }

    private func pruneIfNeeded() {
        guard model.words.count > Self.maxWords else { return }
        // 한 번에 10% 를 비워 매 학습마다 정렬하지 않게 한다.
        let target = Self.maxWords * 9 / 10
        let ranked = model.words.sorted { lhs, rhs in
            let l = Double(lhs.value.count) + recencyBonus(for: lhs.key) * 5
            let r = Double(rhs.value.count) + recencyBonus(for: rhs.key) * 5
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
    }

    private func rebuildKeyCache() {
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
