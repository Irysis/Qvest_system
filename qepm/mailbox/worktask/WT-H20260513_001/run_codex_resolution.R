## ============================================================
## WT-H20260513_001 — Codex Critic Resolution Script
## ============================================================
## Codex REJECT (veto=false) 9 concerns resolution:
##   C1: Pure Function v6.1 R12 hash audit (alpha/risk/optimization)
##   C2: Required stage_artifacts dirs + weights.csv
##   C3: V6 post-hoc reproducibility (ultra-fine grid artifact)
##   C4: DSR penalty consistency (N=37 multi-test)
##   C5: Harvey 5-spec regression (CAPM/Carhart3/Carhart4/FF5/FF6) — provide what's possible (KR factor data dependent)
##   C6: TO round-trip x2 convention
##   C7: Charts verify (charts exist, confirmed 06:46)
##   C8: AX-001 v2 classification (judge-level adjudication note)
##   C9: Source covariance condition (out of forge scope, alpha/risk responsibility)
## ============================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
  library(sandwich); library(lmtest); library(digest)
  library(lubridate)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-H20260513_001")
OUT_DIR  <- file.path(WT_DIR, "output")

# ============================================================
# C1: Hash audit (Pure Function R12)
# ============================================================
cat("[C1] Pure Function R12 hash audit\n")

# Source files start hash (mandatory)
sources <- list(
  alpha_admit_lineage = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
  r05_signal = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
  m4_overlay = "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv",
  ar_overlay = "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv",
  pr_base = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"
)
hash_audit <- list()
for (nm in names(sources)) {
  fp <- file.path(BASE_DIR, sources[[nm]])
  if (file.exists(fp)) {
    h <- tryCatch(digest::digest(file = fp, algo = "md5"),
                   error = function(e) "ERROR")
    sz <- file.info(fp)$size
    mt <- file.info(fp)$mtime
    hash_audit[[nm]] <- list(
      path = sources[[nm]],
      md5 = h,
      size_bytes = sz,
      mtime = as.character(mt),
      exists = TRUE
    )
    cat(sprintf("  %s: md5=%s size=%d\n", nm, substr(h, 1, 12), sz))
  } else {
    hash_audit[[nm]] <- list(path = sources[[nm]], exists = FALSE)
    cat(sprintf("  %s: MISSING\n", nm))
  }
}
write_json(hash_audit, file.path(OUT_DIR, "hash_audit_sources.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ============================================================
# C2: Generate weights.csv (mandate spec) + holdings reconstruction
# ============================================================
cat("\n[C2] Generate weights.csv with monthly scalar schedule\n")

# Load base PR + admit holdings reconstruction
asp <- as.data.table(read_parquet(
  file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
m_valid <- asp[!is.na(score_eff)]
setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by = Date]

# Per-month holdings (admit lineage selection)
n_dates <- length(unique(top20$Date))
cat(sprintf("  Admit lineage top20 sig_dates: %d\n", n_dates))

# Load β_R05 V2 schedule (recommended primary)
pr_dt <- fread(file.path(OUT_DIR, "period_returns_layer5.csv"))
pr_dt[, anchor_date := as.Date(anchor_date)]
pr_dt[, realized_ym_dt := as.Date(paste0(realized_ym, "-01"))]

# Decision_date = realized_ym - 1m (overlay decided at month t-1 EOM)
pr_dt[, decision_ym := format(realized_ym_dt %m-% months(1), "%Y-%m")]

# Build V2 + V6 weights.csv: per as_of_date, scalar overlay
weights_dt <- pr_dt[, .(
  as_of_date = realized_ym_dt,
  decision_date = as.Date(paste0(decision_ym, "-01")),
  realized_ym = realized_ym,
  decision_ym = decision_ym,
  regime = regime,
  R05_z_avg = R05_z_avg,
  base_str1715_weight = 1.0,
  m4_scalar = m4_weight_lag,
  beta_AR = beta_threshold_lag,
  beta_R05_V2 = beta_R05_V2,
  beta_R05_V6 = fcase(regime == "CRISIS", 0.15,
                        regime == "CAUTION", 0.30,
                        default = 1.0),
  combined_overlay_V2 = m4_weight_lag * beta_threshold_lag * beta_R05_V2,
  combined_overlay_V6 = m4_weight_lag * beta_threshold_lag *
                          fcase(regime == "CRISIS", 0.15,
                                  regime == "CAUTION", 0.30,
                                  default = 1.0),
  n_holdings_base = 20,
  weight_per_holding_base_max = 0.20,
  cash_share_V2 = 1 - m4_weight_lag * beta_threshold_lag * beta_R05_V2,
  cash_share_V6 = 1 - m4_weight_lag * beta_threshold_lag *
                        fcase(regime == "CRISIS", 0.15,
                                regime == "CAUTION", 0.30,
                                default = 1.0)
)]
setorder(weights_dt, as_of_date)
fwrite(weights_dt, file.path(WT_DIR, "weights.csv"))
cat(sprintf("  weights.csv saved: n=%d as_of_dates | %s ~ %s\n",
            nrow(weights_dt),
            as.character(min(weights_dt$as_of_date)),
            as.character(max(weights_dt$as_of_date))))

# ============================================================
# C3: V6 ultra-fine grid reproducibility artifact
# ============================================================
cat("\n[C3] V6 ultra-fine grid full save + reproducibility\n")

# Ultra-fine grid (16 combos)
ultra_results <- list()
i <- 1
for (cri in c(0.15, 0.20, 0.25, 0.30)) {
  for (cau in c(0.30, 0.35, 0.40, 0.45)) {
    pr_dt[, bv := fcase(
      regime == "CRISIS", cri,
      regime == "CAUTION", cau,
      default = 1.0
    )]
    pr_dt[, db_v := abs(bv - shift(bv, 1, fill = 1.0))]
    pr_dt[is.na(db_v), db_v := 0]
    pr_dt[, ret_v := bv * beta_threshold_lag * m4_weight_lag * ret_orig -
                       db_thr * 0.0015 - db_v * 0.0015]
    sub <- pr_dt[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
    sub67 <- pr_dt[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
    xr <- xts::xts(sub$ret_v, order.by = sub$anchor_date)
    xr67 <- xts::xts(sub67$ret_v, order.by = sub67$anchor_date)
    ann <- table.AnnualizedReturns(xr, scale = 12, Rf = 0)
    ann67 <- table.AnnualizedReturns(xr67, scale = 12, Rf = 0)
    mdd <- maxDrawdown(xr)
    sortino <- SortinoRatio(xr, MAR = 0)
    calmar <- CalmarRatio(xr)
    to_inc <- mean(sub$db_v) * 12
    # round-trip x2 turnover (C6 resolution)
    to_inc_round_trip <- to_inc * 2
    # NW t
    m <- lm(sub$ret_v ~ 1)
    vc <- NeweyWest(m, lag = 6, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(m, vc)
    t_nw <- unname(ct[1, "t value"])

    ultra_results[[i]] <- list(
      variant_id = sprintf("V6_cri%.2f_cau%.2f", cri, cau),
      crisis_beta = cri,
      caution_beta = cau,
      SR_255m = round(as.numeric(ann[3, 1]), 4),
      CAGR_255m = round(as.numeric(ann[1, 1]), 4),
      Vol_255m = round(as.numeric(ann[2, 1]), 4),
      MDD_255m = round(-as.numeric(mdd), 4),
      Sortino_255m = round(as.numeric(sortino), 4),
      Calmar_255m = round(as.numeric(calmar), 4),
      t_NW_lag6_255m = round(t_nw, 3),
      SR_267m = round(as.numeric(ann67[3, 1]), 4),
      CAGR_267m = round(as.numeric(ann67[1, 1]), 4),
      MDD_267m = round(-as.numeric(maxDrawdown(xr67)), 4),
      TO_inc_oneway = round(to_inc, 4),
      TO_inc_round_trip_x2 = round(to_inc_round_trip, 4)
    )
    i <- i + 1
  }
}
ultra_dt <- rbindlist(ultra_results)
setorder(ultra_dt, -SR_255m)
fwrite(ultra_dt, file.path(OUT_DIR, "grid_ultrafine_regime.csv"))
cat(sprintf("  Saved %d ultra-fine combos\n", nrow(ultra_dt)))
cat("\n  Top 5 V6 grid:\n")
print(ultra_dt[1:5, .(variant_id, SR_255m, CAGR_255m, MDD_255m, TO_inc_oneway, TO_inc_round_trip_x2)])

# Best V6 reproducible
best_v6 <- ultra_dt[1]
cat(sprintf("\n  Best V6 reproduced: %s SR=%.4f (255m)\n",
            best_v6$variant_id, best_v6$SR_255m))

# ============================================================
# C4: DSR penalty consistency (N=37) — apply uniformly
# ============================================================
cat("\n[C4] DSR Bailey-LdP penalty N=37 (consistent multi-test framing)\n")

dsr_results <- list()

# Baseline + ex-ante variants (V1-V5)
all_variants <- list(
  L4_baseline = "ret_L4_baseline",
  L5_V1_mild = "ret_L5_V1",
  L5_V2_aggressive = "ret_L5_V2",
  L5_V3_medium = "ret_L5_V3",
  L5_V4_R05_adaptive = "ret_L5_V4",
  L5_V5_regime_x_R05 = "ret_L5_V5"
)

# V6 ultra-fine variants 16
for (rr in 1:nrow(ultra_dt)) {
  all_variants[[ultra_dt$variant_id[rr]]] <- "ret_top_dummy"  # placeholder
}

sub_255 <- pr_dt[realized_ym >= "2005-02" & realized_ym <= "2026-04"]

for (lab in names(all_variants)) {
  if (lab %in% names(all_variants)[1:6]) {
    # Static variants
    rcol <- all_variants[[lab]]
    if (rcol %in% names(sub_255)) {
      r <- sub_255[[rcol]]
    } else next
  } else {
    # V6 grid variants — reconstruct return
    cri <- ultra_dt[variant_id == lab]$crisis_beta
    cau <- ultra_dt[variant_id == lab]$caution_beta
    sub_255[, bv := fcase(regime == "CRISIS", cri,
                            regime == "CAUTION", cau,
                            default = 1.0)]
    sub_255[, db_v := abs(bv - shift(bv, 1, fill = 1.0))]
    sub_255[is.na(db_v), db_v := 0]
    sub_255[, ret_v := bv * beta_threshold_lag * m4_weight_lag * ret_orig -
                         db_thr * 0.0015 - db_v * 0.0015]
    r <- sub_255$ret_v
  }

  T_ <- length(r); mu <- mean(r); s <- sd(r)
  sr_per <- mu / s
  sr_ann <- sr_per * sqrt(12)
  sk <- mean((r - mu)^3) / s^3
  kr <- mean((r - mu)^4) / s^4 - 3
  sigma_sr_per <- sqrt((1 - sr_per * sk + (kr / 4) * sr_per^2) / (T_ - 1))
  sigma_sr_ann <- sigma_sr_per * sqrt(12)

  # Apply DSR penalty at N=5, N=21, N=37 (universal for all variants)
  dsr_entries <- list()
  for (N in c(5, 21, 37)) {
    em <- sqrt(2 * log(N)) - 0.5772156649 / sqrt(2 * log(N))
    z <- (sr_ann - em) / sigma_sr_ann
    dsr_entries[[sprintf("N%d_Z", N)]] <- round(z, 4)
    dsr_entries[[sprintf("N%d_pass_threshold_0.5", N)]] <- z > 0.5
  }

  dsr_results[[lab]] <- c(list(
    variant = lab,
    SR_ann = round(sr_ann, 4),
    skew = round(sk, 3),
    kurt = round(kr, 3),
    sigma_SR_ann = round(sigma_sr_ann, 4)
  ), dsr_entries)
}

dsr_dt <- rbindlist(dsr_results, fill = TRUE)
setorder(dsr_dt, -SR_ann)
fwrite(dsr_dt, file.path(OUT_DIR, "dsr_consistent_penalty_N37.csv"))
cat("\n  DSR results (consistent N=37 multi-test):\n")
print(dsr_dt[1:10])

# ============================================================
# C5: Harvey-Liu-Zhu 5-spec regression — what's feasible without FF KR data
# ============================================================
cat("\n[C5] Harvey-Liu-Zhu factor regression — KR FF data dependent\n")

# Load benchmark (KOSPI200 total return = factor proxy for KR market)
bm_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/05_benchmark_returns.csv")
bm <- fread(bm_path)
bm[, date := as.Date(date)]
ret_col <- names(bm)[grepl("ret", names(bm), ignore.case = TRUE)][1]
setnames(bm, ret_col, "bm_ret")
bm[, ym := format(date, "%Y-%m")]
bm <- unique(bm[, .(ym, bm_ret)], by = "ym")

# Merge to V2 + V6 returns
sub_w <- merge(sub_255, bm[, .(realized_ym = ym, bm_ret)],
               by = "realized_ym", all.x = TRUE)
sub_w[is.na(bm_ret), bm_ret := 0]

# Best V6 reconstruct
cri_best <- best_v6$crisis_beta; cau_best <- best_v6$caution_beta
sub_w[, bv_best := fcase(regime == "CRISIS", cri_best,
                            regime == "CAUTION", cau_best,
                            default = 1.0)]
sub_w[, db_best := abs(bv_best - shift(bv_best, 1, fill = 1.0))]
sub_w[is.na(db_best), db_best := 0]
sub_w[, ret_v6_best := bv_best * beta_threshold_lag * m4_weight_lag * ret_orig -
                         db_thr * 0.0015 - db_best * 0.0015]

harvey_5spec <- function(r, factors, label) {
  # CAPM proxy: bm_ret only
  out <- list()
  spec_data <- data.table(r = r, mkt = factors$mkt)
  m <- lm(r ~ mkt, data = spec_data)
  vc <- NeweyWest(m, lag = 6, prewhite = FALSE, adjust = TRUE)
  ct <- coeftest(m, vc)
  out[["spec1_CAPM_KR_KOSPI200"]] <- list(
    alpha_monthly = round(coef(m)[1], 5),
    alpha_t_NW = round(ct[1, "t value"], 3),
    alpha_p_NW = round(ct[1, "Pr(>|t|)"], 4),
    beta_market = round(coef(m)[2], 3),
    R2 = round(summary(m)$r.squared, 3),
    n = length(r)
  )
  # Spec 2: Excess (r - bm) — Carhart proxy partial
  # (Full FF/Carhart KR data not available in this artifact set —
  #  partial reporting per RF-F6 spec parity)
  spec_excess <- data.table(r_exc = r - factors$mkt, mkt = factors$mkt)
  m_exc <- lm(r_exc ~ mkt, data = spec_excess)
  vc_exc <- NeweyWest(m_exc, lag = 6, prewhite = FALSE, adjust = TRUE)
  ct_exc <- coeftest(m_exc, vc_exc)
  out[["spec2_excess_over_market"]] <- list(
    alpha_monthly_excess = round(coef(m_exc)[1], 5),
    alpha_t_NW = round(ct_exc[1, "t value"], 3),
    alpha_p_NW = round(ct_exc[1, "Pr(>|t|)"], 4),
    n = length(r),
    note = "excess r - bm regression (KR mkt as only factor)"
  )
  # Spec 3: Plain raw return t (no factor)
  m_plain <- lm(r ~ 1)
  vc_plain <- NeweyWest(m_plain, lag = 6, prewhite = FALSE, adjust = TRUE)
  ct_plain <- coeftest(m_plain, vc_plain)
  out[["spec3_plain_raw_NW"]] <- list(
    mean_monthly = round(mean(r), 5),
    t_NW_lag6 = round(ct_plain[1, "t value"], 3),
    p_NW = round(ct_plain[1, "Pr(>|t|)"], 4),
    n = length(r),
    HLZ_3.0_pass = abs(ct_plain[1, "t value"]) > 3.0
  )
  # Spec 4: Crisis-only subperiod (2008-2010)
  if (length(factors$crisis_idx) >= 5) {
    r_cri <- r[factors$crisis_idx]
    m_cri <- lm(r_cri ~ 1)
    ct_cri <- coeftest(m_cri, NeweyWest(m_cri, lag = 3,
                                         prewhite = FALSE, adjust = TRUE))
    out[["spec4_crisis_2008_2010_only"]] <- list(
      mean_monthly = round(mean(r_cri), 5),
      t_NW = round(ct_cri[1, "t value"], 3),
      p_NW = round(ct_cri[1, "Pr(>|t|)"], 4),
      n = length(r_cri)
    )
  }
  # Spec 5: Post-2010 OOS (FF data widely available post-2010)
  if (length(factors$post2010_idx) >= 24) {
    r_post <- r[factors$post2010_idx]
    bm_post <- factors$mkt[factors$post2010_idx]
    m_post <- lm(r_post ~ bm_post)
    ct_post <- coeftest(m_post, NeweyWest(m_post, lag = 6,
                                            prewhite = FALSE, adjust = TRUE))
    out[["spec5_post2010_CAPM_KR"]] <- list(
      alpha_monthly = round(coef(m_post)[1], 5),
      alpha_t_NW = round(ct_post[1, "t value"], 3),
      beta_market = round(coef(m_post)[2], 3),
      n = length(r_post)
    )
  }
  list(label = label, specs = out)
}

# Build factors
crisis_idx <- which(sub_w$realized_ym >= "2008-09" & sub_w$realized_ym <= "2010-12")
post2010_idx <- which(sub_w$realized_ym >= "2010-01")

# Limitation note: FF5/Carhart KR factor data not available in this artifact;
# what we provide are 5 specs with substituted KR market (KOSPI200) where applicable.
# Full FF5/Carhart KR requires running risk-research factor regression separately.
factors_list <- list(mkt = sub_w$bm_ret,
                      crisis_idx = crisis_idx,
                      post2010_idx = post2010_idx)

harvey_v2 <- harvey_5spec(sub_w$ret_L5_V2, factors_list, "L5_V2_aggressive_regime")
harvey_v6 <- harvey_5spec(sub_w$ret_v6_best, factors_list,
                            sprintf("V6_best_%s", best_v6$variant_id))
harvey_L4 <- harvey_5spec(sub_w$ret_L4_baseline, factors_list, "L4_baseline_admit_precedent")

harvey_combined <- list(
  L4_baseline = harvey_L4,
  L5_V2_aggressive_PRIMARY_RECOMMEND = harvey_v2,
  V6_best_post_hoc = harvey_v6,
  data_caveat = paste(
    "5-spec regression substitutes KR market (KOSPI200 TR) for FF/Carhart factors.",
    "Full FF5/Carhart-4 KR factor data requires risk-research stage artifacts beyond",
    "current forge scope. CAPM-KR (spec1/spec5), market-excess (spec2), plain NW (spec3),",
    "crisis subperiod (spec4) all reported. Risk agent or Q-Lead should supplement with",
    "FF5 KR if available in factor DB (288 monthly factors)."
  )
)
write_json(harvey_combined, file.path(OUT_DIR, "harvey_factor_regression_5spec.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Harvey 5-spec saved (CAPM-KR + market-excess + plain-NW + crisis + post2010)\n")
cat("\n  V2 alpha monthly (CAPM-KR):\n")
print(harvey_v2$specs$spec1_CAPM_KR_KOSPI200)
cat("\n  V6 alpha monthly (CAPM-KR):\n")
print(harvey_v6$specs$spec1_CAPM_KR_KOSPI200)

# ============================================================
# C6: TO round-trip x2 turnover audit
# ============================================================
cat("\n[C6] TO round-trip x2 turnover audit (RF-F7 convention)\n")

to_audit <- list()
for (lab in c("L4_baseline", "L5_V1_mild", "L5_V2_aggressive",
              "L5_V3_medium", "L5_V4_R05_adaptive", "L5_V5_regime_x_R05",
              best_v6$variant_id)) {
  if (lab == "L4_baseline") {
    db_col <- "db_thr"
  } else if (startsWith(lab, "L5_V")) {
    vi <- as.integer(sub("L5_V([0-9]+)_.*", "\\1", lab))
    db_col <- paste0("db_R05_V", vi)
  } else {
    # V6 — reconstruct
    cri <- best_v6$crisis_beta; cau <- best_v6$caution_beta
    sub_255[, bv := fcase(regime == "CRISIS", cri,
                            regime == "CAUTION", cau,
                            default = 1.0)]
    sub_255[, db_R05_V6_temp := abs(bv - shift(bv, 1, fill = 1.0))]
    sub_255[is.na(db_R05_V6_temp), db_R05_V6_temp := 0]
    db_col <- "db_R05_V6_temp"
  }
  if (!db_col %in% names(sub_255)) next
  raw_db <- sub_255[[db_col]]
  # Base PR turnover (one-way) annualized
  to_oneway <- mean(raw_db) * 12
  # Round-trip x2: two-way (buy + sell) annualized
  to_round_trip <- to_oneway * 2
  to_audit[[lab]] <- list(
    variant = lab,
    incremental_TO_oneway_annual = round(to_oneway, 4),
    incremental_TO_round_trip_x2_annual = round(to_round_trip, 4),
    role_prompt_RFF7_compliance = "round_trip_x2",
    cost_15bps_round_trip_x2_annual = round(to_round_trip * 0.0015, 6)
  )
}
write_json(to_audit, file.path(OUT_DIR, "turnover_audit_round_trip_x2.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  TO round-trip x2 (incremental from R05 overlay):\n")
for (lab in names(to_audit)) {
  cat(sprintf("    %s: oneway=%.4f round_trip_x2=%.4f cost@15bps=%.5f\n",
              lab, to_audit[[lab]]$incremental_TO_oneway_annual,
              to_audit[[lab]]$incremental_TO_round_trip_x2_annual,
              to_audit[[lab]]$cost_15bps_round_trip_x2_annual))
}

# ============================================================
# C9: Covariance condition (out-of-scope but documented)
# ============================================================
cat("\n[C9] Source covariance condition (forge_out_of_scope documentation)\n")

cov_audit <- list(
  parent_admit_lineage_cov = list(
    path = "stage_artifacts/WT_D20260425_010/covariance.parquet",
    condition_number = 24.34,
    PSD = TRUE,
    n_assets = 20,
    in_target_threshold_le_100 = TRUE,
    note = "Used in admit WT-P20260504_001 (precedent)"
  ),
  r05_signal_source_cov = list(
    path = "stage_artifacts/WT_D20260512_003/covariance.parquet",
    condition_number = 153.92,
    PSD = TRUE,
    n_assets = 237,
    in_target_threshold_le_100 = FALSE,
    note = "237-asset cov from WT-D20260512_003 risk-research; condition > 100 because of larger universe. Out-of-scope for forge — would require risk-research re-estimate with shrinkage parameter increase."
  ),
  forge_in_scope = "Forge applies sequential scalar overlay only — does NOT use covariance for portfolio construction. Iter31 weights baked into PR ret_net (production weighting source). Covariance condition is risk-research/optimizer responsibility, not forge.",
  resolution = "Documented; out-of-scope per Pure Function R12 (no risk/optimization package modification)."
)
write_json(cov_audit, file.path(OUT_DIR, "covariance_condition_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Covariance condition audit documented (out-of-forge-scope)\n")

# ============================================================
# Save final hash audit (end-of-run)
# ============================================================
cat("\n[Final] Save hash audit + close\n")

# Re-hash sources at end (Pure Function R12 check)
hash_audit_end <- list()
for (nm in names(sources)) {
  fp <- file.path(BASE_DIR, sources[[nm]])
  if (file.exists(fp)) {
    h <- tryCatch(digest::digest(file = fp, algo = "md5"),
                   error = function(e) "ERROR")
    hash_audit_end[[nm]] <- list(
      md5 = h,
      unchanged = (h == hash_audit[[nm]]$md5)
    )
  }
}
combined_hash <- list(
  start = hash_audit,
  end = hash_audit_end,
  all_unchanged = all(sapply(names(hash_audit_end),
                              function(k) hash_audit_end[[k]]$unchanged))
)
write_json(combined_hash, file.path(OUT_DIR, "pure_function_hash_audit_start_vs_end.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Pure Function R12 hash audit: all_unchanged=%s\n",
            combined_hash$all_unchanged))

cat("\n============================================================\n")
cat("Codex Resolution Script Done\n")
cat("============================================================\n")
cat("C1 hash_audit_sources.json + pure_function_hash_audit_start_vs_end.json\n")
cat("C2 weights.csv\n")
cat("C3 grid_ultrafine_regime.csv\n")
cat("C4 dsr_consistent_penalty_N37.csv\n")
cat("C5 harvey_factor_regression_5spec.json\n")
cat("C6 turnover_audit_round_trip_x2.json\n")
cat("C9 covariance_condition_audit.json (out-of-scope documentation)\n")
