# 팩터 DB 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: factor_db`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#factor_db` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 팩터 DB(월간 빌드 · 일간 DB · 신규 팩터 백필 — 데이터 갱신 [6a]~[6d])
- 일정: 데이터 갱신 안의 [6a]~[6d] 단계
- 코드: `02_Infrastructure/factor_db/factor_db_connector.R` · `02_Infrastructure/data/daily_refresh.sh`
- 감시 규칙:
- `build_gate` (log_patterns): 배출 회귀, 빌드 실패, 일간 DB stale

## 알려진 고장 형태 (기억 카드 · 실측)

- 일간 Factor DB(fdb_daily) 자동 재빌드는 기본 OFF — update_daily_fdb(ym) 미완 stub 이 전체 재빌드를 부른다(2026-06-10 검증). [6b] stale 경고는 설계상 남는다 — 소비 경로가 있는지가 영향 판단의 핵심.
- 소비자는 load_month_factors() 만(C15) · 커넥터 v2.5 파티션 캐시(무효화 키 = 월 파일명 · 크기 · mtime · 컬럼).
- [6a-gate] 배출 회귀 0 이 정상.

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
