# Factor DB + Forge 자원 활용 규칙

**Session 40 추가 (C13~C15) / Session 75 v6.4 rule 분리**

## C13~C15 (PIT)

| Code | 위반 패턴 |
|---|---|
| **C13** | NEGATE_FACTORS / FLIP_SIGN 절대 금지. Z_Score_Aligned only |
| **C14** | IC 접근 시 Usable_Date <= sig_date만 허용 |
| **C15** | Factor DB parquet 직접 load 금지. 월간 = `load_month_factors()` / 일간(fdb_daily) = `load_daily_factors()` 경유 (2026-07-25 carve-out 해소) |

**일간 접근자** (`load_daily_factors(ym | date_range, factors=NULL, align_direction=TRUE)`, connector v2.3): `.cache/factor_db_daily/fdb_daily_YYYYMM.parquet` 관문 — Arrow dataset pushdown(요청 월만·전체 441파일 스캔 금지) + C13 방향정렬(월간 ic_sign 경로 재사용 — 일간 IC 패널은 Usable_Date 부재로 방향추론 불가, 한계 문서화) + PIT `Date <= 요청 상한` 하드 강제. 값 semantics = **winsorized raw (z-score 아님)** — 횡단면 표준화는 caller 책임. ⚠ 증분 갱신월의 누산계열 팩터(R13_NCSKEW 등)는 bit-parity 미보장(rank 290/298 보존 — memory project-fdb-daily-incremental-parity).

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

- `02_Infrastructure/factor_db/factor_db_connector.R` (load_month_factors / load_daily_factors)
- `02_Infrastructure/backtest_harness.R` (load_rawdata 정의 — 2026-06-10 링크 정정)
- `infrastructure_state.md` (구체적 코딩 패턴 + L-code 누적)

## 변경 이력

- **2026-07-25**: `load_daily_factors()` 신설 (AST v1.1 §3 불변식 ⑥ — fdb_daily C15 carve-out 해소). C15 행에 일간 관문 병기 + 일간 접근자 절 추가. 실측: 202606+202607 90,389행 x 316팩터 / 월말 대조 M01 pearson 0.9987·spearman 0.9952 (차이 = 일간 winsorize cap + 월간 Raw_Value 미캡 — 정의 차이 문서화).
- **2026-06-10**: "Factor DB 현황" 실측 전면 갱신 — 모집단 5종 구분 (등록 373 / 월간 수록 342·최신월 315 / 일간 수록 304 / census 327 / curated ~94). 구 stale 수치(월간·일간 팩터 수, "활용률" 표기) 전부 제거. 2026-06-10 Z 재계산(winsorize 1/99) — Raw_Value/Rank_Pct 불변, 가역 (트랙 A — 본 rule의 게이트·PIT 규칙과 무관).

## IC 완결 판정 (C14 연계 — 2026-07-26 강화)

`factor_ic_monthly`의 IC[t]는 pair (factor_db[t], factor_db[t+1])의 forward return으로 산출되므로, **t+1 파일이 그 달을 끝까지 담았을 때만 완결**이다. `compute_all_factor_ic_monthly()`의 incomplete-terminal-pair guard는 2조건 OR로 skip한다:

1. **달력 미종료** — `sig_d_t1`의 달력 말일 > 오늘 (진행 중인 달)
2. **파일 미도달** (2026-07-26 신설) — `sig_d_t1` < 그 달 RAWDATA 최종 거래일 (월말 재빌드 지연·실패)

조건 2가 없으면 "달력은 넘었는데 factor_db 월말 재빌드가 안 된" 상태에서 **부분월 forward return IC가 완결로 기록**되고 `Usable_Date`도 과소 기록된다(예: 6/30 sig의 IC가 7/24까지만 반영된 채 확정). 검사 대상은 "그 달이 끝났나"가 아니라 "이 파일이 그 달을 끝까지 담았나"다.

- RAWDATA 자체가 스테일한 경우는 이 guard의 책임 밖 — `cache_freshness_audit`가 담당(책임 분리).
- 실무 함의: 월간 IC 프론티어는 **직전 완결월**이며, 당월 진행 중에는 전월 IC가 최신이다. 월말 cron이 factor_db 월말 빌드 → IC 갱신 순으로 자동 처리한다.

**판정부 소재 (단일 정본, 2026-07-26)** — 인라인 중복 금지:

| 역할 | 위치 |
|---|---|
| 판정 순수 함수 | `02_Infrastructure/factor_db/ic_pair_completeness.R::.ic_pair_complete(sig_d_t1, today, raw_month_last)` |
| 소비 (빌더) | `factor_db_builder.R::compute_all_factor_ic_monthly()` — source 후 호출 1곳 |
| 소비 (감시) | `02_Infrastructure/data/ic_frontier_check.R` — 전용 env 위임(`.ICFC_GUARD`), **전역 이름 미생성** |
| 상설 검사 | `08_Tests/factor_db/test_ic_completion_guard.R` (23건, `run_all_hooks.sh` SUITES 편입) |

⚠ 미러 구현 금지 — 같은 이름(`.ic_pair_complete`)을 다른 시그니처로 두 파일이 정의하면 한 세션에 둘 다 source될 때 나중 것이 이긴다. 2026-07-26 실측: 빌더→감시 순이면 pair 전건이 `unused argument`로 tryCatch에 삼켜져 IC 전량 skip, 감시→빌더 순이면 `guard_agrees`가 항상 FALSE(조용한 오판정). 소비처는 정본을 **위임 호출**만 한다.

## IC 월-프론티어 감시 (2026-07-26 신설)

신선도 축(`Usable_Date` 캘린더 lag ≤ 40일)은 "며칠 지났나"만 재므로, 월말 재빌드 체인(cron → factor_db 월말 스냅샷 → `compute_all_factor_ic_monthly`)이 통째로 실패해도 최대 ~5주간 FRESH로 통과한다. `ic_frontier_check()`가 같은 registry 엔트리에 **"산출 가능한 월을 다 산출했나"** 축을 `::frontier` 결과 1건으로 덧붙인다(소비: `cache_freshness_audit`).

- 판정 operand = guard와 동일(달력 종료 · 그달 RAWDATA 최종 거래일)을 역방향으로 푼 기대 프론티어. 당월 진행 중 전월 IC가 최신인 상태는 `IC_FRONTIER_CURRENT`(OK) — 오탐 아님.
- `IC_FRONTIER_LAG` 1개월=WARN / 2개월+=CRITICAL, 산출가능일 +`grace_days`(기본 3) 이내는 OK. 기대보다 앞서면 `IC_FRONTIER_AHEAD`(WARN — 부분월 pair 기록 의심).
- 실측(2026-07-26): IC max Date 2026-05-29 / 기대 2026-05 → CURRENT·OK, `guard_agrees=TRUE`. 위반 주입(IC를 2026-03로 강제) → CRITICAL 발화 확인.

## factor_db 디렉토리 신선도 = 내용 축 (2026-07-26 수리, P2-02)

`cache_registry.json`의 `.cache/factor_db/`는 `date_col` 미선언이라 **파일명 YYYYMM의 월말**로 lag를 추정했다 — `data_lag = max(0, today − 월말)`이므로 **당월 내내 0/FRESH**였고, 파일 내용을 한 번도 열지 않았다. 실사고: `factor_db_202607`이 `Date=2026-07-03`에 3주 동결된 동안 감사는 매일 FRESH를 보고했다(D2 주간 리프레시가 필요했던 이유 자체가 이 침묵).

- 수리 = registry에 **`date_col: "Date"` 선언**(코드 무변경). 디렉토리형 집계 규약 = `file_pattern` 매칭 **사전순 max 파일 1개**의 `max(date_col)`.
- **`max_lag_days` 40 → 14 동반 조정**: 40은 '파일명-월말' 축에서 "한 달 이상 미빌드"를 잡으려던 값이라 내용 축에는 과대(내용 lag은 RAWDATA를 따라 매일 움직임). 14의 실측 근거 = (a) 직전 14개 완료월 전부 content max == 그 달 최종 거래일(shortfall 0d), (b) 월-전환 구간 최대 lag ~10d. D2 강제 재빌드(7d 초과 지연 시 force)와 정합.
- `date_col` 미선언 디렉토리는 이제 조용히 OK가 아니라 `FILENAME_ESTIMATE_ONLY/WARN` 표기. 내부 월의 구멍(D형)은 이 축 소관 아님 — **`.fdb_gap_months()`(P2-04)는 미수리**로 남아 있다(존재→완비 대리판정 + max 이전 구멍 불가시).
- 실측(2026-07-26 21:00): `.cache/factor_db/` `data_lag=2`(수리 전 구조상 0). 상설 검사 = `08_Tests/data/test_cache_content_reach.R` E3.

## build_hash 계약 (2026-07-26 수리)

`.cache/factor_db/build_hash.txt` 1행 = `<YYYYMMDDHHMMSS>_<rev>`. 소비자는 전부 n=1 읽기.

- `rev` ∈ {`<gitshort>`, `<gitshort>-dirty`, `nogit<8hex 코드 다이제스트>`, `hashfail`}. git이 아닐 때만 2행에 진단(`# rev_source=… reason=…`)이 붙고 **경고를 동반**한다.
- 구 구현은 `system(intern=TRUE)` 실패가 *warning*으로만 나 `tryCatch(error=)`가 못 잡았고 `ignore.stderr=TRUE`가 사유를 버려, 2026-07-25 전기간 재빌드 440 write 중 **415건이 `_unknown`**이었다. rev는 '쓰는 시점'이 아니라 **코드를 읽은 시점(source)** 에 1회 확정한다(빌드 중 auto-commit이 HEAD를 움직여 rev가 갈리던 오귀속 제거).
- 상설 검사: `08_Tests/factor_db/test_build_hash_provenance.R` (17건, SUITES 편입).
