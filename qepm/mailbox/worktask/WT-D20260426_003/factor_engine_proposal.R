#==============================================================================
# WT-D20260426_003 Iter 9 — Growth × Investor_Flow Residualized Cross-family Alpha
#
# Hypothesis: KR market에서 actuals/forecast Growth signal과 Foreign-residualized
#   Investor Flow signal은 개별로는 marginal alpha 이지만, cross-family interaction
#   (multiplicative + residualized) 에서 SR 1.5+ 잠재. Iter 7+8 KR Liquidity_Risk
#   family 연속 ALPHA FAIL → L-209 family avoidance. Pivot to Growth + Flow.
#
# Origin (cross-family — STR_1700 factor list와 zero-overlap):
#   Growth axis (actuals + forecast revision):
#     - GR06_OCF_Growth   (operating cash flow growth — quality of growth)
#     - GR01_Revenue_Growth (top-line growth)
#     - C17_OP_Revision    (operating profit consensus revision — forecast growth)
#   Flow axis (KR domestic information edge — monthly DB):
#     - INV02_Foreign_NetBuy_60d         (외인 60일 net buy intensity)
#     - INV04_Inst_NetBuy_60d            (기관 60일 net buy intensity)
#     - INV08_Foreign_Inst_Agreement     (외인-기관 동조 signal)
# (Note: INV13_Foreign_Resid_Individual_*은 daily-only — monthly DB에 미존재.
#  v2에서 INV02+INV04+INV08 monthly composite로 fallback. residualization은
#  composite 후 Growth ⟂ Flow OLS로 동일하게 적용.)
#
# STR_1700 factor list:
#   theta_core    = C01_SUE, C02_EPS_Chg_1m, C04_ESBR, C06_TP_Gap (Analyst_Consensus)
#   theta_defense = Q07_Earnings_Stability, M08_Residual_Mom, Q25_Ohlson_O (Quality+Mom+Distress)
# → ZERO overlap with Iter 9 set. ZERO common factor name. Cross-family by design.
#
# Construction (3-step):
#   Step 1: per-Date z-score for each of 4 factors (Z_Score_Aligned, winsor 3std)
#   Step 2: Growth_composite = mean(z(GR06), z(GR01), z(C17))   # 3-axis growth
#   Step 3: Cross-family interaction (residualized):
#     - Foreign_z residualized vs Growth_composite (β로 회귀하여 직교)
#     - Final alpha = 0.50 * Growth_composite_z + 0.30 * Foreign_resid_z +
#                     0.20 * sign(Growth) * |Foreign_resid_z|     # interaction term
#       (interaction = "growth-direction-amplified flow" — Hong-Stein 1999 정보 비대칭)
#
# Sleeve structure (AX-007 EXCEPTION#1 multi-sleeve):
#   - Sleeve A — Growth+Flow alpha sleeve (BULL/NORMAL: 80%; CAUTION: 50%; CRISIS: 0%)
#   - Sleeve B — Cash overlay (BULL/NORMAL: 20%; CAUTION: 50%; CRISIS: 100%)
#   Crisis avoidance built-in (regime t-1 lag). CAUTION = partial — Growth signal
#   typically robust there (Cooper-Gulen-Schill 2008).
#
# AX axiom check:
#   AX-003 (KR value EP_STANDALONE): EXCLUSION — no value factor used
#   AX-004 (single quality_profitability): EXCLUSION — Growth + Flow cross-family
#                                          (Q07 등 quality 미사용)
#   AX-005 (BAB single-sleeve top20): EXCLUSION — Growth+Flow, no low-beta
#   AX-007: EXCEPTION#1 multi-sleeve (Growth+Flow alpha sleeve + Cash overlay
#           regime-conditional)
#
# PIT enforcement (C1~C15):
#   - C13: Z_Score_Aligned only (no manual sign flip)
#   - C14: load_month_factors(sig_date) — Usable_Date <= sig_date
#   - C15: Factor DB load_month_factors() 경유 (no direct parquet)
#   - C9 : regime_state lag-1 (prev-month) — same-day circular 회피
#   - C5 : regime overlay t-1
#   - C4 : 재무제표 lag (factor DB에서 이미 적용됨)
#
# Output: stage_artifacts/WT_D20260426_003/alpha_scores.parquet
#         (Date, Ticker, alpha, growth_z, flow_z, interact_z, regime_state,
#          sleeve_w_alpha, sleeve_w_cash, confidence)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID    <- "WT-D20260426_003"
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_003")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Factor selection (cross-family Growth × Investor_Flow) ----
# v2 fix: INV13_Foreign_Resid_*는 daily-only factor (monthly DB 부재)
#         → INV02_Foreign_NetBuy_60d + INV04_Inst_NetBuy_60d (둘 다 monthly DB)
#         + INV08_Foreign_Inst_Agreement (외인-기관 동조 signal)
#         로 대체. Foreign net buy는 KR market 정보 우위 표준 proxy.
GROWTH_FACTORS <- c("GR06_OCF_Growth", "GR01_Revenue_Growth", "C17_OP_Revision")
FLOW_FACTORS   <- c("INV02_Foreign_NetBuy_60d", "INV04_Inst_NetBuy_60d",
                    "INV08_Foreign_Inst_Agreement")
ALL_FACTORS    <- c(GROWTH_FACTORS, FLOW_FACTORS)

# Sleeve weights (regime-conditional)
SLEEVE_W_ALPHA <- list(BULL = 0.80, NORMAL = 0.80, CAUTION = 0.50, CRISIS = 0.00)
SLEEVE_W_CASH  <- list(BULL = 0.20, NORMAL = 0.20, CAUTION = 0.50, CRISIS = 1.00)

# Composite weights (within alpha sleeve)
W_GROWTH      <- 0.50
W_FLOW_RESID  <- 0.30
W_INTERACTION <- 0.20

# ---- Reference data ----
str1700 <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet"))
sig_dates_pool <- sort(unique(str1700$Date))   # 239 monthly sig_dates
cat("[Iter9-Alpha] STR_1700 sig_dates:", length(sig_dates_pool), "\n")

# Regime panel (lag-1 PIT-safe)
rp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_007/regime_panel.parquet"))
setkey(rp, sig_date)
rp[, regime_state_lag := shift(regime_state, n = 1L, type = "lag")]
regime_dt <- rp[, .(Date = sig_date, regime_state = regime_state_lag)]

# Window (discovery)
TRAIN_END   <- as.Date("2017-12-31")
VALID_END   <- as.Date("2023-11-30")
LOCKBOX_BAR <- VALID_END

sig_dates_pool <- sig_dates_pool[sig_dates_pool <= LOCKBOX_BAR &
                                  sig_dates_pool >= as.Date("2004-01-01")]
cat("[Iter9-Alpha] After window isolation: N =", length(sig_dates_pool), "\n")
cat("[Iter9-Alpha] Factors:", paste(ALL_FACTORS, collapse = ", "), "\n")
cat("[Iter9-Alpha] Sleeve config:\n")
for (rg in names(SLEEVE_W_ALPHA)) {
  cat(sprintf("  %s: alpha=%.2f, cash=%.2f\n",
              rg, SLEEVE_W_ALPHA[[rg]], SLEEVE_W_CASH[[rg]]))
}

# ---- Cross-sectional helper ----
xs_zscore <- function(x, winsor_std = 3) {
  if (all(is.na(x))) return(rep(0, length(x)))
  x[is.na(x)] <- median(x, na.rm = TRUE)
  m <- median(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-12) return(rep(0, length(x)))
  x_w <- pmin(pmax(x, m - winsor_std * s), m + winsor_std * s)
  mu <- mean(x_w, na.rm = TRUE); sd0 <- sd(x_w, na.rm = TRUE)
  if (is.na(sd0) || sd0 < 1e-12) return(rep(0, length(x_w)))
  (x_w - mu) / sd0
}

# Residualize y on x (return residual after OLS y = a + b*x)
residualize <- function(y, x) {
  ok <- is.finite(y) & is.finite(x)
  if (sum(ok) < 5) return(y)  # too few — return as is
  if (sd(x[ok]) < 1e-12) return(y - mean(y[ok], na.rm = TRUE))
  fit <- lm(y[ok] ~ x[ok])
  res <- y
  res[ok] <- residuals(fit)
  res[!ok] <- 0
  res
}

# ---- Parallel rolling alpha generation ----
n_workers <- min(8L, parallel::detectCores() - 1L)
cat("[Iter9-Alpha] Parallel workers:", n_workers, "\n")
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

t_start <- Sys.time()

results <- future_lapply(sig_dates_pool, function(sd) {
  tryCatch({
    # Regime lookup (lag-1)
    regm <- regime_dt[Date == sd, regime_state]
    if (length(regm) == 0L || is.na(regm)) return(NULL)
    regm <- as.character(regm)
    if (!regm %in% c("BULL", "NORMAL", "CAUTION", "CRISIS")) return(NULL)

    w_alpha <- SLEEVE_W_ALPHA[[regm]]
    w_cash  <- SLEEVE_W_CASH[[regm]]

    # Factor load (PIT-safe via load_month_factors)
    fdt <- suppressMessages(load_month_factors(sig_date = sd, coverage_min = 0.05))
    if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
    setDT(fdt)

    # Pivot to wide: (Ticker, factor1_z, factor2_z, ...)
    sub <- fdt[Factor_Name %in% ALL_FACTORS,
               .(Ticker, Factor_Name, Z_Score_Aligned)]
    if (nrow(sub) == 0) return(NULL)

    wide <- dcast(sub, Ticker ~ Factor_Name,
                  value.var = "Z_Score_Aligned",
                  fun.aggregate = mean, fill = NA_real_)
    setDT(wide)

    # Skip if any factor entirely missing
    needed <- ALL_FACTORS
    missing_factors <- setdiff(needed, names(wide))
    if (length(missing_factors) > 0) {
      # Use 0 for missing (neutral). Don't return NULL — partial signal still useful
      for (m in missing_factors) wide[, (m) := 0]
    }

    # Drop rows with all 4 NA
    wide[, n_nonna := rowSums(!is.na(.SD)),
         .SDcols = needed]
    wide <- wide[n_nonna >= 2L]  # at least 2 of 4 factors
    wide[, n_nonna := NULL]
    if (nrow(wide) < 30) return(NULL)

    # Per-factor cross-sectional z (re-standardize, winsor 3std)
    for (fn in needed) {
      wide[, (paste0(fn, "_z")) := xs_zscore(get(fn))]
    }

    # Growth composite: mean of 3 growth factors (already direction-aligned via Z_Score_Aligned)
    wide[, growth_z := rowMeans(
      cbind(get(paste0(GROWTH_FACTORS[1], "_z")),
            get(paste0(GROWTH_FACTORS[2], "_z")),
            get(paste0(GROWTH_FACTORS[3], "_z"))),
      na.rm = TRUE)]
    wide[, growth_z := xs_zscore(growth_z)]

    # Flow composite: mean of 3 flow factors (Foreign + Inst + Agreement)
    wide[, flow_z := rowMeans(
      cbind(get(paste0(FLOW_FACTORS[1], "_z")),
            get(paste0(FLOW_FACTORS[2], "_z")),
            get(paste0(FLOW_FACTORS[3], "_z"))),
      na.rm = TRUE)]
    wide[, flow_z := xs_zscore(flow_z)]

    # Residualize Flow on Growth (orthogonal Flow signal)
    wide[, flow_resid := residualize(flow_z, growth_z)]
    wide[, flow_resid_z := xs_zscore(flow_resid)]

    # Interaction term: sign(growth) * |flow_resid|
    # 의미: growth-direction-amplified information edge (Hong-Stein 1999)
    wide[, interact_raw := sign(growth_z) * abs(flow_resid_z)]
    wide[, interact_z := xs_zscore(interact_raw)]

    # Composite alpha (within alpha sleeve)
    wide[, alpha_within_sleeve :=
           W_GROWTH      * growth_z +
           W_FLOW_RESID  * flow_resid_z +
           W_INTERACTION * interact_z]

    # Final alpha (sleeve-weighted; cash sleeve = 0)
    wide[, alpha := w_alpha * alpha_within_sleeve]

    # Confidence: high when alpha sleeve active + signal magnitude clear
    if (w_alpha > 0) {
      wide[, confidence := pmin(1.0, 0.55 + 0.45 * pmin(abs(alpha_within_sleeve) / 2, 1))]
    } else {
      wide[, confidence := 0.5]
    }

    out <- wide[, .(
      Date           = sd,
      Ticker,
      alpha,
      growth_z,
      flow_z,
      flow_resid_z,
      interact_z,
      alpha_within_sleeve,
      regime_state   = regm,
      sleeve_w_alpha = w_alpha,
      sleeve_w_cash  = w_cash,
      confidence
    )]

    return(out)
  }, error = function(e) {
    message("[Iter9-Alpha] sd=", sd, " ERROR: ", conditionMessage(e))
    return(NULL)
  })
})

plan(sequential)
t_secs <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
cat("[Iter9-Alpha] Per-sig_date alpha gen complete in",
    round(t_secs, 1), "secs\n")

# Combine
results <- results[!sapply(results, is.null)]
cat("[Iter9-Alpha] Non-null sig_dates:", length(results), "\n")
alpha_dt <- rbindlist(results, use.names = TRUE, fill = TRUE)
cat("[Iter9-Alpha] Alpha rows:", nrow(alpha_dt),
    " | uniq Dates:", length(unique(alpha_dt$Date)),
    " | uniq Tickers:", length(unique(alpha_dt$Ticker)), "\n")

# Save
out_path <- file.path(ART_DIR, "alpha_scores.parquet")
write_parquet(alpha_dt, out_path)
cat("[Iter9-Alpha] Saved:", out_path, "\n")

# Regime breakdown
cat("\n[Iter9-Alpha] Regime breakdown:\n")
print(alpha_dt[, .(N = .N,
                   mean_alpha = mean(alpha, na.rm=TRUE),
                   sd_alpha = sd(alpha, na.rm=TRUE),
                   mean_growth = mean(growth_z, na.rm=TRUE),
                   mean_flow_resid = mean(flow_resid_z, na.rm=TRUE)),
               by = regime_state])

cat("[Iter9-Alpha] DONE.\n")
