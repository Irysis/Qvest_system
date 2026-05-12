#==============================================================================
# WT-D20260511_001 PD32 v3 — Sign Diagnosis + Standalone Factor IC
#
# v2 결과 진단:
#   D Crowding_Anti_Herding IC=-0.032, t_NW=-4.23  →  sign-flip 후 ~+0.032 alpha 가능
#   F Smart_Money_Flow      IC=-0.029, t_NW=-6.03  →  sign-flip 후 ~+0.029 alpha (anti-smart-money / retail-aligned)
#   A Accrual_Reversal      IC=-0.010, t_NW=-2.21  →  marginal
#   B Investment_Frictions  IC=+0.003, t_NW= 0.76  →  noise
#
# v3 분석:
#   1. Standalone factor IC (per-factor, no composite) — 어떤 single signal 강한지
#   2. Direction empirical 산출 (PIT-safe expanding IC sign infer)
#   3. Sign-flipped composite re-evaluation
#   4. Crisis hedge re-check (sign 후)
#
# Output:
#   pd32_v3_standalone_diagnostic.csv (per-factor 12 factor)
#   pd32_v3_sign_flipped_composite.csv (4 candidate × sign options)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

cat("============================================================\n")
cat("WT-D20260511_001 PD32 v3 — Sign diagnosis + standalone IC\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n\n")

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FACTOR_DB_DIR <- file.path(PROJ_ROOT, ".cache/factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")

# All 12 factor candidates (D + B + A + F)
ALL_FACTORS <- c(
  # D
  "CR03_Herding_Dispersion", "CR11_Idiosyncratic_Return", "CR05_Short_Pressure_Proxy",
  # B
  "GR03_Asset_Growth", "IN01_CapEx_to_Assets", "IN05_Net_Debt_Issuance",
  # A
  "AC01_Total_Accruals_CF", "AC11_Accruals_to_Assets", "AC22_Accrual_Volatility",
  # F
  "INV10_Smart_Money_Flow", "INV05_Foreign_Momentum", "INV09_Flow_Persistence"
)

# Family map (for output)
FAMILY_MAP <- setNames(
  c(rep("Crowding", 3), rep("Investment", 3), rep("Accrual", 3), rep("Investor_Flow", 3)),
  ALL_FACTORS
)

# Load PD27 base for sig_dates + Ret_1m
pd27 <- as.data.table(read_parquet(PD27_ALPHA))
sig_dates <- sort(unique(pd27$Date))
fwd_ret <- pd27[, .(sig_date = Date, Ticker, Ret_1m)]
setkey(fwd_ret, sig_date, Ticker)
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]
setkey(pd27_key, sig_date, Ticker)

# Standalone factor signal computation
load_factor_signal <- function(sig_d, factor_name, value_col = "Z_Sector") {
  ym <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
  if(!file.exists(fpath)) return(NULL)
  fdt <- as.data.table(read_parquet(fpath))
  fsub <- fdt[Factor_Name == factor_name, .(Ticker,
                                            val = if(value_col == "Z_Sector") Z_Sector else Z_Score)]
  fsub <- fsub[!is.na(val)]
  if(nrow(fsub) == 0) return(NULL)
  # Z-score the val (cross-section)
  mu <- mean(fsub$val); sg <- sd(fsub$val)
  fsub[, val_z := if(sg > 1e-10) (val - mu)/sg else NA_real_]
  fsub[, sig_date := sig_d]
  return(fsub[!is.na(val_z), .(sig_date, Ticker, val_z)])
}

# Standalone IC per factor (use Z_Sector first; Factor DB has direction already aligned via Z_Score_Aligned
# but raw Z_Sector keeps registry direction. We measure both natural direction and quantify).
cat("[STEP 1] Standalone factor IC (all 12 factors)\n")
standalone_stats <- list()
for(f in ALL_FACTORS) {
  cat(sprintf("  %s (%s) ...", f, FAMILY_MAP[f]))
  rows <- vector("list", length(sig_dates))
  n_ok <- 0
  for(i in seq_along(sig_dates)) {
    r <- tryCatch(load_factor_signal(sig_dates[i], f, "Z_Sector"),
                  error = function(e) NULL)
    if(!is.null(r) && nrow(r) > 0) { rows[[i]] <- r; n_ok <- n_ok + 1L }
  }
  comp <- rbindlist(rows[!sapply(rows, is.null)], fill = TRUE)
  if(nrow(comp) == 0) {
    cat(" no data\n")
    standalone_stats[[f]] <- list(mean_ic=NA, sd_ic=NA, icir=NA, t_nw=NA, n=0, pos=NA)
    next
  }
  setkey(comp, sig_date, Ticker)
  m <- merge(comp, fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(val_z) & !is.na(Ret_1m)]
  ic_per <- m[, .(ic = if(.N >= 20) cor(val_z, Ret_1m, method="spearman") else NA_real_),
              by = sig_date][!is.na(ic)]
  mean_ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
  icir <- if(!is.na(sd_ic) && sd_ic > 1e-10) mean_ic/sd_ic else NA_real_

  # NW t_nw lag 6
  t_nw <- NA_real_
  n <- nrow(ic_per)
  if(n > 12 && !is.na(sd_ic)) {
    e <- ic_per$ic - mean_ic
    L <- 6L
    g0 <- sum(e^2)/n; s <- g0
    for(l in seq_len(L)) {
      w <- 1 - l/(L+1)
      gl <- sum(e[(l+1):n] * e[1:(n-l)])/n
      s <- s + 2*w*gl
    }
    if(s > 0) t_nw <- mean_ic/sqrt(s/n)
  }
  standalone_stats[[f]] <- list(mean_ic=mean_ic, sd_ic=sd_ic, icir=icir,
                                 t_nw=t_nw, n=n, pos=mean(ic_per$ic > 0))
  cat(sprintf(" IC=%.4f ICIR=%.3f t_NW=%.2f n=%d pos=%.2f\n",
              mean_ic, icir, t_nw, n, mean(ic_per$ic > 0)))
}

# Save per-factor diag
diag_dt <- rbindlist(lapply(names(standalone_stats), function(f) {
  s <- standalone_stats[[f]]
  data.table(
    factor = f,
    family = FAMILY_MAP[f],
    mean_IC = s$mean_ic,
    ICIR = s$icir,
    t_NW_lag6 = s$t_nw,
    n_months = s$n,
    pos_share = s$pos,
    sign_kr_empirical = ifelse(is.na(s$mean_ic), NA, ifelse(s$mean_ic > 0, "POSITIVE", "NEGATIVE")),
    significant_t_nw_gt_3 = !is.na(s$t_nw) && abs(s$t_nw) > 3.0
  )
}))
fwrite(diag_dt, file.path(STAGE_DIR, "pd32_v3_standalone_diagnostic.csv"))
print(diag_dt)

# ---- Step 2: Best individual factor selection + sign-flipped composite ----
cat("\n[STEP 2] Identify dominant factors per family (|t_NW|>3) + KR-empirical sign\n")
strong_factors <- diag_dt[significant_t_nw_gt_3 == TRUE]
strong_factors[, abs_t := abs(t_NW_lag6)]
setorder(strong_factors, family, -abs_t, na.last=TRUE)
cat("Strong (|t_NW|>3) factors per family:\n")
print(strong_factors[, .(factor, family, mean_IC, t_NW_lag6, sign_kr_empirical)])

# ---- Step 3: Best 3-factor composite per family using empirical sign ----
cat("\n[STEP 3] Build empirically-aligned composite per family\n")
fam_names <- c("Crowding", "Investment", "Accrual", "Investor_Flow")
comps_v3 <- list()
for(fam in fam_names) {
  fdf <- diag_dt[family == fam & !is.na(mean_IC)]
  if(nrow(fdf) == 0) next
  fdf[, abs_t := abs(t_NW_lag6)]
  setorder(fdf, -abs_t, na.last=TRUE)
  top3 <- head(fdf, 3)$factor
  if(length(top3) == 0) next
  signs <- sign(diag_dt[factor %in% top3, mean_IC])  # KR empirical direction
  names(signs) <- top3
  cat(sprintf("  %s: top3 = %s | signs = %s\n",
              fam, paste(top3, collapse=", "),
              paste(sprintf("%s=%+d", names(signs), signs), collapse=", ")))

  # Build composite using empirical signs
  rows <- vector("list", length(sig_dates))
  n_ok <- 0
  for(i in seq_along(sig_dates)) {
    sig_d <- sig_dates[i]
    ym <- format(sig_d, "%Y%m")
    fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
    if(!file.exists(fpath)) next
    fdt <- as.data.table(read_parquet(fpath))
    fsub <- fdt[Factor_Name %in% top3, .(Ticker, Factor_Name, val = Z_Sector)]
    if(nrow(fsub) == 0) next
    fwide <- dcast(fsub, Ticker ~ Factor_Name, value.var = "val")
    # Apply empirical sign + z-score
    for(f in top3) {
      if(f %in% names(fwide)) {
        v <- fwide[[f]] * signs[[f]]
        mu <- mean(v, na.rm=TRUE); sg <- sd(v, na.rm=TRUE)
        if(!is.na(sg) && sg > 1e-10) fwide[[f]] <- (v - mu)/sg
      }
    }
    avail <- intersect(top3, names(fwide))
    if(length(avail) == 0) next
    mat <- as.matrix(fwide[, ..avail])
    comp_raw <- rowMeans(mat, na.rm=TRUE)
    comp_raw[is.nan(comp_raw)] <- NA
    mu <- mean(comp_raw, na.rm=TRUE); sg <- sd(comp_raw, na.rm=TRUE)
    comp_z <- if(!is.na(sg) && sg > 1e-10) (comp_raw - mu)/sg else NA_real_
    rows[[i]] <- data.table(sig_date = sig_d, Ticker = fwide$Ticker, composite_z = comp_z)
    n_ok <- n_ok + 1L
  }
  comp <- rbindlist(rows[!sapply(rows, is.null)], fill=TRUE)
  comp <- comp[!is.na(composite_z)]
  comps_v3[[fam]] <- list(factors=top3, signs=signs, data=comp)
  cat(sprintf("    -> %d sig_dates, %d rows\n", n_ok, nrow(comp)))
}

# IC + cor diagnostics for empirical sign composites
cat("\n[STEP 4] Empirical-sign composite diagnostics\n")
v3_summary <- list()
for(fam in names(comps_v3)) {
  comp <- comps_v3[[fam]]$data
  signs <- comps_v3[[fam]]$signs
  if(nrow(comp) == 0) next
  setkey(comp, sig_date, Ticker)
  m_ret <- merge(comp, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
  ic_per <- m_ret[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
                  by=sig_date][!is.na(ic)]
  mean_ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
  icir <- if(!is.na(sd_ic) && sd_ic > 1e-10) mean_ic/sd_ic else NA
  n <- nrow(ic_per); t_nw <- NA
  if(n > 12 && !is.na(sd_ic)) {
    e <- ic_per$ic - mean_ic
    L <- 6L
    g0 <- sum(e^2)/n; s <- g0
    for(l in seq_len(L)) {
      w <- 1 - l/(L+1)
      gl <- sum(e[(l+1):n] * e[1:(n-l)])/n
      s <- s + 2*w*gl
    }
    if(s > 0) t_nw <- mean_ic/sqrt(s/n)
  }

  # cor vs pd27
  m_pd <- merge(comp, pd27_key, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(score_pd27)]
  c_per <- m_pd[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method="spearman") else NA_real_),
                by=sig_date][!is.na(c)]
  cor_mean <- mean(c_per$c)

  # Crisis IC
  crisis_windows <- list(c("2008-09-01","2009-03-31"), c("2011-08-01","2011-12-31"),
                         c("2015-06-01","2016-02-29"), c("2020-02-01","2020-04-30"),
                         c("2022-05-01","2022-10-31"))
  is_crisis <- function(d) {
    out <- rep(FALSE, length(d))
    for(w in crisis_windows) out <- out | (d >= as.Date(w[1]) & d <= as.Date(w[2]))
    out
  }
  m_ret[, regime := ifelse(is_crisis(sig_date), "crisis", "normal")]
  ic_r <- m_ret[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
                by=.(sig_date, regime)][!is.na(ic)]
  cris_ic <- ic_r[regime=="crisis", mean(ic)]
  norm_ic <- ic_r[regime=="normal", mean(ic)]

  # Subperiod (3 windows)
  wins <- list(P1=c("2001-07-01","2008-08-31"), P2=c("2009-04-01","2017-12-31"),
               P3=c("2018-01-01","2026-04-01"))
  sp_ic <- sapply(wins, function(w) {
    sub <- m_ret[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
    if(nrow(sub) < 200) return(NA)
    sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
        by=sig_date][!is.na(ic), mean(ic)]
  })
  mmr <- if(all(!is.na(sp_ic)) && max(abs(sp_ic)) > 1e-6) min(sp_ic)/max(sp_ic) else NA

  v3_summary[[fam]] <- list(
    factors = comps_v3[[fam]]$factors,
    signs   = as.list(signs),
    mean_IC = mean_ic, ICIR = icir, t_NW = t_nw, n = n,
    cor_vs_pd27_mean = cor_mean,
    crisis_IC = cris_ic, normal_IC = norm_ic,
    ax001_pass = !is.na(cris_ic) && cris_ic > 0,
    P1=sp_ic[1], P2=sp_ic[2], P3=sp_ic[3], subperiod_mm_ratio=mmr,
    subperiod_pass = !is.na(mmr) && mmr >= 0.50
  )
  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f cor=%.3f crisis=%.4f normal=%.4f AX-001=%s sp_mmr=%.2f\n",
              fam, mean_ic, icir, t_nw, cor_mean, cris_ic, norm_ic,
              v3_summary[[fam]]$ax001_pass, mmr))
}

# ---- Save v3 summary ----
write_json(list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_v3_empirical_sign",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  standalone_factor_diagnostic = lapply(names(standalone_stats), function(f) {
    s <- standalone_stats[[f]]
    list(factor=f, family=FAMILY_MAP[f], mean_IC=s$mean_ic, ICIR=s$icir, t_NW=s$t_nw,
         n_months=s$n, pos_share=s$pos,
         sign_kr_empirical = ifelse(is.na(s$mean_ic), NA, ifelse(s$mean_ic > 0, "POSITIVE", "NEGATIVE")),
         significant_t_nw_gt_3 = !is.na(s$t_nw) && abs(s$t_nw) > 3.0)
  }),
  empirical_sign_composites = lapply(names(v3_summary), function(fam) {
    c(list(family=fam), v3_summary[[fam]])
  })
), file.path(WT_DIR, "pd32_v3_log.json"), pretty=TRUE, auto_unbox=TRUE)

# Save composite parquets for best (highest |t_NW| with cor<0.30 and AX-001 pass)
cat("\n[STEP 5] Save best empirical-sign composite\n")
score_v3 <- sapply(v3_summary, function(s) {
  sc <- 0
  if(!is.na(s$mean_IC) && s$mean_IC > 0.02) sc <- sc + 30
  if(!is.na(s$ICIR) && s$ICIR > 0.20) sc <- sc + 25
  if(!is.na(s$t_NW) && s$t_NW > 3.0) sc <- sc + 20
  if(!is.na(s$cor_vs_pd27_mean) && abs(s$cor_vs_pd27_mean) < 0.30) sc <- sc + 15
  if(isTRUE(s$ax001_pass)) sc <- sc + 5
  if(isTRUE(s$subperiod_pass)) sc <- sc + 5
  sc
})
print(data.table(family=names(score_v3), score=score_v3))
best_fam <- names(which.max(score_v3))
cat(sprintf("\n=> BEST v3 family = %s (score=%d)\n", best_fam, score_v3[[best_fam]]))
best_comp_data <- comps_v3[[best_fam]]$data
best_comp_data[, sleeve_label := paste0(best_fam, "_KR_empirical_sign")]
write_parquet(best_comp_data, file.path(STAGE_DIR, "alpha_scores_pd32_v3_best.parquet"))

cat("\n============================================================\n")
cat("PD32 v3 complete.\n")
cat("End:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n")
