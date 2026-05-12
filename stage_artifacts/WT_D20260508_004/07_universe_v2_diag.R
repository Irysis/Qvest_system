#==============================================================================
# WT-D20260508_004 — Step 7: L-227 Universe v2 (KR_TOP500_FREEFLOAT) Comparison
#
# Mandate triggered: 1M ICIR = 0.110 < 0.15 → v2 universe diagnostic required.
#
# Approach: rebuild eligibility under v2 (top 500 by Size at sig_date - 1) and
# recompute IC + ICIR using existing alpha_panel.parquet (alpha is universe-agnostic
# at the predictor level since β was estimated per-ticker without universe constraint).
#
# Period: post-2013 OOS, same as primary diagnostic, for direct apples-to-apples.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")

cat("[07] L-227 v2 Universe Diagnostic …\n")

# Load alpha_panel (already eligible KR_top342)
mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel.parquet")))

# Re-load rawdata to build v2 universe (top 500 by Size at t-1)
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache", "rawdata.parquet"),
                                 col_select = c("Date","Ticker","Size","Vol","Close")))
rd <- rd[Date >= "2010-01-01"]
rd[, Date := as.Date(Date)]
rd[, ym := format(Date, "%Y-%m")]
rd[, eom_flag := Date == max(Date), by = .(Ticker, ym)]
rd_eom <- rd[eom_flag == TRUE, .(Ticker, ym, Date_eom = Date, Size_eom = Size,
                                  TV_d = Close * Vol)]
setorder(rd_eom, Ticker, ym)

# 20d ADV per ticker (already computed monthly above as TV_d, but use approximate)
# For speed: use monthly aggregate (mean TV) — close enough for v2 diagnostic
rd[, TV := Close * Vol]
adv_m <- rd[, .(ADV20 = mean(TV, na.rm = TRUE)), by = .(Ticker, ym)]
rd_eom <- merge(rd_eom, adv_m, by = c("Ticker", "ym"))

# Lag by 1 month per ticker
setorder(rd_eom, Ticker, ym)
rd_eom[, Size_lag1 := shift(Size_eom, 1L), by = Ticker]
rd_eom[, ADV_lag1  := shift(ADV20, 1L), by = Ticker]

# v2: top 500 by Size at t-1, ADV >= 2e8
rd_eom[, Size_rank := frank(-Size_lag1, ties.method = "first"), by = ym]
rd_eom[, eligible_v2 := !is.na(Size_lag1) & Size_rank <= 500 &
                       !is.na(ADV_lag1) & ADV_lag1 >= 2e8]

# Loose v2_LIQ1E8: ADV >= 1e8 (with 25bps cost note)
rd_eom[, eligible_v2_liq1e8 := !is.na(Size_lag1) & Size_rank <= 500 &
                              !is.na(ADV_lag1) & ADV_lag1 >= 1e8]

# Merge into mm
mm_v2 <- merge(mm, rd_eom[, .(Ticker, ym, eligible_v2, eligible_v2_liq1e8)],
                by = c("Ticker", "ym"), all.x = TRUE)
mm_v2[is.na(eligible_v2), eligible_v2 := FALSE]
mm_v2[is.na(eligible_v2_liq1e8), eligible_v2_liq1e8 := FALSE]

# Original eligible
mm_v2[, eligible_v1 := eligible]

# Re-z-score alpha within each universe per month (universe-specific cross section)
# Note: alpha was z-scored within KR_top342. For v2 diagnostic, we re-rank within v2 elig set.
mm_v2[, alpha_v2 := {
  v <- ifelse(eligible_v2, alpha, NA_real_)
  if (sum(!is.na(v)) >= 30) {
    sd0 <- sd(v, na.rm=TRUE)
    if (is.na(sd0) || sd0 < 1e-12) rep(0, length(v))
    else (v - mean(v, na.rm=TRUE))/sd0
  } else rep(NA_real_, length(v))
}, by = ym]

mm_v2[, alpha_v2_liq1e8 := {
  v <- ifelse(eligible_v2_liq1e8, alpha, NA_real_)
  if (sum(!is.na(v)) >= 30) {
    sd0 <- sd(v, na.rm=TRUE)
    if (is.na(sd0) || sd0 < 1e-12) rep(0, length(v))
    else (v - mean(v, na.rm=TRUE))/sd0
  } else rep(NA_real_, length(v))
}, by = ym]

# Per-month IC for each universe
ic_v1 <- mm_v2[ym >= "2013-01" & eligible_v1 == TRUE & !is.na(alpha) & !is.na(FwdRet_1M),
               .(rank_ic = cor(alpha, FwdRet_1M, method="spearman"), n=.N), by=ym]
ic_v2 <- mm_v2[ym >= "2013-01" & eligible_v2 == TRUE & !is.na(alpha_v2) & !is.na(FwdRet_1M),
               .(rank_ic = cor(alpha_v2, FwdRet_1M, method="spearman"), n=.N), by=ym]
ic_v2_liq <- mm_v2[ym >= "2013-01" & eligible_v2_liq1e8 == TRUE & !is.na(alpha_v2_liq1e8) & !is.na(FwdRet_1M),
                   .(rank_ic = cor(alpha_v2_liq1e8, FwdRet_1M, method="spearman"), n=.N), by=ym]

summarize_ic <- function(dt, label) {
  list(
    label = label,
    n_periods = nrow(dt),
    n_avg = round(mean(dt$n, na.rm=TRUE), 1),
    ic_mean = round(mean(dt$rank_ic, na.rm=TRUE), 4),
    ic_sd = round(sd(dt$rank_ic, na.rm=TRUE), 4),
    icir = round(mean(dt$rank_ic, na.rm=TRUE) / sd(dt$rank_ic, na.rm=TRUE), 3)
  )
}
v1_sum <- summarize_ic(ic_v1, "KR_top342 (default)")
v2_sum <- summarize_ic(ic_v2, "KR_TOP500_FREEFLOAT (L-227 v2 default)")
v2_liq_sum <- summarize_ic(ic_v2_liq, "KR_TOP500_LIQ1E8 (relaxed liquidity, +25bps cost)")

cat("\n[07] Universe Comparison (post-2013 OOS):\n")
for (s in list(v1_sum, v2_sum, v2_liq_sum)) {
  cat(sprintf("  %s\n    n_periods=%d, avg_n=%g, IC=%.4f, IC_sd=%.4f, ICIR=%.3f\n",
              s$label, s$n_periods, s$n_avg, s$ic_mean, s$ic_sd, s$icir))
}

# Long-horizon (12M) too
ic_v1_12 <- mm_v2[ym >= "2013-01" & eligible_v1 == TRUE & !is.na(alpha) & !is.na(FwdRet_12M),
                  .(rank_ic = cor(alpha, FwdRet_12M, method="spearman"), n=.N), by=ym]
ic_v2_12 <- mm_v2[ym >= "2013-01" & eligible_v2 == TRUE & !is.na(alpha_v2) & !is.na(FwdRet_12M),
                  .(rank_ic = cor(alpha_v2, FwdRet_12M, method="spearman"), n=.N), by=ym]
v1_12 <- summarize_ic(ic_v1_12, "KR_top342 12M")
v2_12 <- summarize_ic(ic_v2_12, "KR_TOP500_FREEFLOAT 12M")

cat("\n[07] Long-horizon (12M) comparison:\n")
for (s in list(v1_12, v2_12)) {
  cat(sprintf("  %s: IC=%.4f ICIR=%.3f n=%d\n", s$label, s$ic_mean, s$icir, s$n_periods))
}

# Save
ortho_old <- fromJSON(file.path(OUT, "orthogonality_vs_hybrid.json"))
universe_comp <- list(
  l227_trigger = "ICIR_1M = 0.110 < 0.15 → v2 mandate active",
  v1_default = v1_sum,
  v2_top500_freefloat = v2_sum,
  v2_top500_liq1e8 = v2_liq_sum,
  v1_12m = v1_12,
  v2_12m = v2_12,
  conclusion = if (v2_sum$icir > v1_sum$icir + 0.05)
    "v2 attenuation present; expand universe recommended"
  else if (v2_sum$icir > v1_sum$icir)
    "v2 marginally better; mid-cap signal modest"
  else
    "v2 no improvement; universe restriction is not the binding constraint",
  rationale = "L-227 v2 diagnostic compares ICIR across universes to detect mid-cap signal attenuation. If v2 ICIR << v1 ICIR + 0.05, universe expansion not justified by improvement."
)
write_json(universe_comp, file.path(OUT, "universe_comparison.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("\n[07] saved universe_comparison.json\n")
