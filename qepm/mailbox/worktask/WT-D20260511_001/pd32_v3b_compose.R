#==============================================================================
# WT-D20260511_001 PD32 v3b — Empirical-Sign Composite Builder
#
# v3 standalone result 기반:
#   AC22 Accrual_Vol         +0.025/+4.85 POSITIVE (자연방향 alpha)
#   CR11 Idio_Return         -0.036/-4.18 NEGATIVE → sign flip
#   INV10 Smart_Money_Flow   -0.029/-5.92 NEGATIVE → sign flip (한국 외인은 short-term contrarian이 알파)
#   INV09 Flow_Persistence   -0.024/-4.99 NEGATIVE → sign flip
#
# Candidate composites (3+) 학술 기반:
#   T_KR_BEHAV  = z(-CR11) + z(-INV10) + z(-INV09)   [KR Behavioral Flow Sentiment]
#   U_AC_HYBRID = z(+AC22) + z(-CR11) + z(-INV10)    [Earnings noise × flow sentiment]
#   V_FLOW_ONLY = z(-INV10) + z(-INV09) + z(-INV05)  [Foreign flow 순수]
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

cat("============================================================\n")
cat("PD32 v3b — Empirical-sign composite builder\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n\n")

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FACTOR_DB_DIR <- file.path(PROJ_ROOT, ".cache/factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")

# Candidate composites — empirical-sign aligned (KR 한국 시장 검증된 방향)
CANDIDATES <- list(
  T = list(
    name = "KR_Behavioral_Flow_Sentiment",
    family = "Investor_Behavior",
    factors_signs = list(
      "CR11_Idiosyncratic_Return" = -1,    # idio mom anti (contrarian)
      "INV10_Smart_Money_Flow"    = -1,    # foreign net buy reversal
      "INV09_Flow_Persistence"    = -1     # flow persistence reversal
    ),
    rationale = "KR retail-heavy + foreign-driven contrarian: idiosyncratic mom + smart-money-flow + flow-persistence 모두 reversal/contrarian (한국 empirical sign). Choe-Kho-Stulz 2005 RFS foreign trading evidence + KR Kim-Lee-Park 2017 PBFJ.",
    references = c(
      "Choe-Kho-Stulz 2005 RFS 18: 795-829 (KR foreign trading)",
      "Daniel-Moskowitz 2016 JFE 122: 221-247 (Momentum Crashes — short-term reversal)",
      "Stambaugh-Yu-Yuan 2015 JF 70: 1903-1948 (arbitrage asymmetry KR retail)"
    )
  ),
  U = list(
    name = "Earnings_Noise_x_Flow_Sentiment",
    family = "Investor_Behavior_Quality",
    factors_signs = list(
      "AC22_Accrual_Volatility" = +1,     # 회계 노이즈 stocks alpha
      "CR11_Idiosyncratic_Return" = -1,
      "INV10_Smart_Money_Flow"    = -1
    ),
    rationale = "Accrual volatility (회계 불확실성) + idiosyncratic contrarian + foreign-flow reversal. KR retail attention bias + earnings uncertainty premium.",
    references = c(
      "Bali-Cakici-Whitelaw 2011 JFE 99: 427-446 (idio vol + lottery preference)",
      "Choe-Kho-Stulz 2005 RFS",
      "Hirshleifer-Hou-Teoh-Zhang 2004 JFE (accrual investor underreaction)"
    )
  ),
  V = list(
    name = "Foreign_Flow_Pure",
    family = "Investor_Flow",
    factors_signs = list(
      "INV10_Smart_Money_Flow" = -1,
      "INV09_Flow_Persistence" = -1,
      "INV05_Foreign_Momentum" = -1
    ),
    rationale = "한국 foreign flow short-term reversal — INV10/INV09/INV05 모두 contrarian. Kim-Lee-Park 2017 PBFJ replication.",
    references = c(
      "Kim-Lee-Park 2017 PBFJ 43: 88-99 (KR foreign reversal)",
      "Bae-Yamada-Ito 2008 JBF 32: 1862-1875"
    )
  )
)

# Load PD27 + sig_dates
pd27 <- as.data.table(read_parquet(PD27_ALPHA))
sig_dates <- sort(unique(pd27$Date))
fwd_ret <- pd27[, .(sig_date = Date, Ticker, Ret_1m)]
setkey(fwd_ret, sig_date, Ticker)
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]
setkey(pd27_key, sig_date, Ticker)
cat("Sig dates:", length(sig_dates), "| tickers:", uniqueN(pd27$Ticker), "\n\n")

# Build composite per candidate
cat("[STEP 1] Build empirical-sign composites (3 candidates)\n")
results <- list()
for(cid in names(CANDIDATES)) {
  cand <- CANDIDATES[[cid]]
  factors <- names(cand$factors_signs)
  signs <- unlist(cand$factors_signs)
  cat(sprintf("  %s = %s: factors=%s signs=%s\n",
              cid, cand$name, paste(factors, collapse=","), paste(sprintf("%+d", signs), collapse=",")))

  rows <- vector("list", length(sig_dates))
  n_ok <- 0L
  for(i in seq_along(sig_dates)) {
    sig_d <- sig_dates[i]
    ym <- format(sig_d, "%Y%m")
    fp <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
    if(!file.exists(fp)) next
    fdt <- as.data.table(read_parquet(fp))
    fsub <- fdt[Factor_Name %in% factors, .(Ticker, Factor_Name, val = Z_Sector)]
    # Fall back to Z_Score if Z_Sector all NA per factor
    z_sec_check <- fsub[, .(allna = all(is.na(val))), by=Factor_Name]
    if(any(z_sec_check$allna)) {
      # Use Z_Score for those with no Z_Sector
      bad_fac <- z_sec_check[allna == TRUE, Factor_Name]
      fsub_bad <- fdt[Factor_Name %in% bad_fac, .(Ticker, Factor_Name, val = Z_Score)]
      fsub <- rbind(fsub[!(Factor_Name %in% bad_fac)], fsub_bad)
    }
    if(nrow(fsub) == 0) next
    fwide <- dcast(fsub, Ticker ~ Factor_Name, value.var = "val")
    # Apply signs + re-zscore
    avail <- intersect(factors, names(fwide))
    for(f in avail) {
      v <- fwide[[f]] * signs[[f]]
      mu <- mean(v, na.rm=TRUE); sg <- sd(v, na.rm=TRUE)
      if(!is.na(sg) && sg > 1e-10) fwide[[f]] <- (v - mu)/sg
      else fwide[[f]] <- NA_real_
    }
    mat <- as.matrix(fwide[, ..avail])
    comp_raw <- rowMeans(mat, na.rm=TRUE)
    comp_raw[is.nan(comp_raw)] <- NA
    mu <- mean(comp_raw, na.rm=TRUE); sg <- sd(comp_raw, na.rm=TRUE)
    comp_z <- if(!is.na(sg) && sg > 1e-10) (comp_raw - mu)/sg else NA_real_
    rows[[i]] <- data.table(sig_date = sig_d, Ticker = fwide$Ticker, composite_z = comp_z,
                            n_factors_used = length(avail))
    n_ok <- n_ok + 1L
  }
  comp <- rbindlist(rows[!sapply(rows, is.null)], fill=TRUE)
  comp <- comp[!is.na(composite_z)]
  cat(sprintf("    -> %d sig_dates ok, %d rows\n", n_ok, nrow(comp)))
  results[[cid]] <- comp
}

# ---- Step 2: Diagnostics ----
cat("\n[STEP 2] Diagnostics per candidate\n")
nw_t <- function(x) {
  n <- length(x); if(n < 12) return(NA_real_)
  mu <- mean(x); e <- x - mu; L <- 6L
  g0 <- sum(e^2)/n; s <- g0
  for(l in seq_len(L)) {
    w <- 1 - l/(L+1)
    gl <- sum(e[(l+1):n] * e[1:(n-l)])/n
    s <- s + 2*w*gl
  }
  if(s <= 0) return(NA_real_)
  mu / sqrt(s/n)
}

# Crisis windows
crisis_windows <- list(c("2008-09-01","2009-03-31"), c("2011-08-01","2011-12-31"),
                       c("2015-06-01","2016-02-29"), c("2020-02-01","2020-04-30"),
                       c("2022-05-01","2022-10-31"))
is_crisis <- function(d) {
  out <- rep(FALSE, length(d))
  for(w in crisis_windows) out <- out | (d >= as.Date(w[1]) & d <= as.Date(w[2]))
  out
}

# Subperiods
windows <- list(P1=c("2001-07-01","2008-08-31"), P2=c("2009-04-01","2017-12-31"),
                P3=c("2018-01-01","2026-04-01"))

summary_list <- list()
for(cid in names(CANDIDATES)) {
  comp <- results[[cid]]
  cand <- CANDIDATES[[cid]]
  if(nrow(comp) == 0) {
    summary_list[[cid]] <- list(error="empty composite")
    next
  }
  setkey(comp, sig_date, Ticker)
  # IC
  m <- merge(comp, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
  ic_per <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
              by=sig_date][!is.na(ic)]
  mean_ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
  icir <- if(sd_ic > 1e-10) mean_ic/sd_ic else NA
  t_nw <- nw_t(ic_per$ic)

  # cor vs PD27
  m_pd <- merge(comp, pd27_key, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(score_pd27)]
  c_per <- m_pd[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method="spearman") else NA_real_),
                by=sig_date][!is.na(c)]
  cor_overall <- cor(m_pd$composite_z, m_pd$score_pd27, method="spearman")
  cor_per_mean <- mean(c_per$c)
  cor_per_sd <- sd(c_per$c)

  # Crisis hedge
  m[, regime := ifelse(is_crisis(sig_date), "crisis", "normal")]
  ic_r <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
            by=.(sig_date, regime)][!is.na(ic)]
  cris_ic <- ic_r[regime=="crisis", mean(ic)]
  norm_ic <- ic_r[regime=="normal", mean(ic)]

  # Subperiod
  sp_ic <- sapply(windows, function(w) {
    sub <- m[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
    if(nrow(sub) < 200) return(NA)
    sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
        by=sig_date][!is.na(ic), mean(ic)]
  })
  mmr <- if(all(!is.na(sp_ic)) && max(abs(sp_ic)) > 1e-6) min(sp_ic)/max(sp_ic) else NA

  summary_list[[cid]] <- list(
    name = cand$name, family = cand$family,
    factors_signs = cand$factors_signs,
    rationale = cand$rationale,
    references = cand$references,
    diagnostics = list(
      mean_IC = mean_ic, sd_IC = sd_ic, ICIR = icir, t_NW_lag6 = t_nw,
      n_months = nrow(ic_per), pos_share = mean(ic_per$ic > 0)
    ),
    cor_vs_pd27 = list(
      cor_overall = cor_overall, cor_per_date_mean = cor_per_mean,
      cor_per_date_sd = cor_per_sd, n_dates = nrow(c_per),
      pass_lt_0_30 = !is.na(cor_per_mean) && abs(cor_per_mean) < 0.30
    ),
    crisis_hedge = list(
      crisis_IC = cris_ic, normal_IC = norm_ic,
      ratio_c_over_n = if(!is.na(norm_ic) && abs(norm_ic) > 1e-10) cris_ic/norm_ic else NA,
      n_crisis_months = nrow(ic_r[regime=="crisis"]),
      n_normal_months = nrow(ic_r[regime=="normal"]),
      ax001_v2_pass = !is.na(cris_ic) && cris_ic > 0
    ),
    subperiod = list(
      P1_2001_2008 = list(rank_ic=sp_ic[1]),
      P2_2009_2017 = list(rank_ic=sp_ic[2]),
      P3_2018_2026 = list(rank_ic=sp_ic[3]),
      min_max_ratio = mmr,
      pass = !is.na(mmr) && mmr >= 0.50
    )
  )
  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f | cor=%.3f | crisis=%.4f normal=%.4f AX=%s | sp_mmr=%.2f\n",
              cid, mean_ic, icir, t_nw, cor_per_mean, cris_ic, norm_ic,
              !is.na(cris_ic) && cris_ic > 0, mmr))
}

# ---- Step 3: Selection ----
cat("\n[STEP 3] Selection scoring\n")
score_v3b <- list()
for(cid in names(CANDIDATES)) {
  s <- summary_list[[cid]]
  if(is.null(s$diagnostics)) { score_v3b[[cid]] <- list(score=-1, reasons="empty"); next }
  sc <- 0; r <- character()
  d <- s$diagnostics; co <- s$cor_vs_pd27; ch <- s$crisis_hedge; sp <- s$subperiod
  if(!is.na(d$mean_IC) && d$mean_IC > 0.02)   { sc <- sc + 30; r <- c(r, sprintf("IC=%.4f>0.02", d$mean_IC)) }
  if(!is.na(d$ICIR)    && d$ICIR    > 0.20)   { sc <- sc + 25; r <- c(r, sprintf("ICIR=%.3f>0.20", d$ICIR)) }
  if(!is.na(d$t_NW_lag6) && d$t_NW_lag6 > 3.0){ sc <- sc + 20; r <- c(r, sprintf("t_NW=%.2f>3", d$t_NW_lag6)) }
  if(isTRUE(co$pass_lt_0_30))                 { sc <- sc + 15; r <- c(r, sprintf("cor=%.3f<0.30", co$cor_per_date_mean)) }
  if(isTRUE(ch$ax001_v2_pass))                { sc <- sc + 5;  r <- c(r, "AX-001 v2 PASS") }
  if(isTRUE(sp$pass))                         { sc <- sc + 5;  r <- c(r, "subperiod PASS") }
  score_v3b[[cid]] <- list(score=sc, reasons=r)
  cat(sprintf("  %s (%s): score=%d | %s\n", cid, s$name, sc, paste(r, collapse="; ")))
}

best <- names(which.max(sapply(score_v3b, function(x) x$score)))
cat(sprintf("\n=> BEST = %s (%s, score=%d)\n", best, CANDIDATES[[best]]$name, score_v3b[[best]]$score))

# Save best composite parquet
best_comp <- results[[best]]
best_comp[, sleeve_label := CANDIDATES[[best]]$name]
write_parquet(best_comp, file.path(STAGE_DIR, "alpha_scores_pd32_v3b_best.parquet"))
cat("Best parquet:", file.path(STAGE_DIR, "alpha_scores_pd32_v3b_best.parquet"), "\n")

# Save all 3 candidate composites + diagnostics
for(cid in names(results)) {
  if(nrow(results[[cid]]) > 0) {
    results[[cid]][, candidate := cid]
    results[[cid]][, sleeve_label := CANDIDATES[[cid]]$name]
  }
}
all_comp <- rbindlist(results[!sapply(results, function(x) nrow(x) == 0)], fill=TRUE)
write_parquet(all_comp, file.path(STAGE_DIR, "alpha_scores_pd32_v3b_all_candidates.parquet"))

write_json(list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_v3b_empirical_sign_composite",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  candidates = lapply(names(CANDIDATES), function(cid) {
    c(list(id=cid), summary_list[[cid]],
      list(selection_score = score_v3b[[cid]]$score,
           selection_reasons = score_v3b[[cid]]$reasons))
  }),
  selected = best,
  best_parquet = file.path(STAGE_DIR, "alpha_scores_pd32_v3b_best.parquet")
), file.path(WT_DIR, "pd32_v3b_log.json"), pretty=TRUE, auto_unbox=TRUE)

cat("\nLog:", file.path(WT_DIR, "pd32_v3b_log.json"), "\n")
cat("\n============================================================\n")
cat("PD32 v3b complete.\n")
cat("End:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n")
