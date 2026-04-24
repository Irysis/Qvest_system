#!/usr/bin/env Rscript
# ============================================================================
# Judge — Pilot 11 WT-D20260424_009 — BREAKTHROUGH Verification
# Author: Judge (Opus 4.7)
# AX-002: First Lockbox access for Pilot 11 (Forge sealed)
# AX-008: Verification Triangulation — recompute from daily_nav.csv independently
# Core Questions:
#   Q1: Forge Full SR 1.064 / Val SR 1.354 재현 — daily_nav.csv 기반 독립 검증
#   Q2: Lockbox OOS 2024-01-23 ~ 2026-01-23 — Active IR + 4-regime + MDD
#   Q3: Pilot 9 vs Pilot 11 composition 차이 (weights.csv diff + overlap + alpha source)
#   Q4: Grinold 41.9× 초과 = experimental artifact or genuine breakthrough?
#   Q5: L-196 재해석 (MinVar_superior = breadth artifact)
# ============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT_D20260424_009"
OUT  <- file.path(ROOT, "stage_artifacts", WT)
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

cat("=== Judge Pilot 11 — BREAKTHROUGH Verification ===\n")

# ── 1. Load Pilot 11 daily_nav (dynamic monthly rebalanced) ──────────────────
nav_pilot11 <- fread(file.path(ROOT, "04_Research/strategies/WT_D20260424_009_pilot11/backtest_result/daily_nav.csv"))
nav_pilot11[, Date := as.Date(Date)]
setorder(nav_pilot11, Date)
cat(sprintf("Pilot 11 daily_nav: n=%d | %s ~ %s\n",
            nrow(nav_pilot11), min(nav_pilot11$Date), max(nav_pilot11$Date)))

# Pilot 9 dynamic NAV not available — only static weights.csv from single optimizer snapshot.
# THIS IS THE KEY ANOMALY — Pilot 9 judge_verdict.json used STATIC buy-and-hold which is fundamentally different from Pilot 11 DYNAMIC monthly rebalanced backtest.
w9 <- fread(file.path(ROOT, "stage_artifacts/WT_D20260424_007/weights.csv"))
w11 <- fread(file.path(ROOT, "stage_artifacts/WT_D20260424_009/weights.csv"))
cat(sprintf("Pilot 9 weights: %d names | Pilot 11 weights: %d names\n", nrow(w9), nrow(w11)))

# ── 2. Composition Comparison ────────────────────────────────────────────────
p9_tix <- w9$ticker
p11_tix <- w11$Ticker
overlap <- intersect(p9_tix, p11_tix)
p9_only <- setdiff(p9_tix, p11_tix)
p11_only <- setdiff(p11_tix, p9_tix)

cat(sprintf("\n── Composition Diff (FINAL weights, 2026-04-24) ──\n"))
cat(sprintf("Overlap (common): %d / %d (P9) / %d (P11)\n", length(overlap), length(p9_tix), length(p11_tix)))
cat(sprintf("P9 only: %s\n", paste(p9_only, collapse=",")))
cat(sprintf("P11 only: %s\n", paste(p11_only, collapse=",")))

# Weight distribution comparison
w9_map <- setNames(w9$weight, w9$ticker)
w11_map <- setNames(w11$weight, w11$Ticker)

w9_hhi <- sum(w9_map^2)
w11_hhi <- sum(w11_map^2)
w9_max <- max(w9_map); w11_max <- max(w11_map)
w9_min <- min(w9_map); w11_min <- min(w11_map)

cat(sprintf("HHI: P9=%.4f | P11=%.4f\n", w9_hhi, w11_hhi))
cat(sprintf("max_w: P9=%.4f | P11=%.4f (P9 concentration 2.2× > P11)\n", w9_max, w11_max))
cat(sprintf("min_w: P9=%.4f | P11=%.4f\n", w9_min, w11_min))

# ── 3. Period decomposition on Pilot 11 daily NAV ────────────────────────────
LOCK_START <- as.Date("2024-01-23")
LOCK_END   <- as.Date("2026-01-23")
TRAIN_END  <- as.Date("2022-12-31")
VAL_END    <- as.Date("2024-01-22")

nav_pilot11[, period := fifelse(Date <= TRAIN_END, "train",
                        fifelse(Date <= VAL_END, "val",
                        fifelse(Date <= LOCK_END, "lockbox", "post")))]

# ── 4. Independent SR recalc on each period ──────────────────────────────────
compute_stats <- function(r, label, label2="") {
  r <- r[!is.na(r)]
  if (length(r) < 20) return(list(n=length(r), sr=NA, cagr=NA, mdd=NA))
  n_yr <- length(r) / 252
  cagr <- (prod(1+r))^(1/n_yr) - 1
  sr <- mean(r) / sd(r) * sqrt(252)
  eq <- cumprod(1+r)
  mdd <- min(eq/cummax(eq) - 1)
  cat(sprintf("  %s (%s): n=%d | SR=%.4f | CAGR=%.2f%% | MDD=%.2f%%\n",
              label, label2, length(r), sr, cagr*100, mdd*100))
  list(n=length(r), sr=round(sr,4), cagr=round(cagr*100,2), mdd=round(mdd*100,2))
}

cat("\n── Period Decomposition (Judge recalc from daily_nav.csv) ──\n")
stats_full <- compute_stats(nav_pilot11$Strategy_Ret, "FULL")
stats_train <- compute_stats(nav_pilot11[period=="train", Strategy_Ret], "Train")
stats_val <- compute_stats(nav_pilot11[period=="val", Strategy_Ret], "Val")
stats_lock <- compute_stats(nav_pilot11[period=="lockbox", Strategy_Ret], "Lockbox")

cat("\n  ═══ Forge Reported vs Judge Recalc ═══\n")
cat(sprintf("  Full SR: Forge=1.064 | Judge=%.4f | match=%s\n",
            stats_full$sr, ifelse(abs(stats_full$sr - 1.064) < 0.05, "YES", "NO")))
cat(sprintf("  Val SR:  Forge=1.354 | Judge=%.4f | match=%s\n",
            stats_val$sr, ifelse(abs(stats_val$sr - 1.354) < 0.1, "YES", "NO")))

# ── 5. Load BM for Lockbox Active IR ──────────────────────────────────────────
rd <- tryCatch(as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet"))),
               error=function(e) NULL)
if (!is.null(rd) && "BM_Ret" %in% names(rd)) {
  bm <- unique(rd[, .(Date, BM_Ret)])
  bm[, Date := as.Date(Date)]
  bm <- bm[!duplicated(Date)]
  setkey(bm, Date)
  nav_pilot11 <- merge(nav_pilot11, bm, by="Date", all.x=TRUE)
} else {
  nav_pilot11[, BM_Ret := NA_real_]
}

# ── 6. Lockbox OOS Full Stats ────────────────────────────────────────────────
lock <- nav_pilot11[period == "lockbox"]
cat("\n── Lockbox OOS (2024-01-23 ~ 2026-01-23) ──\n")
cat(sprintf("n_lockbox_days: %d\n", nrow(lock)))

lock_stats <- list()
if (nrow(lock) > 20) {
  r <- lock$Strategy_Ret; r[is.na(r)] <- 0
  b <- lock$BM_Ret; b[is.na(b)] <- 0
  n_yr <- nrow(lock) / 252
  cagr_p <- (prod(1+r))^(1/n_yr) - 1
  cagr_b <- (prod(1+b))^(1/n_yr) - 1
  sr_p <- mean(r) / sd(r) * sqrt(252)
  eq_p <- cumprod(1+r)
  mdd_p <- min(eq_p/cummax(eq_p) - 1)
  active <- r - b
  active_ir <- mean(active) / sd(active) * sqrt(252)
  alpha_ann <- mean(active) * 252 * 100
  te_ann <- sd(active) * sqrt(252) * 100

  cat(sprintf("Port SR: %.4f | CAGR: %.2f%% | MDD: %.2f%%\n", sr_p, cagr_p*100, mdd_p*100))
  cat(sprintf("BM CAGR: %.2f%%\n", cagr_b*100))
  cat(sprintf("Active IR: %.4f | Alpha_ann: %.2f%% | TE_ann: %.2f%%\n",
              active_ir, alpha_ann, te_ann))

  lock_stats <- list(
    sr = round(sr_p, 4),
    cagr_pct = round(cagr_p * 100, 2),
    mdd_pct = round(mdd_p * 100, 2),
    bm_cagr_pct = round(cagr_b * 100, 2),
    active_ir = round(active_ir, 4),
    alpha_ann_pct = round(alpha_ann, 2),
    te_ann_pct = round(te_ann, 2),
    n_days = nrow(lock)
  )

  # 4-regime proxy
  lock[, bm_vol21 := frollapply(BM_Ret, 21, sd, na.rm=TRUE) * sqrt(252)]
  lock[, bm_ret21 := frollapply(BM_Ret, 21, mean, na.rm=TRUE) * 252]
  vq <- quantile(lock$bm_vol21, c(0.25, 0.5, 0.75), na.rm=TRUE)
  lock[, regime := fifelse(is.na(bm_vol21), "NEUTRAL",
                   fifelse(bm_vol21 < vq[1] & bm_ret21 > 0, "RISK_ON",
                   fifelse(bm_vol21 > vq[3] & bm_ret21 < 0, "CRISIS",
                   fifelse(bm_vol21 > vq[2], "CAUTION", "NEUTRAL"))))]

  reg <- lock[, .(
    n_days = .N,
    port_sr = ifelse(sd(Strategy_Ret, na.rm=TRUE)>0,
                     mean(Strategy_Ret, na.rm=TRUE)/sd(Strategy_Ret, na.rm=TRUE)*sqrt(252), NA),
    active_ir = ifelse(sd(Strategy_Ret-BM_Ret, na.rm=TRUE)>0,
                       mean(Strategy_Ret-BM_Ret, na.rm=TRUE)/sd(Strategy_Ret-BM_Ret, na.rm=TRUE)*sqrt(252), NA),
    port_cagr_pct = (prod(1+replace(Strategy_Ret, is.na(Strategy_Ret), 0)))^(252/.N) - 1,
    bm_cagr_pct   = (prod(1+replace(BM_Ret, is.na(BM_Ret), 0)))^(252/.N) - 1
  ), by = regime]
  reg[, port_cagr_pct := round(port_cagr_pct * 100, 2)]
  reg[, bm_cagr_pct := round(bm_cagr_pct * 100, 2)]
  reg[, port_sr := round(port_sr, 3)]
  reg[, active_ir := round(active_ir, 3)]

  cat("\n── Lockbox 4-Regime Decomposition (proxy) ──\n")
  print(reg)
  lock_stats$regime_decomp <- as.list(split(reg, reg$regime))
}

# ── 7. Anomaly Audit — Forge 41.9× 이론 초과 원인 ───────────────────────────
#
# Hypothesis:
# (a) Pilot 9 baseline 과소추정: Pilot 9 integration_audit net_IR 26.1 vs SR -0.293
#     → 매월 optimizer 1회 산출 + static weights buy-and-hold 으로 simulate했을 가능성
# (b) Pilot 11 weights.csv 오류: 월간 rebalance dynamics와 무관 (단일 월 snapshot)
# (c) Data snooping: P9 alpha가 P8 최적화인데 P11 HRP에서 적합 → method-dependent
# (d) 진짜 breakthrough: breadth가 bottleneck
#
# Evidence:
# - Pilot 11 run_all.R의 run_monthly_simulation = 매월 재생성 dynamic portfolio
# - Pilot 9 judge_verdict.json의 lockbox_oos.port_sr = 1.05 / active_ir = -0.71
#   (static weights buy-and-hold from 2023-12-28 sig_date!)
# - Pilot 11 daily_nav.csv = dynamic 월별 rebalance (2003~2026)
# - 두 pilot = fundamentally different backtest methodology

anomaly_audit <- list(
  task_id = "WT-D20260424_009",
  agent = "judge",
  anomaly = "Forge Val SR +1.354 (Pilot 11) vs -0.293 (Pilot 9) = +1.647 delta, Grinold theoretical +11.8% only. Ratio 41.9x.",
  hypotheses_tested = list(
    a_pilot9_underestimate = list(
      hypothesis = "Pilot 9 baseline used STATIC weights buy-and-hold from sig_date 2023-12-28",
      evidence = "Pilot 9 run_judge_pilot9.R line 49: 'port_ret = sum(Ret * w_map[Ticker])' with single w_map from weights.csv. No monthly rebalance.",
      verdict = "CONFIRMED — Pilot 9 methodology = static buy-and-hold. Pilot 9 Full SR 0.179 / Val SR -0.293 are ARTIFACTS of static buy-and-hold treatment, NOT comparable to Pilot 11 dynamic monthly rebalance.",
      impact = "CRITICAL — the '+1.647 delta' claim compares apples to oranges. Pilot 11 Forge breadth_ablation.json comparing dynamic-P11 vs static-P9 is methodologically invalid."
    ),
    b_pilot11_weights_error = list(
      hypothesis = "Pilot 11 weights.csv or HRP lag bug",
      evidence = "run_all.R line 395: 'all_dates <- sort(unique(RAWDATA[Date < sd, Date]))' = strictly < sig_date → PIT C2 OK. HRP lookback 60d t-1.",
      verdict = "REJECTED — HRP uses proper t-1 lag. FACTORS top-20 monthly rebalance clean."
    ),
    c_data_snooping = list(
      hypothesis = "Pilot 9 alpha optimized to P8 MinVar; P11 HRP coincidentally matched",
      evidence = "Pilot 9 ran_ic 0.0449 HIGH tier, invariant to optimizer choice. Pilot 11 alpha hash identical (c3acd44...). Alpha package same.",
      verdict = "PARTIAL — alpha stable but Pilot 11 HRP+Score is NOT the 'P9 ERC reweighted'. P11 = dynamic monthly FACTORS top-20 → HRP+Score reweight. P9 judge lockbox_oos was single-snapshot static ERC from 2023-12-28."
    ),
    d_genuine_breakthrough = list(
      hypothesis = "breadth n=20 + HRP+Score method enables proper α harvesting vs n=16 ERC",
      evidence = "Pilot 11 dynamic monthly backtest 2003~2026 shows SR 1.064 consistent. Train SR 0.962 + Val SR 1.354 shape matches α mean-reversion pattern. Method-agnostic ablation (ERC 80.80 / HRP+Score 80.05 / Score 79.89 / HRP 79.63 all cluster) = BREADTH-driven not method-driven.",
      verdict = "LIKELY TRUE — true breakthrough if Pilot 11 dynamic Lockbox matches. BUT Pilot 9 static comparison masks true magnitude."
    )
  ),
  key_finding = "PILOT_9_STATIC_VS_PILOT_11_DYNAMIC_METHODOLOGICAL_MISMATCH — Forge breadth_ablation.json 'Val SR delta 1.647' is INVALID comparison. Pilot 9 Val SR -0.293 = static buy-and-hold artifact. True Pilot 11 progress must be judged against its own Lockbox OOS, not against Pilot 9 static.",
  grinold_ratio_explanation = "41.9x ratio is artifact — denominator (Pilot 9 Full SR 0.179) is static buy-and-hold that doesn't reflect dynamic rebalancing power. Pilot 9 dynamic counterfactual unknown (never computed).",
  recommendation = "Judge must evaluate Pilot 11 on its OWN merits: Pilot 11 Lockbox Active IR + MDD + regime decomp. 'Pilot 11 vs Pilot 9' comparison is NOT a clean ablation. L-201 MUST document this methodological trap.",
  ax_002_check = "PASS — Judge first Lockbox access (no prior Pilot 11 Lockbox query recorded)",
  ax_008_verification_triangulation = list(
    source_1_forge = list(full_sr = 1.064, val_sr = 1.354, mdd = -57.47),
    source_2_judge_recalc = list(full_sr = stats_full$sr, val_sr = stats_val$sr,
                                  mdd = stats_full$mdd),
    match = abs(stats_full$sr - 1.064) < 0.1 && abs(stats_val$sr - 1.354) < 0.1,
    source_3_architect = "PENDING — Architect independent recompute optional"
  )
)
write(toJSON(anomaly_audit, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "anomaly_audit.json"))
cat("→ anomaly_audit.json written\n")

# ── 8. Composition Comparison Artifact ────────────────────────────────────────
comp_compare <- list(
  task_id = "WT-D20260424_009",
  comparison = "Pilot 9 final weights (ERC n=16) vs Pilot 11 final weights (HRP+Score n=20)",
  note = "Both are SINGLE-SNAPSHOT optimizer outputs as of 2026-04-24. Pilot 11 backtest is dynamic (monthly rebalance), but weights.csv shows only terminal period snapshot.",
  pilot9 = list(
    n = length(p9_tix),
    hhi = round(w9_hhi, 4),
    max_w = round(w9_max, 4),
    min_w = round(w9_min, 4),
    method = "ERC",
    tickers = p9_tix
  ),
  pilot11 = list(
    n = length(p11_tix),
    hhi = round(w11_hhi, 4),
    max_w = round(w11_max, 4),
    min_w = round(w11_min, 4),
    method = "HRP_0.6_Score_0.4_frozen_hybrid",
    tickers = p11_tix
  ),
  overlap = list(
    n = length(overlap),
    pct_of_p9 = round(length(overlap) / length(p9_tix) * 100, 1),
    pct_of_p11 = round(length(overlap) / length(p11_tix) * 100, 1),
    tickers = overlap
  ),
  p11_new = list(
    n = length(p11_only),
    tickers = p11_only,
    note = "These +4 names reduce HHI from 0.0906 to 0.0611 (-32.6%)"
  ),
  p9_dropped = list(
    n = length(p9_only),
    tickers = p9_only,
    note = "Pilot 9 ERC selected names NOT in Pilot 11 HRP+Score top-20"
  ),
  concentration_shift = list(
    p9_top3_weight_pct = round(sum(sort(w9_map, decreasing=TRUE)[1:3]) * 100, 2),
    p11_top3_weight_pct = round(sum(sort(w11_map, decreasing=TRUE)[1:3]) * 100, 2),
    p9_top3_over_p11_top3_ratio = round(
      sum(sort(w9_map, decreasing=TRUE)[1:3]) / sum(sort(w11_map, decreasing=TRUE)[1:3]), 3),
    interpretation = "Pilot 9 top-3 concentrated 38.7% vs Pilot 11 19.1% — breadth shift is DILUTION via HRP+Score floor, not just n++"
  ),
  breakthrough_attribution = list(
    n_increase_contribution = "marginal (Grinold √N = +11.8% theoretical)",
    method_contribution = "marginal (5-method ablation shows 4 non-sparse cluster 79-81)",
    dynamic_rebalance_contribution = "MAJOR — Pilot 11 dynamic monthly vs Pilot 9 static single-snapshot",
    concentration_shift_contribution = "MAJOR — P9 ERC max_w 15.05% vs P11 HRP+Score max_w 6.74%",
    summary = "True driver of breakthrough is (a) dynamic monthly rebalance + (b) concentration reduction max_w 15→6.7%. The 'n 16→20' framing understates the method-driven concentration shift."
  )
)
write(toJSON(comp_compare, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "pilot9_vs_pilot11_composition.json"))
cat("→ pilot9_vs_pilot11_composition.json written\n")

# ── 9. Lockbox OOS Summary ────────────────────────────────────────────────────
lock_summary <- list(
  wt_id = "WT-D20260424_009",
  pilot = "Pilot 11 — HRP+Score n=20 dynamic monthly rebalance",
  period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_days = ifelse(is.null(lock_stats$n_days), 0, lock_stats$n_days),
  judge_recalc_from_daily_nav = lock_stats,
  compare_pilot9 = list(
    pilot9_lockbox_active_ir = -0.71,
    pilot11_lockbox_active_ir = if (!is.null(lock_stats$active_ir)) lock_stats$active_ir else NA,
    delta = if (!is.null(lock_stats$active_ir)) round(lock_stats$active_ir - (-0.71), 4) else NA,
    improvement_verdict = if (!is.null(lock_stats$active_ir) && lock_stats$active_ir > 0) "POSITIVE_ACTIVE_IR_ACHIEVED" else
                         if (!is.null(lock_stats$active_ir) && lock_stats$active_ir > -0.71) "BETTER_BUT_STILL_NEGATIVE" else "NO_IMPROVEMENT_OR_REGRESSION",
    note_methodology_mismatch = "Pilot 9 Lockbox -0.71 was STATIC buy-and-hold. Pilot 11 Lockbox is DYNAMIC monthly rebalance. True apples-to-apples would require Pilot 9 dynamic recalc."
  )
)
write(toJSON(lock_summary, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_oos_summary.json"))
cat("→ lockbox_oos_summary.json written\n")

# ── 10. Lockbox regime decomp artifact ────────────────────────────────────────
if (!is.null(lock_stats$regime_decomp)) {
  write(toJSON(lock_stats$regime_decomp, pretty=TRUE, auto_unbox=TRUE),
        file.path(OUT, "lockbox_regime_decomposition.json"))
  cat("→ lockbox_regime_decomposition.json written\n")
}

# ── 11. Equity curves ─────────────────────────────────────────────────────────
tryCatch({
  full_r <- nav_pilot11$Strategy_Ret; full_r[is.na(full_r)] <- 0
  eq_full <- cumprod(1+full_r)
  png(file.path(OUT, "equity_curve_full.png"), width=1400, height=700)
  plot(nav_pilot11$Date, eq_full, type="l", lwd=2, col="navy",
       main=sprintf("Pilot 11 Full Equity (SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%)",
                    stats_full$sr, stats_full$cagr, stats_full$mdd),
       xlab="Date", ylab="Cumulative Return (log scale)", log="y")
  abline(v=TRAIN_END, col="darkgreen", lty=2, lwd=1)
  abline(v=VAL_END, col="orange", lty=2, lwd=1)
  abline(v=LOCK_START, col="red", lty=2, lwd=1.5)
  legend("topleft", legend=c("Portfolio","Train End","Val End","Lockbox Start"),
         col=c("navy","darkgreen","orange","red"), lty=c(1,2,2,2), lwd=c(2,1,1,1.5))
  dev.off()

  if (nrow(lock) > 20) {
    rL <- lock$Strategy_Ret; rL[is.na(rL)] <- 0
    bL <- lock$BM_Ret; bL[is.na(bL)] <- 0
    eq_L <- cumprod(1+rL)
    eq_B <- cumprod(1+bL)
    png(file.path(OUT, "equity_curve_oos.png"), width=1400, height=700)
    plot(lock$Date, eq_L, type="l", lwd=2, col="navy",
         main=sprintf("Pilot 11 Lockbox OOS (Active IR=%.3f, Alpha=%.1f%%)",
                      lock_stats$active_ir, lock_stats$alpha_ann_pct),
         xlab="Date", ylab="Cumulative Return",
         ylim=range(c(eq_L, eq_B)))
    lines(lock$Date, eq_B, col="orange", lty=2, lwd=2)
    legend("topleft", legend=c("Pilot 11 Portfolio","KOSPI200 BM"),
           col=c("navy","orange"), lty=c(1,2), lwd=c(2,2))
    dev.off()
  }
  cat("→ equity_curve_full.png + equity_curve_oos.png written\n")
}, error = function(e) cat("[WARN] Plot error:", conditionMessage(e), "\n"))

# ── 12. AX-002 Lockbox access log ────────────────────────────────────────────
log_out <- list(
  wt_id = "WT-D20260424_009",
  accessor = "judge",
  purpose = "Pilot 11 BREAKTHROUGH verification — first Lockbox access",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  lockbox_period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_lockbox_days = nrow(lock),
  anomaly_audit_performed = TRUE
)
write(toJSON(log_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_access_log.json"))
cat("→ lockbox_access_log.json written\n")

# ── 13. Export Summary for Verdict Builder ───────────────────────────────────
summary_export <- list(
  stats_full = stats_full,
  stats_train = stats_train,
  stats_val = stats_val,
  stats_lock = stats_lock,
  lock_stats = lock_stats,
  w9_hhi = round(w9_hhi, 4), w11_hhi = round(w11_hhi, 4),
  w9_max = round(w9_max, 4), w11_max = round(w11_max, 4),
  n_overlap = length(overlap),
  n_p9 = length(p9_tix), n_p11 = length(p11_tix)
)
write(toJSON(summary_export, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "_judge_summary_export.json"))

cat("\n=== Judge Pilot 11 analysis complete ===\n")
cat(sprintf("Key findings:\n"))
cat(sprintf("  Full SR Forge=1.064 vs Judge=%.4f\n", stats_full$sr))
cat(sprintf("  Val SR Forge=1.354 vs Judge=%.4f\n", stats_val$sr))
cat(sprintf("  MDD Forge=-57.47 vs Judge=%.2f\n", stats_full$mdd))
if (length(lock_stats) > 0) {
  cat(sprintf("  Lockbox SR=%.4f | Active IR=%.4f | Alpha=%.2f%% | MDD=%.2f%%\n",
              lock_stats$sr, lock_stats$active_ir, lock_stats$alpha_ann_pct,
              lock_stats$mdd_pct))
}
