#==============================================================================
# WT-D20260426_002 Iter 8 — L01_Amihud Regime-Conditional Sleeve
#
# Hypothesis: Amihud (2002) illiquidity premium은 KR market에서 unconditional 측정
#   시 negative IC (Iter 7 입증, IC=-0.05). 그러나 regime-conditional 적용 시
#   BULL/NORMAL 국면에서 positive premium (Pastor-Stambaugh 2003 패턴),
#   CAUTION/CRISIS에서는 flight-to-liquidity로 reverse → alpha=0 (cash sleeve)
#   회피 시 regime-weighted alpha 보존 가능.
#
# 본 alpha는 STR_1700과 cross-family (Liquidity_Risk vs Multi-axis Quality+Mom).
# Sequential Admission target: TDC vs STR_1700 < 0.30.
#
# Sleeve 구조 (AX-007 EXCEPTION#1 multi-sleeve):
#   Sleeve 1 — Liquidity sleeve (BULL/NORMAL only):
#     L01_Amihud raw cross-sectional rank (lower Amihud = more liquid → premium 음수;
#     실제로 'illiquidity premium'은 high-Amihud long; KR에서는 reverse 가능).
#     Iter 8에서는 Z_Score_Aligned (IC-aligned direction) 그대로 사용 →
#     positive IC면 high-z long, negative IC면 low-z long (이미 align됨).
#     Sleeve weight = 70% in BULL/NORMAL, 0% in CAUTION/CRISIS.
#   Sleeve 2 — Cash sleeve (CAUTION/CRISIS only):
#     모든 ticker alpha = 0 (현금 회피). weight = 30% baseline + 70% from Sleeve1
#     transfer in CAUTION/CRISIS = 100% in CAUTION/CRISIS, 30% in BULL/NORMAL.
#
# Per-sig_date alpha logic:
#   BULL/NORMAL → alpha_t = z(L01_Amihud)_aligned  (sleeve 1 active 70%)
#   CAUTION/CRISIS → alpha_t = 0 (sleeve 2 cash)
#
# AX axiom check:
#   AX-003 (KR value EP_STANDALONE): EXCLUSION — no value
#   AX-004 (single quality_profitability): EXCLUSION — no quality
#   AX-005 (BAB single-sleeve): EXCLUSION — Liquidity_Risk family, not low-beta
#   AX-007: EXCEPTION#1 multi-sleeve (Liquidity sleeve 70% + Cash sleeve 30%
#           regime-conditional swap)
#
# PIT enforcement:
#   - load_month_factors(sig_date) — Usable_Date <= sig_date 강제 (C14)
#   - regime_state @ sig_date — same-day 사용 시 C9 위반 가능 → t-1 lag 적용
#     (regime_panel는 sig_date 기준 record, 우리는 prev-month regime 사용)
#   - returns Ret_1m forward (1M ahead) — IC 계산용, no leakage to alpha
#
# Output: stage_artifacts/WT_D20260426_002/alpha_scores.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

# ---- Paths & config ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID    <- "WT-D20260426_002"
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_002")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

SELECTED_FACTOR <- "L01_Amihud"   # single-axis, regime-conditional

# Sleeve weights
SLEEVE_LIQ_WEIGHT_BULLNORMAL  <- 0.70
SLEEVE_LIQ_WEIGHT_CAUTIONCRIS <- 0.00
SLEEVE_CASH_WEIGHT_BULLNORMAL <- 0.30
SLEEVE_CASH_WEIGHT_CAUTIONCRIS <- 1.00

# ---- Reference data ----
# (1) STR_1700 reference (TDC + sig_date alignment)
str1700 <- read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet") |>
  setDT()
str1700_alpha <- str1700[, .(Date, Ticker, alpha_str1700 = score_eff)]
sig_dates_pool <- sort(unique(str1700$Date))   # 239 monthly sig_dates

# (2) Regime panel — PIT-safe: USE LAGGED regime_state (prev-month)
rp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_007/regime_panel.parquet"))
setkey(rp, sig_date)
# Lag regime by 1 month (C9 violation 방지)
rp[, regime_state_lag := shift(regime_state, n = 1L, type = "lag")]
# rp 결합용 sig_date 키
regime_dt <- rp[, .(Date = sig_date, regime_state = regime_state_lag)]

# Discovery WT period — 2004-01 ~ 2023-11
TRAIN_END  <- as.Date("2017-12-31")
VALID_END  <- as.Date("2023-11-30")
LOCKBOX_BAR <- VALID_END  # alpha agent: train_window + validation_window only

cat("[Iter8-Alpha] Sig dates in pool:", length(sig_dates_pool),
    "from", as.character(min(sig_dates_pool)), "to",
    as.character(max(sig_dates_pool)), "\n")
cat("[Iter8-Alpha] Train end:", as.character(TRAIN_END),
    "| Validation end:", as.character(VALID_END), "\n")
cat("[Iter8-Alpha] Selected factor:", SELECTED_FACTOR,
    "| Sleeve config: BULL/NORMAL Liq", SLEEVE_LIQ_WEIGHT_BULLNORMAL,
    "/ Cash", SLEEVE_CASH_WEIGHT_BULLNORMAL,
    "; CAUTION/CRISIS Liq", SLEEVE_LIQ_WEIGHT_CAUTIONCRIS,
    "/ Cash", SLEEVE_CASH_WEIGHT_CAUTIONCRIS, "\n")

# ---- Restrict sig_dates to discovery window ----
sig_dates_pool <- sig_dates_pool[sig_dates_pool <= LOCKBOX_BAR]
sig_dates_pool <- sig_dates_pool[sig_dates_pool >= as.Date("2004-01-01")]
cat("[Iter8-Alpha] After window isolation: N =", length(sig_dates_pool), "\n")

# ---- Parallel rolling alpha generation per sig_date ----
n_workers <- min(8L, parallel::detectCores() - 1L)
cat("[Iter8-Alpha] Parallel workers:", n_workers, "\n")
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

t_alpha_start <- Sys.time()

# Per-sig_date alpha_score generation
# regime_dt와 SELECTED_FACTOR 등은 globals 자동 공유
results <- future_lapply(sig_dates_pool, function(sd) {
  tryCatch({
    # Regime lookup (lagged)
    regm <- regime_dt[Date == sd, regime_state]
    if (length(regm) == 0L || is.na(regm)) return(NULL)

    # Sleeve weight by regime
    if (regm %in% c("BULL", "NORMAL")) {
      w_liq <- SLEEVE_LIQ_WEIGHT_BULLNORMAL
      w_cash <- SLEEVE_CASH_WEIGHT_BULLNORMAL
    } else {  # CAUTION / CRISIS
      w_liq <- SLEEVE_LIQ_WEIGHT_CAUTIONCRIS
      w_cash <- SLEEVE_CASH_WEIGHT_CAUTIONCRIS
    }

    # Factor load (PIT-safe)
    fdt <- suppressMessages(load_month_factors(sig_date = sd, coverage_min = 0.05))
    if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
    setDT(fdt)
    sub <- fdt[Factor_Name == SELECTED_FACTOR,
               .(Ticker, z = Z_Score_Aligned)]
    if (nrow(sub) == 0) return(NULL)

    # Winsorize at 3-std
    z <- sub$z
    z_med <- median(z, na.rm = TRUE)
    z_sd <- sd(z, na.rm = TRUE)
    if (!is.na(z_sd) && z_sd > 1e-12) {
      lo <- z_med - 3 * z_sd; hi <- z_med + 3 * z_sd
      z <- pmin(pmax(z, lo), hi)
    }
    z[is.na(z)] <- 0  # missing → neutral

    # Cross-sectional re-standardize
    z_mean <- mean(z, na.rm = TRUE)
    z_std  <- sd(z, na.rm = TRUE)
    z_std_safe <- ifelse(!is.na(z_std) && z_std > 1e-12, z_std, 1)
    z_norm <- (z - z_mean) / z_std_safe

    # Sleeve-weighted alpha:
    #   alpha = w_liq * z_norm + w_cash * 0
    # In BULL/NORMAL: alpha = 0.70 * z_norm
    # In CAUTION/CRISIS: alpha = 0 (full cash, no liquidity bet)
    alpha_raw <- w_liq * z_norm

    # Confidence: high in BULL/NORMAL (regime aligned with hypothesis),
    # low in CAUTION/CRISIS (cash → 신뢰도 낮음 BUT alpha=0이므로 영향 없음)
    if (regm %in% c("BULL", "NORMAL")) {
      conf <- pmin(1.0, 0.6 + 0.4 * pmin(abs(z_norm) / 2, 1))
    } else {
      conf <- rep(0.5, length(z_norm))  # cash sleeve, neutral confidence
    }

    out <- data.table(
      Date            = sd,
      Ticker          = sub$Ticker,
      alpha           = alpha_raw,
      z_amihud        = z_norm,
      regime_state    = regm,
      sleeve_w_liq    = w_liq,
      sleeve_w_cash   = w_cash,
      confidence      = conf
    )
    return(out)
  }, error = function(e) {
    message("[Iter8-Alpha] sd=", sd, " ERROR: ", conditionMessage(e))
    return(NULL)
  })
})

plan(sequential)

t_alpha_secs <- as.numeric(difftime(Sys.time(), t_alpha_start, units = "secs"))
cat("[Iter8-Alpha] Per-sig_date alpha gen complete in",
    round(t_alpha_secs, 1), "secs\n")

# Combine
results <- results[!sapply(results, is.null)]
cat("[Iter8-Alpha] Non-null sig_dates:", length(results), "\n")
alpha_dt <- rbindlist(results, use.names = TRUE, fill = TRUE)
cat("[Iter8-Alpha] Alpha rows:", nrow(alpha_dt),
    " | uniq Dates:", length(unique(alpha_dt$Date)),
    " | uniq Tickers:", length(unique(alpha_dt$Ticker)), "\n")

# ---- Save alpha_scores.parquet (시계열 alpha) ----
out_path <- file.path(ART_DIR, "alpha_scores.parquet")
write_parquet(alpha_dt, out_path)
cat("[Iter8-Alpha] Saved:", out_path, "\n")

# Save regime breakdown
print(alpha_dt[, .(N=.N, mean_alpha=mean(alpha), sd_alpha=sd(alpha)),
               by=regime_state])

cat("[Iter8-Alpha] DONE.\n")
