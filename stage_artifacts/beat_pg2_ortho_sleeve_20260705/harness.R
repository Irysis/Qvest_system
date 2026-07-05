#!/usr/bin/env Rscript
# harness.R — PG2 recon-baseline + orthogonal sleeve candidate eval (beat_pg2_ortho_sleeve_20260705)
#
# 규율: 실측-only. PIT C1~C15. pinned cache 고정(.cache/RAWDATA_pin20260703 + benchmark_pin20260703, IKS200).
#   자체합성 금지: 포트 recon은 extract_book_carrier.R 엔진(run_all.R verbatim) 복제 + canonical_screen_bt().
#   드리프트 상쇄: 모든 candidate/PG2가 동일 pinned cache 통과 → recon-vs-recon marginal.
#
# 산출물(함수):
#   build_pg2_baseline()  : STR_1715 score_eff top-20 tilt × 오버레이(m4×β_R05) net → book IR (≈1.416)
#   eval_book(base_z, sleeve_z, blend_w) : base+sleeve 블렌드 → 동일 오버레이 → net IR (marginal harness)
#   book_active_series()  : PG2 recon net active(−BM) 월시계열 (직교 cor 기준)
#   canon_active(scores)  : candidate top-25 EW long-only canonical active(−BM) + PORT_t
#
# 세그폴트 방어: setDTthreads(1), arrow io 단일, col_select. Rscript -e 한글 금지(본 .R source).

suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if (dir.exists(root)) setwd(root)

RAW_PIN   <- ".cache/RAWDATA_pin20260703.parquet"
BENCH_PIN <- ".cache/benchmark_pin20260703.parquet"
STR1715_ASP <- "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
OVERLAY_CSV <- "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"
FDB_DIR   <- ".cache/factor_db"
OUTDIR    <- "stage_artifacts/beat_pg2_ortho_sleeve_20260705"

source("02_Infrastructure/portfolio/strategy_tilt_weights.R")   # linear_tilt_* / normalize_long_only
source("02_Infrastructure/contracts/backtest_result_contract.R") # build_benchmark_compare (explicit — canonical의 relative source가 nested서 실패)
source("02_Infrastructure/contracts/canonical_screen_bt.R")     # canonical_screen_bt()

# ------------------------------------------------------------------ shared data (loaded once)
.LOAD <- new.env()
load_shared <- function() {
  if (!is.null(.LOAD$raw)) return(invisible())
  raw <- as.data.table(read_parquet(RAW_PIN, col_select = c("Date","Ticker","Close","Vol","Ret")))
  setkey(raw, Date, Ticker); raw[, TradingAmt := Close * Vol]
  .LOAD$raw <- raw
  # daily benchmark → we compound over (start_d,end_d] to align to book eval windows
  b <- as.data.table(read_parquet(BENCH_PIN, col_select = c("Date","BM_Ret")))
  b[, Date := as.Date(Date)]
  .LOAD$bm_daily <- b[!is.na(BM_Ret)]
  invisible()
}

# monthly BM return compounded over (start_d, end_d] — SAME window logic as stock forward returns (no realized_ym lag bug)
bm_month <- function(start_d, end_d) {
  bd <- .LOAD$bm_daily
  seg <- bd[Date > start_d & Date <= end_d, BM_Ret]
  if (length(seg) == 0L) return(0)
  prod(1 + seg) - 1
}

# ------------------------------------------------------------------ walk-forward recon (run_all.R verbatim)
# scores_dt: data.table(Date, Ticker, score, regime_state). Returns per-month gross port return + eval windows.
recon_book_gross <- function(scores_dt, score_col = "score", topn = 20L, minn = 15L,
                             liq = 2e8, lam = 1.5, phi = 3.0, ub = 0.20, ubcr = 0.10) {
  load_shared(); raw <- .LOAD$raw
  A <- as.data.table(scores_dt)
  setnames(A, score_col, "score", skip_absent = TRUE)
  if (!"regime_state" %in% names(A)) A[, regime_state := "NORMAL"]
  sig_dates <- sort(unique(A[!is.na(score), Date]))
  mret <- vector("list", length(sig_dates) - 1L); w_prev <- NULL
  for (i in seq_len(length(sig_dates) - 1L)) {
    sig_label <- sig_dates[i]; next_sig <- sig_dates[i + 1L]
    start_d <- min(raw[Date >= sig_label]$Date)
    if (length(start_d) == 0L || is.na(start_d) || is.infinite(start_d)) next
    end_d <- { nxt <- min(raw[Date >= next_sig]$Date); if (length(nxt)==0L||is.na(nxt)||is.infinite(nxt)) max(raw$Date) else nxt }
    panel_t <- A[Date == sig_label & !is.na(score)]
    if (nrow(panel_t) == 0L) next
    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -score)
    N_elig <- nrow(panel_t); N_tgt <- min(topn, N_elig)
    if (N_tgt < minn && N_elig >= minn) N_tgt <- minn
    if (N_tgt < 5L) next
    picks <- panel_t[seq_len(N_tgt)]
    alpha_t <- setNames(picks$score, picks$Ticker)
    liq_data <- raw[Date >= (start_d - 30L) & Date < start_d, .(ADV = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    liquid <- liq_data[ADV >= liq, Ticker]
    tk_liq <- intersect(names(alpha_t), liquid)
    if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)
    alpha_liq <- alpha_t[tk_liq]
    if (is.null(names(alpha_liq)) || length(alpha_liq) < 5L) next
    ub_use <- if (identical(regime_i, "CRISIS")) min(ub, ubcr) else ub
    w_raw <- tryCatch(linear_tilt_to_penalty_qd(alpha_liq, lambda = lam, w_prev = w_prev, phi = phi, lb = 0, ub = ub_use),
                      error = function(e) linear_tilt_qd(alpha_liq, lambda = lam, lb = 0, ub = ub_use))
    names(w_raw) <- names(alpha_liq)
    w_risk <- normalize_long_only(w_raw, lb = 0, ub = ub_use, target_sum = 1)
    pd <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
    sret <- pd[, .(ret_fwd = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    held <- data.table(Ticker = names(w_risk), weight_strategy = as.numeric(w_risk))
    held <- merge(held, sret, by = "Ticker", all.x = TRUE); held[is.na(ret_fwd), ret_fwd := 0]
    mret[[i]] <- data.table(decision_date = sig_label, eval_date = end_d, regime = regime_i,
                            port_ret_gross = sum(held$weight_strategy * held$ret_fwd),
                            bm_ret = bm_month(start_d, end_d))
    w_prev <- setNames(as.numeric(w_risk), names(w_risk))
  }
  M <- rbindlist(mret, use.names = TRUE, fill = TRUE); setorder(M, eval_date); M
}

# ------------------------------------------------------------------ overlay series (m4 × beta_R05, noLayer4)
load_overlay <- function() {
  ov <- fread(OVERLAY_CSV)
  ov[, anchor_date := as.Date(anchor_date)]
  ov[, ov_mult := m4 * beta_R05]   # noLayer4: β_faith/β_AR 미적용
  ov[, .(return_ym, anchor_date, regime, ov_mult, m4, beta_R05, ret_orig)]
}

# align overlay to recon months by return_ym (overlay return_ym = 수익 실현월 라벨)
apply_overlay <- function(M, ov) {
  M[, ym := format(eval_date, "%Y-%m")]
  ov2 <- copy(ov)[, ym := return_ym]
  X <- merge(M, ov2[, .(ym, ov_mult, ret_orig_ov = ret_orig)], by = "ym", all.x = TRUE)
  X[is.na(ov_mult), ov_mult := 1]
  setorder(X, eval_date)
  X
}

# IR (net_active_recon_v1): mean(active)/sd(active)*sqrt(12), active = ret_net - bm
ir_active <- function(ret_net, bm) {
  active <- ret_net - bm
  mean(active) / stats::sd(active) * sqrt(12)
}
sr_ann <- function(r) mean(r)/stats::sd(r)*sqrt(12)

# ================================================================== PG2 BASELINE
build_pg2_baseline <- function() {
  A <- as.data.table(read_parquet(STR1715_ASP))
  M <- recon_book_gross(A, score_col = "score_eff")
  ov <- load_overlay()
  X <- apply_overlay(M, ov)
  X[, ret_net := port_ret_gross * ov_mult]          # book net (gross carrier × overlay; contract cost는 base 내재)
  X[, active := ret_net - bm_ret]
  ir <- ir_active(X$ret_net, X$bm_ret)
  # frozen-equivalent check: ret_orig × ov_mult from stored series (independent of recon)
  froz <- ov[!is.na(ret_orig)]
  list(monthly = X, book_ir = ir,
       base_gross_sr = sr_ann(X$port_ret_gross),
       net_active_series = data.table(ym = X$ym, eval_date = X$eval_date, active = X$active, ret_net = X$ret_net, bm = X$bm_ret),
       n_months = nrow(X))
}

# eval_book: base_z (data.table Date,Ticker,score) blended with sleeve_z at blend_w on sleeve
#   blend score = (1-blend_w)*z(base) + blend_w*z(sleeve), cross-sectional z per Date. sleeve_z=NULL → pure base recon.
eval_book <- function(base_z, sleeve_z = NULL, blend_w = 0.0, base_col = "score_eff", sleeve_col = "score") {
  B <- as.data.table(base_z)[, .(Date, Ticker, bscore = get(base_col), regime_state = if("regime_state" %in% names(base_z)) regime_state else "NORMAL")]
  if (is.null(sleeve_z) || blend_w == 0) {
    M <- recon_book_gross(B, score_col = "bscore")
  } else {
    S <- as.data.table(sleeve_z)[, .(Date, Ticker, sscore = get(sleeve_col))]
    zc <- function(x) { m <- mean(x, na.rm=TRUE); s <- stats::sd(x, na.rm=TRUE); if (is.na(s)||s==0) rep(0,length(x)) else (x-m)/s }
    B[, bz := zc(bscore), by = Date]
    J <- merge(B, S, by = c("Date","Ticker"), all.x = TRUE)
    J[, sz := { v <- sscore; m <- mean(v, na.rm=TRUE); s <- stats::sd(v, na.rm=TRUE); if (is.na(s)||s==0) rep(0,length(v)) else (v-m)/s }, by = Date]
    J[is.na(sz), sz := 0]
    J[, blend := (1 - blend_w) * bz + blend_w * sz]
    M <- recon_book_gross(J, score_col = "blend")
  }
  ov <- load_overlay(); X <- apply_overlay(M, ov)
  X[, ret_net := port_ret_gross * ov_mult]; X[, active := ret_net - bm_ret]
  list(book_ir = ir_active(X$ret_net, X$bm_ret), base_gross_sr = sr_ann(X$port_ret_gross), monthly = X)
}

# ================================================================== CANDIDATE canonical (top-25 EW, active + PORT_t)
# scores_dt: data.table(Date, Ticker, score). Returns canonical active(−BM) series + PORT_t (NW lag3).
canon_active <- function(scores_dt, top_n = 25L) {
  load_shared(); raw <- .LOAD$raw
  S <- as.data.table(scores_dt)[!is.na(score), .(Date, Ticker, score)]
  sig_dates <- sort(unique(S$Date))
  # forward Ret_1m per (sig, Ticker): compound raw Ret over (start_d, end_d]
  R_list <- vector("list", length(sig_dates)-1L); bm_list <- vector("list", length(sig_dates)-1L)
  for (i in seq_len(length(sig_dates)-1L)) {
    sig <- sig_dates[i]; nxt <- sig_dates[i+1L]
    start_d <- min(raw[Date >= sig]$Date); if (length(start_d)==0L||is.na(start_d)) next
    end_d <- { z <- min(raw[Date >= nxt]$Date); if (length(z)==0L||is.na(z)) max(raw$Date) else z }
    pd <- raw[Date > start_d & Date <= end_d, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by = Ticker]
    pd[, Date := sig]; R_list[[i]] <- pd[, .(Date, Ticker, Ret_1m = ret_fwd)]
    bm_list[[i]] <- data.table(Date = sig, BM_Ret = bm_month(start_d, end_d))
  }
  R <- rbindlist(R_list); BM <- rbindlist(bm_list)
  # liquidity t-1 ADV
  liq_list <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    sig <- sig_dates[i]; start_d <- min(raw[Date >= sig]$Date); if (length(start_d)==0L||is.na(start_d)) next
    ld <- raw[Date >= (start_d-30L) & Date < start_d, .(adv = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    ld[, Date := sig]; liq_list[[i]] <- ld[, .(Date, Ticker, adv)]
  }
  LQ <- rbindlist(liq_list)
  res <- canonical_screen_bt(S[Date %in% R$Date], R, BM, top_n = top_n, cost_bps_oneway = 15,
                             liq_dt = LQ, liq_min = 2e8, run_id = "cand", strategy_id = "cand")
  res
}

# ---- precompute forward returns / BM / liquidity for a fixed monthly sig_date grid (shared across factors) ----
# sig_dates: vector of month-end trading dates (must exist in raw as >= anchors). Returns list(R, BM, LQ).
precompute_grid <- function(sig_dates) {
  load_shared(); raw <- .LOAD$raw
  sig_dates <- sort(unique(sig_dates))
  R_list <- vector("list", length(sig_dates)-1L); bm_list <- vector("list", length(sig_dates)-1L)
  liq_list <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    sig <- sig_dates[i]
    start_d <- min(raw[Date >= sig]$Date); if (length(start_d)==0L||is.na(start_d)) next
    ld <- raw[Date >= (start_d-30L) & Date < start_d, .(adv = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    ld[, Date := sig]; liq_list[[i]] <- ld[, .(Date, Ticker, adv)]
    if (i < length(sig_dates)) {
      nxt <- sig_dates[i+1L]
      end_d <- { z <- min(raw[Date >= nxt]$Date); if (length(z)==0L||is.na(z)) max(raw$Date) else z }
      pd <- raw[Date > start_d & Date <= end_d, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by = Ticker]
      pd[, Date := sig]; R_list[[i]] <- pd[, .(Date, Ticker, Ret_1m = ret_fwd)]
      bm_list[[i]] <- data.table(Date = sig, BM_Ret = bm_month(start_d, end_d))
    }
  }
  list(R = rbindlist(R_list), BM = rbindlist(bm_list), LQ = rbindlist(liq_list))
}

# fast canonical using precomputed grid. scores_dt: (Date, Ticker, score) on the grid's sig_dates.
canon_active_fast <- function(scores_dt, grid, top_n = 25L) {
  S <- as.data.table(scores_dt)[!is.na(score), .(Date, Ticker, score)]
  S <- S[Date %in% grid$R$Date]
  if (nrow(S) == 0L) return(NULL)
  canonical_screen_bt(S, grid$R, grid$BM, top_n = top_n, cost_bps_oneway = 15,
                      liq_dt = grid$LQ, liq_min = 2e8, run_id = "cand", strategy_id = "cand")
}

if (identical(Sys.getenv("HARNESS_SELFTEST"), "1")) {
  cat("[harness] self-test: PG2 baseline recon ...\n")
  bl <- build_pg2_baseline()
  cat(sprintf("[harness] PG2 recon book_ir = %.4f (target 1.416) | base_gross_SR = %.3f | n_months = %d\n",
              bl$book_ir, bl$base_gross_sr, bl$n_months))
  saveRDS(bl, file.path(OUTDIR, "pg2_baseline.rds"))
  fwrite(bl$net_active_series, file.path(OUTDIR, "pg2_net_active_series.csv"))
  cat("[harness] saved pg2_baseline.rds + pg2_net_active_series.csv\n")
}
