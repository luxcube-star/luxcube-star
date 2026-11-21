---
tags: [모아플러스추천, 개발기록]
date: 2026-11-21
---
# 2026-11-21 모아+ 추천 AltServer 동기화

> 앞 기록: [[2026-11-20 모아+ 추천 처음 맞추기 자리 확인]] · 현황: [[00 모아+ 추천 개발 현황]]

1. 원모아가 앱스토어에 새 판을 올리면 할 일 여쭘 → 「원모아 새 코드 가져와 줘」 한마디면 Claude 가 차례대로 함: 새 커밋 확인 → 바뀐 것 · 겹치는 곳 보여 드림 → 구현해 → 테스트 → push 허락 → 빌드 → iCloud. 새모아 앱 ID 는 원모아와 같은 kr.koh0001.moa-plus. 앱스토어 원모아를 업데이트하면 AltStore 로 넣은 새모아가 영향을 받는지는 못 찾음. 찾은 것은 개인 블로그 한 건뿐(AltStore 가 앱 그룹 이름에 팀 ID 를 붙인다고 함), 공식 문서는 못 찾음
2. ★ 함정 (사용자가 알아냄): 맥미니와 아이폰이 동기화되어 있지 않으면 AltStore 가 새모아를 아이폰으로 가져오지 못하고 끊긴다. AltStore 공식 설치 안내에도 Finder 에서 그 기기의 「Wi-Fi 연결 시 이 iPhone 보기」를 켜라고 되어 있음. 오류 2003 「AltServer could not find this device」의 공식 해법도 Wi-Fi 동기화를 켜거나 케이블로 잇기
3. 바로잡음 (사용자): 케이블은 필요 없음 — 아이폰이 와이파이에 연결된 상태에서 맥미니 Finder 에서 동기화하면 된다(2번의 「케이블로 잇고」 안내는 지움 대상)
4. 추천 칸 수 검토(검색: Hunnicutt 2002 · AAC 5단어 ≈ 15단어 창 속도 같음 · Quinn·Zhai 2016 · Gboard 3개) → 사용자 결정 1가 · 2가: 4칸 그대로, 리포트 절약률을 본 뒤 다시 정함. 늘리고 싶은 까닭은 「원하는 단어가 칸에 안 뜸」 → 안 뜬 예를 받아 순위 쪽을 봄
5. 아이패드(원모아 사용 중) 기능행: 숫자패드 붙는 배치에서 엔터가 넓은 까닭 = 자음 칸은 화면 폭의 69%인데 엔터 폭은 화면 전체 기준 키 크기로 셈(FunctionRowView.returnWidth). 사용자 결정 1가 · 2가: 숫자패드 왼쪽 배치만 스페이스바 끝 = ㅊ 키 끝, 엔터는 ㅍ 왼쪽 끝 ~ 내림 키 앞. 오른쪽 배치는 그대로(같은 규칙이면 스페이스바 자리가 없음 — 사진 셈). 새모아를 아이패드에도 설치할 생각 → 구현해 대기
6. 아이패드용 앱을 따로 만들지 여쭘 → 새모아는 이미 아이폰 · 아이패드 겸용(TARGETED_DEVICE_FAMILY 1,2)이라 같은 ipa 로 아이패드에 설치됨. 따로 만들면 Bundle ID · App Group 을 새로 써야 하고, 무료 Apple ID 는 AltStore 로 7일에 App ID 10개 · 기기마다 앱 3개 한도(AltStore FAQ)
7. 사용자 결정 가(아이패드용 앱 따로 안 만듦 · 같은 새모아를 아이패드에) → 아이패드에 AltStore 설치 방법 안내(AltStore 공식 macOS 설치 안내 차례: 케이블 · 신뢰 → Finder Wi-Fi 칸 → AltServer 메뉴 Install AltStore → 아이패드 고름 → Apple ID 는 사용자가 직접 → 설정 › 일반 › VPN 및 기기 관리 신뢰 → 개발자 모드)
8. 케이블이 꼭 필요한지 여쭘 → Apple Mac 사용 설명서: Wi-Fi 동기화를 켜려면 처음 한 번은 케이블로 이은 뒤 「Wi-Fi 연결 시 이 기기 보기」를 켬. 이미 켜져 있어 Finder 옆 목록에 아이패드가 보이면 케이블 없이 진행
9. 아이패드 미니: 케이블로 맥미니에 이음 → AltStore 설치 → 신뢰 · 개발자 모드(재시동) → 새모아 설치 끝냄(사용자). 아이패드 판은 엔터 폭 고치기 전 판
10. 구현해 → 엔터 폭: KeyboardMetrics.iPadSplitReturnLeadingX(그리드 ㅍ 왼쪽 끝) · FunctionRowView.returnLeadingX/alignedReturnWidth/baseReturnWidth · KeyboardView 가 숫자패드 왼쪽일 때만 넘김. 테스트 FunctionRowWidthTests 2개 더함(iPad mini 가로 1133pt · 지구본/내림 키 4조합 · 긴 스페이스/기본). 맥미니에 Xcode 없어 컴파일 · 테스트는 GitHub Actions 로만. CLAUDE.md · CHANGELOG 적음
