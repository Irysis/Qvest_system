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
- 필요 팩터만 필터 (15~20개). **288개 전체 로드 금지**.
- RAWDATA: `load_rawdata(use_cache=TRUE)` 한 번만

### data.table 키

`setkey(dt, Date, Ticker)` — merge 속도 10x 향상.

### 루프 내 parquet 반복 로드 절대 금지 (L-534)

### RAM / CPU

- RAM 80% 이하 유지
- R 프로세스 당 4 GB 이하
- CPU 80%+까지 병렬 활용 허용

## Factor DB 현황

- 월간 288 factor × 436 개월 (1990~2026.04, 5.1 GB Long)
- 일간 309 factor × 436 개월 (22 GB Wide, 프로덕션 승인)
- Registry 327개, 활용률 ~133/327
- 가용 cache: `.cache/factor_db/factor_db_YYYYMM.parquet` (월간) + `.cache/factor_db_daily/` (일간)

## 코딩 버그 패턴

- 한글 경로: `normalizePath()` 금지. `tryCatch(dirname(sys.frame(1)$ofile))` 사용
- RAWDATA 컬럼: `Vol` (NOT Volume), `Size`, `Ret`, `Close`, `Open`, `High`, `Low`, `BM_Ret`, `Ticker`
- 함수 시그니처: `commission` (NOT tc_bps), `buffer_zone=list(keep_n, entry_n)`
- VT/DD/FM lag: t-1 데이터 필수 (same-day circular = SR 25~50% 과대추정)
- MRS/FRED 시차: 1일 lag 또는 expanding percentile (L-441/450, C11)

## 참조

- `02_Infrastructure/factor_db/factor_db_connector.R` (load_month_factors)
- `02_Infrastructure/factor_db/load_rawdata.R`
- `infrastructure_state.md` (구체적 코딩 패턴 + L-code 누적)
