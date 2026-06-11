# =============================================================================
# probe_verify.R - Track W adversarial verification probe (independent)
#   A. Extract run_trial_portfolio + COMMISSION from trackw_engine.R (actual
#      code text, no heavy harness sourcing) and test on synthetic data:
#      A1 cost delta-proportionality (two methods, different turnover)
#      A2 drift-aware netting + gross return correctness vs hand expectation
#   B. Prep-output audit (s1_sel / s1_grid / bench_monthly / b_panel):
#      B1 grid integrity (r_idx = next month-end of w_idx, unique, sorted)
#      B2 selection integrity (20 names/month, Score non-NA, formula check)
#      B3 forward-return PIT direction: Ret_1m(w_idx) == compound of daily Ret
#         over the CALENDAR MONTH OF r_idx (next month) from RAWDATA - sample
#      B4 bench_monthly spot-check vs benchmark parquet
# Output: ASCII only. Verifier-side hand math is cross-check, not reporting.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(arrow)
})
options(scipen = 999)
PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TW <- file.path(PR, "04_Research/composition_search/cycle1b_trackW")
INT <- file.path(TW, "intermediate")

fails <- character(0)
chk <- function(name, cond, detail = "") {
  status <- if (isTRUE(cond)) "PASS" else "FAIL"
  if (!isTRUE(cond)) fails <<- c(fails, name)
  cat(sprintf("[%s] %s %s\n", status, name, detail))
}

# ── A. extract actual engine code (COMMISSION + run_trial_portfolio only) ────
exprs <- parse(file.path(TW, "trackw_engine.R"))
got <- 0L
for (e in exprs) {
  if (is.call(e) && identical(as.character(e[[1]]), "<-")) {
    lhs <- deparse(e[[2]])
    if (lhs %in% c("COMMISSION", "run_trial_portfolio")) { eval(e); got <- got + 1L }
  }
}
chk("A0_code_extraction", got == 2L, sprintf("(extracted %d/2 defs)", got))
chk("A0_commission_value", isTRUE(all.equal(COMMISSION, 0.0015)), sprintf("COMMISSION=%g", COMMISSION))

# ── A1. cost delta proportionality (zero returns -> no drift) ────────────────
mg <- data.table(w_idx = as.Date(c("2020-01-31","2020-02-29","2020-03-31")),
                 r_idx = as.Date(c("2020-02-29","2020-03-31","2020-04-30")))
# zero returns for two names across all months
rets0 <- CJ(w_idx = mg$w_idx, Ticker = c("AAA","BBB"))[, Ret_1m := 0]
bench <- data.table(r_idx = mg$r_idx, bm_ret = 0)
# LOW turnover: constant 50/50
wL <- CJ(w_idx = mg$w_idx, Ticker = c("AAA","BBB"))[, w := 0.5]
# HIGH turnover: flip 100% each month  (1,0) -> (0,1) -> (1,0)
wH <- rbindlist(list(
  data.table(w_idx = mg$w_idx[1], Ticker = c("AAA","BBB"), w = c(1,0)),
  data.table(w_idx = mg$w_idx[2], Ticker = c("AAA","BBB"), w = c(0,1)),
  data.table(w_idx = mg$w_idx[3], Ticker = c("AAA","BBB"), w = c(1,0))))
mL <- run_trial_portfolio(wL, rets0, mg, bench)
mH <- run_trial_portfolio(wH, rets0, mg, bench)
# expectations (hand cross-check): LOW traded = 1,0,0 ; HIGH traded = 1,2,2
chk("A1_low_traded",  isTRUE(all.equal(mL$traded, c(1,0,0), tolerance = 1e-12)),
    sprintf("got [%s]", paste(sprintf("%.6f", mL$traded), collapse = ",")))
chk("A1_high_traded", isTRUE(all.equal(mH$traded, c(1,2,2), tolerance = 1e-12)),
    sprintf("got [%s]", paste(sprintf("%.6f", mH$traded), collapse = ",")))
chk("A1_cost_eq_traded_x_15bps",
    isTRUE(all.equal(mL$cost, mL$traded * 0.0015, tolerance = 1e-12)) &&
    isTRUE(all.equal(mH$cost, mH$traded * 0.0015, tolerance = 1e-12)))
# delta model discriminator: same rebalance count, cost ratio == turnover ratio (not flat)
rt <- sum(mH$cost[-1]) / max(sum(mL$cost[-1]), 1e-300)
chk("A1_delta_not_flat", is.infinite(rt) || rt > 100,
    sprintf("(post-initial cost LOW=%.6f HIGH=%.6f; flat model would equalize)",
            sum(mL$cost[-1]), sum(mH$cost[-1])))

# ── A2. drift-aware netting + gross return vs hand expectation ───────────────
r1 <- c(AAA = 0.10, BBB = -0.05); r2 <- c(AAA = 0.02, BBB = 0.03)
mg2 <- mg[1:2]
rets2 <- rbindlist(list(
  data.table(w_idx = mg2$w_idx[1], Ticker = names(r1), Ret_1m = as.numeric(r1)),
  data.table(w_idx = mg2$w_idx[2], Ticker = names(r2), Ret_1m = as.numeric(r2))))
w2 <- rbindlist(list(
  data.table(w_idx = mg2$w_idx[1], Ticker = c("AAA","BBB"), w = c(0.6, 0.4)),
  data.table(w_idx = mg2$w_idx[2], Ticker = c("AAA","BBB"), w = c(0.5, 0.5))))
m2 <- run_trial_portfolio(w2, rets2, mg2, bench[1:2])
g1_exp <- 0.6 * 0.10 + 0.4 * (-0.05)            # 0.04
eop1 <- c(0.6 * 1.10, 0.4 * 0.95) / (1 + g1_exp) # drifted weights
g2_exp <- 0.5 * 0.02 + 0.5 * 0.03
tr2_exp <- sum(abs(c(0.5, 0.5) - eop1))
chk("A2_gross_m1", isTRUE(all.equal(m2$ret_gross[1], g1_exp, tolerance = 1e-12)),
    sprintf("got %.10f exp %.10f", m2$ret_gross[1], g1_exp))
chk("A2_gross_m2", isTRUE(all.equal(m2$ret_gross[2], g2_exp, tolerance = 1e-12)))
chk("A2_traded_m2_drift_aware", isTRUE(all.equal(m2$traded[2], tr2_exp, tolerance = 1e-12)),
    sprintf("got %.10f exp %.10f (naive |dW| target-target would be %.10f)",
            m2$traded[2], tr2_exp, sum(abs(c(0.5,0.5) - c(0.6,0.4)))))
chk("A2_net_eq_gross_minus_cost",
    isTRUE(all.equal(m2$ret_net, m2$ret_gross - m2$cost, tolerance = 1e-15)))

# ── B. prep output audit ─────────────────────────────────────────────────────
s1g <- fread(file.path(INT, "s1_grid.csv"))
s1g[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
me <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L
nxt_me <- as.Date(vapply(s1g$w_idx, function(d)
  as.character(me(seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2])),
  character(1)))
chk("B1_grid_r_is_next_month_end", all(s1g$r_idx == nxt_me),
    sprintf("(%d rows, %d mismatches)", nrow(s1g), sum(s1g$r_idx != nxt_me)))
chk("B1_grid_unique_sorted", !anyDuplicated(s1g$w_idx) && !is.unsorted(s1g$w_idx))

s1 <- as.data.table(read_parquet(file.path(INT, "s1_sel.parquet")))
s1[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx), Date = as.Date(Date))]
cnt <- s1[, .N, by = w_idx]
chk("B2_20_names_per_month", all(cnt$N == 20),
    sprintf("(months=%d, N range %d..%d)", nrow(cnt), min(cnt$N), max(cnt$N)))
chk("B2_score_non_na", s1[is.na(Score), .N] == 0)
chk("B2_sel_months_in_grid", all(s1$w_idx %in% s1g$w_idx))

pan <- as.data.table(read_parquet(file.path(INT, "b_panel.parquet")))
pan[, Date := as.Date(Date)]
mm <- merge(s1[, .(Date, Ticker, Score, Ret_1m)],
            pan[, .(Date, Ticker, score_eff, score_core_z, score_defense_z, Ret_1m_pan = Ret_1m)],
            by = c("Date","Ticker"), all.x = TRUE)
chk("B2_score_eq_score_eff", isTRUE(all.equal(mm$Score, mm$score_eff, tolerance = 1e-12)))
fdiff <- max(abs(mm$score_eff - (0.65 * mm$score_core_z + 0.35 * mm$score_defense_z)), na.rm = TRUE)
chk("B2_prod_formula_65_35", fdiff < 1e-9, sprintf("max|diff|=%.2e", fdiff))
rdiff <- mm[!is.na(Ret_1m_pan), max(abs(Ret_1m - Ret_1m_pan))]
chk("B2_ret1m_matches_panel", rdiff < 1e-12, sprintf("max|diff|=%.2e", rdiff))

# ── B3. forward-return PIT direction vs RAWDATA (sample of 8 rows) ───────────
set.seed(7)
smp <- s1[Ret_1m != 0][sample(.N, 8)]
tks <- unique(smp$Ticker)
rd <- as.data.table(read_parquet(file.path(PR, ".cache/RAWDATA.parquet"),
                                 col_select = c("Date","Ticker","Ret")))
rd <- rd[Ticker %in% tks]
rd[, Date := as.Date(Date)]
rd[, ym := format(Date, "%Y-%m")]
ok_fwd <- logical(nrow(smp)); same_m <- numeric(nrow(smp))
for (i in seq_len(nrow(smp))) {
  ym_fwd  <- format(smp$r_idx[i], "%Y-%m")     # month AFTER formation
  ym_form <- format(smp$w_idx[i], "%Y-%m")     # formation month
  v  <- rd[Ticker == smp$Ticker[i] & ym == ym_fwd  & !is.na(Ret), Ret]
  vf <- rd[Ticker == smp$Ticker[i] & ym == ym_form & !is.na(Ret), Ret]
  cmp  <- if (length(v))  prod(1 + v)  - 1 else NA_real_  # verifier cross-check math
  cmpf <- if (length(vf)) prod(1 + vf) - 1 else NA_real_
  ok_fwd[i] <- isTRUE(all.equal(smp$Ret_1m[i], cmp, tolerance = 1e-8))
  same_m[i] <- if (is.na(cmpf)) NA_real_ else abs(smp$Ret_1m[i] - cmpf)
  cat(sprintf("  B3 %s %s w=%s r=%s Ret_1m=%+.6f fwd_month=%+.6f form_month=%+.6f %s\n",
              smp$Ticker[i], as.character(smp$Date[i]), as.character(smp$w_idx[i]),
              as.character(smp$r_idx[i]), smp$Ret_1m[i],
              ifelse(is.na(cmp), NaN, cmp), ifelse(is.na(cmpf), NaN, cmpf),
              ifelse(ok_fwd[i], "OK", "MISMATCH")))
}
chk("B3_ret1m_is_forward_month", all(ok_fwd),
    sprintf("(%d/%d matched next-month compound)", sum(ok_fwd), length(ok_fwd)))
chk("B3_not_same_month", sum(same_m < 1e-8, na.rm = TRUE) <= 1,
    "(formation-month return does NOT equal Ret_1m except chance)")
rm(rd); invisible(gc(FALSE))

# ── B4. bench_monthly spot-check vs benchmark parquet ────────────────────────
bmq <- as.data.table(read_parquet(file.path(PR, ".cache/benchmark.parquet")))
bmq[, Date := as.Date(Date)]
bm <- fread(file.path(INT, "bench_monthly.csv"))
spot <- c("2008-10", "2020-03", "2024-06")
all_ok <- TRUE
for (s in spot) {
  v <- bmq[format(Date, "%Y-%m") == s & !is.na(BM_Ret), BM_Ret]
  exp <- prod(1 + v) - 1                       # verifier cross-check math
  got <- bm[ym == s, bm_ret]
  ok <- isTRUE(all.equal(got, exp, tolerance = 1e-8))
  all_ok <- all_ok && ok
  cat(sprintf("  B4 %s bench=%+.6f recomputed=%+.6f %s\n", s, got, exp, ifelse(ok, "OK", "MISMATCH")))
}
chk("B4_bench_monthly", all_ok)

cat("\n=== PROBE SUMMARY ===\n")
if (length(fails) == 0) cat("ALL CHECKS PASS\n") else
  cat(sprintf("FAILURES (%d): %s\n", length(fails), paste(fails, collapse = ", ")))
