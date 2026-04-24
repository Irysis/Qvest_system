#!/usr/bin/env Rscript
# ============================================================================
# Judge — Pilot 10 WT-D20260424_008 — Lockbox Overlay Ablation
# Author: Judge (Opus 4.7)
# Core Question:
#   Pilot 10 = Pilot 9 alpha/risk/opt + Monthly 3-Layer MRS Overlay.
#   Forge train+val: OVERLAY_MARGINAL (SR -0.05 나쁨, MDD +3.01 개선).
#   Lockbox (2024-01~2026-01)에 CRISIS 4.3% 포함 (Pilot 9: Active IR +3.92).
#   **Lockbox에서 overlay가 CRISIS alpha를 오히려 깎았는지 / 개선했는지 판정.**
# ============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT_D20260424_008"
OUT  <- file.path(ROOT, "stage_artifacts", WT)
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

cat("=== Judge Pilot 10 — Lockbox Overlay Ablation ===\n")

# ── 1. Load artifacts ────────────────────────────────────────────────────────
weights <- fread(file.path(OUT, "weights.csv"))
cat("Weights:", nrow(weights), "names | sum =", round(sum(weights$weight),6), "\n")

rd <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
mrs <- as.data.table(read_parquet(file.path(ROOT, ".cache/unified_regime_signal.parquet")))

SIG_DATE   <- as.Date("2023-12-28")
LOCK_START <- as.Date("2024-01-23")
LOCK_END   <- as.Date("2026-01-23")

tickers <- weights$ticker
w_map <- setNames(weights$weight, weights$ticker)

# ── 2. Portfolio daily returns within Lockbox ─────────────────────────────────
ret_dt <- rd[Ticker %in% tickers & Date >= LOCK_START & Date <= LOCK_END,
             .(Date, Ticker, Ret, BM_Ret)]
setkey(ret_dt, Date, Ticker)

lock_daily <- ret_dt[, .(port_ret = sum(Ret * w_map[Ticker], na.rm=TRUE),
                         bm_ret   = mean(BM_Ret, na.rm=TRUE),
                         n_active = sum(!is.na(Ret))),
                     by = Date]
lock_daily <- lock_daily[n_active > 0]
setorder(lock_daily, Date)
cat("Lockbox daily rows:", nrow(lock_daily), "\n")

# ── 3. Monthly MRS → Layer assignment (C5 PIT: prior month-end MRS → next month fw) ─
mrs_lock <- mrs[Date >= as.Date("2023-11-30") & Date <= LOCK_END,
                .(eom = Date, MRS = Regime_Score)]
setorder(mrs_lock, eom)

# crisis_consec: 이전(포함) N개월 중 MRS>=60 연속 월수
mrs_lock[, crisis_ind := as.integer(MRS >= 60)]
mrs_lock[, crisis_consec := {
  # Rolling-back consecutive count (PIT: at time t, using prior months' crisis_ind)
  n <- .N
  out <- integer(n)
  for (i in seq_len(n)) {
    c <- 0L
    for (j in i:1) {
      if (crisis_ind[j] == 1L) c <- c + 1L else break
    }
    out[i] <- c
  }
  out
}]

# Layer + fw
mrs_lock[, fw := fifelse(
  MRS < 30, 1.0,
  fifelse(MRS >= 60 & crisis_consec >= 3, 0.0,
          pmax(0.5, 1 - (MRS - 30) / 60)))]
mrs_lock[, layer := fifelse(
  MRS < 30, 1L,
  fifelse(MRS >= 60 & crisis_consec >= 3, 3L, 2L))]

# PIT apply rule: for month m, use MRS of end of month m-1
# Here mrs_lock$eom is month-end; apply fw to the NEXT month
mrs_lock[, next_month_start := {
  y <- as.integer(format(eom, "%Y"))
  m <- as.integer(format(eom, "%m"))
  ny <- ifelse(m == 12, y + 1L, y)
  nm <- ifelse(m == 12, 1L, m + 1L)
  as.Date(sprintf("%04d-%02d-01", ny, nm))
}]
mrs_lock[, apply_ym := format(next_month_start, "%Y-%m")]

cat("\n── MRS Lockbox monthly (prior-month-end → applied to next month) ──\n")
print(mrs_lock[, .(eom, MRS = round(MRS, 2), crisis_consec, layer, fw = round(fw, 3), apply_ym)])

# ── 4. Attach fw to daily returns ─────────────────────────────────────────────
lock_daily[, ym := format(Date, "%Y-%m")]
# merge fw by apply_ym
lock_daily <- merge(lock_daily, mrs_lock[, .(apply_ym, fw, layer)],
                    by.x = "ym", by.y = "apply_ym", all.x = TRUE)
setorder(lock_daily, Date)

# fallback: days without fw → assume Layer 1
lock_daily[is.na(fw), fw := 1.0]
lock_daily[is.na(layer), layer := 1L]

# ── 5. Overlay applied return (cash=0 return remainder) ───────────────────────
# overlay: r_overlay = fw * r_port + (1-fw) * 0
# Switching cost: 15 bps on month-boundary where fw changes
lock_daily[, fw_lag := shift(fw, 1, fill = 1.0)]
lock_daily[, sw_event := as.integer(fw != fw_lag)]
n_switches <- sum(lock_daily$sw_event)
lock_daily[, sw_cost := sw_event * 0.0015]

lock_daily[, port_ret_overlay := fw * port_ret - sw_cost]

cat("\nLockbox switch events:", n_switches, "| total cost:", round(sum(lock_daily$sw_cost)*100, 4), "%\n")

# ── 6. Compute Lockbox stats (baseline vs overlay) ────────────────────────────
calc_stats <- function(r, b) {
  n <- length(r)
  n_years <- n / 252
  cagr <- (prod(1 + r, na.rm=TRUE))^(1/n_years) - 1
  sr <- mean(r, na.rm=TRUE) / sd(r, na.rm=TRUE) * sqrt(252)
  eq <- cumprod(1 + replace(r, is.na(r), 0))
  mdd <- min(eq / cummax(eq) - 1, na.rm=TRUE)
  active <- r - b
  ir <- mean(active, na.rm=TRUE) / sd(active, na.rm=TRUE) * sqrt(252)
  alpha_ann <- mean(active, na.rm=TRUE) * 252 * 100
  te_ann <- sd(active, na.rm=TRUE) * sqrt(252) * 100
  list(sr=sr, cagr=cagr*100, mdd=mdd*100,
       active_ir=ir, alpha_ann=alpha_ann, te_ann=te_ann)
}

base <- calc_stats(lock_daily$port_ret, lock_daily$bm_ret)
ovl  <- calc_stats(lock_daily$port_ret_overlay, lock_daily$bm_ret)

cat("\n── Lockbox (baseline Pilot 9) ──\n")
cat(sprintf("SR %.3f | CAGR %.2f%% | MDD %.2f%% | Active IR %.3f | α %.2f%% | TE %.2f%%\n",
            base$sr, base$cagr, base$mdd, base$active_ir, base$alpha_ann, base$te_ann))
cat("\n── Lockbox (Pilot 10 overlay applied) ──\n")
cat(sprintf("SR %.3f | CAGR %.2f%% | MDD %.2f%% | Active IR %.3f | α %.2f%% | TE %.2f%%\n",
            ovl$sr, ovl$cagr, ovl$mdd, ovl$active_ir, ovl$alpha_ann, ovl$te_ann))

delta <- list(
  sr = ovl$sr - base$sr,
  cagr = ovl$cagr - base$cagr,
  mdd = ovl$mdd - base$mdd,  # positive=improvement (less negative MDD)
  active_ir = ovl$active_ir - base$active_ir,
  alpha_ann = ovl$alpha_ann - base$alpha_ann,
  te_ann = ovl$te_ann - base$te_ann
)

cat("\n── Delta (Pilot 10 Overlay - Pilot 9 Baseline) ──\n")
cat(sprintf("ΔSR %+.3f | ΔCAGR %+.2fpp | ΔMDD %+.2fpp | ΔActive_IR %+.3f | Δα %+.2fpp | ΔTE %+.2fpp\n",
            delta$sr, delta$cagr, delta$mdd, delta$active_ir, delta$alpha_ann, delta$te_ann))

# ── 7. Layer composition in Lockbox ───────────────────────────────────────────
layer_comp <- lock_daily[, .(
  n_days = .N,
  pct = round(100 * .N / nrow(lock_daily), 1),
  mean_fw = round(mean(fw, na.rm=TRUE), 3),
  base_sr = mean(port_ret, na.rm=TRUE)/sd(port_ret, na.rm=TRUE)*sqrt(252),
  overlay_sr = mean(port_ret_overlay, na.rm=TRUE)/sd(port_ret_overlay, na.rm=TRUE)*sqrt(252),
  base_active_ir = mean(port_ret - bm_ret, na.rm=TRUE)/sd(port_ret - bm_ret, na.rm=TRUE)*sqrt(252),
  overlay_active_ir = mean(port_ret_overlay - bm_ret, na.rm=TRUE)/sd(port_ret_overlay - bm_ret, na.rm=TRUE)*sqrt(252)
), by = layer]
setorder(layer_comp, layer)

cat("\n── Lockbox Layer composition ──\n")
print(layer_comp)

# ── 8. Regime decomposition (Pilot 9 methodology: BM vol/ret quantile proxy) ─
bm_roll_vol <- frollapply(lock_daily$bm_ret, 21, sd, na.rm=TRUE) * sqrt(252)
bm_roll_ret <- frollapply(lock_daily$bm_ret, 21, mean, na.rm=TRUE) * 252
lock_daily[, vol21 := bm_roll_vol]
lock_daily[, ret21 := bm_roll_ret]

vol_q <- quantile(lock_daily$vol21, c(0.25, 0.5, 0.75), na.rm=TRUE)
lock_daily[, regime_proxy := fifelse(vol21 < vol_q[1] & ret21 > 0, "RISK_ON",
                            fifelse(vol21 > vol_q[3] & ret21 < 0, "CRISIS",
                            fifelse(vol21 > vol_q[2], "CAUTION", "NEUTRAL")))]

reg_base <- lock_daily[!is.na(regime_proxy), .(
  n_days = .N,
  sr_base = mean(port_ret, na.rm=TRUE)/sd(port_ret, na.rm=TRUE)*sqrt(252),
  sr_overlay = mean(port_ret_overlay, na.rm=TRUE)/sd(port_ret_overlay, na.rm=TRUE)*sqrt(252),
  active_ir_base = mean(port_ret - bm_ret, na.rm=TRUE)/sd(port_ret - bm_ret, na.rm=TRUE)*sqrt(252),
  active_ir_overlay = mean(port_ret_overlay - bm_ret, na.rm=TRUE)/sd(port_ret_overlay - bm_ret, na.rm=TRUE)*sqrt(252),
  mean_fw = round(mean(fw, na.rm=TRUE), 3)
), by = regime_proxy]
setorder(reg_base, -n_days)

cat("\n── Lockbox Regime Decomposition (baseline vs overlay) ──\n")
print(reg_base)

# ── 9. Verdict determination ──────────────────────────────────────────────────
# OVERLAY_DECISIVE: Active IR 개선 > 0.4
# OVERLAY_BIDIRECTIONAL: Train 악화(Forge OVERLAY_MARGINAL 확인) + Lockbox 개선
# OVERLAY_MARGINAL: |delta Active IR| <= 0.2
# OVERLAY_NEGATIVE: 모든 구간 악화 or Lockbox Active IR 악화 > 0.2
overlay_verdict <- if (delta$active_ir > 0.4) {
  "OVERLAY_DECISIVE"
} else if (delta$active_ir > 0.05) {
  "OVERLAY_BIDIRECTIONAL"
} else if (abs(delta$active_ir) <= 0.15) {
  "OVERLAY_MARGINAL"
} else {
  "OVERLAY_NEGATIVE"
}
cat("\n=== Overlay Verdict:", overlay_verdict, "===\n")

# ── 10. Write lockbox_overlay_effect.json (핵심 산출물) ────────────────────────
overlay_out <- list(
  wt_id = "WT-D20260424_008",
  pilot_label = "Pilot 10 — Monthly 3-Layer MRS Overlay Ablation",
  period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_days = nrow(lock_daily),
  pilot9_baseline_lockbox = list(
    sr = round(base$sr, 4),
    cagr = round(base$cagr, 2),
    mdd = round(base$mdd, 2),
    active_ir = round(base$active_ir, 4),
    alpha_ann_pct = round(base$alpha_ann, 2),
    te_ann_pct = round(base$te_ann, 2)
  ),
  pilot10_overlay_lockbox = list(
    sr = round(ovl$sr, 4),
    cagr = round(ovl$cagr, 2),
    mdd = round(ovl$mdd, 2),
    active_ir = round(ovl$active_ir, 4),
    alpha_ann_pct = round(ovl$alpha_ann, 2),
    te_ann_pct = round(ovl$te_ann, 2)
  ),
  delta_overlay_minus_baseline = list(
    sr = round(delta$sr, 4),
    cagr_pp = round(delta$cagr, 2),
    mdd_pp = round(delta$mdd, 2),
    active_ir = round(delta$active_ir, 4),
    alpha_ann_pp = round(delta$alpha_ann, 2),
    te_ann_pp = round(delta$te_ann, 2)
  ),
  layer_composition_lockbox = layer_comp,
  regime_decomposition_lockbox = reg_base,
  switching = list(
    n_events = n_switches,
    total_cost_pct = round(sum(lock_daily$sw_cost) * 100, 4)
  ),
  mrs_lockbox_monthly = mrs_lock[, .(eom = as.character(eom), MRS = round(MRS, 2),
                                      crisis_consec, layer, fw = round(fw, 3),
                                      apply_ym)],
  verdict = overlay_verdict,
  verdict_rationale = sprintf(
    "Lockbox Δ Active IR = %+.4f. Baseline Active IR %.4f → Overlay %.4f. Layer 2 monthly days: %d. No Layer 3 activation (Lockbox max MRS %.2f < 60 threshold).",
    delta$active_ir, base$active_ir, ovl$active_ir,
    sum(lock_daily$layer == 2L), max(mrs_lock$MRS, na.rm=TRUE)
  ),
  judge_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

write(toJSON(overlay_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_overlay_effect.json"))
cat("→ lockbox_overlay_effect.json written\n")

# ── 11. Lockbox OOS summary (standard) ────────────────────────────────────────
summary_out <- list(
  wt_id = "WT-D20260424_008",
  pilot_label = "Pilot 10 — Monthly 3-Layer MRS Overlay",
  period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_days = nrow(lock_daily),
  baseline_pilot9 = overlay_out$pilot9_baseline_lockbox,
  overlay_pilot10 = overlay_out$pilot10_overlay_lockbox,
  delta = overlay_out$delta_overlay_minus_baseline,
  pilot9_reference = list(sr = 1.05, active_ir = -0.71, source = "WT-D20260424_007/judge_verdict.json")
)
write(toJSON(summary_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_oos_summary.json"))
cat("→ lockbox_oos_summary.json written\n")

# ── 12. Equity curves ─────────────────────────────────────────────────────────
tryCatch({
  eq_base <- cumprod(1 + replace(lock_daily$port_ret, is.na(lock_daily$port_ret), 0))
  eq_ovl  <- cumprod(1 + replace(lock_daily$port_ret_overlay, is.na(lock_daily$port_ret_overlay), 0))
  eq_bm   <- cumprod(1 + replace(lock_daily$bm_ret, is.na(lock_daily$bm_ret), 0))

  png(file.path(OUT, "equity_curve_full.png"), width=1200, height=600)
  plot(lock_daily$Date, eq_ovl, type="l", lwd=2, col="darkgreen",
       main="Pilot 10 Lockbox: Baseline vs Overlay vs BM",
       xlab="Date", ylab="Cumulative Return",
       ylim=range(c(eq_base, eq_ovl, eq_bm), na.rm=TRUE))
  lines(lock_daily$Date, eq_base, col="navy", lwd=2, lty=1)
  lines(lock_daily$Date, eq_bm,   col="orange", lty=2, lwd=2)
  legend("topleft",
         legend=c("Pilot 10 Overlay", "Pilot 9 Baseline", "Benchmark"),
         col=c("darkgreen","navy","orange"), lty=c(1,1,2), lwd=c(2,2,2))
  dev.off()

  png(file.path(OUT, "equity_curve_oos.png"), width=1200, height=600)
  plot(lock_daily$Date, eq_ovl - eq_base, type="l", lwd=2, col="purple",
       main="Pilot 10 Overlay - Pilot 9 Baseline (Excess Equity)",
       xlab="Date", ylab="Overlay minus Baseline")
  abline(h=0, lty=3)
  dev.off()

  cat("→ equity_curve_full.png + equity_curve_oos.png written\n")
}, error = function(e) cat("[WARN] Plot error:", conditionMessage(e), "\n"))

# ── 13. Access log (AX-002) ──────────────────────────────────────────────────
log_out <- list(
  wt_id = "WT-D20260424_008",
  accessor = "judge",
  purpose = "Pilot 10 Lockbox overlay ablation — first and only access",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  lockbox_period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_lockbox_days = nrow(lock_daily),
  overlay_verdict = overlay_verdict
)
write(toJSON(log_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_access_log.json"))
cat("→ lockbox_access_log.json written\n")

cat("\n=== Judge Pilot 10 analysis complete ===\n")
cat("Overlay verdict:", overlay_verdict, "\n")
cat("Delta Active IR:", sprintf("%+.4f", delta$active_ir), "\n")
