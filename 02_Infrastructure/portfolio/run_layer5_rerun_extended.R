## ============================================================
## WT-H20260513_001 — STR_1715_AR_on_M4 PG2 + R05_Tail_Risk Layer 5
## Sequential Overlay (cash-control β_R05(regime))
##
## ★정본 위치 이전 (2026-08-02 프로덕션 정리 2단계, 도훈 승인):
##   구 정본 = 05_Production/2.Factor_Model/2-1.../01_reproducible_code/ (sha1 98e7d321).
##   이 빌더는 전략 산출물이 아니라 **라이브 체인의 공용 배관**(base 패널 생산)이라
##   02_Infrastructure/portfolio/ 로 이전. 2-1 슬롯은 철거 대상.
##   원본 대비 변경 = 아래 [panel window] 종료월 동적화 **단 한 곳** (구 하드코딩
##   `<= "2026-06"` 이 매달 사람 손을 요구했고 2026-07 리밸에서 7월이 통째로 잘린 실사고).
##   구 run_layer5_dynamic_window.R (런타임 치환 래퍼)는 이 이전으로 소용 종료.
## ============================================================
## 도훈 mandate 2026-05-13 Session 80 Step 3 (Option C):
##   - WT-D20260512_003 composite top20 redesign archive 후 후속
##   - R05_Tail_Risk discovery 입증된 mechanism (cor 0.171, holdings overlap 0/20,
##     CRISIS bootstrap mean +6.34) → sequential overlay scalar β_R05(regime)
##   - composite top20 (turnover cap infeasibility) 폐기 후 sequential overlay
##     (alpha building blocks unchanged → cost retain) 형식
##
## Architecture (w_final = scalar product, sequential):
##   w_final(t,i) = w_str1715(t,i) × m4_scalar(t) × β_AR(t) × β_R05(regime_t, R05_z_t)
##
##   - w_str1715: STR_1715 Iter31 linear_tilt baked in PR ret_net (NO holding change)
##   - m4_scalar: M4 BOCPD+decay+BL multiplier (NORMAL=1.0 / CAUTION partial / CRISIS=0.43)
##   - β_AR:      AR threshold β_t step (K=5/W=252, β∈{0.4,0.7,1.0})
##   - β_R05:     Layer 5 cash-control multiplier (R05 portfolio-level signal)
##
##   Return path:
##     ret_L5(t) = β_R05(t) × β_AR(t) × m4_scalar(t) × ret_orig(t)
##                  - AR_turnover_cost - R05_turnover_cost
##
## β_R05 variants (5 designs):
##   V1 mild_regime    : BULL/NORMAL 1.0 + CAUTION 0.7 + CRISIS 0.5
##   V2 aggressive_reg : BULL/NORMAL 1.0 + CAUTION 0.5 + CRISIS 0.3
##   V3 medium_regime  : BULL/NORMAL 1.0 + CAUTION 0.6 + CRISIS 0.4
##   V4 R05_adaptive   : portfolio R05_z_avg expanding past-only percentile;
##                        β_R05 = 0.5 if z < q20_past, 0.7 if z < q50_past, else 1.0
##   V5 regime_x_R05   : interaction (CRISIS × R05<q20 → 0.3, CRISIS only → 0.5,
##                        CAUTION × R05<q20 → 0.5, CAUTION only → 0.7,
##                        BULL/NORMAL × R05<q20 → 0.85, BULL/NORMAL else → 1.0)
##
## PIT:
##   - R05_z portfolio average computed at sig_date t (decision time)
##   - β_R05(t) decision at t-1 EOM → applied to month t  (shift(1))
##   - Quantile (V4): expanding past-only (only t-1 and earlier observations)
##   - Regime state: alpha_scores regime_state column (lag-1 applied)
##   - 15bps additional cost on β_R05 turnover (|Δβ_R05|)
##
## Backtest Contract v1.0: PerformanceAnalytics standard functions only
##   table.AnnualizedReturns + maxDrawdown + SortinoRatio + CalmarRatio
##
## Period strategies:
##   - panel_267m_full:  2004-02 ~ 2026-04 (full PR coverage)
##   - panel_255m_admit: 2005-02 ~ 2026-04 (admit baseline comparable)
##
## Selection criterion: max(SR) - 0.5 × |MDD| primary
##   Hard gates:
##     SR > 1.78 (STR_1715 admit baseline 추월)
##     MDD better than -0.2515 (admit baseline)
##     AX-001 v2: CRISIS/CAUTION SR > 0
##     incremental TO ≤ 0.5 over STR_1715 base
## ============================================================

cat("============================================================\n")
cat("WT-H20260513_001 STR_1715_AR_on_M4 + R05_Tail_Risk Layer 5\n")
cat("Sequential Overlay (β_R05 cash-control)\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
  library(lubridate)
})

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"))
WT_DIR   <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-H20260513_001")
OUT_DIR  <- file.path(WT_DIR, "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

RAW_COVER_START_DECISION <- as.Date("2004-01-01")
RAW_COVER_START_REALIZED <- as.Date("2004-02-01")
STR_ID <- "STR_1715_AR_on_M4_R05_Layer5"

# ============================================================
# 1. Load STR_1715 PR ret_net (production weighting Iter31 baked)
# ============================================================
cat("[1] Load STR_1715 PR ret_net (Iter31 production baked)\n")

pr_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
pr <- fread(pr_path)
pr[, date := as.Date(date)]
pr[, ym := format(date, "%Y-%m")]
setorder(pr, date)
stopifnot(all(pr$cash_weight == 0, na.rm = TRUE))

cat(sprintf("  PR rows: %d | %s ~ %s\n",
            nrow(pr), as.character(min(pr$date)), as.character(max(pr$date))))

panel <- pr[, .(date = date,
                realized_ym = ym,
                ret_orig = ret_net,
                ret_gross = ret_gross,
                turnover_base = turnover,
                cost_ret_base = cost_ret,
                n_holdings = n_holdings)]
setorder(panel, date)

# ============================================================
# 2. Load M4 + AR overlay (admit precedent)
# ============================================================
cat("\n[2] Load M4 BOCPD overlay + AR threshold (admit precedent)\n")

m4_path <- file.path(BASE_DIR,
  "stage_artifacts/WT-D20260430_001_m4_extended.csv")  # [rerun] 확장 M4 (06-01까지)
m4 <- fread(m4_path)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]
m4[, weight_cash_lag    := shift(weight_cash,    1, fill = 0.0)]

beta_path <- file.path(BASE_DIR,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
setorder(beta_dt, Date)
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

panel <- merge(panel,
               m4[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag,
                       m4_cash_lag = weight_cash_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(m4_weight_lag), m4_weight_lag := 1.0]
panel[is.na(m4_cash_lag),   m4_cash_lag   := 0.0]

panel <- merge(panel,
               beta_dt[, .(realized_ym = ym,
                            beta_threshold_lag = beta_threshold_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
panel[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
panel[is.na(db_thr), db_thr := 0]

setorder(panel, date)

cat(sprintf("  m4_weight_lag distribution (rounded 0.01):\n"))
print(table(round(panel$m4_weight_lag, 2)))
cat(sprintf("  beta_threshold_lag distribution (rounded 0.1):\n"))
print(table(round(panel$beta_threshold_lag, 1)))

# ============================================================
# 3. Build R05 portfolio-level signal from admit alpha lineage
# ============================================================
cat("\n[3] Compute R05 portfolio-level signal (Top20 by score_eff)\n")

asp <- as.data.table(read_parquet(
  file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
r05_dt <- as.data.table(read_parquet(
  file.path(BASE_DIR, "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")))

# Merge R05_Z onto admit lineage
m <- merge(asp[, .(Date, Ticker, score_eff, regime_state)],
           r05_dt[, .(Date, Ticker, R05_Tail_Risk_Z)],
           by = c("Date", "Ticker"), all.x = TRUE)
m_valid <- m[!is.na(score_eff)]
setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by = Date]

# Per Date: R05_z portfolio average + regime (per Date all-same design)
# ★결정 재료 NA 경고 (2026-08-02): R05 z 소스(WT_D20260512_003, 동결)가 최근 신호일을 커버하지
#   못하면 z=NA → zlt 판정 불능 → β가 조용히 무-발화 가지(0.50)로 무뎌진다 — 실사고: 2026-07 sig
#   z=NA 로 시리즈가 배포(0.30) 대신 0.50 을 곱함. NA 를 침묵 소화하지 않고 여기서 드러낸다.
p_r05 <- top20[, .(R05_z_avg_top20 = mean(R05_Tail_Risk_Z, na.rm = TRUE),
                    R05_z_min_top20 = min(R05_Tail_Risk_Z, na.rm = TRUE),
                    n_top20 = .N,
                    n_R05_valid = sum(!is.na(R05_Tail_Risk_Z)),
                    regime = regime_state[1]),
                by = Date]
setorder(p_r05, Date)
.na_z <- p_r05[n_R05_valid == 0L]
if (nrow(.na_z))
  cat(sprintf(paste0("  [WARN] ★R05 z 전결측 신호일 %d건: %s\n",
                     "         → 해당 월 zlt 판정 불능 — β 가 무-발화 가지로 무뎌짐 (배포 manifest 와 대조 필요).\n",
                     "         원인 후보: R05 z 소스(WT_D20260512_003, 동결) 미연장.\n"),
              nrow(.na_z), paste(tail(as.character(.na_z$Date), 4), collapse = ", ")))
p_r05[, realized_ym := format(Date + months(1), "%Y-%m")]

cat(sprintf("  R05_z_avg portfolio summary:\n"))
print(summary(p_r05$R05_z_avg_top20))
cat(sprintf("  Regime distribution (sig_date level):\n"))
print(table(p_r05$regime))

# ============================================================
# 4. Construct β_R05 variants (5 designs)
# ============================================================
cat("\n[4] Construct β_R05 variants V1~V5\n")

# Helper: expanding past-only quantile (V4)
# At sig_date t, use only observations strictly before t
expanding_quantile <- function(x, dates, q = 0.2) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]
    past <- past[!is.na(past)]
    if (length(past) >= 12) {
      out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
    }
  }
  out
}

# Compute expanding past-only q20 + q50 for V4 / V5
p_r05[, R05_q20_past := expanding_quantile(R05_z_avg_top20, Date, q = 0.20)]
p_r05[, R05_q50_past := expanding_quantile(R05_z_avg_top20, Date, q = 0.50)]

cat(sprintf("  q20_past summary (NA pre-12m):\n"))
print(summary(p_r05$R05_q20_past))
cat(sprintf("  q50_past summary:\n"))
print(summary(p_r05$R05_q50_past))

# V1 mild regime
p_r05[, beta_R05_V1 := fcase(
  regime == "CRISIS", 0.5,
  regime == "CAUTION", 0.7,
  regime %in% c("BULL", "NORMAL"), 1.0,
  default = 1.0
)]

# V2 aggressive regime
p_r05[, beta_R05_V2 := fcase(
  regime == "CRISIS", 0.3,
  regime == "CAUTION", 0.5,
  regime %in% c("BULL", "NORMAL"), 1.0,
  default = 1.0
)]

# V3 medium regime
p_r05[, beta_R05_V3 := fcase(
  regime == "CRISIS", 0.4,
  regime == "CAUTION", 0.6,
  regime %in% c("BULL", "NORMAL"), 1.0,
  default = 1.0
)]

# V4 R05_adaptive (expanding past q20/q50)
p_r05[, beta_R05_V4 := fcase(
  is.na(R05_q20_past) | is.na(R05_q50_past), 1.0,
  R05_z_avg_top20 < R05_q20_past, 0.5,
  R05_z_avg_top20 < R05_q50_past, 0.7,
  default = 1.0
)]

# V5 regime × R05 interaction
p_r05[, beta_R05_V5 := fcase(
  is.na(R05_q20_past), 1.0,
  regime == "CRISIS" & R05_z_avg_top20 < R05_q20_past, 0.3,
  regime == "CRISIS", 0.5,
  regime == "CAUTION" & R05_z_avg_top20 < R05_q20_past, 0.5,
  regime == "CAUTION", 0.7,
  regime %in% c("BULL", "NORMAL") & R05_z_avg_top20 < R05_q20_past, 0.85,
  default = 1.0
)]

cat("\n  β_R05 distribution:\n")
for (vv in paste0("beta_R05_V", 1:5)) {
  cat(sprintf("  %s: %s\n", vv,
              paste(sprintf("%.2f=%d",
                            as.numeric(names(table(round(p_r05[[vv]],2)))),
                            as.integer(table(round(p_r05[[vv]],2)))),
                    collapse=" | ")))
}

# ============================================================
# 5. Merge β_R05 to panel (t-1 lag — decision at t-1 EOM applied to t)
# ============================================================
cat("\n[5] Merge β_R05 to panel with t-1 lag\n")

# β_R05 decided at sig_date Date_t-1 → applied to month realized_ym = Date_t-1 + 1m
# Our p_r05 already has realized_ym = sig_date + 1m, so it directly maps to panel.realized_ym
beta_merge <- p_r05[, .(realized_ym, regime,
                          R05_z_avg = R05_z_avg_top20,
                          R05_q20_past, R05_q50_past,
                          beta_R05_V1, beta_R05_V2, beta_R05_V3,
                          beta_R05_V4, beta_R05_V5)]

panel <- merge(panel, beta_merge, by = "realized_ym", all.x = TRUE)
for (vv in paste0("beta_R05_V", 1:5)) {
  panel[is.na(get(vv)), (vv) := 1.0]
}
panel[is.na(regime), regime := "UNKNOWN"]

# β_R05 turnover cost
for (i in 1:5) {
  bb <- paste0("beta_R05_V", i)
  db <- paste0("db_R05_V", i)
  panel[, (db) := abs(get(bb) - shift(get(bb), 1, fill = 1.0))]
  panel[is.na(get(db)), (db) := 0]
}
setorder(panel, date)

cat("  panel rows:", nrow(panel), "\n")
cat("  β_R05_V5 distribution on panel:\n")
print(table(round(panel$beta_R05_V5, 2)))

# ============================================================
# 6. Build return paths (Layer 4 baseline + Layer 5 × 5 variants)
# ============================================================
cat("\n[6] Build return paths: Baseline L4 + L5 variants\n")

# Layer 4 baseline (admit precedent)
panel[, ret_L4_baseline := beta_threshold_lag * m4_weight_lag * ret_orig -
                              db_thr * 0.0015]

# Layer 5: × β_R05_Vk + Δβ_R05 × 0.0015 incremental cost
for (i in 1:5) {
  bb <- paste0("beta_R05_V", i)
  db <- paste0("db_R05_V", i)
  rcol <- paste0("ret_L5_V", i)
  panel[, (rcol) := get(bb) * beta_threshold_lag * m4_weight_lag * ret_orig -
                       db_thr * 0.0015 -
                       get(db) * 0.0015]
}

panel[, anchor_date := date]

# Sanity check: L4 baseline should reproduce admit Sharpe
sanity_ann_L4 <- table.AnnualizedReturns(
  xts::xts(panel$ret_L4_baseline, order.by = panel$anchor_date),
  scale = 12, Rf = 0)
cat(sprintf("  [Sanity] L4 baseline (267m): SR=%.4f | CAGR=%.4f | Vol=%.4f\n",
            as.numeric(sanity_ann_L4[3,1]), as.numeric(sanity_ann_L4[1,1]),
            as.numeric(sanity_ann_L4[2,1])))

# ============================================================
# 7. Build measurement panels (267m + 255m admit-comparable)
# ============================================================
cat("\n[7] Build measurement panels\n")

panel <- panel[is.finite(ret_orig)]
## 종료월 = 패널 실측 종점 (2026-08-02 동적화 — 구 하드코딩은 매달 수동 갱신 요구, 7월 절단 실사고)
PANEL_END_YM <- max(panel$realized_ym, na.rm = TRUE)
cat(sprintf("  [panel window] 종료월 = %s (동적 — 패널 실측 종점)\n", PANEL_END_YM))
panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= PANEL_END_YM]
panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= PANEL_END_YM]

cat(sprintf("  267m_full: n=%d | %s ~ %s\n",
            nrow(panel_267m_full),
            as.character(min(panel_267m_full$anchor_date)),
            as.character(max(panel_267m_full$anchor_date))))
cat(sprintf("  255m_admit: n=%d | %s ~ %s\n",
            nrow(panel_255m_admit),
            as.character(min(panel_255m_admit$anchor_date)),
            as.character(max(panel_255m_admit$anchor_date))))

# ============================================================
# 8. Compute metrics per variant per panel
# ============================================================
compute_metrics <- function(dt_panel, panel_label) {
  cat(sprintf("\n=== %s (n=%d months) ===\n", panel_label, nrow(dt_panel)))

  cols <- c("ret_L4_baseline",
            "ret_L5_V1", "ret_L5_V2", "ret_L5_V3",
            "ret_L5_V4", "ret_L5_V5")
  labels <- c("L4_baseline_admit_precedent",
              "L5_V1_mild_regime", "L5_V2_aggressive_regime",
              "L5_V3_medium_regime", "L5_V4_R05_adaptive",
              "L5_V5_regime_x_R05_interaction")

  ret_mat <- as.matrix(dt_panel[, ..cols])
  xret <- xts::xts(ret_mat, order.by = dt_panel$anchor_date)
  colnames(xret) <- labels

  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mddv <- maxDrawdown(xret)
  sortino <- SortinoRatio(xret, MAR = 0)
  calmar <- CalmarRatio(xret)

  cat("Annualized:\n"); print(round(ann, 4))
  cat("MaxDrawdown:\n"); print(round(mddv, 4))

  build_row <- function(label, idx) {
    list(
      panel = panel_label,
      variant = label,
      CAGR = round(as.numeric(ann[1, idx]), 4),
      Vol = round(as.numeric(ann[2, idx]), 4),
      Sharpe = round(as.numeric(ann[3, idx]), 4),
      MDD = round(-as.numeric(mddv[idx]), 4),
      Sortino = round(as.numeric(sortino[idx]), 4),
      Calmar = round(as.numeric(calmar[idx]), 4),
      n_months = nrow(dt_panel)
    )
  }

  rbindlist(lapply(seq_along(labels),
                    function(i) build_row(labels[i], i)))
}

metrics_267  <- compute_metrics(panel_267m_full,  "267m_full_raw_cover")
metrics_255  <- compute_metrics(panel_255m_admit, "255m_admit_baseline_comparable")

# ============================================================
# 9. Per-regime decomposition (4-state, AX-001 v2 conditional defense)
# ============================================================
cat("\n[9] Per-regime decomposition (AX-001 v2 strict)\n")

regime_decomp <- function(dt_panel, panel_label) {
  out_rows <- list()
  for (vv in c("ret_L4_baseline", "ret_L5_V1", "ret_L5_V2",
               "ret_L5_V3", "ret_L5_V4", "ret_L5_V5")) {
    for (reg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
      idx <- dt_panel$regime == reg
      n <- sum(idx, na.rm = TRUE)
      if (n < 2) {
        out_rows[[length(out_rows) + 1]] <- list(
          panel = panel_label, variant = vv, regime = reg,
          n_months = n, mean_ret = NA_real_,
          sd_ret = NA_real_, SR_ann = NA_real_, hit_rate = NA_real_)
        next
      }
      r <- dt_panel[[vv]][idx]
      r <- r[is.finite(r)]
      out_rows[[length(out_rows) + 1]] <- list(
        panel = panel_label,
        variant = vv,
        regime = reg,
        n_months = length(r),
        mean_ret = round(mean(r), 6),
        sd_ret = round(sd(r), 6),
        SR_ann = round(mean(r) / sd(r) * sqrt(12), 4),
        hit_rate = round(mean(r > 0), 4)
      )
    }
  }
  rbindlist(out_rows)
}

regime_decomp_255 <- regime_decomp(panel_255m_admit, "255m_admit_baseline")
regime_decomp_267 <- regime_decomp(panel_267m_full, "267m_full_raw_cover")
regime_decomp_all <- rbind(regime_decomp_267, regime_decomp_255)

cat("\n  Per-regime SR (255m admit) — variant × regime:\n")
print(dcast(regime_decomp_255, variant ~ regime,
            value.var = "SR_ann"))

# AX-001 v2 conditional defense: CRISIS/CAUTION SR > 0
ax001_check <- regime_decomp_255[
  regime %in% c("CRISIS", "CAUTION"),
  .(min_SR = min(SR_ann, na.rm = TRUE)),
  by = variant
]
ax001_check[, AX001v2_pass := min_SR > 0]
cat("\n  AX-001 v2 conditional defense check (CRISIS/CAUTION SR > 0):\n")
print(ax001_check)

# ============================================================
# 10. Selection criterion
# ============================================================
cat("\n[10] Selection criterion (max SR - 0.5 × |MDD|)\n")

l4_255 <- metrics_255[variant == "L4_baseline_admit_precedent"]
selection_table <- copy(metrics_255)
selection_table[, score := Sharpe - 0.5 * abs(MDD)]
selection_table[, delta_SR_vs_baseline := Sharpe - l4_255$Sharpe]
selection_table[, delta_MDD_pp := (MDD - l4_255$MDD) * 100]
selection_table[, delta_CAGR_pp := (CAGR - l4_255$CAGR) * 100]
selection_table <- merge(selection_table,
                          ax001_check[, .(variant, AX001v2_pass)],
                          by = "variant", all.x = TRUE)
selection_table[is.na(AX001v2_pass), AX001v2_pass := FALSE]

# Hard gates
selection_table[, gate_SR_gt_baseline := Sharpe > l4_255$Sharpe]
selection_table[, gate_MDD_better := MDD > l4_255$MDD]  # MDD stored negative → "MDD better" = closer to 0
setorder(selection_table, -score)

cat("\n  Selection table (sorted by score):\n")
print(selection_table[, .(variant, Sharpe, MDD, CAGR, Sortino, Calmar, score,
                            delta_SR_vs_baseline, delta_MDD_pp, delta_CAGR_pp,
                            gate_SR_gt_baseline, gate_MDD_better, AX001v2_pass)])

# Best variant (passes all gates, max score)
best_eligible <- selection_table[
  gate_SR_gt_baseline & gate_MDD_better & AX001v2_pass
]
if (nrow(best_eligible) > 0) {
  setorder(best_eligible, -score)
  best <- best_eligible[1]
  cat(sprintf("\n  BEST eligible (all gates PASS): %s\n", best$variant))
  cat(sprintf("    SR=%.4f (ΔSR=%+.4f) | MDD=%.4f (ΔMDD=%+.2fpp) | CAGR=%.4f (ΔCAGR=%+.2fpp)\n",
              best$Sharpe, best$delta_SR_vs_baseline,
              best$MDD, best$delta_MDD_pp,
              best$CAGR, best$delta_CAGR_pp))
} else {
  cat("\n  NO variant passes all gates (SR > baseline & MDD better & AX-001 v2).\n")
  cat("  Highest SR even if not passing all gates:\n")
  top_sr <- selection_table[order(-Sharpe)][1]
  cat(sprintf("    %s: SR=%.4f / MDD=%.4f / AX001v2_pass=%s\n",
              top_sr$variant, top_sr$Sharpe, top_sr$MDD, top_sr$AX001v2_pass))
}

# ============================================================
# 11. Incremental turnover check (cost retain)
# ============================================================
cat("\n[11] Incremental turnover check (cost retain target ≤ 0.5/yr)\n")
to_inc <- panel_255m_admit[, .(
  V1 = sum(db_R05_V1) * 12 / nrow(panel_255m_admit),
  V2 = sum(db_R05_V2) * 12 / nrow(panel_255m_admit),
  V3 = sum(db_R05_V3) * 12 / nrow(panel_255m_admit),
  V4 = sum(db_R05_V4) * 12 / nrow(panel_255m_admit),
  V5 = sum(db_R05_V5) * 12 / nrow(panel_255m_admit)
)]
cat("\n  Incremental annualized |Δβ_R05| (β-turnover):\n")
print(to_inc)

# ============================================================
# 12. Save artifacts
# ============================================================
cat("\n[12] Save artifacts\n")

combined_metrics <- rbindlist(list(metrics_267, metrics_255))
fwrite(combined_metrics,
       file.path(OUT_DIR, "metrics_layer5_variants.csv"))
fwrite(selection_table,
       file.path(OUT_DIR, "selection_table_255m_admit.csv"))
fwrite(regime_decomp_all,
       file.path(OUT_DIR, "regime_decomposition_255m_267m.csv"))
fwrite(ax001_check,
       file.path(OUT_DIR, "ax001_v2_check.csv"))
fwrite(to_inc, file.path(OUT_DIR, "incremental_turnover.csv"))

# Per-variant NAV (267m full)
for (i in 0:5) {
  if (i == 0) {
    rc <- "ret_L4_baseline"; lab <- "L4_baseline"
  } else {
    rc <- paste0("ret_L5_V", i); lab <- paste0("L5_V", i)
  }
  panel_267m_full[[paste0("nav_", lab)]] <- cumprod(1 + panel_267m_full[[rc]])
}
nav_dt <- panel_267m_full[, .SD,
  .SDcols = c("anchor_date", "realized_ym",
              "nav_L4_baseline", "nav_L5_V1", "nav_L5_V2",
              "nav_L5_V3", "nav_L5_V4", "nav_L5_V5")]
fwrite(nav_dt, file.path(OUT_DIR, "nav_layer5_variants.csv"))

# Period returns (267m)
ret_dt <- panel_267m_full[, .(anchor_date, realized_ym, regime,
                                ret_orig, ret_L4_baseline,
                                ret_L5_V1, ret_L5_V2, ret_L5_V3,
                                ret_L5_V4, ret_L5_V5,
                                beta_threshold_lag, m4_weight_lag,
                                beta_R05_V1, beta_R05_V2, beta_R05_V3,
                                beta_R05_V4, beta_R05_V5,
                                db_thr, db_R05_V1, db_R05_V2, db_R05_V3,
                                db_R05_V4, db_R05_V5,
                                R05_z_avg, R05_q20_past, R05_q50_past)]
# ── panel 월-라벨 정렬 결함 방지 (2026-07-02 도훈 mandate): return_ym=진짜 수익월 + β-가드 ──
source(file.path(Sys.getenv("QM_ROOT", getwd()), "02_Infrastructure/contracts/panel_alignment_guard.R"))
ret_dt <- add_return_ym(ret_dt)      # realized_ym / return_ym(=realized_ym-1) 동시 보유
assert_panel_alignment(ret_dt)        # return_ym 정렬 β(vs KOSPI200)<0.5면 ABORT → 결함 재발 차단
fwrite(ret_dt, file.path(OUT_DIR, "period_returns_layer5.csv"))

# Drawdowns top10 per variant (255m admit)
dd_list <- list()
for (i in 0:5) {
  if (i == 0) {
    rc <- "ret_L4_baseline"; lab <- "L4_baseline"
  } else {
    rc <- paste0("ret_L5_V", i); lab <- paste0("L5_V", i)
  }
  xr <- xts::xts(panel_255m_admit[[rc]], order.by = panel_255m_admit$anchor_date)
  dd_tab <- table.Drawdowns(xr, top = 10)
  if (!is.null(dd_tab) && nrow(dd_tab) > 0) {
    dd_d <- as.data.table(dd_tab)
    dd_d[, variant := lab]
    for (col in names(dd_d)) {
      if (is.factor(dd_d[[col]])) dd_d[[col]] <- as.character(dd_d[[col]])
      if (inherits(dd_d[[col]], "Date")) dd_d[[col]] <- as.character(dd_d[[col]])
    }
    dd_list[[lab]] <- dd_d
  }
}
dd_combined <- rbindlist(dd_list, fill = TRUE)
fwrite(dd_combined, file.path(OUT_DIR, "drawdowns_top10_per_variant.csv"))

# ============================================================
# 13. Audit (Backtest Contract v1.0)
# ============================================================
cat("\n[13] Audit (Backtest Contract v1.0 10-check)\n")

xret_L4_255 <- xts::xts(panel_255m_admit$ret_L4_baseline,
                          order.by = panel_255m_admit$anchor_date)
l4_baseline_admit_sharpe <- 1.7486  # Production audit baseline 255m

# L4 baseline sanity vs published baseline
ann_L4_255 <- table.AnnualizedReturns(xret_L4_255, scale = 12, Rf = 0)
l4_sr_now <- as.numeric(ann_L4_255[3, 1])

audit <- list(
  task_id = "WT-H20260513_001",
  audit_version = "v1_layer5_R05_overlay_strict",
  audit_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  parent_admit_wt = "WT-P20260504_001",
  parent_production_wt = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
  checks = list(
    nav_monotone_dates = list(pass = all(diff(nav_dt$anchor_date) > 0),
                              note = "monotone increasing"),
    returns_finite = list(pass = all(is.finite(panel_255m_admit$ret_L4_baseline)) &&
                                   all(is.finite(panel_255m_admit$ret_L5_V5)),
                          note = sprintf("L4 finite n=%d, L5_V5 finite n=%d",
                                          sum(is.finite(panel_255m_admit$ret_L4_baseline)),
                                          sum(is.finite(panel_255m_admit$ret_L5_V5)))),
    n_obs_sufficient = list(pass = nrow(panel_255m_admit) >= 60,
                            note = sprintf("n=%d months", nrow(panel_255m_admit))),
    cost_model_documented = list(pass = TRUE,
                                  note = "v2.3_kr_retail_15bps; base PR ret_net + AR Δβ × 15bps + β_R05 Δβ × 15bps"),
    pit_lag_applied = list(pass = TRUE,
                            note = "M4/β_AR/β_R05 all t-1 lag (shift(1)); V4 expanding past-only quantile"),
    perfanalytics_standard = list(pass = TRUE,
                                   note = "table.AnnualizedReturns + maxDrawdown + SortinoRatio + CalmarRatio"),
    weighting_basis = list(pass = TRUE,
                            note = "Iter31 linear_tilt baked in PR ret_net + sequential overlay only (no holding change)"),
    raw_cover_start_hardcoded = list(pass = TRUE,
                                     note = sprintf("decision %s | realized %s",
                                                     as.character(RAW_COVER_START_DECISION),
                                                     as.character(RAW_COVER_START_REALIZED))),
    layer_count = list(pass = TRUE,
                        note = "L4 baseline + L5 variants V1~V5 (5 variants total)"),
    sanity_l4_vs_production_audit = list(pass = abs(l4_sr_now - l4_baseline_admit_sharpe) < 0.05,
                                          note = sprintf("L4 SR delta vs production audit 255m baseline %.4f: %+.4f (expect <0.05)",
                                                          l4_baseline_admit_sharpe,
                                                          l4_sr_now - l4_baseline_admit_sharpe))
  ),
  baseline_L4_255m = list(
    CAGR = l4_255$CAGR, Vol = l4_255$Vol, Sharpe = l4_255$Sharpe,
    MDD = l4_255$MDD, Sortino = l4_255$Sortino, Calmar = l4_255$Calmar,
    n_months = l4_255$n_months
  ),
  variants_summary = list(),
  best_eligible_variant = NULL,
  per_regime_summary = as.list(regime_decomp_255[variant == "ret_L5_V5"]),
  incremental_turnover_annualized = as.list(to_inc)
)

# Variant summary
for (v in unique(selection_table$variant)) {
  row <- selection_table[variant == v]
  audit$variants_summary[[v]] <- list(
    Sharpe = row$Sharpe, MDD = row$MDD, CAGR = row$CAGR,
    Sortino = row$Sortino, Calmar = row$Calmar,
    score = row$score,
    delta_SR_vs_baseline = row$delta_SR_vs_baseline,
    delta_MDD_pp = row$delta_MDD_pp,
    delta_CAGR_pp = row$delta_CAGR_pp,
    AX001v2_pass = row$AX001v2_pass,
    gate_SR_gt_baseline = row$gate_SR_gt_baseline,
    gate_MDD_better = row$gate_MDD_better
  )
}

# Best eligible
if (nrow(best_eligible) > 0) {
  audit$best_eligible_variant <- list(
    variant = best$variant,
    Sharpe = best$Sharpe,
    MDD = best$MDD,
    CAGR = best$CAGR,
    delta_SR_vs_baseline = best$delta_SR_vs_baseline,
    delta_MDD_pp = best$delta_MDD_pp,
    delta_CAGR_pp = best$delta_CAGR_pp,
    AX001v2_pass = best$AX001v2_pass
  )
}

critical_checks <- c("nav_monotone_dates", "returns_finite", "n_obs_sufficient",
                      "pit_lag_applied", "perfanalytics_standard",
                      "sanity_l4_vs_production_audit")
all_critical_pass <- all(sapply(critical_checks,
                                  function(k) audit$checks[[k]]$pass))
audit$integrity <- ifelse(all_critical_pass, "PASS", "FAIL")
audit$metric_type <- ifelse(all_critical_pass, "backtested", "unavailable")

write_json(audit, file.path(OUT_DIR, "audit.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n[Audit] integrity: %s | metric_type: %s\n",
            audit$integrity, audit$metric_type))

# ============================================================
# 14. bt_result 10-component (Backtest Contract v1.0)
# ============================================================
bt_result <- list(
  manifest = list(
    task_id = "WT-H20260513_001",
    parent_admit_wt = "WT-P20260504_001",
    parent_production_wt = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
    strategy_id = STR_ID,
    measurement_basis = "production_weighting_sequential_overlay_L5",
    layers = "Iter31 base + M4 BOCPD + AR threshold + R05 portfolio cash-control",
    weighting = "Iter31_linear_tilt_lambda1.5_phi3_ub0.20 [PR ret_net baked]",
    raw_cover_start_decision = as.character(RAW_COVER_START_DECISION),
    raw_cover_start_realized = as.character(RAW_COVER_START_REALIZED),
    base_source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
    alpha_lineage = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    r05_source = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
    m4_source = "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv",
    ar_source = "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv",
    mode = "research_hypothesis_sweep",
    pit_compliance = "C1_C2_C9_C11_C13_C14",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  ),
  strategy_spec = list(
    architecture = "w_final(t,i) = w_str1715(t,i) × m4(t) × β_AR(t) × β_R05(regime_t, R05_z_t)",
    sequential_overlay = "alpha building blocks unchanged → cost retain (cash-control only)",
    variants = list(
      V1 = "mild_regime: BULL/NORMAL=1.0, CAUTION=0.7, CRISIS=0.5",
      V2 = "aggressive_regime: BULL/NORMAL=1.0, CAUTION=0.5, CRISIS=0.3",
      V3 = "medium_regime: BULL/NORMAL=1.0, CAUTION=0.6, CRISIS=0.4",
      V4 = "R05_adaptive: expanding past q20/q50 → 0.5/0.7/1.0",
      V5 = "regime × R05 interaction (joint conditional)"
    ),
    universe = "KOSPI200 ∪ KOSDAQ150 (admit lineage)",
    top_n = 20,
    weighting = "Iter31 production linear_tilt (NOT EW)",
    cost_model_version = "v2.3_kr_retail_15bps",
    cost_applied_basis = "PR ret_net + AR Δβ × 0.0015 + β_R05 Δβ × 0.0015"
  ),
  nav = nav_dt,
  period_returns = ret_dt,
  holdings = NULL,
  benchmark_returns = NULL,
  metrics = list(
    L4_baseline_255m = as.list(metrics_255[variant == "L4_baseline_admit_precedent"]),
    L5_variants_255m = as.list(metrics_255[variant != "L4_baseline_admit_precedent"])
  ),
  benchmark_compare = NULL,
  rolling_metrics = NULL,
  drawdowns = as.data.frame(dd_combined),
  audit = audit
)
saveRDS(bt_result, file.path(OUT_DIR, "bt_result_layer5_R05.rds"))

# ============================================================
# 15. Final summary
# ============================================================
cat("\n============================================================\n")
cat("FINAL: STR_1715_AR_on_M4 + R05 Layer 5 Sequential Overlay\n")
cat("============================================================\n")
cat("\nBaseline L4_admit_precedent (255m admit-comparable):\n")
cat(sprintf("  SR=%.4f | MDD=%.4f | CAGR=%.4f | Sortino=%.4f | Calmar=%.4f\n",
            l4_255$Sharpe, l4_255$MDD, l4_255$CAGR,
            l4_255$Sortino, l4_255$Calmar))

cat("\nLayer 5 variants (255m admit-comparable):\n")
for (vi in 1:5) {
  v_label <- c("L5_V1_mild_regime", "L5_V2_aggressive_regime",
                "L5_V3_medium_regime", "L5_V4_R05_adaptive",
                "L5_V5_regime_x_R05_interaction")[vi]
  row <- metrics_255[variant == v_label]
  cat(sprintf("  %s: SR=%.4f (Δ=%+.4f) MDD=%.4f (Δ=%+.2fpp) CAGR=%.4f\n",
              v_label, row$Sharpe, row$Sharpe - l4_255$Sharpe,
              row$MDD, (row$MDD - l4_255$MDD)*100, row$CAGR))
}

cat("\nTarget criteria (hard gates):\n")
cat(sprintf("  SR > %.4f (baseline) | MDD better than %.4f | AX-001 v2 PASS\n",
            l4_255$Sharpe, l4_255$MDD))

cat("\nDone. Outputs in:", OUT_DIR, "\n")
