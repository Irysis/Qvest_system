# Factor DB + Forge 자원 활용 규칙

**Session 40 추가 (C13~C15) / Session 75 v6.4 rule 분리**

## C13~C15 (PIT)

| Code | 위반 패턴 |
|---|---|
| **C13** | NEGATE_FACTORS / FLIP_SIGN 절대 금지. Z_Score_Aligned only |
| **C14** | IC 접근 시 Usable_Date <= sig_date만 허용 |
| **C15** | Factor DB parquet 직접 load 금지. `load_month_factors()` 경유 |

## Forge 자원 활용 (컴퓨팅 최적화)

### 한 번만 로드 + 메모리 캐싱

- Factor DB parquet은 **rbindlist once pattern**
- 필요 팩터만 필터 (15~20개). **수록 342개 전체 로드 금지**.
- RAWDATA: `load_rawdata(use_cache=TRUE)` 한 번만

### data.table 키

`setkey(dt, Date, Ticker)` — merge 속도 10x 향상.

### 루프 내 parquet 반복 로드 절대 금지 (L-534)

### RAM / CPU

- RAM 80% 이하 유지
- R 프로세스 당 4 GB 이하
- CPU 80%+까지 병렬 활용 허용

## Factor DB 현황 (실측 2026-06-10 — 모집단 구분 필수)

5개 숫자는 **서로 다른 모집단**이므로 혼용 금지:

| 모집단 | 수치 | 정의 |
|---|---|---|
| **등록 (registry)** | 373 | `02_Infrastructure/factor_db/factor_registry.json` 등재 수 (+2 = AC14_Discretionary_Accruals · XF_Q06_Op_Margin 2026-06-10 등재 진행 중) |
| **월간 수록** | 342 (최신월 315) | 월간 parquet에 실재하는 distinct Factor_Name. 437파일 199001~202605, Long 스키마 (Date/Ticker/Factor_Name/Raw_Value/Z_Score/Z_Sector/Rank_Pct/Coverage) |
| **일간 수록** | 304 | 일간 parquet 수록 팩터. 437파일 ~202605, Wide |
| **census 측정가능** | 327 | IC 산출 가능 팩터 (`factor_ic_monthly.parquet` 기준) |
| **현행 curated 실사용** | ~94 | 현행 전략·파이프라인이 실제 소비하는 curated 팩터 |

- 용량: 월간 9.1 GB / 일간 21.6 GB — **2026-06-10 전 파일 로컬 수화 + OneDrive 핀 고정 완료**
- IC: `factor_ic_monthly.parquet` 327팩터, 1990~2026-04 (Usable_Date 2026-05-31, 2026-06-10 재산출)
- 가용 cache: `.cache/factor_db/factor_db_YYYYMM.parquet` (월간) + `.cache/factor_db_daily/` (일간)

## 코딩 버그 패턴

- 한글 경로: `normalizePath()` 금지. `tryCatch(dirname(sys.frame(1)$ofile))` 사용
- RAWDATA 컬럼: `Vol` (NOT Volume), `Size`, `Ret`, `Close`, `Open`, `High`, `Low`, `BM_Ret`, `Ticker`
- 함수 시그니처: `commission` (NOT tc_bps), `buffer_zone=list(keep_n, entry_n)`
- VT/DD/FM lag: t-1 데이터 필수 (same-day circular = SR 25~50% 과대추정)
- MRS/FRED 시차: 1일 lag 또는 expanding percentile (L-441/450, C11)

## 참조

- `02_Infrastructure/factor_db/factor_db_connector.R` (load_month_factors)
- `02_Infrastructure/backtest_harness.R` (load_rawdata 정의 — 2026-06-10 링크 정정)
- `infrastructure_state.md` (구체적 코딩 패턴 + L-code 누적)

## 변경 이력

- **2026-06-10**: "Factor DB 현황" 실측 전면 갱신 — 모집단 5종 구분 (등록 373 / 월간 수록 342·최신월 315 / 일간 수록 304 / census 327 / curated ~94). 구 stale 수치(월간·일간 팩터 수, "활용률" 표기) 전부 제거. 2026-06-10 Z 재계산(winsorize 1/99) — Raw_Value/Rank_Pct 불변, 가역 (트랙 A — 본 rule의 게이트·PIT 규칙과 무관).
