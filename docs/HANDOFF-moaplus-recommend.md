# 모아+ 추천 — 작업 인계 (2026-11-10)

## 저장소 / 브랜치
- `luxcube-star/luxcube-star`, 브랜치 `claude/moaplus-app-search-ko18nf`
- 원본: koh0001/moa-plus v2.2.6 (build 32, MIT) 전체 이력 위에 작업

## 추가한 기능
1. 학습형 단어 추천 바 (`MoaPlusKeyboard/Engine/PredictionEngine.swift`, `PredictionStore.swift`, `Views/PredictionBarView.swift`)
2. 이름: 기본 Info.plist `MoaPlus Recommend`, 한국어 `ko.lproj/InfoPlist.strings` = "모아+ 추천" (AltServer 가 한글 이름을 App ID 로 거절 — AltStore #1150)
3. 주황 아이콘
4. 긋기 미리보기: 완성 글자 크게, 위치 설정(기본 오른손=왼쪽 위), 기본 ON (`Models/GesturePreviewPosition.swift`)
5. App Group: AltServer 가 바꾼 ID(Info.plist `ALTAppGroups`)를 우선 사용 (`KeyboardSettings.appGroupId`)
6. 개발자 리포트에 App Group 진단 줄

## 빌드
- `.github/workflows/build-ipa.yml`: push 마다 macOS 러너에서 unsigned archive → **ad-hoc 서명으로 entitlements(App Group) 주입** → IPA 아티팩트 + 유닛 테스트
- 최신 IPA: run 42827220954, artifact 13769134396 (2026-12-10 만료)

## 사용자 환경
- iPhone 14 Pro Max, iOS 27.0.1, 오른손 입력
- 맥미니(집, 24시간, 유선 LAN), Xcode 미설치(사이트 운영 때문에 설치 꺼림) → GitHub 빌드 사용
- 무료 Apple 계정, AltServer(최신) 설치, AltStore 설치됨
- AltStore 앱 내 로그인: HTTP 503 실패 (AltStore #1842, 공식 수정 미배포) → 7일 자동 갱신 불가
- 설치 방법: 맥미니 AltServer **Option+클릭 › Sideload .ipa...** (무선 동작 확인)

## 현재 미해결
- 앱에서 바꾼 설정(클래식 레이아웃)이 키보드(카카오톡)에 반영 안 됨. 전체 접근 허용 ON.
  - 원인 추정: unsigned IPA 라 entitlements 없음 → AltServer 가 App Group 미부여. run 42827220954 IPA 에서 수정(빌드 로그로 entitlements 확인) — **기기 설치 결과 미확인**
  - 안 되면: 앱 › 설정 › 입력 기록 › 개발자 리포트의 "전체 접근", "App Group" 줄 확인
- 사용자가 말한 "그 밖의 오류 많음" — 구체 목록 아직 못 받음
- 7일마다 맥미니에서 재설치 필요 (AltStore 로그인 고쳐지기 전까지)
