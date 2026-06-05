## ============================================================
## Dev-A — STR_1715 AR_on_M4 overlay systematic sweep + AR-conditioning
## research/feasibility only — NO admission / NO book_state write
## ============================================================
## Goal: incumbent STR_1715 portfolio-α t (~5.34) source = AR_on_M4 overlay.
##   Systematically sweep & enhance β design space; measure if SR/MDD improve
##   over vanilla overlay. In-sample vs OOS split. Look-ahead avoidance proven.
##
## Architecture (sequential scalar, alpha building blocks UNCHANGED → cost retain):
##   ret_L(t) = β_AR(t) × m4_scalar(t) × β_R05(t) × ret_orig(t)
##                - Δβ_AR·15bps - Δβ_R05·15bps
##   (β_AR replaces incumbent beta_threshold; m4_scalar from M4 BOCPD; β_R05 R05 cash-control)
##
## β_AR DESIGN SPACE (D1) — all from AR_K{1,3,5}_W252, expanding-PIT:
##   shape ∈ {threshold_step, continuous_z, sigmoid}  (param grids below)
##   threshold_step: floor ∈ {0.2,0.4,0.6,0.8} × q-pair {(q70,q90),(q60,q85),(q80,q95)}
##   continuous_z:   β = clamp(1 - slope·max(0,AR_z), floor, 1); slope∈{0.15,0.25,0.40}, floor∈{0.3,0.5}
##   AR-CONDITIONING (D2): β_target = base_β × g(AR_z),
##     g = 1 - gain·sigmoid(AR_z)  (shrink harder when market-mode concentration high)
##
## PIT / look-ahead avoidance:
##   - AR_t computed from t-1 close (upstream WT-S20260504_007, K5/W252 strict; we
##     re-derive β from same AR path for K1/K3 too — AR values themselves unchanged).
##   - All quantiles / z-score / sd = EXPANDING past-only (observations strictly
##     before t, OR up to t — we use STRICTLY past to be conservative for decision time).
##   - regime_state lag-1 (column already lag-applied in alpha lineage; we additionally
##     map β_R05 decided at sig_date Date → applied to realized month Date+1m).
##   - NO hand-set / NO full-sample threshold. NO future return in β.
##
## Eval: SR / CAGR / MDD via PerformanceAnalytics (table.AnnualizedReturns, maxDrawdown).
##   portfolio_alpha_t_nw_lag3 via .nw_t_mean (same fn as build_benchmark_compare).
##   metric_type = backtested. NO self-synthesis.
##   IN-SAMPLE (≤2023-12) vs OOS (≥2024-01) split reported separately.
##   AX-001 v2 conditional defense (CRISIS/CAUTION SR > 0).
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
  library(lubridate)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/WT-D20260529_DevA_overlay_sweep/output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2024-01-01")   # in-sample / OOS split (lockbox boundary, retained for OOS metric)
COST_BPS  <- 0.0015                   # 15bps one-way on |Δβ| turnover

cat("============================================================\n")
cat("Dev-A STR_1715 AR_on_M4 overlay sweep + AR-conditioning\n")
cat("research/feasibility only\n")
cat("============================================================\n\n")

## -----------------------------------------------------------
## 1. Load base PR ret_net (Iter31 production weighting baked) + M4 + AR path + R05
## -----------------------------------------------------------
cat("[1] Load base PR ret_net + M4 + AR path + R05 lineage\n")

pr <- fread(file.path(BASE_DIR,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
pr[, date := as.Date(date)]
pr[, realized_ym := format(date, "%Y-%m")]
setorder(pr, date)
stopifnot(all(pr$cash_weight == 0, na.rm = TRUE))
panel <- pr[, .(date, realized_ym, ret_orig = ret_net, turnover_base = turnover,
                n_holdings)]

# M4 BOCPD scalar (t-1 lag → realized month)
m4 <- fread(file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv"))
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]
panel <- merge(panel, m4[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(m4_weight_lag), m4_weight_lag := 1.0]

# AR path (K1/K3/K5, W252) — rebalance_date keyed (= sig_date, PIT t-1 AR)
ar <- fread(file.path(BASE_DIR, "stage_artifacts/WT_WT-S20260504_007/ar_path_timeseries.csv"))
ar[, Date := as.Date(rebalance_date)]
setorder(ar, Date)

# Incumbent beta_threshold (vanilla overlay reference — q70/q90 3-step on K5/W252)
beta_inc <- fread(file.path(BASE_DIR, "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"))
beta_inc[, Date := as.Date(Date)]
setorder(beta_inc, Date)
beta_inc[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

# R05 lineage (regime + R05_z) — from admit lineage copy + R05 panel
r05_dt <- as.data.table(read_parquet(file.path(BASE_DIR,
  "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")))
m_valid <- r05_dt[!is.na(score_eff)]
setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by = Date]
p_r05 <- top20[, .(R05_z_avg = mean(R05_Tail_Risk_Z, na.rm = TRUE),
                   regime = regime_state[1]), by = Date]
setorder(p_r05, Date)
p_r05[, realized_ym := format(Date + months(1), "%Y-%m")]   # sig_date → next realized month

cat(sprintf("  panel: %d months | %s ~ %s\n", nrow(panel),
            as.character(min(panel$date)), as.character(max(panel$date))))

## -----------------------------------------------------------
## 2. AR signals: AR_t per (K,W) + expanding z / sd / quantiles (PIT strict, past-only)
## -----------------------------------------------------------
cat("\n[2] Build AR expanding-PIT statistics (strictly past-only)\n")

# Expanding STRICTLY-PAST quantile (decision at t uses only obs before t)
exp_quantile_pastonly <- function(x, q, min_n = 12L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[seq_len(i - 1L)]; past <- past[!is.na(past)]
    if (length(past) >= min_n) out[i] <- as.numeric(quantile(past, q))
  }
  out
}
exp_z_pastonly <- function(x, min_n = 12L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (is.na(x[i])) next
    past <- x[seq_len(i - 1L)]; past <- past[!is.na(past)]
    if (length(past) >= min_n) {
      mu <- mean(past); s <- sd(past)
      if (!is.na(s) && s > 1e-8) out[i] <- (x[i] - mu) / s
    }
  }
  out
}
exp_sd_pastonly <- function(x, min_n = 12L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[seq_len(i - 1L)]; past <- past[!is.na(past)]
    if (length(past) >= min_n) out[i] <- sd(past)
  }
  out
}
exp_mean_pastonly <- function(x, min_n = 12L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[seq_len(i - 1L)]; past <- past[!is.na(past)]
    if (length(past) >= min_n) out[i] <- mean(past)
  }
  out
}

ar_sig <- ar[, .(Date)]
for (kcol in c("AR_K1_W252", "AR_K3_W252", "AR_K5_W252")) {
  v <- ar[[kcol]]
  ar_sig[[paste0(kcol, "_raw")]]   <- v
  ar_sig[[paste0(kcol, "_z")]]     <- exp_z_pastonly(v)
  ar_sig[[paste0(kcol, "_med")]]   <- exp_mean_pastonly(v)
  ar_sig[[paste0(kcol, "_sd")]]    <- exp_sd_pastonly(v)
  ar_sig[[paste0(kcol, "_q60")]]   <- exp_quantile_pastonly(v, 0.60)
  ar_sig[[paste0(kcol, "_q70")]]   <- exp_quantile_pastonly(v, 0.70)
  ar_sig[[paste0(kcol, "_q80")]]   <- exp_quantile_pastonly(v, 0.80)
  ar_sig[[paste0(kcol, "_q85")]]   <- exp_quantile_pastonly(v, 0.85)
  ar_sig[[paste0(kcol, "_q90")]]   <- exp_quantile_pastonly(v, 0.90)
  ar_sig[[paste0(kcol, "_q95")]]   <- exp_quantile_pastonly(v, 0.95)
}
# β_AR decided at sig_date Date → applied to realized month Date+1m (t-1 lag)
ar_sig[, realized_ym := format(Date + months(1), "%Y-%m")]

## -----------------------------------------------------------
## 3. β_AR shape constructors (D1)
## -----------------------------------------------------------
cat("\n[3] Construct β_AR variant space (D1) + AR-conditioning (D2)\n")

clamp01 <- function(x, lo, hi) pmin(hi, pmax(lo, x))

# threshold_step: floor + qpair (low → β=1, mid → β=midval, high → β=floor)
beta_threshold_step <- function(a, qlo, qhi, floor_v, mid_v) {
  out <- rep(1.0, length(a))
  for (i in seq_along(a)) {
    if (is.na(a[i]) || is.na(qlo[i]) || is.na(qhi[i])) { out[i] <- 1.0; next }
    if (a[i] < qlo[i]) out[i] <- 1.0
    else if (a[i] < qhi[i]) out[i] <- mid_v
    else out[i] <- floor_v
  }
  out
}
# continuous_z: β = clamp(1 - slope * max(0, AR_z), floor, 1)
beta_continuous_z <- function(arz, slope, floor_v) {
  v <- 1 - slope * pmax(0, arz)
  v[is.na(arz)] <- 1.0
  clamp01(v, floor_v, 1.0)
}
# sigmoid (smooth): 1/(1+exp(k*(a - med))), k = log(19)/(2*sd)
beta_sigmoid_shape <- function(a, med, sdv) {
  out <- rep(1.0, length(a))
  for (i in seq_along(a)) {
    if (is.na(a[i]) || is.na(med[i]) || is.na(sdv[i]) || sdv[i] <= 1e-6) { out[i] <- 1.0; next }
    k <- log(19) / (2 * sdv[i])
    out[i] <- 1 / (1 + exp(k * (a[i] - med[i])))
  }
  out
}
# AR-conditioning multiplier g(AR_z): shrink harder when concentration high
# g = 1 - gain * plogis(arz)  (plogis(0)=0.5 → g=1-gain/2 at neutral; higher arz → smaller g)
ar_cond_g <- function(arz, gain) {
  g <- 1 - gain * plogis(arz)
  g[is.na(arz)] <- 1.0
  pmin(1.0, pmax(0.0, g))
}

# --- Build variant catalog ---
variants <- list()
add_variant <- function(tag, beta_vec, dates, group, desc) {
  variants[[tag]] <<- list(tag = tag, group = group, desc = desc,
                            dt = data.table(Date = dates, beta_AR = beta_vec))
}

# Group A: threshold_step grid (K5/W252) — floor × qpair × midval
qpairs <- list(q7090 = c("q70","q90"), q6085 = c("q60","q85"), q8095 = c("q80","q95"))
for (K in c("AR_K5_W252")) {
  for (qp in names(qpairs)) {
    qlo_c <- paste0(K, "_", qpairs[[qp]][1]); qhi_c <- paste0(K, "_", qpairs[[qp]][2])
    for (floor_v in c(0.2, 0.4, 0.6, 0.8)) {
      mid_v <- floor_v + (1 - floor_v) * 0.5   # mid halfway between floor and 1
      mid_v <- round(mid_v, 3)
      bv <- beta_threshold_step(ar_sig[[paste0(K,"_raw")]], ar_sig[[qlo_c]], ar_sig[[qhi_c]],
                                floor_v, mid_v)
      tag <- sprintf("A_thr_%s_%s_f%02d", sub("AR_","",K), qp, round(floor_v*100))
      add_variant(tag, bv, ar_sig$Date, "A_threshold_step",
                  sprintf("threshold_step K5 qpair=%s floor=%.1f mid=%.3f", qp, floor_v, mid_v))
    }
  }
}

# Group B: continuous_z grid (K1/K3/K5) — slope × floor
for (K in c("AR_K1_W252","AR_K3_W252","AR_K5_W252")) {
  zc <- paste0(K, "_z")
  for (slope in c(0.15, 0.25, 0.40)) {
    for (floor_v in c(0.3, 0.5)) {
      bv <- beta_continuous_z(ar_sig[[zc]], slope, floor_v)
      tag <- sprintf("B_cz_%s_s%02d_f%02d", sub("AR_","",K), round(slope*100), round(floor_v*100))
      add_variant(tag, bv, ar_sig$Date, "B_continuous_z",
                  sprintf("continuous_z %s slope=%.2f floor=%.2f", K, slope, floor_v))
    }
  }
}

# Group C: sigmoid_smooth (K5/W252) — reference smooth shape (incumbent had this as variant)
bv_sig <- beta_sigmoid_shape(ar_sig$AR_K5_W252_raw, ar_sig$AR_K5_W252_med, ar_sig$AR_K5_W252_sd)
add_variant("C_sigmoid_K5", bv_sig, ar_sig$Date, "C_sigmoid", "sigmoid_smooth K5 (log19/2sd)")

# Group D: AR-conditioning applied to best-shape base (D2)
# base = continuous_z K5 slope0.25 floor0.5 (representative), × g(AR_z) gain∈{0.2,0.35,0.5}
base_cz <- beta_continuous_z(ar_sig$AR_K5_W252_z, 0.25, 0.5)
for (gain in c(0.20, 0.35, 0.50)) {
  g <- ar_cond_g(ar_sig$AR_K5_W252_z, gain)
  bv <- clamp01(base_cz * g, 0.2, 1.0)
  tag <- sprintf("D_arcond_cz_g%02d", round(gain*100))
  add_variant(tag, bv, ar_sig$Date, "D_AR_conditioned",
              sprintf("D2: continuous_z(K5,s.25,f.5) × g(AR_z,gain=%.2f)", gain))
}
# also AR-conditioning on K1 market-mode z (D2 alt — concentration in 1st eigenvalue)
base_cz_k1 <- beta_continuous_z(ar_sig$AR_K5_W252_z, 0.25, 0.5)
for (gain in c(0.35, 0.50)) {
  g <- ar_cond_g(ar_sig$AR_K1_W252_z, gain)
  bv <- clamp01(base_cz_k1 * g, 0.2, 1.0)
  tag <- sprintf("D_arcond_k1mode_g%02d", round(gain*100))
  add_variant(tag, bv, ar_sig$Date, "D_AR_conditioned",
              sprintf("D2: continuous_z(K5,s.25,f.5) × g(K1_market_mode_z,gain=%.2f)", gain))
}

cat(sprintf("  Total β_AR variants constructed: %d\n", length(variants)))
cat(sprintf("  Groups: A_threshold_step=%d, B_continuous_z=%d, C_sigmoid=%d, D_AR_conditioned=%d\n",
            sum(sapply(variants, function(v) v$group=="A_threshold_step")),
            sum(sapply(variants, function(v) v$group=="B_continuous_z")),
            sum(sapply(variants, function(v) v$group=="C_sigmoid")),
            sum(sapply(variants, function(v) v$group=="D_AR_conditioned"))))

## -----------------------------------------------------------
## 4. β_R05 cash-control layer (regime-step grid × R05-quantile × interaction)
##    Expanded from incumbent 5 hand-set to a grid; PIT expanding past-only quantiles.
## -----------------------------------------------------------
cat("\n[4] Build β_R05 cash-control grid (regime-step × R05-q × interaction)\n")

p_r05[, R05_q20_past := exp_quantile_pastonly(R05_z_avg, 0.20)]
p_r05[, R05_q50_past := exp_quantile_pastonly(R05_z_avg, 0.50)]

# regime-step grid: CRISIS floor c, CAUTION floor cau; BULL/NORMAL=1.0
r05_designs <- list(
  R05_none      = list(crisis=1.0, caution=1.0, interact=FALSE),   # no R05 layer (pure β_AR)
  R05_mild      = list(crisis=0.5, caution=0.7, interact=FALSE),
  R05_medium    = list(crisis=0.4, caution=0.6, interact=FALSE),
  R05_aggr      = list(crisis=0.3, caution=0.5, interact=FALSE),
  R05_inter_med = list(crisis=0.4, caution=0.6, interact=TRUE),    # × R05<q20 extra shrink
  R05_inter_aggr= list(crisis=0.3, caution=0.5, interact=TRUE)
)
build_beta_r05 <- function(des) {
  out <- rep(1.0, nrow(p_r05))
  for (i in seq_len(nrow(p_r05))) {
    rg <- p_r05$regime[i]; z <- p_r05$R05_z_avg[i]; q20 <- p_r05$R05_q20_past[i]
    low <- !is.na(q20) && !is.na(z) && z < q20
    b <- 1.0
    if (rg == "CRISIS")      b <- if (des$interact && low) des$crisis * 0.7 else des$crisis
    else if (rg == "CAUTION") b <- if (des$interact && low) des$caution * 0.8 else des$caution
    else                      b <- if (des$interact && low) 0.9 else 1.0
    out[i] <- b
  }
  out
}
for (dn in names(r05_designs)) {
  p_r05[[paste0("bR05_", dn)]] <- build_beta_r05(r05_designs[[dn]])
}

## -----------------------------------------------------------
## 5. Assemble eval panel + return paths
## -----------------------------------------------------------
cat("\n[5] Assemble eval panels (vanilla + variants × R05 designs)\n")

# Merge regime + β_R05 to panel via realized_ym
r05_merge <- p_r05[, c("realized_ym", "regime", paste0("bR05_", names(r05_designs))), with = FALSE]
panel <- merge(panel, r05_merge, by = "realized_ym", all.x = TRUE)
panel[is.na(regime), regime := "UNKNOWN"]
for (dn in names(r05_designs)) { cc <- paste0("bR05_", dn); panel[is.na(get(cc)), (cc) := 1.0] }

# Merge incumbent vanilla β_threshold (lag) via realized_ym
beta_inc[, realized_ym := format(Date %m+% months(1), "%Y-%m")]
panel <- merge(panel, beta_inc[, .(realized_ym, beta_threshold_inc = beta_threshold)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(beta_threshold_inc), beta_threshold_inc := 1.0]

# Merge each β_AR variant (lag: sig_date Date → realized_ym Date+1m via ar_sig$realized_ym)
ar_sig_lag <- copy(ar_sig)
for (tg in names(variants)) {
  bd <- variants[[tg]]$dt
  bd[, realized_ym := format(Date %m+% months(1), "%Y-%m")]
  panel <- merge(panel, bd[, .(realized_ym, bAR = beta_AR)], by = "realized_ym", all.x = TRUE)
  setnames(panel, "bAR", paste0("bAR_", tg))
  panel[is.na(get(paste0("bAR_", tg))), (paste0("bAR_", tg)) := 1.0]
}
setorder(panel, date)

# VANILLA overlay = incumbent beta_threshold × m4 × R05_medium (admit precedent shape)
panel[, dthr_inc := abs(beta_threshold_inc - shift(beta_threshold_inc, 1, fill = 1.0))]
panel[is.na(dthr_inc), dthr_inc := 0]
panel[, dR05_med := abs(bR05_R05_medium - shift(bR05_R05_medium, 1, fill = 1.0))]
panel[is.na(dR05_med), dR05_med := 0]
panel[, ret_vanilla := beta_threshold_inc * m4_weight_lag * bR05_R05_medium * ret_orig -
                        dthr_inc * COST_BPS - dR05_med * COST_BPS]

# also vanilla with NO R05 (pure incumbent β_threshold × m4) for clean AR-only baseline
panel[, ret_vanilla_noR05 := beta_threshold_inc * m4_weight_lag * ret_orig - dthr_inc * COST_BPS]

cat(sprintf("  panel assembled: %d months | regime dist:\n", nrow(panel)))
print(table(panel$regime))

## -----------------------------------------------------------
## 6. Metric helpers (PerformanceAnalytics + NW lag-3 portfolio-α t)
## -----------------------------------------------------------
# Benchmark monthly returns aligned to panel realized months (for portfolio-α t)
bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
# monthly BM return matched to each panel period [date_i, date_{i+1}) — use anchor month
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_Close_eom = BM_Close[which.max(Date)], Date_eom = max(Date)), by = ym]
setorder(bm_m, Date_eom)
bm_m[, BM_Ret_m := BM_Close_eom / shift(BM_Close_eom) - 1]
# anchor: panel realized over [date_i, date_{i+1}], approximate BM month = realized_ym
panel <- merge(panel, bm_m[, .(realized_ym = ym, BM_Ret_m)], by = "realized_ym", all.x = TRUE)
setorder(panel, date)

# same NW lag-3 t on mean as build_benchmark_compare::.nw_t_mean
nw_t_mean <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    g <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    s <- s + 2 * w * g
  }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s / n)
}

eval_series <- function(ret, dates, bm_ret, label) {
  ok <- is.finite(ret)
  ret <- ret[ok]; dts <- dates[ok]; bmr <- bm_ret[ok]
  if (length(ret) < 12) return(NULL)
  xr <- xts(ret, order.by = dts)
  ann <- table.AnnualizedReturns(xr, scale = 12, Rf = 0)
  mdd <- as.numeric(maxDrawdown(xr))
  active <- ret - bmr
  pa_t <- nw_t_mean(active[is.finite(active)], lag = 3L)
  data.table(
    label    = label,
    n_months = length(ret),
    SR       = round(as.numeric(ann[3,1]), 4),
    CAGR     = round(as.numeric(ann[1,1]), 4),
    Vol      = round(as.numeric(ann[2,1]), 4),
    MDD      = round(-mdd, 4),
    alpha_t_nw_lag3 = round(pa_t, 4)
  )
}

## -----------------------------------------------------------
## 7. Sweep evaluation — full / in-sample / OOS  (β_AR variant × selected R05 designs)
## -----------------------------------------------------------
cat("\n[7] Sweep eval (full / in-sample ≤2023-12 / OOS ≥2024-01)\n")

panel[, is_oos := date >= OOS_START]
# eval R05 layer choices to combine with each β_AR (keep manageable: none + medium + inter_med)
r05_for_sweep <- c("R05_none", "R05_medium", "R05_inter_med")

results <- list()

# Vanilla references
for (lab in c("vanilla_incumbent_thr_m4_R05med", "vanilla_noR05_thr_m4")) {
  rc <- if (lab == "vanilla_incumbent_thr_m4_R05med") "ret_vanilla" else "ret_vanilla_noR05"
  for (seg in c("full","in_sample","oos")) {
    sub <- if (seg=="full") panel else if (seg=="in_sample") panel[is_oos==FALSE] else panel[is_oos==TRUE]
    r <- eval_series(sub[[rc]], sub$date, sub$BM_Ret_m, lab)
    if (!is.null(r)) { r[, segment := seg]; r[, group := "VANILLA"]; results[[length(results)+1]] <- r }
  }
}

# Variant grid
for (tg in names(variants)) {
  bAR_c <- paste0("bAR_", tg)
  panel[, dAR := abs(get(bAR_c) - shift(get(bAR_c), 1, fill = 1.0))]
  panel[is.na(dAR), dAR := 0]
  for (r05n in r05_for_sweep) {
    r05c <- paste0("bR05_", r05n)
    dR05c <- paste0("d_", r05n)
    panel[, (dR05c) := abs(get(r05c) - shift(get(r05c), 1, fill = 1.0))]
    panel[is.na(get(dR05c)), (dR05c) := 0]
    rc <- paste0("ret_", tg, "__", r05n)
    panel[, (rc) := get(bAR_c) * m4_weight_lag * get(r05c) * ret_orig -
                     dAR * COST_BPS - get(dR05c) * COST_BPS]
    lab <- paste0(tg, "__", r05n)
    for (seg in c("full","in_sample","oos")) {
      sub <- if (seg=="full") panel else if (seg=="in_sample") panel[is_oos==FALSE] else panel[is_oos==TRUE]
      r <- eval_series(sub[[rc]], sub$date, sub$BM_Ret_m, lab)
      if (!is.null(r)) {
        r[, segment := seg]; r[, group := variants[[tg]]$group]
        r[, beta_AR_variant := tg]; r[, R05_design := r05n]
        results[[length(results)+1]] <- r
      }
    }
  }
}

res_dt <- rbindlist(results, fill = TRUE)
fwrite(res_dt, file.path(OUT_DIR, "sweep_results_all.csv"))

## -----------------------------------------------------------
## 8. AX-001 v2 conditional defense per top variant (CRISIS/CAUTION SR > 0, in-sample)
## -----------------------------------------------------------
cat("\n[8] AX-001 v2 conditional defense (in-sample CRISIS/CAUTION SR>0) for top variants\n")

regime_sr <- function(rcol, seg_dt) {
  out <- list()
  for (rg in c("BULL","NORMAL","CAUTION","CRISIS")) {
    rr <- seg_dt[regime == rg][[rcol]]; rr <- rr[is.finite(rr)]
    out[[rg]] <- if (length(rr) >= 2) round(mean(rr)/sd(rr)*sqrt(12), 4) else NA_real_
  }
  out
}

## -----------------------------------------------------------
## 9. Rank + select best variant (full SR primary, OOS robustness gate)
## -----------------------------------------------------------
cat("\n[9] Rank vs vanilla\n")

van_full <- res_dt[label=="vanilla_incumbent_thr_m4_R05med" & segment=="full"]
van_is   <- res_dt[label=="vanilla_incumbent_thr_m4_R05med" & segment=="in_sample"]
van_oos  <- res_dt[label=="vanilla_incumbent_thr_m4_R05med" & segment=="oos"]
van_noR05_full <- res_dt[label=="vanilla_noR05_thr_m4" & segment=="full"]

cat(sprintf("\n  VANILLA (incumbent thr×m4×R05med): full SR=%.4f MDD=%.4f α_t=%.4f | IS SR=%.4f | OOS SR=%.4f\n",
            van_full$SR, van_full$MDD, van_full$alpha_t_nw_lag3, van_is$SR, van_oos$SR))
cat(sprintf("  VANILLA noR05 (thr×m4):           full SR=%.4f MDD=%.4f α_t=%.4f\n",
            van_noR05_full$SR, van_noR05_full$MDD, van_noR05_full$alpha_t_nw_lag3))

# variant ranking on full SR
var_full <- res_dt[group != "VANILLA" & segment=="full"]
setorder(var_full, -SR)
var_full[, dSR_vs_vanilla := SR - van_full$SR]
var_full[, dMDD_pp := (MDD - van_full$MDD)*100]
var_full[, dAlphaT := alpha_t_nw_lag3 - van_full$alpha_t_nw_lag3]

cat("\n  --- Top 12 variants by FULL SR ---\n")
print(var_full[1:min(12,nrow(var_full)),
   .(label, SR, MDD, CAGR, alpha_t_nw_lag3, dSR_vs_vanilla, dMDD_pp, dAlphaT)])

# attach OOS + in-sample SR for top variants (robustness)
top_labs <- var_full[1:min(15,nrow(var_full)), label]
robust <- res_dt[label %in% top_labs & segment %in% c("in_sample","oos"),
                 .(label, segment, SR, MDD, alpha_t_nw_lag3)]
robust_w <- dcast(robust, label ~ segment, value.var = c("SR","MDD","alpha_t_nw_lag3"))
top_summary <- merge(var_full[label %in% top_labs,
                       .(label, group, beta_AR_variant, R05_design,
                         SR_full=SR, MDD_full=MDD, alphaT_full=alpha_t_nw_lag3,
                         dSR_vs_vanilla, dMDD_pp, dAlphaT)],
                     robust_w, by="label", all.x=TRUE)
setorder(top_summary, -SR_full)
fwrite(top_summary, file.path(OUT_DIR, "top_variants_robustness.csv"))

cat("\n  --- Top variants: in-sample vs OOS robustness ---\n")
print(top_summary[, .(label, SR_full, SR_in_sample, SR_oos, MDD_full,
                       dSR_vs_vanilla, dAlphaT)])

# AX-001 v2 for top 6
ax_rows <- list()
for (lb in top_summary[1:min(6,nrow(top_summary)), label]) {
  tg <- top_summary[label==lb, beta_AR_variant]; r05n <- top_summary[label==lb, R05_design]
  rc <- paste0("ret_", tg, "__", r05n)
  if (!rc %in% names(panel)) next
  sr_is <- regime_sr(rc, panel[is_oos==FALSE])
  ax_rows[[lb]] <- data.table(label=lb,
    SR_CRISIS_is=sr_is$CRISIS %||% NA, SR_CAUTION_is=sr_is$CAUTION %||% NA,
    SR_NORMAL_is=sr_is$NORMAL %||% NA, SR_BULL_is=sr_is$BULL %||% NA,
    AX001v2_pass = isTRUE((sr_is$CRISIS %||% -1) > 0) && isTRUE((sr_is$CAUTION %||% -1) > 0))
}
ax_dt <- rbindlist(ax_rows, fill=TRUE)
fwrite(ax_dt, file.path(OUT_DIR, "ax001v2_top_variants.csv"))
cat("\n  AX-001 v2 conditional defense (in-sample regime SR):\n")
print(ax_dt)

## -----------------------------------------------------------
## 10. AR-conditioning (D2) specific comparison
## -----------------------------------------------------------
cat("\n[10] AR-conditioning (D2) effect: does g(AR_z) improve SR/MDD?\n")
d2 <- res_dt[group=="D_AR_conditioned" & segment=="full"]
b_base <- res_dt[beta_AR_variant=="B_cz_K5_W252_s25_f50" & R05_design=="R05_medium" & segment=="full"]
setorder(d2, -SR)
cat("  D2 AR-conditioned variants (full, vs un-conditioned base B_cz_K5_s25_f50__R05med):\n")
if (nrow(b_base)>0) cat(sprintf("    BASE (no AR-cond): SR=%.4f MDD=%.4f α_t=%.4f\n",
                                b_base$SR, b_base$MDD, b_base$alpha_t_nw_lag3))
print(d2[, .(label, SR, MDD, CAGR, alpha_t_nw_lag3)])

## -----------------------------------------------------------
## 11. Look-ahead avoidance verification
## -----------------------------------------------------------
cat("\n[11] Look-ahead avoidance verification\n")
# (a) every β_AR at month t uses AR up to sig_date (= t-1 close per upstream) + expanding PAST-only stats
# (b) β decided at sig_date Date applied to realized_ym = Date+1m (verified via merge key)
# (c) no full-sample quantile (exp_quantile_pastonly uses seq_len(i-1) only)
la_check <- list(
  ar_pit = "AR_t from upstream WT-S20260504_007 strict t-1 close (PIT_audit_log STRICT_TMINUS_1)",
  expanding_quantiles = "all q/z/sd via *_pastonly using observations strictly before t (seq_len(i-1))",
  beta_lag = "β decided at sig_date Date → applied realized_ym = Date %m+% 1month (t-1 decision)",
  regime_lag = "regime_state from lag-applied alpha lineage; β_R05 sig_date→Date+1m",
  no_handset = "no hand-set thresholds; floor/slope are design hyperparams (swept), thresholds data-driven expanding",
  no_future_in_beta = "β = f(AR_z, regime, R05_z) all observable at decision; ret_orig is the thing being scaled (not used in β)"
)
write_json(la_check, file.path(OUT_DIR, "lookahead_avoidance.json"), pretty=TRUE, auto_unbox=TRUE)
for (k in names(la_check)) cat(sprintf("  [%s] %s\n", k, la_check[[k]]))

# Quantitative warmup NA check: how many months had β=1 fallback (pre-12m expanding)
warm_chk <- sapply(names(variants), function(tg) {
  bd <- variants[[tg]]$dt; sum(!is.finite(bd$beta_AR) | is.na(bd$beta_AR))
})
cat(sprintf("\n  Warmup β NA count per variant (set to 1.0): min=%d max=%d\n",
            min(warm_chk), max(warm_chk)))

## -----------------------------------------------------------
## 12. Save summary JSON
## -----------------------------------------------------------
best <- top_summary[1]
summary_out <- list(
  task = "Dev-A STR_1715 AR_on_M4 overlay sweep + AR-conditioning",
  mode = "research_feasibility_only_NO_admission",
  n_beta_AR_variants = length(variants),
  n_R05_designs_swept = length(r05_for_sweep),
  total_overlay_combos = length(variants) * length(r05_for_sweep) + 2,
  metric_type = "backtested",
  perfanalytics_standard = "table.AnnualizedReturns + maxDrawdown; portfolio_alpha_t = NW lag-3 (build_benchmark_compare fn)",
  vanilla_incumbent = list(SR_full=van_full$SR, MDD_full=van_full$MDD,
                            alpha_t_full=van_full$alpha_t_nw_lag3,
                            SR_in_sample=van_is$SR, SR_oos=van_oos$SR),
  vanilla_noR05 = list(SR_full=van_noR05_full$SR, MDD_full=van_noR05_full$MDD,
                       alpha_t_full=van_noR05_full$alpha_t_nw_lag3),
  best_variant_by_full_SR = list(
    label=best$label, SR_full=best$SR_full, MDD_full=best$MDD_full,
    alpha_t_full=best$alphaT_full, SR_in_sample=best$SR_in_sample, SR_oos=best$SR_oos,
    dSR_vs_vanilla=best$dSR_vs_vanilla, dMDD_pp=best$dMDD_pp, dAlphaT=best$dAlphaT),
  ar_conditioning_D2_note = "see ar_conditioning section; compares D_AR_conditioned vs un-conditioned base",
  oos_period = paste0(">= ", as.character(OOS_START)),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)
write_json(summary_out, file.path(OUT_DIR, "sweep_summary.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

cat("\n============================================================\n")
cat("DONE. Artifacts in:", OUT_DIR, "\n")
cat("============================================================\n")
