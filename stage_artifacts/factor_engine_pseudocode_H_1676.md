# H_1676 factor_engine.R Pseudocode — Scout 초안

## 목적
Forge S1 구현 가속화. VERDICT conditions_for_s1 7건 모두 반영된 factor_engine.R 초안. 실행 가능한 pseudocode이나 Forge가 최종 검증 + preflight + Factor DB 실제 field 매핑 필요.

## Dependencies
```r
library(data.table)
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "factor_db", "factor_db_connector.R"))  # load_month_factors
source(file.path(VALIDATION_DIR, "pit_enforcement.R"))  # pit_zscore_vec, pit_filter
```

## Main factor_engine.R structure

```r
# ============================================================
# H_1676 Residual Consensus Revision Breadth — factor_engine.R
# Scout 초안 (v1) — Forge 최종 검증 + preflight 필수
# ============================================================

# Configurable parameters (S0 record 기반)
WEIGHT_BASE      <- "C13_Revision_Breadth_3m"   # 잔차화 대상 base factor
REGRESSORS       <- c("log_MarketCap", "R12_Idiosyncratic_Risk")  # COND_03 대응 시 M01_CAPM_Beta 추가 slot
WINSORIZATION_PCT <- c(0.01, 0.99)              # Codex R1 우려 반영
MIN_N_XSEC        <- 200                         # cross-section 최소 종목수 (OLS statistical power)
N_HOLD            <- 20L
COMMISSION        <- 0.0015
BUFFER_ZONE       <- list(keep_n = 22L, entry_n = 20L)

# ============================================================
# Step 1: Load factors (C15 준수, load_month_factors 경유)
# ============================================================
# Factor DB에서 필요 필드만 필터 (L-534: 288개 전체 로드 금지)
needed_factors <- c(WEIGHT_BASE, "R12_Idiosyncratic_Risk")

FACTOR_PANEL <- load_month_factors(
  factor_names = needed_factors,
  coverage_min = 0.01,
  use_cache = TRUE  # one-time load pattern
)
setkey(FACTOR_PANEL, Date, Ticker)

# MarketCap은 RAWDATA에서 추출 (기존 패턴)
# 월말 기준 Size (PIT: sig_date 시점 관측 가능한 최신 값)
RAWDATA_SNAP <- RAWDATA[, .(Date, Ticker, Size)]
RAWDATA_SNAP[, log_MarketCap := log(Size)]
setkey(RAWDATA_SNAP, Date, Ticker)

# ============================================================
# Step 2: 월별 rebalance 날짜 리스트
# ============================================================
rebal_dates <- sort(unique(FACTOR_PANEL$Date))
rebal_dates <- rebal_dates[rebal_dates >= as.Date("2005-01-01")]  # 표준 시작점

# ============================================================
# Step 3: 단일 월 cross-section 잔차화 함수
# ============================================================
#' @param sd 신호 월말 날짜 (sig_date)
#' @return data.table(Date=sd, Ticker, Score) 또는 NULL (cross-section 부족)
build_residual_signal <- function(sd) {
  # (a) Load base factor + R12
  f_base <- FACTOR_PANEL[Date == sd & Factor_Name == WEIGHT_BASE,
                         .(Ticker, Z_Base = Z_Score_Aligned)]
  f_r12  <- FACTOR_PANEL[Date == sd & Factor_Name == "R12_Idiosyncratic_Risk",
                         .(Ticker, Z_R12 = Z_Score_Aligned)]
  # (b) Load log_MarketCap
  f_mcap <- RAWDATA_SNAP[Date == sd, .(Ticker, log_mcap = log_MarketCap)]

  # (c) Merge
  dt <- merge(f_base, f_r12, by = "Ticker", all = FALSE)
  dt <- merge(dt, f_mcap, by = "Ticker", all = FALSE)
  dt <- dt[complete.cases(dt)]

  if (nrow(dt) < MIN_N_XSEC) {
    cat(sprintf("[WARN] %s: cross-section n=%d < %d, skip\n", sd, nrow(dt), MIN_N_XSEC))
    return(NULL)
  }

  # (d) Winsorization (Codex R1 우려 반영)
  dt[, Z_Base_w := pmin(pmax(Z_Base, quantile(Z_Base, WINSORIZATION_PCT[1])),
                                     quantile(Z_Base, WINSORIZATION_PCT[2]))]
  dt[, Z_R12_w  := pmin(pmax(Z_R12,  quantile(Z_R12,  WINSORIZATION_PCT[1])),
                                     quantile(Z_R12,  WINSORIZATION_PCT[2]))]
  dt[, log_mcap_w := pmin(pmax(log_mcap, quantile(log_mcap, WINSORIZATION_PCT[1])),
                                         quantile(log_mcap, WINSORIZATION_PCT[2]))]

  # (e) Cross-section OLS: Z_Base ~ log_mcap + R12
  #     Single-month (C1 준수 — full-sample 통계 아님)
  fit <- lm(Z_Base_w ~ log_mcap_w + Z_R12_w, data = dt)
  dt[, resid := residuals(fit)]

  # (f) Cross-section Z-score of residual (Z_Score_Aligned style, expanding 불필요 — 이미 single-month)
  dt[, Score := (resid - mean(resid)) / sd(resid)]

  # Return
  dt[, .(Date = sd, Ticker, Score)]
}

# ============================================================
# Step 4: 전체 기간 signal 생성
# ============================================================
cat("[Phase 1] Building residual signals (", length(rebal_dates), "months)...\n")
factor_list <- lapply(rebal_dates, build_residual_signal)
factor_list <- Filter(Negate(is.null), factor_list)
FACTORS <- rbindlist(factor_list)
setkey(FACTORS, Date, Ticker)

# Liquidity filter (C10) — applied in run_monthly_simulation via LIQ_THRESHOLD
# Already standard pattern in backtest_harness.R

# ============================================================
# Step 5: S1 gate pre-check outputs (for Scout S2 reference)
# ============================================================
# (a) Signal stats per month
sig_stats <- FACTORS[, .(
  n_tickers = .N,
  mean_score = mean(Score),
  sd_score = sd(Score)
), by = Date]
fwrite(sig_stats, file.path(output_dir, "h1676_signal_stats.csv"))

# (b) Residual ICIR (for COND_04 r12_stability)
# Note: 실제 IC 측정은 strategy_analyzer가 수행. 여기서는 signal only.
cat(sprintf("[Signal Summary] months=%d, avg_n_tickers=%.0f\n",
            uniqueN(FACTORS$Date), mean(sig_stats$n_tickers)))

# FACTORS is the final signal table used by run_monthly_simulation
# Structure: (Date, Ticker, Score)
```

## Post-S1 analyses (run_all.R에서 별도 수행)

### COND_03 portfolio CAPM beta 측정

```r
# After sim_result produced
strategy_ret <- as.numeric(sim$strategy_xts)
bm_ret <- as.numeric(sim$bm_xts)

capm_fit <- lm(strategy_ret ~ bm_ret)
capm_beta <- coef(capm_fit)[2]
cat(sprintf("[COND_03] Portfolio CAPM beta = %.4f\n", capm_beta))
cat(sprintf("  Gate: |beta| < 0.15 → %s\n",
            ifelse(abs(capm_beta) < 0.15, "PASS", "FAIL → activate S5 Slot C")))

jsonlite::write_json(list(
  capm_beta = capm_beta,
  gate_pass = abs(capm_beta) < 0.15,
  next_action = ifelse(abs(capm_beta) < 0.15, "proceed_to_S3",
                       "activate_S5_Slot_C_market_beta_ortho")
), file.path(output_dir, "h1676_capm_beta.json"), auto_unbox = TRUE)
```

### COND_04 rolling 3Y 잔차 ICIR drift

```r
# Monthly residual IC (Scout Step 3에서 dt 내 resid vs next-month return 필요)
# Actual IC measurement in strategy_analyzer — here we document expectation
# rolling_3y_icir <- compute_rolling_icir(residual_ic_series, window=36)
# drift <- sd(rolling_3y_icir) / mean(rolling_3y_icir)
# Gate: drift < 0.30 → PASS
```

### COND_05 PIT evidence

```r
# Factor DB Usable_Date verification (C13 필드)
c13_registry_entry <- jsonlite::fromJSON(FACTOR_REG_PATH)$C13_Revision_Breadth_3m
c13_usable_date_logic <- c13_registry_entry$pit$usable_date_formula
c13_snapshot_policy <- c13_registry_entry$pit$snapshot_policy

# Verify: Usable_Date <= Signal Date
# Verify: As-of snapshot (지식 기준일) documented

# Save to pit_evidence field
pit_evidence <- list(
  factor = "C13_Revision_Breadth_3m",
  usable_date_formula = c13_usable_date_logic,
  snapshot_policy = c13_snapshot_policy,
  c14_verification = "PASS/FAIL/UNKNOWN (Forge 확인)",
  notes = "Analyst consensus revision signal의 as-of 수집 시점 + vendor cutoff 정책 확인"
)
```

## Forge 검증 체크리스트

- [ ] preflight_check("STR_XXXX", family="consensus") 성공
- [ ] load_month_factors 경유 (C15, parquet 직접 로드 금지)
- [ ] log_MarketCap = log(Size from RAWDATA), PIT compliant
- [ ] Single-month OLS 구현 (full-sample 통계 금지, C1)
- [ ] Winsorization 1~99% 적용
- [ ] Cross-section Z-score of residual (final Score)
- [ ] N_HOLD=20, EW, commission=0.0015, buffer_zone=list(keep=22, entry=20)
- [ ] No overlay (S0/S1 금지)
- [ ] run_monthly_simulation 표준 호출
- [ ] run_analysis + run_hurdle_gate 호출
- [ ] Post-S1: CAPM beta 측정 → h1676_capm_beta.json
- [ ] PIT evidence 기록 → s1_construction_H_1676.json
- [ ] 결과 DONE_S1_RESULT_H_1676_*.json Scout inbox 발송

## Axiom compliance 확인 (Forge 재확인)

- AX-003 value: 미사용 ✓
- AX-004 quality_profitability: 미사용 ✓
- AX-005 defense (low-beta/Q07+D25/BAB): 미사용 ✓

## 예상 실행 시간
- Factor DB load: ~30초
- Per-month OLS: ~50ms × 250 months = ~12초
- Full backtest: ~2분
- Analysis + hurdle: ~3분
- **총 예상 ~5~7분**

## 문서 상태
- 작성자: Scout
- 작성일: 2026-04-17
- 버전: v1 (초안)
- 용도: Forge H_1676 S1 구현 가속화
- Forge 수정 권한: **전체** (이 문서는 참고용, Forge가 최종 검증)
