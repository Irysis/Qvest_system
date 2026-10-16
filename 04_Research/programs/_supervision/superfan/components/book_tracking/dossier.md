# BOOK 트래킹 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: book_tracking`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#book_tracking` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: BOOK 트래킹(아침 체인 nolayer4 일별 평가 · /book)
- 일정: 아침 체인 [3b] 평일
- 코드: `02_Infrastructure/monitoring/mark_nolayer4_daily.R` · `02_Infrastructure/book/book_registry.R`
- 감시 규칙:
- `mtm_errors` (log_patterns): 일별 평가 건너뜀, 일별 평가 실패
- `mtm_fresh` (freshness): ~/AppData/Local/Temp/qm_morning.log

## 알려진 고장 형태 (기억 카드 · 실측)

- BOOK 일별 YTD 가 8월부터 MTD 였다 — 레인 이관 때 빈 원장(기억 카드 project-book-ytd-was-mtd-after-lane-migration-20261007).
- BOOK_0001 은 MSM C1 봉쇄(PIT-C1-MSM-PARAMS — 도훈 10-15 안 A 결정 · 수리 진행 예정) — 전진 트래킹은 계속, 과거 이력 인용 금지.

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
