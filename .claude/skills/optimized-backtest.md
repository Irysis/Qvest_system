---
name: optimized-backtest
description: "최적화 백테스팅 코드 작성 스킬 (v8.x 계약 정합). 성능: Rcpp + data.table + arrow + 병렬/메모리. 측정: build_bt_result() 계약 + essence_score() 등급 의무 (summarise_perf/hurdle_gate은 진단용). Forge / lean-forge 전용."
---

## 최적화 백테스팅 코드 작성 가이드

연구용 백테스트 R 코드 작성 시 반드시 아래 최적화를 적용한다.

### ⭐ 측정 권위 (Level 0 — v8.x 계약, 2026-05-31)

**성능 최적화(아래 원칙 0~6)와 측정 무결성을 분리하라.** 성과·등급 산출은 **반드시 계약 경유**:
- 성과 = **`02_Infrastructure/contracts/build_bt_result()`** (10-component, NW lag-3 PORT_t, audit). `summarise_perf()` 등 legacy 손계산 = proxy → **권위 아님**.
- 등급 = **`02_Infrastructure/contracts/essence_score()`** (PORT_t/OOS retention/Sharpe/CAGR/Calmar). `run_hurdle_gate()` 18-component = **진단용(authoritative=FALSE)**, 등급 권위 아님.
- **포트폴리오 수익률 *구성* = `Return.portfolio()`** (PerformanceAnalytics, 도훈 mandate 2026-05-31 안 A). weight drift·rebalance를 검증함수가 처리. **수동 Σ(wᵢrᵢ)/일별 cumprod 합성 금지 — 언어무관.** Python도 동일: **비중(weights)만 산출 → R 브릿지 → `Return.portfolio`** (Python-native lib 미도입, python-policy §4). lean-forge: (holdings 비중, asset 일별수익) → Return.portfolio → ret_net → build_bt_result.
- 자체합성 금지(`prod(1+r)`/`cumprod`/수동 Sharpe — answer-principles). 위반 = AX-002 동급.
- 표준 템플릿(맨 아래)이 정본 흐름. **성능 패턴은 살리되 측정은 계약으로.**
  - ⚠️ legacy `backtest_harness.R::run_monthly_simulation`은 NAV 수동 구성(→ proxy 원인). lean-forge는 Return.portfolio 경유 의무. 기존 sim 마이그레이션은 별도(178 전략 영향).

### 원칙 0: Rcpp 필수 (Level 0 — 최상위 규칙)

**모든 루프 집약 연산에 Rcpp 사용 필수.** R for-loop으로 행/열 순회 금지.

**Rcpp 적용 대상 (반드시):**
- 월별 시뮬레이션 루프 (`run_monthly_simulation` 내부)
- 공분산 행렬 계산 (Gerber, RMT denoise, Ledoit-Wolf)
- HRP/NCO/MinVar 가중 계산
- 롤링 통계량 (z-score, IC, drawdown)
- crisis_consec 누적 카운터

**Rcpp 코드 위치:**
- `02_Infrastructure/factor_db/factor_db_daily_rcpp.cpp` — 기존 Rcpp (참조)
- 새 Rcpp: `02_Infrastructure/portfolio/weight_engine.cpp` (가중 계산)
- 새 Rcpp: `02_Infrastructure/sim_engine.cpp` (시뮬레이션 루프)

**패턴:**
```r
# R에서 Rcpp 로드
Rcpp::sourceCpp(file.path(INFRA_DIR, "portfolio/weight_engine.cpp"))

# C++ 함수 호출 (R for-loop 대체)
w <- cpp_gerber_hrp_weights(ret_matrix, threshold = 0.5, max_w = 0.15)
nav <- cpp_simulate_monthly(prices, weights, dates, commission = 0.0015)
```

**금지 패턴:**
```r
# BAD — R for-loop으로 250개월 순회
for (i in seq_along(signal_dates)) {
  # 종목별 가격 조회, 가중 계산, NAV 업데이트...
}

# BAD — R에서 공분산 행렬 원소별 계산
for (i in 1:n) for (j in 1:n) cov_mat[i,j] <- ...
```

**Rcpp 미구현 시 최소 조치:**
- `data.table` 벡터화 연산으로 대체 (setkey + binary join)
- `frollmean/frollapply` C 구현 활용
- `Reduce` + `lapply` 벡터화 패턴

**성능 기준:** 250개월 시뮬레이션 1건 = Rcpp 시 **30초 이내** (현재 R loop: 2분)

### 원칙 1: Factor DB 일괄 프리로드 (I/O 최소화)

**금지**: 매월 `load_month_factors()` / `load_factor_db()` 반복 호출
```r
# BAD — 255회 parquet I/O
for (sig_date in month_ends) {
  fdb <- load_month_factors(sig_date)  # 매번 파일 읽기
}
```

**필수**: 전기간 일괄 로드 → 메모리 캐싱 → 날짜 필터
```r
# GOOD — 1회 로드, 메모리에서 필터
cat("[OPT] Bulk-loading Factor DB...\n")
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt
}), use.names = TRUE, fill = TRUE)
setkey(FDB_ALL, YM, Ticker)
cat(sprintf("[OPT] FDB_ALL: %s rows, %d months\n",
            format(nrow(FDB_ALL), big.mark = ","), uniqueN(FDB_ALL$YM)))

# 사용 시:
get_month_factors <- function(sig_date, factors = NULL) {
  ym <- format(as.Date(sig_date), "%Y%m")
  dt <- FDB_ALL[YM == ym]
  if (!is.null(factors)) dt <- dt[Factor_Name %in% factors]
  dt
}
```

**메모리 절약**: 필요 팩터만 필터 후 로드
```r
# 15~20개 팩터만 로드 (288개 전체 로드 금지 — CLAUDE.md 규칙)
NEEDED <- c("C19_Composite_Earnings", "Q01_GPA", "D01_IdioVol")
FDB_ALL <- FDB_ALL[Factor_Name %in% NEEDED]
```

### 원칙 2: RAWDATA 1회 로드 + setkey

```r
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

# 필수 키 설정 (merge 10x 가속)
setkey(RAWDATA, Ticker, Date)
setkey(BM_DT, Date)

# Forward return 사전 계산 (루프 내 반복 계산 금지)
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
```

### 원칙 3: Forward Return 벡터화 사전 계산

**금지**: 루프 내 매월 forward return 계산
```r
# BAD
for (sig_date in month_ends) {
  fwd <- RAWDATA[Date > sig_d & Date <= next_month,
                 .(Fwd_Ret = sum(Ret)), by = Ticker]
}
```

**필수**: 전기간 월간 수익률 사전 계산
```r
# GOOD — 벡터화 1회 계산
MONTHLY_RET <- RAWDATA[, .(
  Monthly_Ret = sum(Ret, na.rm = TRUE),
  N_Days = .N
), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)

# Next month return 매핑
ym_list <- sort(unique(MONTHLY_RET$YM))
ym_next <- data.table(YM = ym_list[-length(ym_list)], YM_Next = ym_list[-1])
MONTHLY_RET <- merge(MONTHLY_RET, ym_next, by = "YM")

FWD_RET <- MONTHLY_RET[, .(Ticker, YM, Fwd_Ret = Monthly_Ret)]
setnames(FWD_RET, "YM", "YM_Next")
# sig_date의 YM에 대해 YM_Next의 Fwd_Ret를 매핑
```

### 원칙 4: copy() 최소화

**금지**: variant마다 `copy(RAWDATA_ORIG)` (14M × 4 = 56M rows)
```r
# BAD
for (v in variants) {
  RAWDATA <- copy(RAWDATA_ORIG)  # 14M rows 복사 × 4회
}
```

**필수**: RAWDATA는 읽기 전용, FACTORS만 variant별 생성
```r
# GOOD — RAWDATA 1벌, FACTORS만 교체
RAWDATA_ORIG <- load_rawdata(use_cache = TRUE)$RAWDATA
setkey(RAWDATA_ORIG, Ticker, Date)

for (v in variants) {
  FACTORS_v <- build_factors_variant(v, FDB_ALL, MONTHLY_RET)
  sim <- run_monthly_simulation(RAWDATA = RAWDATA_ORIG, FACTORS = FACTORS_v, ...)
}
```

### 원칙 5: CPU 병렬 — mclapply 우선 (fork COW)

**독립 백테스트 N건은 반드시 병렬.** 순차 for loop 금지 (OPT-4 hook 차단).

**1순위: mclapply (Linux/WSL — fork COW로 RAWDATA 14M rows 복사 없음)**
```r
# 독립 백테스트 N건 병렬 (RAWDATA COW 공유, 복사 ZERO)
results <- mclapply(methods, function(m) {
  FACTORS <- build_factors(m)
  sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
           n_holdings = 20L, commission = 0.0015,
           buffer_zone = list(keep_n = 30L, entry_n = 20L))
  summarise_perf(sim$strategy_xts, m)
}, mc.cores = min(length(methods), parallel::detectCores() - 1L))
```

**2순위: future_lapply (mclapply 불가 시)**
```r
library(future.apply)
plan(multisession, workers = min(4L, parallel::detectCores() - 1L))
results <- future_lapply(methods, function(m) { ... }, future.seed = TRUE)
plan(sequential)
```

**3순위: Agent tool 스폰 (5건+ 대규모, 또는 메모리 부족 시)**
Q-Lead가 각 variant를 별도 Agent로 스폰. 각 Agent가 독립 R 프로세스 실행.

**IC 계산 등 경량 독립 연산도 mclapply 적용:**
```r
factor_ics <- mclapply(factor_cols, function(fc) {
  data.table(factor_id = fc,
             ic = cor(merged[[fc]], merged$Fwd_Ret, use = "pairwise.complete.obs"))
}, mc.cores = min(length(factor_cols), parallel::detectCores() - 1L))
```

**RAM 가드:** 병렬 전 반드시 확인
```r
ram_pct <- as.numeric(system("free | awk '/Mem:/ {printf \"%.0f\", ($2-$7)/$2*100}'", intern = TRUE))
n_cores <- if (ram_pct > 70) 2L else min(length(methods), parallel::detectCores() - 1L)
```

### 원칙 6: LIQ 필터 t-1 month lag (C10 필수)

**금지**: 당월 거래량으로 유동성 필터
```r
# BAD — C10 위반: 당월 거래대금으로 당월 종목 필터
LIQ <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20))), by = .(Ticker, YM)]
```

**필수**: 전월 거래대금으로 필터
```r
# GOOD — C10 준수: 전월 AvgTV20으로 당월 종목 필터
LIQ_RAW <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20))), by = .(Ticker, YM)]
ym_all <- sort(unique(LIQ_RAW$YM))
ym_shift <- data.table(YM_prev = ym_all[-length(ym_all)],
                       YM_use  = ym_all[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev")
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
```

### 원칙 7: RAM 예산 관리

```r
# 시작 시 RAM 체크
ram_pct <- as.numeric(system("free | awk '/Mem:/ {printf \"%.0f\", ($2-$7)/$2*100}'", intern = TRUE))
cat(sprintf("[OPT] RAM: %d%%\n", ram_pct))
if (ram_pct > 70) {
  cat("[WARN] RAM > 70%. gc() 실행 + 대형 객체 제거 권장\n")
  gc(verbose = FALSE)
}

# Factor DB 로드 후 크기 확인
cat(sprintf("[OPT] FDB_ALL: %.1f MB\n", object.size(FDB_ALL) / 1e6))

# 백테스트 후 즉시 정리
rm(FACTORS_v); gc(verbose = FALSE)
```

### 표준 템플릿 (정본 흐름 — 성능 최적화 + 계약 측정)

```r
cat("=== TEST-KR-XXX: [테스트명] ===\n")
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

# ── 1. 데이터 1회 로드 ───────────────────────────────────────────
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)

# ── 2. Factor DB 필요 팩터만 일괄 프리로드 ─────────────────────────
NEEDED <- c("C19_Composite_Earnings", "Q01_GPA")  # 필요한 것만
fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                        pattern = "\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% NEEDED]
}), fill = TRUE)
setkey(FDB_ALL, YM, Ticker, Factor_Name)
cat(sprintf("[OPT] FDB: %.1fMB, %d months\n",
            object.size(FDB_ALL)/1e6, uniqueN(FDB_ALL$YM)))

# ── 3. Forward Return 사전 계산 ───────────────────────────────────
RAWDATA[, YM := format(Date, "%Y%m")]
MONTHLY_RET <- RAWDATA[, .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)

# ── 4. LIQ 필터 사전 계산 ────────────────────────────────────────
RAWDATA[, TV := Close * Vol]
LIQ_MONTHLY <- RAWDATA[, .(
  AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)
), by = .(Ticker, YM)]
setkey(LIQ_MONTHLY, Ticker, YM)

# ── 5. FACTORS 생성 (월별 벡터화) ─────────────────────────────────
ym_list <- sort(unique(FDB_ALL$YM))
FACTORS <- rbindlist(lapply(ym_list, function(ym) {
  fdt <- FDB_ALL[YM == ym]
  if (nrow(fdt) == 0) return(NULL)

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # LIQ 필터
  liq <- LIQ_MONTHLY[YM == ym]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= 2e8]
  if (nrow(fdt_wide) < 30) return(NULL)

  # Score 계산 (전략별 로직)
  fdt_wide[, Score := C19_Composite_Earnings]  # 예시
  setorder(fdt_wide, -Score)
  top <- head(fdt_wide[!is.na(Score)], 30)

  # 월말 날짜 매핑
  sig_date <- RAWDATA[YM == ym, max(Date)]
  top[, Date := sig_date]
  top[, .(Date, Ticker, Score)]
}), fill = TRUE)

setorder(FACTORS, Date, -Score)
RAWDATA[, c("YM", "TV") := NULL]  # cleanup
gc(verbose = FALSE)

# ── 6. 백테스트 (max 25 종목 — 도훈 mandate 2026-05-29) ──────────
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 25L, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 25L)
)

# ── 7. PIT 검증 #1 (결과 수용 전 의무 — 언어무관) ────────────────
source("02_Infrastructure/validation/pit_enforcement.R")
source("02_Infrastructure/sanity_checks/bear_date_audit.R")
# forward label 생성 시: validate_label_direction() + audit_bear_dates(target, bm) PASS 후 진행.
# (Cycle 50 shift-convention lookahead 재발 방지 — .claude/rules/data_table_shift_convention.md)

# ── 8. 계약 빌드 = 권위 측정 (summarise_perf 아님) ───────────────
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
strategy_spec <- list(strategy_id = "TEST_NAME", universe = "KOSPI200_KOSDAQ150",
                      n_holdings = 25L, weight_method = "equal",
                      cost_model_version = "v2.3_kr_retail_15bps")
bt <- build_bt_result(sim, strategy_spec,
                      run_id = "TEST_NAME_001", strategy_id = "TEST_NAME",
                      frequency = "monthly", annualization_factor = 12,
                      transaction_cost_bps = 15)
bt <- audit_bt_result(bt)   # Component 11 audit 채움 (Critical FAIL → metric_type=unavailable)

# ── 9. 등급 = essence_score (권위; hurdle_gate은 진단용) ──────────
source("02_Infrastructure/contracts/essence_score.R")
# 1논문/1알파 → n_trials_cumulative=NULL (DSR 부적용). 명시적 스윕이면 시행수 전달.
g <- essence_score(bt, n_trials_cumulative = NULL)
out_dir <- "04_Research/korea_research/XXX_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(bt, file.path(out_dir, "bt_result.rds"))
jsonlite::write_json(g, file.path(out_dir, "essence_grade.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("GRADE=%s | PORT_t=%s OOS_ret=%s Sharpe=%s CAGR=%s Calmar=%s | %s\n",
            g$grade, g$essence$portfolio_alpha_t_nw_lag3, g$essence$oos_retention,
            g$essence$net_sharpe, g$essence$cagr, g$essence$calmar, g$reasons[1]))

# (선택) 진단용 — 등급 권위 아님:
# generate_charts(sim, output_dir = out_dir, strategy_name = "TEST_NAME")
# hd <- run_hurdle_gate(sim, FACTORS, "TEST_NAME", out_dir)  # authoritative=FALSE (18-component proxy)
```

### 원칙 8: Shared-Factor 백테스트 러너 (비중 비교 시 필수)

**동일 팩터/종목에서 가중 방식만 비교할 때**, `shared_factor_runner.R`의 정본 함수를 사용.

```r
source("02_Infrastructure/config.R")
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(PORTFOLIO_DIR, "shared_factor_runner.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)

# factor_engine.R → FACTORS (Date, Ticker, Score)
source(file.path(STRAT_DIR, "factor_engine.R"))

# Regime overlay (optional)
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE)

# 7가지 가중 방식 한 번에 비교
results <- run_weight_comparison(FACTORS, RAWDATA, BM_DT, regime_dt = REGIME)
print(results$comparison)  # 비교 테이블
cat("Best:", results$best$name, "SR:", results$best$sr)
```

**정본 R 파일**: `02_Infrastructure/portfolio/shared_factor_runner.R`
**함수**: `run_weight_comparison(FACTORS, RAWDATA, BM_DT, weight_methods, regime_dt, ...)`
**지원 가중 7가지**: equal, ivol, hrp, hrp_lw, minvar, riskparity, score_tilt
**효과**: 7가지를 ~10분에 비교 (vs 70분 개별 실행)

### 원칙 8b: Regime Overlay 정본 함수

overlay 코드를 인라인으로 작성하지 말고 정본 함수 호출.

```r
source(file.path(REGIME_DIR, "apply_regime_overlay.R"))
overlay_sim <- apply_regime_overlay(sim, regime_dt, BM_DT)
```

**정본 R 파일**: `02_Infrastructure/regime/apply_regime_overlay.R`
**PIT NOTE**: MRS는 이미 t-1 lagged. 추가 shift() 금지.

### 원칙 9: Codex PIT Review 연동

Forge가 코드 작성 완료 후, **실행 전에** Codex PIT review를 요청.
Q-Lead가 codex:codex-rescue 에이전트로 스폰:
```
Agent(subagent_type="codex:codex-rescue", prompt="
  run_all.R + factor_engine.R의 C1~C15 위반 검사.
  특히: C5 overlay t-1 lag, C13 Z_Score_Aligned, C15 load_month_factors
")
```
Codex APPROVE 후에만 Forge가 실행.

### 원칙 10: R LSP 정적 분석 활용

코드 작성 후 lintr 자동 체크가 실행됨 (settings.json LSP 설정).
주요 확인 사항:
- `no visible binding for global variable` → data.table NSE 패턴 (무시 가능)
- `no visible global function definition` → source() 누락 가능성 (확인 필요)
- `object_name_linter` → UPPER_SNAKE_CASE 상수는 프로젝트 컨벤션 (무시)

**실제 버그 가능성이 높은 경고**:
- `local variable assigned but may not be used` → 실제 미사용 변수
- `Use seq_len() instead of 1:` → 빈 벡터 엣지 케이스
- lintr가 잡지 못하는 것: PIT 위반 → Codex + detect_lookahead.R로 보완

### PIT 체크리스트 (코드 내 주석 필수)
- C1: expanding/rolling window만. full-sample 금지
- C2: same-day circular 금지. t-1 lag
- C4: 재무제표 래깅 (연간→5월, 분기→45일)
- C9: DD/VT lag: t-1 기준
- C13: Z_Score_Aligned만 사용
- C14: IC 접근 시 Usable_Date <= sig_date
- C15: Factor DB는 load_month_factors() 또는 일괄 프리로드 경유

### 메모리 예산 가이드
| 객체 | 예상 크기 | 비고 |
|------|----------|------|
| RAWDATA | 2~3 GB | 14M rows |
| FDB_ALL (15팩터) | 0.5~1 GB | 255개월 × 800종목 × 15 |
| FDB_ALL (288팩터) | 5~8 GB | 절대 전체 로드 금지 |
| MONTHLY_RET | 0.1 GB | 집계 테이블 |
| sim_result | 0.3 GB | xts 시계열 |
| **단일 백테스트 총** | **~4 GB** | RAM 27GB 중 15% |
| **동시 2개** | **~8 GB** | 30% — 안전 |
| **동시 3개** | **~12 GB** | 44% — 한계 |
