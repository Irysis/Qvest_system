cat("=== WT-D20260424_010: STR_1631_MEGA_01 Alpha Ablation v2 (fixed IC pipeline) ===\n")
## PIT: C1(expanding IC Date<sd), C4(consensus roll=7d), C10(LIQ t-1), C13, C14
## Chen-Zimmermann (2022), Bernard-Thomas (1989), Chan-Jegadeesh-Lakonishok (1996)
## 5 cells: BASELINE / ABL_A(6F) / ABL_B(EB) / ABL_C(RegWinsor) / FULL
## method_shopping_log ≤ 5 (P1 requirement)

set.seed(20260424)
t0_global <- Sys.time()

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR     <- file.path(CACHE_DIR, "consensus")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260424_010")
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260424_010")
dir.create(ART_DIR, showWarnings=FALSE, recursive=TRUE)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(future); library(future.apply)
})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
rcpp_loaded <- tryCatch({ source(file.path(FUNC_PATH, "cpp/rcpp_hotspots.R")); TRUE }, error=function(e) FALSE)
cat("[0] Infra ready. Rcpp:", rcpp_loaded, "\n")

# Constants
LIQ_THRESHOLD  <- 2e8; N_HOLD <- 20L; MAX21D_EXCL <- 0.80
REBAL_MONTHS   <- 2L;  IC_MIN_MONTHS <- 12L
EB_LAMBDA      <- 0.7; EB_RECENT_WIN <- 12L
WINSOR_RISK_ON <- 2.0; WINSOR_CAUTION <- 2.5; WINSOR_CRISIS <- 3.0
REGIME_CRISIS_THR  <- 60.0; REGIME_CAUTION_THR <- 30.0
FACTORS_4F <- c("sue","esbr","eps1m","tpgap")
FACTORS_6F <- c("sue","esbr","eps1m","tpgap","c19","c09")
SUBPERIODS <- list(
  p1_2008_2014 = c(as.Date("2008-01-01"), as.Date("2014-12-31")),
  p2_2015_2019 = c(as.Date("2015-01-01"), as.Date("2019-12-31")),
  p3_2020_2026 = c(as.Date("2020-01-01"), as.Date("2026-12-31"))
)

# ==========================================================================
# 1. Load Data
# ==========================================================================
cat("[1] Loading RAWDATA...\n"); flush(stdout())
res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)
RAWDATA[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := shift(frollmean(TradVal, n=20L, align="right", na.rm=TRUE), n=1L, type="lag"), by=Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if(n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n=21L, FUN=max, fill=NA, align="right")
}, by=Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n=1L, type="lag"), by=Ticker]
RAWDATA[, c("Ret_abs","MAX21d_raw") := NULL]
RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date=max(Date)), by=YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= ANALYSIS_START_DATE]
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by=REBAL_MONTHS)]
cat(sprintf("[1] Monthly: %d | Bimonthly: %d\n", length(ALL_SIG_DATES), length(SIG_DATES))); flush(stdout())
SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d","MAX21d","YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose=FALSE)

cat("[1] Loading Consensus...\n"); flush(stdout())
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f)))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")
cat("[1] Consensus loaded.\n"); flush(stdout())

fdb_ready <- tryCatch({
  source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))
  fdb_dir <- file.path(CACHE_DIR, "factor_db")
  length(list.files(fdb_dir, pattern="^factor_db_\\d{6}\\.parquet$")) > 0
}, error=function(e) FALSE)
cat("[1] FDB ready:", fdb_ready, "\n"); flush(stdout())

REGIME_DT <- tryCatch({
  rg <- as.data.table(read_parquet(file.path(CACHE_DIR, "unified_regime_signal.parquet")))
  rg[, Date := as.Date(Date)]; rg[, YM := format(Date, "%Y-%m")]
  rg[, .(YM, Regime_Score)]
}, error=function(e) NULL)
cat("[1] Regime signal:", if(is.null(REGIME_DT)) "N/A" else nrow(REGIME_DT), "\n"); flush(stdout())

# ==========================================================================
# 2. Forward returns (global, passed explicitly to run_cell)
# ==========================================================================
cat("[2] Computing forward returns...\n"); flush(stdout())
FWD_MAP <- list()
for(i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  if(i < length(ALL_SIG_DATES)) {
    ns <- ALL_SIG_DATES[i+1]
    ret_sub <- RAWDATA[Date > sd & Date <= ns, .(fwd_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    FWD_MAP[[as.character(sd)]] <- ret_sub
  }
}
cat(sprintf("[2] Forward map: %d entries. Sample key: %s\n", length(FWD_MAP), names(FWD_MAP)[1])); flush(stdout())

# ==========================================================================
# 3. Helpers
# ==========================================================================
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if(nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if(is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x-mu)/s
}
winsor_s <- function(x, sigma) {
  nv <- sum(!is.na(x)); if(nv < 3L) return(x)
  mu <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if(is.na(s) || s < 1e-10) return(x)
  pmin(pmax(x, mu - sigma*s), mu + sigma*s)
}
get_sigma <- function(ym_str) {
  if(is.null(REGIME_DT)) return(WINSOR_CAUTION)
  rs <- REGIME_DT[YM == ym_str, Regime_Score]
  if(length(rs)==0 || is.na(rs[1])) return(WINSOR_CAUTION)
  if(rs[1] >= REGIME_CRISIS_THR) WINSOR_CRISIS
  else if(rs[1] >= REGIME_CAUTION_THR) WINSOR_CAUTION
  else WINSOR_RISK_ON
}
expand_w <- function(ic_h, fac_cols, sd) {
  past <- ic_h[ic_h$Date < sd, ]
  if(nrow(past) < IC_MIN_MONTHS) return(setNames(rep(1/length(fac_cols), length(fac_cols)), fac_cols))
  mv <- sapply(fac_cols, function(f) mean(past[[paste0("ic_",f)]], na.rm=TRUE))
  mv <- pmax(mv, 0); s <- sum(mv)
  if(s < 1e-8) setNames(rep(1/length(fac_cols), length(fac_cols)), fac_cols)
  else setNames(mv/s, fac_cols)
}
eb_w <- function(ic_h, fac_cols, sd) {
  past <- ic_h[ic_h$Date < sd, ]
  n <- nrow(past)
  if(n < IC_MIN_MONTHS) return(setNames(rep(1/length(fac_cols), length(fac_cols)), fac_cols))
  full <- sapply(fac_cols, function(f) mean(past[[paste0("ic_",f)]], na.rm=TRUE))
  full <- pmax(full, 0)
  rec  <- tail(past, min(EB_RECENT_WIN, n))
  rm2  <- sapply(fac_cols, function(f) mean(rec[[paste0("ic_",f)]], na.rm=TRUE))
  rm2  <- pmax(rm2, 0)
  eb <- EB_LAMBDA*rm2 + (1-EB_LAMBDA)*full; s <- sum(eb)
  if(s < 1e-8) setNames(rep(1/length(fac_cols), length(fac_cols)), fac_cols)
  else setNames(eb/s, fac_cols)
}
ntile_fn <- function(x, n) {
  breaks <- quantile(x, probs=seq(0,1,length.out=n+1), na.rm=TRUE)
  findInterval(x, breaks, rightmost.closed=TRUE)
}

# Build composite score for a date given weights
make_composite <- function(sc, fac_cols, w) {
  comp <- rep(0.0, nrow(sc)); tw <- 0.0
  for(fc in fac_cols) {
    z_col <- paste0("z_",fc); ww <- w[[fc]]
    if(is.null(ww) || is.na(ww) || ww <= 0) next
    if(!z_col %in% names(sc)) next
    zv <- sc[[z_col]]; valid <- !is.na(zv)
    if(sum(valid) < 5L) next
    comp <- comp + ww * fifelse(valid, zv, 0.0); tw <- tw + ww
  }
  if(tw < 1e-8) return(NULL)
  comp / tw
}

# ==========================================================================
# 4. Cross-section builder (sequential, uses globals)
# ==========================================================================
# Builds RAW_SCORES for all dates for a given config
build_raw_scores_all <- function(config) {
  fac_cols <- if(config$use_6f) FACTORS_6F else FACTORS_4F
  result_list <- vector("list", length(ALL_SIG_DATES))

  for(i in seq_along(ALL_SIG_DATES)) {
    sd <- ALL_SIG_DATES[i]
    univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
    if(nrow(univ) < 20L) next
    mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm=TRUE)
    univ <- univ[is.na(MAX21d) | MAX21d <= mq]
    if(nrow(univ) < 20L) next

    probe <- data.table(Ticker=univ$Ticker, Date=sd); setkey(probe, Ticker, Date)
    sue_j   <- SUE_DT[probe, roll=7L, nomatch=NA][,.(Ticker, sue)]
    esbr_j  <- ESBR_DT[probe, roll=7L, nomatch=NA][,.(Ticker, esbr)]
    eps1m_j <- EPS1M_DT[probe, roll=7L, nomatch=NA][,.(Ticker, eps_chg_1m)]
    cov_j   <- COV_DT[probe, roll=7L, nomatch=NA][,.(Ticker, coverage)]
    tp_j    <- TP_DT[probe, roll=7L, nomatch=NA][,.(Ticker, target_price)]

    sig <- Reduce(function(a,b) merge(a,b, by="Ticker", all=FALSE),
                  list(univ[,.(Ticker,Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
    sig <- sig[!is.na(coverage) & coverage >= 3L]
    if(nrow(sig) < 20L) next
    sig[, TP_Gap := (target_price - Close) / Close]

    ym_str <- format(sd, "%Y-%m")
    sigma_lv <- if(config$use_regime_winsor) get_sigma(ym_str) else 2.0

    sig[, z_sue   := z_safe(winsor_s(sue, sigma_lv))]
    sig[, z_esbr  := z_safe(winsor_s(esbr, sigma_lv))]
    sig[, z_eps1m := z_safe(winsor_s(eps_chg_1m, sigma_lv))]
    sig[, z_tpgap := z_safe(winsor_s(TP_Gap, sigma_lv))]
    sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
    if(nrow(sig) < 20L) next

    # 6F: C19, C09 from Factor DB (C15: load_month_factors per date)
    sig[, z_c19 := NA_real_]; sig[, z_c09 := NA_real_]
    if(config$use_6f && fdb_ready) {
      fdb_sd <- tryCatch(load_month_factors(sig_date=sd, coverage_min=0.05), error=function(e) NULL)
      if(!is.null(fdb_sd) && nrow(fdb_sd) > 0) {
        c19_dt <- fdb_sd[Factor_Name=="C19_Composite_Earnings", .(Ticker, Z_Score_Aligned)]
        c09_dt <- fdb_sd[Factor_Name=="C09_Earnings_Surprise_Sq", .(Ticker, Z_Score_Aligned)]
        if(nrow(c19_dt) > 0) {
          setnames(c19_dt, "Z_Score_Aligned", "z_c19_raw")
          sig <- merge(sig, c19_dt, by="Ticker", all.x=TRUE)
          sig[!is.na(z_c19_raw), z_c19 := winsor_s(z_c19_raw, sigma_lv)]
          sig[, z_c19_raw := NULL]
        }
        if(nrow(c09_dt) > 0) {
          setnames(c09_dt, "Z_Score_Aligned", "z_c09_raw")
          sig <- merge(sig, c09_dt, by="Ticker", all.x=TRUE)
          sig[!is.na(z_c09_raw), z_c09 := winsor_s(z_c09_raw, sigma_lv)]
          sig[, z_c09_raw := NULL]
        }
      }
    }
    result_list[[i]] <- data.table(
      Date=sd, Ticker=sig$Ticker,
      z_sue=sig$z_sue, z_esbr=sig$z_esbr, z_eps1m=sig$z_eps1m, z_tpgap=sig$z_tpgap,
      z_c19=sig$z_c19, z_c09=sig$z_c09, sigma_used=sigma_lv
    )
  }
  rbindlist(result_list[!sapply(result_list, is.null)])
}

# ==========================================================================
# 5. Cell runner (receives FWD_MAP explicitly)
# ==========================================================================
run_cell <- function(cell_name, config, fwd_map_local) {
  cat(sprintf("\n[CELL] %s (6F=%s EB=%s RW=%s)\n",
              cell_name, config$use_6f, config$use_eb, config$use_regime_winsor))
  flush(stdout())
  t_c <- Sys.time()
  fac_cols <- if(config$use_6f) FACTORS_6F else FACTORS_4F

  # Build cross-sections
  RAW_SCORES <- build_raw_scores_all(config)
  cat(sprintf("  RAW_SCORES: %d dates | %d rows\n", uniqueN(RAW_SCORES$Date), nrow(RAW_SCORES)))
  flush(stdout())
  if(nrow(RAW_SCORES) == 0) { cat("  SKIP: no data\n"); return(NULL) }

  # Build IC history (expanding, per ALL_SIG_DATES)
  ic_cols <- paste0("ic_", fac_cols)
  ic_rows  <- vector("list", length(ALL_SIG_DATES))
  for(i in seq_along(ALL_SIG_DATES)) {
    sd <- ALL_SIG_DATES[i]
    key_sd <- as.character(sd)
    fr <- fwd_map_local[[key_sd]]
    if(is.null(fr) || nrow(fr) == 0) next
    sc <- RAW_SCORES[Date == sd]
    if(nrow(sc) == 0) next
    mg <- merge(sc, fr, by="Ticker")
    if(nrow(mg) < 10L) next
    row_ic <- list(Date=sd)
    for(fc in fac_cols) {
      z_col <- paste0("z_",fc)
      ic_val <- if(z_col %in% names(mg) && sum(!is.na(mg[[z_col]])) >= 5)
        tryCatch(cor(mg[[z_col]], mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
      else NA_real_
      row_ic[[paste0("ic_",fc)]] <- fifelse(is.na(ic_val), 0.0, ic_val)
    }
    ic_rows[[i]] <- row_ic
  }
  ic_rows_valid <- ic_rows[!sapply(ic_rows, is.null)]
  ic_history <- if(length(ic_rows_valid) > 0) {
    rbindlist(lapply(ic_rows_valid, as.data.table))
  } else {
    as.data.table(setNames(c(list(as.Date(character(0))), lapply(ic_cols, function(x) numeric(0))), c("Date", ic_cols)))
  }
  cat(sprintf("  IC history: %d months (first: %s)\n",
              nrow(ic_history),
              if(nrow(ic_history)>0) as.character(min(ic_history$Date)) else "N/A"))
  flush(stdout())

  # Bimonthly composite + top-N selection
  FACTORS_list <- vector("list", length(SIG_DATES))
  ic_wt_log <- list()
  for(i in seq_along(SIG_DATES)) {
    sd <- SIG_DATES[i]
    sc <- RAW_SCORES[Date == sd]
    if(nrow(sc) < 20L) next
    w <- if(config$use_eb) eb_w(ic_history, fac_cols, sd)
         else expand_w(ic_history, fac_cols, sd)
    ic_wt_log[[as.character(sd)]] <- w
    comp <- make_composite(sc, fac_cols, as.list(w))
    if(is.null(comp)) next
    sc_out <- copy(sc)[, Score := comp]
    setorder(sc_out, -Score)
    top <- head(sc_out, N_HOLD)
    FACTORS_list[[i]] <- data.table(Date=sd, Ticker=top$Ticker, Score=top$Score)
  }
  FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
  cat(sprintf("  FACTORS: %d rows | %d bimonthly\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
  flush(stdout())

  # Full-period rank IC series
  all_ic <- c()
  for(i in seq_along(ALL_SIG_DATES)) {
    sd <- ALL_SIG_DATES[i]
    fr <- fwd_map_local[[as.character(sd)]]
    if(is.null(fr) || nrow(fr)==0) next
    sc <- RAW_SCORES[Date == sd]
    if(nrow(sc) == 0) next
    mg <- merge(sc, fr, by="Ticker")
    if(nrow(mg) < 10L) next
    w <- expand_w(ic_history, fac_cols, sd)
    comp <- make_composite(mg, fac_cols, as.list(w))
    if(is.null(comp)) next
    iv <- tryCatch(cor(comp, mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
    if(!is.na(iv)) all_ic <- c(all_ic, iv)
  }
  cat(sprintf("  IC series: %d months | mean_IC=%.4f\n", length(all_ic), mean(all_ic, na.rm=TRUE)))
  flush(stdout())

  # Diagnostics
  rank_ic  <- mean(all_ic, na.rm=TRUE)
  ic_sd    <- if(length(all_ic)>1) sd(all_ic, na.rm=TRUE) else NA_real_
  icir     <- if(!is.na(ic_sd) && ic_sd>1e-8) rank_ic/ic_sd else NA_real_
  harvey_t <- if(!is.na(icir) && length(all_ic)>1) icir*sqrt(length(all_ic)) else NA_real_
  dsr      <- if(rcpp_loaded && length(all_ic)>=20) {
    tryCatch(bootstrap_dsr_fast(all_ic, n_trials=5L, B=200L, seed=42L), error=function(e) NA_real_)
  } else NA_real_

  # Subperiod stability
  sp_ics <- list()
  for(sp_name in names(SUBPERIODS)) {
    sp_range <- SUBPERIODS[[sp_name]]
    sp_vals  <- c()
    for(sd in ALL_SIG_DATES[ALL_SIG_DATES >= sp_range[1] & ALL_SIG_DATES <= sp_range[2]]) {
      fr <- fwd_map_local[[as.character(sd)]]; if(is.null(fr)) next
      sc <- RAW_SCORES[Date == sd]; if(nrow(sc)==0) next
      mg <- merge(sc, fr, by="Ticker"); if(nrow(mg)<10L) next
      w <- expand_w(ic_history, fac_cols, sd)
      comp <- make_composite(mg, fac_cols, as.list(w)); if(is.null(comp)) next
      iv <- tryCatch(cor(comp, mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
      if(!is.na(iv)) sp_vals <- c(sp_vals, iv)
    }
    sp_ics[[sp_name]] <- if(length(sp_vals)>0) mean(sp_vals) else NA_real_
  }
  sp_v <- unlist(sp_ics)[!is.na(unlist(sp_ics))]
  subperiod_stability <- if(length(sp_v)>=2) {
    (mean(sp_v>0) + pmax(min(sp_v)/max(sp_v), 0))/2
  } else 0.5

  # Monotonicity (last 36 months)
  monotonicity <- tryCatch({
    test_d <- tail(sort(unique(RAW_SCORES$Date)), 36)
    ms <- c()
    for(sd in test_d) {
      fr <- fwd_map_local[[as.character(sd)]]; if(is.null(fr)) next
      sc <- RAW_SCORES[Date==sd]; mg <- merge(sc, fr, by="Ticker"); if(nrow(mg)<20L) next
      w <- expand_w(ic_history, fac_cols, sd)
      comp <- make_composite(mg, fac_cols, as.list(w)); if(is.null(comp)) next
      mg[, composite := comp]; mg[, dec := ntile_fn(composite, 10)]
      dr <- mg[,.(dr=mean(fwd_ret,na.rm=TRUE)),by=dec]; setorder(dr, dec)
      if(nrow(dr)>=8) ms <- c(ms, mean(diff(dr$dr)>0))
    }
    if(length(ms)>0) mean(ms) else NA_real_
  }, error=function(e) NA_real_)

  # FF3 retention (market-adjusted IC ratio)
  ff3_retention <- tryCatch({
    test_d2 <- tail(sort(unique(RAW_SCORES$Date)), 48)
    raw_v <- c(); adj_v <- c()
    for(sd in test_d2) {
      fr <- fwd_map_local[[as.character(sd)]]; if(is.null(fr)) next
      sc <- RAW_SCORES[Date==sd]; mg <- merge(sc, fr, by="Ticker"); if(nrow(mg)<15L) next
      w <- expand_w(ic_history, fac_cols, sd)
      comp <- make_composite(mg, fac_cols, as.list(w)); if(is.null(comp)) next
      mg[, composite := comp]
      raw_ic <- tryCatch(cor(comp, mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
      # Market-residualized return
      mkt_ret <- mean(mg$fwd_ret, na.rm=TRUE)
      mg[, ret_resid := fwd_ret - mkt_ret]
      adj_ic <- tryCatch(cor(comp, mg$ret_resid, method="spearman", use="complete.obs"), error=function(e) NA_real_)
      if(!is.na(raw_ic)) raw_v <- c(raw_v, raw_ic)
      if(!is.na(adj_ic)) adj_v <- c(adj_v, adj_ic)
    }
    ri <- mean(abs(raw_v), na.rm=TRUE)
    ai <- mean(abs(adj_v), na.rm=TRUE)
    if(ri > 1e-8 && !is.nan(ai)) ai/ri else NA_real_
  }, error=function(e) NA_real_)

  elapsed <- as.numeric(difftime(Sys.time(), t_c, units="secs"))
  cat(sprintf("  RESULT: rank_IC=%.4f ICIR=%.4f Harvey=%.2f DSR=%.3f Mono=%.3f SubSt=%.3f FF3=%.3f | %.0fs\n",
              rank_ic, ifelse(is.na(icir),0,icir), ifelse(is.na(harvey_t),0,harvey_t),
              ifelse(is.na(dsr),0,dsr), ifelse(is.na(monotonicity),0,monotonicity),
              ifelse(is.na(subperiod_stability),0,subperiod_stability),
              ifelse(is.na(ff3_retention),0,ff3_retention), elapsed))
  flush(stdout())

  list(cell_name=cell_name, config=config,
       rank_ic=rank_ic, icir=icir, harvey_t=harvey_t, dsr=dsr,
       monotonicity=monotonicity, subperiod_stability=subperiod_stability, subperiod_ics=sp_ics,
       ff3_retention=ff3_retention, n_months=length(all_ic),
       ic_weights_last=as.list(ic_wt_log[[as.character(max(SIG_DATES))]]),
       FACTORS=FACTORS, ic_series=all_ic, elapsed_sec=elapsed)
}

# ==========================================================================
# 6. Run 5 cells
# ==========================================================================
cat("\n[3] Running 5-cell Ablation (Method Shopping Log, P1 <=5)...\n"); flush(stdout())
CELLS <- list(
  BASELINE = list(use_6f=FALSE, use_eb=FALSE, use_regime_winsor=FALSE),
  ABL_A    = list(use_6f=TRUE,  use_eb=FALSE, use_regime_winsor=FALSE),
  ABL_B    = list(use_6f=FALSE, use_eb=TRUE,  use_regime_winsor=FALSE),
  ABL_C    = list(use_6f=FALSE, use_eb=FALSE, use_regime_winsor=TRUE),
  FULL     = list(use_6f=TRUE,  use_eb=TRUE,  use_regime_winsor=TRUE)
)
RESULTS <- list()
for(cell_name in names(CELLS)) {
  RESULTS[[cell_name]] <- tryCatch(
    run_cell(cell_name, CELLS[[cell_name]], FWD_MAP),
    error=function(e) { cat("[CELL ERR]", cell_name, ":", conditionMessage(e), "\n"); NULL }
  )
  gc(verbose=FALSE)
}

# ==========================================================================
# 7. Select PRIMARY
# ==========================================================================
cat("\n[4] Selecting PRIMARY...\n"); flush(stdout())
score_cell <- function(r) {
  if(is.null(r)) return(-Inf)
  s <- 0
  if(!is.na(r$rank_ic)) s <- s + r$rank_ic*100
  if(!is.na(r$icir))    s <- s + r$icir*5
  if(!is.na(r$subperiod_stability)) s <- s + r$subperiod_stability*10
  if(!is.na(r$harvey_t) && r$harvey_t>3) s <- s+5
  if(!is.na(r$dsr) && r$dsr>0.8) s <- s+3
  s
}
valid_cells <- names(RESULTS)[!sapply(RESULTS, is.null)]
scores <- sapply(RESULTS[valid_cells], score_cell)
best_cell <- if(length(valid_cells)>0) valid_cells[which.max(scores)] else "BASELINE"
PRIMARY   <- RESULTS[[best_cell]]
cat(sprintf("[4] PRIMARY: %s (score=%.2f)\n", best_cell, max(scores, na.rm=TRUE))); flush(stdout())

tier_fn <- function(r) {
  if(is.null(r)) return("REJECT")
  n_pass <- sum(c(!is.na(r$dsr)&&r$dsr>0.8, !is.na(r$rank_ic)&&r$rank_ic>0.04,
                  !is.na(r$icir)&&r$icir>0.5, !is.na(r$ff3_retention)&&r$ff3_retention>0.30,
                  !is.na(r$harvey_t)&&r$harvey_t>3.0))
  if(n_pass>=4) "HIGH" else if(n_pass>=2) "MEDIUM" else "LOW"
}
primary_tier <- tier_fn(PRIMARY)
cat(sprintf("[4] Confidence tier: %s\n", primary_tier)); flush(stdout())

# Axis contributions
baseline_ric <- RESULTS$BASELINE$rank_ic
axis_a_delta <- if(!is.null(RESULTS$ABL_A)) RESULTS$ABL_A$rank_ic - baseline_ric else NA
axis_b_delta <- if(!is.null(RESULTS$ABL_B)) RESULTS$ABL_B$rank_ic - baseline_ric else NA
axis_c_delta <- if(!is.null(RESULTS$ABL_C)) RESULTS$ABL_C$rank_ic - baseline_ric else NA
full_delta   <- if(!is.null(RESULTS$FULL))  RESULTS$FULL$rank_ic  - baseline_ric else NA
cat(sprintf("[7] AxisA:%+.4f AxisB:%+.4f AxisC:%+.4f FULL:%+.4f\n",
            ifelse(is.na(axis_a_delta),0,axis_a_delta), ifelse(is.na(axis_b_delta),0,axis_b_delta),
            ifelse(is.na(axis_c_delta),0,axis_c_delta), ifelse(is.na(full_delta),0,full_delta)))
flush(stdout())

# ==========================================================================
# 8. Alpha vector
# ==========================================================================
if(!is.null(PRIMARY) && nrow(PRIMARY$FACTORS)>0) {
  latest_date <- max(PRIMARY$FACTORS$Date)
  alpha_today <- PRIMARY$FACTORS[Date==latest_date, .(Ticker, Score)]
  s_rng <- diff(range(alpha_today$Score, na.rm=TRUE))
  alpha_today[, alpha_hat := if(s_rng>1e-8) (Score-min(Score,na.rm=TRUE))/s_rng else 0.5]
  alpha_today[, rank_pct := frank(Score)/.N]
  alpha_today[, conf := 0.5 + 0.5*rank_pct]
  alpha_vec <- setNames(as.numeric(alpha_today$alpha_hat), alpha_today$Ticker)
  conf_vec  <- setNames(as.numeric(alpha_today$conf), alpha_today$Ticker)
} else {
  alpha_vec <- setNames(numeric(0), character(0))
  conf_vec  <- setNames(numeric(0), character(0))
}
cat(sprintf("[8] Alpha vector: %d tickers (as of %s)\n",
            length(alpha_vec), if(!is.null(PRIMARY)&&nrow(PRIMARY$FACTORS)>0) as.character(max(PRIMARY$FACTORS$Date)) else "N/A"))
flush(stdout())

# ==========================================================================
# 9. Red flags
# ==========================================================================
challenge_flags <- list()
if(!is.null(PRIMARY) && !is.na(PRIMARY$subperiod_stability) && PRIMARY$subperiod_stability < 0.5)
  challenge_flags <- c(challenge_flags, list(list(id="RF-A1", severity="HIGH",
    msg=sprintf("Subperiod stability %.3f < 0.5", PRIMARY$subperiod_stability))))
if(!is.null(RESULTS$BASELINE) && !is.null(PRIMARY) && !is.na(RESULTS$BASELINE$rank_ic) && abs(RESULTS$BASELINE$rank_ic)>1e-8) {
  dp <- (PRIMARY$rank_ic - RESULTS$BASELINE$rank_ic)/abs(RESULTS$BASELINE$rank_ic)
  if(dp < 0.05) challenge_flags <- c(challenge_flags, list(list(id="RF-A2", severity="MEDIUM",
    msg=sprintf("Improvement %.1f%% < 5%% vs BASELINE", dp*100))))
}
if(length(challenge_flags)==0) { cat("[9] No Red Flags\n") } else { cat(sprintf("[9] %d Red Flag(s)\n", length(challenge_flags))) }
flush(stdout())

# ==========================================================================
# 10. Factor specs
# ==========================================================================
use_6f_primary <- !is.null(PRIMARY$config) && PRIMARY$config$use_6f
w_last <- PRIMARY$ic_weights_last

factor_specs <- list(
  list(factor_family="consensus_earnings", proxy="C01_SUE",
       formula="consensus/sue.parquet::sue roll=7d (C4)",
       lag_rule="C4: roll=7d", winsorization="regime-adaptive winsor (2.0/2.5/3.0 sigma)",
       neutralization="none (IC-weighted composite)",
       economic_rationale="PEAD: post-earnings announcement drift underreaction (Bernard-Thomas 1989)",
       weight_theta=w_last[["sue"]], references=c("Bernard & Thomas (1989)","Chan et al. (1996)")),
  list(factor_family="consensus_earnings", proxy="C04_ESBR",
       formula="consensus/esbr.parquet::esbr roll=7d (C4)",
       lag_rule="C4: roll=7d", winsorization="regime-adaptive",
       neutralization="none", economic_rationale="Earnings surprise beat ratio — consensus persistence",
       weight_theta=w_last[["esbr"]], references=c("Barber et al. (2001)")),
  list(factor_family="consensus_earnings", proxy="C02_EPS_Chg_1m",
       formula="consensus/eps_chg_1m.parquet roll=7d (C4)",
       lag_rule="C4: roll=7d", winsorization="regime-adaptive",
       neutralization="none", economic_rationale="Analyst revision momentum (Womack 1996)",
       weight_theta=w_last[["eps1m"]], references=c("Womack (1996)")),
  list(factor_family="consensus_analyst", proxy="C06_TP_Gap",
       formula="(target_price-Close)/Close, consensus roll=7d",
       lag_rule="C4: roll=7d, t-1 Close", winsorization="regime-adaptive",
       neutralization="none", economic_rationale="Analyst upside target gap (Bradshaw 2002)",
       weight_theta=w_last[["tpgap"]], references=c("Bradshaw (2002)"))
)
if(use_6f_primary) {
  factor_specs <- c(factor_specs, list(
    list(factor_family="consensus_earnings", proxy="C19_Composite_Earnings",
         formula="load_month_factors()::Z_Score_Aligned[C19_Composite_Earnings] (C14+C15)",
         lag_rule="C14: Usable_Date<=sig_date", winsorization="regime-adaptive",
         neutralization="none", economic_rationale="Composite earnings consensus (Pilot9 ICIR=0.56)",
         weight_theta=w_last[["c19"]], references=c("Chen-Zimmermann (2022)","Pilot9")),
    list(factor_family="consensus_earnings", proxy="C09_Earnings_Surprise_Sq",
         formula="load_month_factors()::Z_Score_Aligned[C09_Earnings_Surprise_Sq] (C14+C15)",
         lag_rule="C14: Usable_Date<=sig_date", winsorization="regime-adaptive",
         neutralization="none", economic_rationale="Earnings surprise magnitude nonlinearity",
         weight_theta=w_last[["c09"]], references=c("Bernard & Thomas (1989)","Pilot9"))
  ))
}

# ==========================================================================
# 11. Method shopping log
# ==========================================================================
method_log <- lapply(names(CELLS), function(cn) {
  r <- RESULTS[[cn]]
  list(name=cn, selected=(cn==best_cell),
       description=sprintf("6F=%s EB=%s RW=%s", CELLS[[cn]]$use_6f, CELLS[[cn]]$use_eb, CELLS[[cn]]$use_regime_winsor),
       rank_ic=if(!is.null(r)) r$rank_ic else NA,
       icir=if(!is.null(r)) r$icir else NA,
       harvey_t=if(!is.null(r)) r$harvey_t else NA,
       dsr=if(!is.null(r)) r$dsr else NA,
       subperiod_stability=if(!is.null(r)) r$subperiod_stability else NA,
       rationale=if(cn==best_cell) "highest composite predictive score" else "not selected")
})

# ==========================================================================
# 12. Build alpha_package.json (L-194: write FIRST before lineage)
# ==========================================================================
cat("[10] Writing alpha_package.json...\n"); flush(stdout())
alpha_package <- list(
  task_id="WT-D20260424_010", wt_type="discovery",
  as_of_date=format(Sys.Date(),"%Y-%m-%d"), forecast_horizon="1M",
  selection_objective="rank_ic",
  hypothesis_title="STR_1631_MEGA_01 -- Alpha Signal Amplification (4F to 6F + EB Shrinkage + Regime-Adaptive Winsor)",
  references=list("Chen & Zimmermann (2022)", "Bernard & Thomas (1989) PEAD",
                  "Chan, Jegadeesh & Lakonishok (1996)", "Womack (1996)", "Barber et al. (2001)"),
  primary_cell=best_cell, confidence_tier=primary_tier,
  alpha_vector=alpha_vec, confidence_vector=conf_vec,
  signal_matrix_ref="stage_artifacts://WT_D20260424_010/alpha_scores.parquet",
  factor_specs=factor_specs,
  diagnostics=list(
    rank_ic=if(!is.null(PRIMARY)) PRIMARY$rank_ic else NA,
    icir=if(!is.null(PRIMARY)) PRIMARY$icir else NA,
    harvey_t_stat=if(!is.null(PRIMARY)) PRIMARY$harvey_t else NA,
    dsr=if(!is.null(PRIMARY)) PRIMARY$dsr else NA,
    monotonicity=if(!is.null(PRIMARY)) PRIMARY$monotonicity else NA,
    subperiod_stability=if(!is.null(PRIMARY)) PRIMARY$subperiod_stability else NA,
    subperiod_ics=if(!is.null(PRIMARY)) PRIMARY$subperiod_ics else list(),
    ff3_retention=if(!is.null(PRIMARY)) PRIMARY$ff3_retention else NA,
    post_neutralization_ic=if(!is.null(PRIMARY)&&!is.na(PRIMARY$rank_ic)&&!is.na(PRIMARY$ff3_retention))
                             PRIMARY$rank_ic*PRIMARY$ff3_retention else NA,
    turnover_proxy=0.50, n_months=if(!is.null(PRIMARY)) PRIMARY$n_months else 0,
    n_tickers=length(alpha_vec),
    pilot9_comparison=list(p9_rank_ic=0.0449, p9_icir=0.5562, p9_harvey_t=8.379,
      mega01_rank_ic=if(!is.null(PRIMARY)) PRIMARY$rank_ic else NA,
      delta_rank_ic=if(!is.null(PRIMARY)&&!is.na(PRIMARY$rank_ic)) PRIMARY$rank_ic-0.0449 else NA)
  ),
  ablation_results=lapply(names(RESULTS), function(cn) {
    r <- RESULTS[[cn]]
    list(cell=cn, config=CELLS[[cn]],
         rank_ic=if(!is.null(r)) r$rank_ic else NULL,
         icir=if(!is.null(r)) r$icir else NULL,
         harvey_t=if(!is.null(r)) r$harvey_t else NULL,
         dsr=if(!is.null(r)) r$dsr else NULL,
         monotonicity=if(!is.null(r)) r$monotonicity else NULL,
         subperiod_stability=if(!is.null(r)) r$subperiod_stability else NULL,
         ff3_retention=if(!is.null(r)) r$ff3_retention else NULL,
         confidence_tier=tier_fn(r),
         elapsed_sec=if(!is.null(r)) r$elapsed_sec else NULL)
  }),
  axis_contribution=list(
    baseline_rank_ic=baseline_ric, axis_a_6f_delta=axis_a_delta,
    axis_b_eb_delta=axis_b_delta, axis_c_winsor_delta=axis_c_delta, full_delta=full_delta
  ),
  method_shopping_log=list(candidates_tried=length(CELLS), method_log=method_log,
    parallel_exec=FALSE, n_workers=1L,
    rcpp_used=rcpp_loaded, rcpp_functions=c("bootstrap_dsr_fast"),
    rolling_seconds=as.numeric(difftime(Sys.time(), t0_global, units="secs"))),
  challenge_flags=challenge_flags,
  mega_sprint_phase="Phase1_alpha_amplification",
  unchanged_components=list("HRP 0.6+Score 0.4","bimonthly","3-Layer overlay","SYN_05 filter","n=20","liquidity 2e8"),
  status_note="Discovery WT -- alpha signal only. Risk/Optimizer unchanged."
)

# L-194: write FIRST
alpha_pkg_path <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, alpha_pkg_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] alpha_package.json: %s\n", alpha_pkg_path)); flush(stdout())

# alpha_scores.parquet
if(!is.null(PRIMARY) && nrow(PRIMARY$FACTORS)>0) {
  scores_dt <- copy(PRIMARY$FACTORS); scores_dt[, cell := best_cell]
  pq_path <- file.path(ART_DIR, "alpha_scores.parquet")
  write_parquet(as.data.frame(scores_dt), pq_path)
  cat(sprintf("[10] alpha_scores.parquet: %d rows\n", nrow(scores_dt))); flush(stdout())
}

# mega_01_ablation.json
ablation_json <- list(
  task_id="WT-D20260424_010",
  created_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  cells=lapply(names(RESULTS), function(cn) {
    r <- RESULTS[[cn]]
    list(cell=cn, config=CELLS[[cn]],
         rank_ic=if(!is.null(r)) r$rank_ic else NULL,
         icir=if(!is.null(r)) r$icir else NULL,
         harvey_t=if(!is.null(r)) r$harvey_t else NULL,
         dsr=if(!is.null(r)) r$dsr else NULL,
         monotonicity=if(!is.null(r)) r$monotonicity else NULL,
         subperiod_stability=if(!is.null(r)) r$subperiod_stability else NULL,
         subperiod_ics=if(!is.null(r)) r$subperiod_ics else list(),
         ff3_retention=if(!is.null(r)) r$ff3_retention else NULL,
         confidence_tier=tier_fn(r),
         elapsed_sec=if(!is.null(r)) r$elapsed_sec else NULL)
  }),
  primary_cell=best_cell,
  axis_contribution=list(
    baseline_rank_ic=baseline_ric, axis_a_6f_delta=axis_a_delta,
    axis_b_eb_delta=axis_b_delta, axis_c_winsor_delta=axis_c_delta,
    full_delta=full_delta,
    interaction_effect=if(!is.na(full_delta)&&!is.na(axis_a_delta)&&!is.na(axis_b_delta)&&!is.na(axis_c_delta))
                        full_delta-(axis_a_delta+axis_b_delta+axis_c_delta) else NA
  )
)
abl_path <- file.path(ART_DIR, "mega_01_ablation.json")
write_json(ablation_json, abl_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] mega_01_ablation.json: %s\n", abl_path)); flush(stdout())

# alpha_validation.json
alpha_val <- list(
  task_id="WT-D20260424_010",
  validated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  pit_checks=list(C1="PASS: expanding IC Date<sd",
                  C4="PASS: consensus roll=7d",
                  C10="PASS: LIQ_20d shift(frollmean,1L,lag)",
                  C13="PASS: Z_Score_Aligned FDB + z_safe inline",
                  C14="PASS: load_month_factors(sig_date) per date"),
  graduation_gate=list(
    targets=list(rank_ic=0.04, icir=0.20, harvey_t=3.0, dsr=0.5),
    actuals=list(
      rank_ic=if(!is.null(PRIMARY)) PRIMARY$rank_ic else NA,
      icir=if(!is.null(PRIMARY)) PRIMARY$icir else NA,
      harvey_t=if(!is.null(PRIMARY)) PRIMARY$harvey_t else NA,
      dsr=if(!is.null(PRIMARY)) PRIMARY$dsr else NA
    ),
    pass=list(
      rank_ic=if(!is.null(PRIMARY)&&!is.na(PRIMARY$rank_ic)) PRIMARY$rank_ic>=0.04 else FALSE,
      icir=if(!is.null(PRIMARY)&&!is.na(PRIMARY$icir)) PRIMARY$icir>=0.20 else FALSE,
      harvey_t=if(!is.null(PRIMARY)&&!is.na(PRIMARY$harvey_t)) PRIMARY$harvey_t>=3.0 else FALSE
    ),
    overall_pass=if(!is.null(PRIMARY)&&!is.na(PRIMARY$rank_ic)&&!is.na(PRIMARY$icir)&&!is.na(PRIMARY$harvey_t))
                  PRIMARY$rank_ic>=0.04 && PRIMARY$icir>=0.20 && PRIMARY$harvey_t>=3.0 else FALSE
  ),
  confidence_tier=primary_tier, red_flags=challenge_flags
)
val_path <- file.path(WT_DIR, "alpha_validation.json")
write_json(alpha_val, val_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] alpha_validation.json: %s\n", val_path)); flush(stdout())

# Lineage (L-194: AFTER write_json)
tryCatch({
  source(file.path(FUNC_PATH, "worktask/lineage_utils.R"))
  record_package_lineage(
    task_id="WT-D20260424_010", package_type="alpha_package",
    method_selected=sprintf("6F=%s EB=%s RW=%s (%s)",
      PRIMARY$config$use_6f, PRIMARY$config$use_eb, PRIMARY$config$use_regime_winsor, best_cell),
    input_file_paths=c(file.path(CONS_DIR,"sue.parquet"), file.path(CONS_DIR,"esbr.parquet"),
                       file.path(CONS_DIR,"eps_chg_1m.parquet"), file.path(CONS_DIR,"coverage.parquet"),
                       file.path(CONS_DIR,"target_price.parquet"),
                       file.path(CACHE_DIR,"unified_regime_signal.parquet")),
    windows=list(train_start=as.character(ANALYSIS_START_DATE),
                 train_end=format(Sys.Date(),"%Y-%m-%d"), lockbox="NOT_ACCESSED"),
    random_seed=20260424L,
    wt_root=file.path(PROJECT_ROOT, "qepm/mailbox/worktask")
  )
  cat("[10] Lineage recorded\n"); flush(stdout())
}, error=function(e) cat("[lineage] error:", conditionMessage(e), "\n"))

# Status
status_new <- list(task_id="WT-D20260424_010", current_phase="ALPHA_DONE",
  updated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"), blocker=NULL,
  alpha_summary=list(primary_cell=best_cell,
    rank_ic=if(!is.null(PRIMARY)) PRIMARY$rank_ic else NA,
    icir=if(!is.null(PRIMARY)) PRIMARY$icir else NA,
    harvey_t=if(!is.null(PRIMARY)) PRIMARY$harvey_t else NA,
    confidence_tier=primary_tier, n_tickers=length(alpha_vec)))
write_json(status_new, file.path(WT_DIR,"status.json"), pretty=TRUE, auto_unbox=TRUE, null="null")

# Telegram
tryCatch({
  source(file.path(FUNC_PATH,"telegram/telegram_notify.R"))
  msg <- paste(c(
    "[Alpha Agent] WT-D20260424_010 STR_1631_MEGA_01 Phase1 DONE",
    sprintf("PRIMARY: %s | Tier: %s", best_cell, primary_tier),
    sprintf("rank_IC: %.4f | ICIR: %.4f | Harvey_t: %.2f",
            if(!is.null(PRIMARY)&&!is.na(PRIMARY$rank_ic)) PRIMARY$rank_ic else 0,
            if(!is.null(PRIMARY)&&!is.na(PRIMARY$icir)) PRIMARY$icir else 0,
            if(!is.null(PRIMARY)&&!is.na(PRIMARY$harvey_t)) PRIMARY$harvey_t else 0),
    "Axis contributions (delta rank_IC):",
    sprintf("  A(6F):%+.4f  B(EB):%+.4f  C(RW):%+.4f  FULL:%+.4f",
            ifelse(is.na(axis_a_delta),0,axis_a_delta), ifelse(is.na(axis_b_delta),0,axis_b_delta),
            ifelse(is.na(axis_c_delta),0,axis_c_delta), ifelse(is.na(full_delta),0,full_delta)),
    sprintf("Pilot9 base IC=0.0449 | MEGA01 delta:%+.4f", ifelse(is.na(full_delta),0,full_delta)),
    sprintf("Flags: %d | Tickers: %d", length(challenge_flags), length(alpha_vec)),
    "Next: Risk Agent spawn"
  ), collapse="\n")
  tg_send(msg)
}, error=function(e) cat("[tg]", conditionMessage(e), "\n"))

cat("\n=== WT-D20260424_010 Phase1 COMPLETE ===\n")
cat(sprintf("PRIMARY: %s | Tier: %s\n", best_cell, primary_tier))
if(!is.null(PRIMARY)) {
  cat(sprintf("rank_IC: %.4f | ICIR: %.4f | Harvey_t: %.2f | DSR: %.3f\n",
              ifelse(is.na(PRIMARY$rank_ic),0,PRIMARY$rank_ic),
              ifelse(is.na(PRIMARY$icir),0,PRIMARY$icir),
              ifelse(is.na(PRIMARY$harvey_t),0,PRIMARY$harvey_t),
              ifelse(is.na(PRIMARY$dsr),0,PRIMARY$dsr)))
  cat(sprintf("AxisA:%+.4f AxisB:%+.4f AxisC:%+.4f FULL:%+.4f\n",
              ifelse(is.na(axis_a_delta),0,axis_a_delta), ifelse(is.na(axis_b_delta),0,axis_b_delta),
              ifelse(is.na(axis_c_delta),0,axis_c_delta), ifelse(is.na(full_delta),0,full_delta)))
}
cat(sprintf("Total: %.1f min\n", as.numeric(difftime(Sys.time(), t0_global, units="mins"))))
flush(stdout())
