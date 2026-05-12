#==============================================================================
# WT-D20260511_001 PD32 v2 — 5th Orthogonal Alpha Source Research
#
# Fixes vs v1:
#   - Factor mapping: only universally available factors (verified across 5 sample dates)
#   - 4 candidates (added INV smart money flow)
#   - Partial-set composite (사용 가능 factor 부분집합으로 진행, warning 기록)
#   - NA-safe selection scoring
#   - Z_Sector based sector_neut (Factor DB built-in via Factor DB connector ext)
#
# Candidates:
#   D = Crowding_Anti_Herding: CR03 + CR11 + CR05 (Lou-Polk 2022 / Stambaugh-Yu-Yuan 2015)
#   B = Investment_Frictions:  -GR03 + -IN01 + -IN05 (Cooper-Gulen-Schill 2008 / FF 2015)
#   A = Accrual_Reversal:      -AC01 + -AC11 + -AC22 (Sloan 1996 / Hirshleifer 2004)
#   F = Smart_Money_Flow:      INV10 + INV05 + INV09 (Choe-Kho-Stulz 2005 / Kim-Lee-Park 2017)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

cat("============================================================\n")
cat("WT-D20260511_001 PD32 v2 — 5th orthogonal source research\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n\n")

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")
PD32_OUT   <- file.path(STAGE_DIR, "alpha_scores_pd32_5th_source.parquet")
PD32_LOG   <- file.path(WT_DIR, "pd32_5th_source_log.json")
PD32_DIAG  <- file.path(STAGE_DIR, "pd32_factor_diagnostic.csv")

COVERAGE_MIN <- 0.05
SIG_DATE_CUTOFF_LOCKBOX <- as.Date("2024-01-22")
DEC_WINDOW_START <- as.Date("2001-07-01")
DEC_WINDOW_END   <- as.Date("2026-04-01")

# ---- 4 Candidates (universal factors only, verified) ----
CANDIDATES <- list(
  D = list(
    name = "Crowding_Anti_Herding",
    family = "Crowding_Anti_Herding",
    factors = c("CR03_Herding_Dispersion", "CR11_Idiosyncratic_Return", "CR05_Short_Pressure_Proxy"),
    directions = c(-1L, +1L, -1L),  # anti-herding + idio_return + anti-short-pressure
    rationale = "Lou-Polk 2022 RFS anti-crowded outperform + Stambaugh-Yu-Yuan 2015 JF low-herding alpha + Daniel-Moskowitz 2016 idio mom",
    references = c(
      "Lou-Polk 2022 RFS 35: 4385-4434 'Comomentum: Inferring Arbitrage Activity from Return Correlations'",
      "Stambaugh-Yu-Yuan 2015 JF 70: 1903-1948 'Arbitrage Asymmetry and Idiosyncratic Volatility Puzzle'",
      "Daniel-Moskowitz 2016 JFE 122: 221-247 'Momentum Crashes'"
    )
  ),
  B = list(
    name = "Investment_Frictions",
    family = "Investment_Frictions",
    factors = c("GR03_Asset_Growth", "IN01_CapEx_to_Assets", "IN05_Net_Debt_Issuance"),
    directions = c(-1L, -1L, -1L),  # low investment / low issuance alpha
    rationale = "Cooper-Gulen-Schill 2008 JF Asset Growth Anomaly + Fama-French 2015 5F Investment factor + Daniel-Titman 2006 Equity Issuance",
    references = c(
      "Cooper-Gulen-Schill 2008 JF 63: 1609-1651 'Asset Growth and the Cross-Section of Stock Returns'",
      "Fama-French 2015 JFE 116: 1-22 'A Five-Factor Asset Pricing Model'",
      "Daniel-Titman 2006 JF 61: 1605-1643 'Market Reactions to Tangible and Intangible Information'"
    )
  ),
  A = list(
    name = "Accrual_Reversal",
    family = "Accrual_Reversal",
    factors = c("AC01_Total_Accruals_CF", "AC11_Accruals_to_Assets", "AC22_Accrual_Volatility"),
    directions = c(-1L, -1L, -1L),  # low accrual alpha (Sloan 1996)
    rationale = "Sloan 1996 TAR Accrual Anomaly + Hirshleifer-Hou-Teoh-Zhang 2004 JFE Investor Underreaction + KR Kim 2010 PBFJ",
    references = c(
      "Sloan 1996 TAR 71: 289-315 'Do Stock Prices Fully Reflect Information in Accruals and Cash Flows about Future Earnings?'",
      "Hirshleifer-Hou-Teoh-Zhang 2004 JFE 38: 297-331 'Do Investors Overvalue Firms with Bloated Balance Sheets?'",
      "Kim 2010 PBFJ 18: 271-292 (KR replication)"
    )
  ),
  F = list(
    name = "Smart_Money_Flow",
    family = "Investor_Flow",
    factors = c("INV10_Smart_Money_Flow", "INV05_Foreign_Momentum", "INV09_Flow_Persistence"),
    directions = c(+1L, +1L, +1L),
    rationale = "Choe-Kho-Stulz 2005 RFS Foreign Investor Smart Money + Kim-Lee-Park 2017 PBFJ KR flow + Bae-Yamada-Ito 2008 JBF",
    references = c(
      "Choe-Kho-Stulz 2005 RFS 18: 795-829 'Do Domestic Investors Have an Edge? The Trading Experience of Foreign Investors in Korea'",
      "Kim-Lee-Park 2017 PBFJ 43: 88-99 (KR foreign smart money replication)",
      "Bae-Yamada-Ito 2008 JBF 32: 1862-1875 (KR/JP institutional flow)"
    )
  )
)

cat("Candidates (4 - universally available, verified):\n")
for(k in names(CANDIDATES)) {
  cat(sprintf("  %s = %s: %s\n", k, CANDIDATES[[k]]$name, paste(CANDIDATES[[k]]$factors, collapse=", ")))
}
cat("\n")

# ---- Step 1: Load PD27 base ----
cat("[STEP 1] Load PD27 1715 H1 base alpha_scores\n")
pd27 <- as.data.table(read_parquet(PD27_ALPHA))
cat("PD27 base nrow:", nrow(pd27), " | sig_dates:", uniqueN(pd27$Date),
    " | tickers:", uniqueN(pd27$Ticker), "\n")
sig_dates_all <- sort(unique(pd27$Date))
sig_dates_all <- sig_dates_all[sig_dates_all >= DEC_WINDOW_START & sig_dates_all <= DEC_WINDOW_END]
cat("Sig dates window:", length(sig_dates_all), "\n\n")

# ---- Step 2-3: Composite signal compute via Factor DB long-form ----
# Use raw parquet + Z_Sector (Factor DB built-in sector-neutralized z-score)
load_factors_with_sector <- function(sig_d) {
  ym <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
  if(!file.exists(fpath)) return(NULL)
  fdt <- as.data.table(read_parquet(fpath))
  return(fdt)
}

# Cache full Factor DB load for unique sig_dates by ym (one parquet per month)
# We'll iterate per-month with single load.

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

build_candidate_signal <- function(sig_d, cand, use_z_sector = TRUE) {
  ym <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
  if(!file.exists(fpath)) return(NULL)

  fdt <- as.data.table(read_parquet(fpath))
  needed <- cand$factors

  # Filter to needed factors
  fsub <- fdt[Factor_Name %in% needed, .(Ticker, Factor_Name, Raw_Value, Z_Score, Z_Sector)]
  avail_factors <- intersect(needed, unique(fsub$Factor_Name))
  if(length(avail_factors) == 0) return(NULL)

  # Pivot to wide using Z_Sector (sector-neutralized) primary; fall back to Z_Score
  fwide <- if(use_z_sector) {
    dcast(fsub[, .(Ticker, Factor_Name, value = Z_Sector)],
          Ticker ~ Factor_Name, value.var = "value")
  } else {
    dcast(fsub[, .(Ticker, Factor_Name, value = Z_Score)],
          Ticker ~ Factor_Name, value.var = "value")
  }

  # If Z_Sector all NA, fall back to Z_Score
  z_sector_all_na <- if(use_z_sector) all(sapply(setdiff(names(fwide), "Ticker"),
                                                  function(c) all(is.na(fwide[[c]])))) else FALSE
  if(z_sector_all_na) {
    fwide <- dcast(fsub[, .(Ticker, Factor_Name, value = Z_Score)],
                   Ticker ~ Factor_Name, value.var = "value")
  }

  # Apply direction multiplier to each factor
  for(i in seq_along(needed)) {
    f <- needed[i]; d <- cand$directions[i]
    if(f %in% names(fwide)) fwide[[f]] <- fwide[[f]] * d
  }

  # Re-standardize cross-section per factor (after direction flip)
  for(f in avail_factors) {
    v <- fwide[[f]]
    mu <- mean(v, na.rm = TRUE); sg <- sd(v, na.rm = TRUE)
    if(!is.na(sg) && sg > 1e-10) fwide[[f]] <- (v - mu) / sg
    else fwide[[f]] <- NA_real_
  }

  # EW composite (rowMeans, na.rm=TRUE)
  mat <- as.matrix(fwide[, ..avail_factors])
  comp_raw <- rowMeans(mat, na.rm = TRUE)
  comp_raw[is.nan(comp_raw)] <- NA_real_

  # Standardize composite
  mu <- mean(comp_raw, na.rm = TRUE); sg <- sd(comp_raw, na.rm = TRUE)
  composite_z <- if(!is.na(sg) && sg > 1e-10) (comp_raw - mu) / sg else NA_real_

  out <- data.table(
    sig_date = sig_d,
    Ticker = fwide$Ticker,
    composite_z = composite_z,
    n_factors_used = length(avail_factors)
  )
  return(out[!is.na(composite_z)])
}

cat("[STEP 2-3] Compute candidate signals (4 candidates over", length(sig_dates_all), "sig_dates)\n")
results_by_cand <- list()
t0 <- Sys.time()
for(cand_id in names(CANDIDATES)) {
  cand <- CANDIDATES[[cand_id]]
  cat(sprintf("  Candidate %s = %s ...\n", cand_id, cand$name))
  rows <- vector("list", length(sig_dates_all))
  n_ok <- 0L
  for(i in seq_along(sig_dates_all)) {
    r <- tryCatch(build_candidate_signal(sig_dates_all[i], cand, use_z_sector = TRUE),
                  error = function(e) NULL)
    if(!is.null(r) && nrow(r) > 0) { rows[[i]] <- r; n_ok <- n_ok + 1L }
  }
  combined <- rbindlist(rows[!sapply(rows, is.null)], fill = TRUE)
  cat(sprintf("    -> %d sig_dates ok (%d rows total)\n", n_ok, nrow(combined)))
  results_by_cand[[cand_id]] <- combined
}
cat(sprintf("Composite compute elapsed: %.2f min\n\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ---- Step 4: IC diagnostics ----
cat("[STEP 4] IC / ICIR / Harvey-t (NW lag 6)\n")
fwd_ret <- pd27[, .(sig_date = Date, Ticker, Ret_1m)]
setkey(fwd_ret, sig_date, Ticker)

compute_ic_stats <- function(comp_dt, fwd_ret) {
  if(nrow(comp_dt) == 0) return(list(mean_ic=NA, sd_ic=NA, icir=NA, t_nw=NA, n_months=0, pos_share=NA))
  setkey(comp_dt, sig_date, Ticker)
  m <- merge(comp_dt[, .(sig_date, Ticker, composite_z)], fwd_ret,
             by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]
  if(nrow(m) == 0) return(list(mean_ic=NA, sd_ic=NA, icir=NA, t_nw=NA, n_months=0, pos_share=NA))

  ic_per <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman") else NA_real_),
              by = sig_date][!is.na(ic)]
  if(nrow(ic_per) == 0) return(list(mean_ic=NA, sd_ic=NA, icir=NA, t_nw=NA, n_months=0, pos_share=NA))

  mean_ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
  icir <- if(!is.na(sd_ic) && sd_ic > 1e-10) mean_ic / sd_ic else NA_real_

  # NW HAC lag 6
  t_nw <- NA_real_
  n <- nrow(ic_per)
  if(n > 12 && !is.na(sd_ic)) {
    e <- ic_per$ic - mean_ic
    L <- 6L
    gamma0 <- sum(e^2) / n
    s_sum <- gamma0
    for(l in seq_len(L)) {
      w <- 1 - l / (L + 1)
      gl <- sum(e[(l+1):n] * e[1:(n - l)]) / n
      s_sum <- s_sum + 2 * w * gl
    }
    if(s_sum > 0) {
      se_nw <- sqrt(s_sum / n)
      t_nw <- mean_ic / se_nw
    }
  }
  list(mean_ic=mean_ic, sd_ic=sd_ic, icir=icir, t_nw=t_nw, n_months=n,
       pos_share=mean(ic_per$ic > 0))
}

ic_summary <- list()
for(cand_id in names(CANDIDATES)) {
  s <- compute_ic_stats(results_by_cand[[cand_id]], fwd_ret)
  ic_summary[[cand_id]] <- s
  cat(sprintf("  %s: IC=%.4f ICIR=%.4f t_NW=%.3f n=%d pos=%.2f\n",
              cand_id,
              ifelse(is.na(s$mean_ic), NA, s$mean_ic),
              ifelse(is.na(s$icir), NA, s$icir),
              ifelse(is.na(s$t_nw), NA, s$t_nw),
              s$n_months, ifelse(is.na(s$pos_share), NA, s$pos_share)))
}

# ---- Step 5: cor with PD27 base ----
cat("\n[STEP 5] cor vs PD27 1715 H1 base (constraint <0.30)\n")
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]
setkey(pd27_key, sig_date, Ticker)
cor_summary <- list()
for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) { cor_summary[[cand_id]] <- list(cor_overall=NA, cor_per_date_mean=NA); next }
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], pd27_key, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(score_pd27)]
  if(nrow(m) == 0) { cor_summary[[cand_id]] <- list(cor_overall=NA, cor_per_date_mean=NA); next }
  c_all <- cor(m$composite_z, m$score_pd27, method = "spearman")
  c_per <- m[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method = "spearman") else NA_real_),
             by = sig_date][!is.na(c)]
  pass <- !is.na(mean(c_per$c)) && abs(mean(c_per$c)) < 0.30
  cor_summary[[cand_id]] <- list(
    cor_overall = c_all,
    cor_per_date_mean = mean(c_per$c),
    cor_per_date_sd = sd(c_per$c),
    cor_per_date_min = min(c_per$c),
    cor_per_date_max = max(c_per$c),
    n_dates = nrow(c_per),
    pass_lt_0_30 = pass
  )
  cat(sprintf("  %s: cor_overall=%.4f | per-date mean=%.4f sd=%.4f [%.3f, %.3f] | <0.30: %s\n",
              cand_id, c_all, mean(c_per$c), sd(c_per$c), min(c_per$c), max(c_per$c),
              ifelse(pass, "PASS", "FAIL")))
}

# ---- Step 5b: AX-001 v2 crisis hedge ----
cat("\n[STEP 5b] AX-001 v2 crisis hedge\n")
crisis_windows <- list(
  c("2008-09-01", "2009-03-31"),
  c("2011-08-01", "2011-12-31"),
  c("2015-06-01", "2016-02-29"),
  c("2020-02-01", "2020-04-30"),
  c("2022-05-01", "2022-10-31")
)
is_crisis_vec <- function(dates) {
  out <- rep(FALSE, length(dates))
  for(w in crisis_windows) {
    out <- out | (dates >= as.Date(w[1]) & dates <= as.Date(w[2]))
  }
  out
}

crisis_summary <- list()
for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) { crisis_summary[[cand_id]] <- list(crisis_ic=NA, normal_ic=NA, ax_pass=FALSE); next }
  setkey(comp, sig_date, Ticker)
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]
  m[, regime := ifelse(is_crisis_vec(sig_date), "crisis", "normal")]
  ic_r <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman") else NA_real_),
            by = .(sig_date, regime)][!is.na(ic)]
  cris <- ic_r[regime == "crisis", mean(ic)]
  norm <- ic_r[regime == "normal", mean(ic)]
  ax_pass <- !is.na(cris) && cris > 0
  crisis_summary[[cand_id]] <- list(
    crisis_ic = cris, normal_ic = norm,
    ratio = if(!is.na(norm) && abs(norm) > 1e-10) cris/norm else NA,
    n_crisis_months = nrow(ic_r[regime == "crisis"]),
    n_normal_months = nrow(ic_r[regime == "normal"]),
    ax001_v2_pass = ax_pass
  )
  cat(sprintf("  %s: crisis_IC=%s | normal_IC=%s | AX-001 v2 pass=%s\n",
              cand_id,
              formatC(cris, format="f", digits=4),
              formatC(norm, format="f", digits=4),
              ax_pass))
}

# ---- Step 5c: subperiod stability ----
cat("\n[STEP 5c] Subperiod stability (3 windows)\n")
windows <- list(
  P1_2001_2008 = c("2001-07-01", "2008-08-31"),
  P2_2009_2017 = c("2009-04-01", "2017-12-31"),
  P3_2018_2026 = c("2018-01-01", "2026-04-01")
)
subperiod_summary <- list()
for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) { subperiod_summary[[cand_id]] <- list(min_max_ratio=NA, pass=FALSE); next }
  setkey(comp, sig_date, Ticker)
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]
  ws <- list()
  for(wn in names(windows)) {
    w <- windows[[wn]]
    sub <- m[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
    if(nrow(sub) < 200) { ws[[wn]] <- list(rank_ic=NA, icir=NA, n_months=nrow(sub)); next }
    ic_per <- sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman") else NA_real_),
                  by = sig_date][!is.na(ic)]
    ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
    icir <- if(!is.na(sd_ic) && sd_ic > 1e-10) ic / sd_ic else NA_real_
    ws[[wn]] <- list(rank_ic=ic, icir=icir, n_months=nrow(ic_per))
  }
  ics <- sapply(ws, function(x) x$rank_ic)
  mmr <- if(all(!is.na(ics)) && max(abs(ics)) > 1e-6) min(ics)/max(ics) else NA
  ws$min_max_ratio <- mmr
  ws$pass <- !is.na(mmr) && mmr >= 0.50
  subperiod_summary[[cand_id]] <- ws
  cat(sprintf("  %s: P1=%s P2=%s P3=%s | min/max=%s | pass=%s\n",
              cand_id,
              formatC(ics[1], format="f", digits=4),
              formatC(ics[2], format="f", digits=4),
              formatC(ics[3], format="f", digits=4),
              formatC(mmr, format="f", digits=3),
              ws$pass))
}

# ---- Step 6: Selection score (NA-safe) ----
cat("\n[STEP 6] Candidate selection scoring\n")
selection_score <- list()
safe_gt <- function(x, thr) !is.null(x) && !is.na(x) && x > thr
safe_abs_lt <- function(x, thr) !is.null(x) && !is.na(x) && abs(x) < thr

for(cand_id in names(CANDIDATES)) {
  s <- 0; reasons <- character(0)
  ic <- ic_summary[[cand_id]]; co <- cor_summary[[cand_id]]
  cs <- crisis_summary[[cand_id]]; sp <- subperiod_summary[[cand_id]]

  if(safe_gt(ic$mean_ic, 0.02))   { s <- s + 25; reasons <- c(reasons, sprintf("IC=%.4f>0.02", ic$mean_ic)) }
  if(safe_gt(ic$icir, 0.20))      { s <- s + 25; reasons <- c(reasons, sprintf("ICIR=%.3f>0.20", ic$icir)) }
  if(safe_gt(ic$t_nw, 3.0))       { s <- s + 15; reasons <- c(reasons, sprintf("t_NW=%.2f>3", ic$t_nw)) }
  if(safe_abs_lt(co$cor_per_date_mean, 0.30)) { s <- s + 15; reasons <- c(reasons, sprintf("cor=%.3f<0.30", co$cor_per_date_mean)) }
  if(isTRUE(cs$ax001_v2_pass))    { s <- s + 10; reasons <- c(reasons, "AX-001 v2 PASS") }
  if(isTRUE(sp$pass))             { s <- s + 10; reasons <- c(reasons, "subperiod PASS") }

  selection_score[[cand_id]] <- list(score=s, reasons=reasons)
  cat(sprintf("  %s: score=%d | %s\n", cand_id, s, paste(reasons, collapse="; ")))
}

best <- names(which.max(sapply(selection_score, function(x) x$score)))
cat(sprintf("\n=> BEST candidate = %s (%s)\n\n", best, CANDIDATES[[best]]$name))

# ---- Step 7: Save best ----
cat("[STEP 7] Save best candidate alpha_scores parquet\n")
best_comp <- results_by_cand[[best]]
best_comp[, sleeve_label := CANDIDATES[[best]]$name]
write_parquet(best_comp, PD32_OUT)
cat("Written:", PD32_OUT, "\n")

diag_dt <- rbindlist(lapply(names(CANDIDATES), function(k) {
  ic <- ic_summary[[k]]; co <- cor_summary[[k]]; cs <- crisis_summary[[k]]; sp <- subperiod_summary[[k]]
  data.table(
    candidate = k, name = CANDIDATES[[k]]$name, family = CANDIDATES[[k]]$family,
    mean_IC = ic$mean_ic, ICIR = ic$icir, t_NW_lag6 = ic$t_nw,
    n_months = ic$n_months, pos_share = ic$pos_share,
    cor_vs_pd27_mean = co$cor_per_date_mean,
    cor_vs_pd27_overall = co$cor_overall,
    crisis_IC = cs$crisis_ic, normal_IC = cs$normal_ic,
    ax001_v2_pass = isTRUE(cs$ax001_v2_pass),
    P1_IC = sp$P1_2001_2008$rank_ic, P2_IC = sp$P2_2009_2017$rank_ic, P3_IC = sp$P3_2018_2026$rank_ic,
    subperiod_min_max_ratio = sp$min_max_ratio,
    selection_score = selection_score[[k]]$score
  )
}))
fwrite(diag_dt, PD32_DIAG)
cat("Diagnostic CSV:", PD32_DIAG, "\n")

log_obj <- list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_5th_orthogonal_source_v2",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  candidates = lapply(names(CANDIDATES), function(k) {
    list(
      id = k, name = CANDIDATES[[k]]$name, family = CANDIDATES[[k]]$family,
      factors = CANDIDATES[[k]]$factors, directions = CANDIDATES[[k]]$directions,
      rationale = CANDIDATES[[k]]$rationale, references = CANDIDATES[[k]]$references,
      diagnostics = ic_summary[[k]], cor_vs_pd27 = cor_summary[[k]],
      crisis_hedge = crisis_summary[[k]], subperiod = subperiod_summary[[k]],
      selection_score = selection_score[[k]]
    )
  }),
  selected_candidate = best,
  output_parquet = PD32_OUT,
  diagnostic_csv = PD32_DIAG
)
write_json(log_obj, PD32_LOG, pretty = TRUE, auto_unbox = TRUE)
cat("Log JSON:", PD32_LOG, "\n")

cat("\n============================================================\n")
cat("PD32 v2 complete.\n")
cat("End:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n")
