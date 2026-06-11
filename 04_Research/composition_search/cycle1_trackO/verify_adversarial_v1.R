# ============================================================
# Track O ADVERSARIAL VERIFICATION (independent re-run)
# Implements prereg formulas from prereg_combine_candidates.json
# directly (NOT sourcing run_combine_ab.R). ASCII output only.
# Checks:
#  V1 baseline L5_V2 recomposition residual (independent)
#  V2 cost-leg identities (db_thr == |d beta_AR|, db_R05 == |d beta_R05|)
#  V3 deep-guard schedule time series (b_inc<0.25 months, per candidate)
#  V4 numeric reproduction: O3 (selected) + 1 random candidate,
#     all 4 windows, SR/MDD vs stored JSON, tol 1e-6
#  V5 unrounded IS SR argmax check (selection robustness)
#  V6 OOS confirmation rule re-evaluation
#  V7 CSV vs JSON consistency
# ============================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROD <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
OUT  <- file.path(ROOT, "04_Research/composition_search/cycle1_trackO")

l5 <- fread(file.path(PROD, "04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
cat(sprintf("[V0] panel n=%d range %s..%s\n", nrow(l5), min(l5$realized_ym), max(l5$realized_ym)))

# ---- V1 baseline residual (independent arithmetic) ----
resid <- l5$beta_R05_V2 * l5$beta_threshold_lag * l5$m4_weight_lag * l5$ret_orig -
         0.0015 * l5$db_thr - 0.0015 * l5$db_R05_V2 - l5$ret_L5_V2
cat(sprintf("[V1] baseline L5_V2 recomposition max|resid| = %.4e (PASS if <1e-12)\n", max(abs(resid))))

# ---- V2 cost-leg identities ----
id_thr <- max(abs(l5$db_thr   - c(0, abs(diff(l5$beta_threshold_lag)))))
id_r05 <- max(abs(l5$db_R05_V2 - c(0, abs(diff(l5$beta_R05_V2)))))
# adversarial alt: was db_thr maybe |d g_inc| (AR x M4) instead?
g_inc <- l5$beta_threshold_lag * l5$m4_weight_lag
id_alt <- max(abs(l5$db_thr - c(0, abs(diff(g_inc)))))
cat(sprintf("[V2] db_thr==|d beta_AR| max|resid| = %.4e | db_R05==|d beta_R05| = %.4e\n", id_thr, id_r05))
cat(sprintf("[V2] (alt) db_thr vs |d(AR*M4)| max|diff| = %.4e -> production charged AR leg ONLY (m4 leg uncharged)\n", id_alt))
cat(sprintf("[V2] first row: betas (AR,M4,R05) = (%g,%g,%g), db = (%g,%g) -> delta-vs-1.0 convention\n",
    l5$beta_threshold_lag[1], l5$m4_weight_lag[1], l5$beta_R05_V2[1], l5$db_thr[1], l5$db_R05_V2[1]))

# ---- candidates from prereg formulas (independent implementation) ----
b_inc <- g_inc * l5$beta_R05_V2
deep  <- b_inc < 0.25
cat(sprintf("[V3] deep months (b_inc<0.25) = %d\n", sum(deep)))
RHO <- 0.4951
bAR <- l5$beta_threshold_lag; m4 <- l5$m4_weight_lag
gc_raw <- list(
  O1_MIN_DEDUP      = pmin(bAR, m4),
  O2_M4_PRIORITY_OR = ifelse(m4 < 1 - 1e-12, m4, bAR),
  O3_MIDBAND_FLOOR  = ifelse(g_inc < 0.25, g_inc, pmax(g_inc, 0.5)),
  O4_POWER_RHO      = (bAR * m4)^(1/(1+RHO)),
  O5_BLEND_RHO      = (1-RHO)*(bAR*m4) + RHO*pmin(bAR, m4)
)
gc <- lapply(gc_raw, function(g) { g[deep] <- g_inc[deep]; g })
gc$INCUMBENT_REPRICED <- g_inc

# ---- V3 deep-guard schedule time series ----
dd <- data.table(ym = l5$realized_ym[deep], b_inc = b_inc[deep])
for (nm in setdiff(names(gc), "INCUMBENT_REPRICED")) {
  b_cand <- gc[[nm]] * l5$beta_R05_V2
  dd[[paste0("diff_", substr(nm,1,2))]] <- b_cand[deep] - b_inc[deep]
}
cat("[V3] deep months schedule (candidate total beta minus incumbent, must be exactly 0):\n")
print(dd, digits = 17)
maxdiff_all <- max(sapply(setdiff(names(gc), "INCUMBENT_REPRICED"),
       function(nm) max(abs(gc[[nm]][deep]*l5$beta_R05_V2[deep] - b_inc[deep]))))
cat(sprintf("[V3] global deep-guard max|beta diff| over all 5 candidates = %.4e\n", maxdiff_all))
# also: candidates never cut exposure anywhere (no new deep months possible)
for (nm in setdiff(names(gc), "INCUMBENT_REPRICED"))
  cat(sprintf("[V3] %-18s months g_cand < g_inc - 1e-12 : %d\n", nm, sum(gc[[nm]] < g_inc - 1e-12)))

# ---- series under uniform cost convention (prereg series_construction) ----
mkret <- function(g) {
  dg <- abs(diff(c(1, g)))
  l5$beta_R05_V2 * g * l5$ret_orig - 0.0015*dg - 0.0015*l5$db_R05_V2
}
rets <- lapply(gc, mkret)
costs <- lapply(gc, function(g) 0.0015*abs(diff(c(1,g))) + 0.0015*l5$db_R05_V2)

wins <- list(
  IS_2005_2018  = l5$realized_ym >= "2005-01" & l5$realized_ym <= "2018-12",
  OOS_2019_2026 = l5$realized_ym >= "2019-01",
  FULL_267m     = rep(TRUE, nrow(l5)),
  SUB2017_2026  = l5$realized_ym >= "2017-01")
cat(sprintf("[V4] window n: IS=%d OOS=%d FULL=%d SUB=%d\n",
    sum(wins[[1]]), sum(wins[[2]]), sum(wins[[3]]), sum(wins[[4]])))

met <- function(r, m) {
  x <- xts(r[m], order.by = l5$anchor_date[m])
  ta <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  c(SR = as.numeric(ta[3,1]), CAGR = as.numeric(ta[1,1]),
    MDD = -abs(as.numeric(maxDrawdown(x))))
}

# ---- V4 reproduction: selected O3 + 1 random + incumbent repriced ----
set.seed(20260612)
others <- setdiff(names(gc_raw), "O3_MIDBAND_FLOOR")
rnd <- sample(others, 1)
cat(sprintf("[V4] random second candidate drawn (seed 20260612): %s\n", rnd))
stored <- as.data.table(read_json(file.path(OUT, "combine_ab_results.json"),
                                  simplifyVector = TRUE)$table)
check_arms <- c("O3_MIDBAND_FLOOR", rnd, "INCUMBENT_REPRICED")
fails <- 0L
for (arm in check_arms) for (wn in names(wins)) {
  m  <- met(rets[[arm]], wins[[wn]])
  s  <- stored[window == wn & arm_ == arm] # placeholder fixed below
}
# (data.table column is named 'arm' in stored; avoid name clash)
for (a in check_arms) for (wn in names(wins)) {
  m <- met(rets[[a]], wins[[wn]])
  s <- stored[stored$window == wn & stored$arm == a, ]
  cost_ann <- mean(costs[[a]][wins[[wn]]]) * 12
  dSR  <- round(m["SR"],4)  - s$SR
  dMDD <- round(m["MDD"],4) - s$MDD
  dCAGR<- round(m["CAGR"],4)- s$CAGR
  dC   <- round(cost_ann,5) - s$ann_overlay_cost
  ok <- abs(dSR) < 1e-6 && abs(dMDD) < 1e-6 && abs(dCAGR) < 1e-6 && abs(dC) < 1e-6
  if (!ok) fails <- fails + 1L
  cat(sprintf("[V4] %-18s %-13s SR %.4f (stored %.4f, d=%.1e) MDD %.4f (stored %.4f, d=%.1e) CAGR d=%.1e cost d=%.1e -> %s\n",
      a, wn, round(m["SR"],4), s$SR, dSR, round(m["MDD"],4), s$MDD, dMDD, dCAGR, dC,
      ifelse(ok, "MATCH", "MISMATCH")))
}
cat(sprintf("[V4] reproduction mismatches = %d\n", fails))

# ---- V5 unrounded IS SR argmax (selection robustness, all 5) ----
cat("[V5] unrounded IS SR (selection robustness):\n")
is_sr <- sapply(names(gc_raw), function(a) met(rets[[a]], wins$IS_2005_2018)["SR"])
is_mdd <- sapply(names(gc_raw), function(a) met(rets[[a]], wins$IS_2005_2018)["MDD"])
for (a in names(gc_raw))
  cat(sprintf("      %-18s IS SR = %.8f | IS MDD = %.12f\n", a, is_sr[paste0(a,".SR")], is_mdd[paste0(a,".MDD")]))
cat(sprintf("[V5] unrounded argmax = %s\n", names(gc_raw)[which.max(is_sr)]))

# ---- V6 OOS confirmation rule re-check ----
o3 <- met(rets$O3_MIDBAND_FLOOR, wins$OOS_2019_2026)
ic <- met(rets$INCUMBENT_REPRICED, wins$OOS_2019_2026)
sr_ok  <- round(o3["SR"],4)  >= round(ic["SR"],4) - 0.05
mdd_ok <- round(o3["MDD"],4) >= round(ic["MDD"],4) - 0.03
cat(sprintf("[V6] OOS confirm: O3 SR %.4f vs inc %.4f (rule >= inc-0.05: %s) | O3 MDD %.4f vs inc %.4f (rule <= inc+3pp: %s) -> %s\n",
    o3["SR"], ic["SR"], sr_ok, o3["MDD"], ic["MDD"], mdd_ok,
    ifelse(sr_ok && mdd_ok, "CONFIRMED", "FAIL")))

# ---- V7 CSV vs JSON consistency ----
csvt <- fread(file.path(OUT, "combine_ab_results.csv"))
jt   <- stored
setkey(csvt, window, arm); setDF(jt)
mm <- merge(csvt, as.data.table(jt), by = c("window","arm"), suffixes = c("_csv","_json"))
cat(sprintf("[V7] CSV vs JSON rows merged = %d (expect 32) | max|SR diff| = %.1e | max|MDD diff| = %.1e\n",
    nrow(mm), max(abs(mm$SR_csv - mm$SR_json)), max(abs(mm$MDD_csv - mm$MDD_json))))
cat("[done]\n")
