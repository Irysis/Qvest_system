## ============================================================================
## eval_defense.R — PG2 defense-sleeve book-level evaluation harness.
##
## eval_defense(defense_spec, regime_map=NULL) reconstructs the DEFENSE sleeve
## from a cached factor panel, holds CORE fixed (stored score_core_z), rebuilds
## the noLayer4 book, and returns book metrics + episode active + oos_retention.
##
## defense_spec: list(factors=<chr vec of panel factors>, weights=<named num or NULL=EW>)
## regime_map:   optional named list regime -> defense_spec (candidate-6 국면조건부).
##               Keys in {BULL,NORMAL,CAUTION,CRISIS}; missing regimes use `defense_spec`.
##
## CONSTRUCTION (canonical, factor_engine_proposal.R L410-459 verbatim):
##   def_z: winsor_z(2.5σ) each aligned Z over post-filter scope, EW(or w) sum -> Score_Defense
##          -> per-sig_date x-sec z (na.rm). NA in a factor -> NA contribution (canonical).
##   score_eff_new = 0.65*score_core_z(STORED) + 0.35*def_z_new
## BOOK (extract_book_carrier.R L57-99 verbatim):
##   walk-forward top-20 by score_eff -> liq PIT t-30..t-1 (>=2e8) ->
##   linear_tilt_to_penalty_qd(λ1.5,φ3,ub0.20/CRISIS0.10) -> forward prod(1+Ret)-1
##   = base_book_gross (ret_orig).
## OVERLAY (recompute_bt_noLayer4_clean.R L23-24): stored beta_R05 x m4 (alpha-independent,
##   reused verbatim) -> ret_noL4 = beta_R05*m4*ret_orig - |Δbeta_R05|*15bps.
## METRICS: contract build_metrics + build_benchmark_compare (annualization=12), pinned IKS200.
## oos_retention: essence_score v2 (anchored 3-split median). PORT_t = NW lag-3 authoritative.
##
## Self-synth 금지: 포트수익=carrier prod(1+Ret)-1 (run_all verbatim), 지표=contract 함수.
## Segfault guard: setDTthreads(1), read_parquet col_select, no open_dataset, taskkill 사전.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
ED_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || all(is.na(a))) b else a

source(file.path(ED_ROOT,"02_Infrastructure/portfolio/strategy_tilt_weights.R"))
source(file.path(ED_ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ED_ROOT,"02_Infrastructure/contracts/essence_score.R"))

## ---- one-time cached inputs (module-level, load once) ----------------------
.ED <- new.env()
## PANEL source: "regdir" (registry fixed direction, vintage-stable — DEFAULT) or
##               "ic" (legacy IC-sign panel, for drift comparison only).
.ED$PANEL_SRC <- Sys.getenv("ED_PANEL_SRC", "regdir")
ed_init <- function(force=FALSE){
  if (!force && isTRUE(.ED$ready)) return(invisible())
  suppressWarnings(try(arrow::set_io_thread_count(2L), silent=TRUE))  ## io>=2 (io=1 hangs on parquet)
  ## LOCAL-staged parquet reads (OneDrive mmap segfault avoidance — byte-identical copies).
  SC <- Sys.getenv("ED_LOCAL_DIR",
          "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad")
  OUT <- file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize")
  panel_local <- if (identical(.ED$PANEL_SRC,"ic")) file.path(SC,"defense_factor_panel_ic_local.parquet")
                 else file.path(SC,"defense_factor_panel_regdir_local.parquet")
  panel_file  <- if (identical(.ED$PANEL_SRC,"ic")) "defense_factor_panel.parquet"
                 else "defense_factor_panel_regdir.parquet"
  panel_path <- if (file.exists(panel_local)) panel_local else file.path(OUT,panel_file)
  .ED$PANEL <- as.data.table(read_parquet(panel_path))
  .ED$PANEL[, sig_date := as.Date(sig_date)]
  cat(sprintf("[ed_init] PANEL_SRC=%s path=%s rows=%d\n", .ED$PANEL_SRC, panel_path, nrow(.ED$PANEL)))
  ap_local <- file.path(SC,"alpha_scores_local.parquet")
  ap_path <- if (file.exists(ap_local)) ap_local else file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
  ap <- as.data.table(read_parquet(ap_path))
  ap[, Date := as.Date(Date)]
  .ED$AP <- ap[, .(Date, Ticker, score_core_z, score_defense_z, score_eff, regime_state)]
  ## GRID variant: consume the arm-INVARIANT precomputed carrier grid instead of scanning
  ## the 419MB RAW 271x per arm (repeated full-column logical scans segfault under
  ## fragmentation). Grid = {window(sig_label,start_d,end_d), fwd(sig_label,Ticker,ret_fwd),
  ## adv(sig_label,Ticker,ADV)} built from the SAME pinned local RAW (precompute_carrier_grid.R).
  ## Forward returns + liquidity are spec-invariant, so every arm shares an identical substrate;
  ## only picks/weights differ. Verified to reproduce the recon baseline (validate_grid.R).
  GRID_PATH <- Sys.getenv("ED_GRID_PATH",
                 file.path("C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad","carrier_grid.rds"))
  cat(sprintf("[ed_init] GRID from: %s\n", GRID_PATH)); flush.console()
  .ED$GRID <- readRDS(GRID_PATH)
  cat(sprintf("[ed_init] GRID windows=%d fwd=%d adv=%d\n",
              nrow(.ED$GRID$window), nrow(.ED$GRID$fwd), nrow(.ED$GRID$adv))); flush.console()
  ## stored overlay series (beta_R05 x m4) + anchor dates — 5-panel (alpha-independent, reused)
  p5 <- fread(file.path(ED_ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
  p5[, anchor_date := as.Date(anchor_date)]; setorder(p5, realized_ym)
  .ED$P5 <- p5[, .(realized_ym, anchor_date, regime5=regime, beta_R05, m4, ret_orig_book=ret_orig)]
  ## PINNED benchmark (IKS200) — anchored month cumulation. pin20260703 (local-staged).
  bm_local <- file.path(SC,"benchmark_pin20260703_local.parquet")
  BM_PIN <- if (file.exists(bm_local)) bm_local else file.path(ED_ROOT,".cache/benchmark_pin20260703.parquet")
  bm <- as.data.table(read_parquet(BM_PIN)); bm[, Date := as.Date(Date)]
  bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
  .ED$BM_X <- xts(bm$BM_Ret, order.by=bm$Date)
  ## drawdown episodes
  ep <- fread(file.path(ED_ROOT,"stage_artifacts/pg2_defense_drawdown/episodes.csv"))
  .ED$EPI <- ep
  .ED$ready <- TRUE
  invisible()
}

.winsor_z <- function(x, sigma=2.5){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}

## ---- reconstruct def_z for one sig_date given a spec ------------------------
## spec: list(factors=chr, weights=named num|NULL). scope = alpha tickers (already pinned in panel).
.recon_defz_one <- function(SD, spec){
  facs <- spec$factors
  sub <- .ED$PANEL[sig_date==SD & Factor_Name %in% facs]
  if (!nrow(sub)) return(NULL)
  fw <- dcast(sub, Ticker ~ Factor_Name, value.var="Z_Aligned", fill=NA_real_)
  facp <- intersect(facs, names(fw))
  if (!length(facp)) return(NULL)
  w <- spec$weights %||% setNames(rep(1/length(facs), length(facs)), facs)
  w <- w[facs]; w[is.na(w)] <- 0
  # canonical: EW over the *full* spec factor set (theta on all named), NA propagates
  score_vec <- rep(0, nrow(fw))
  for (fn in facp){
    cv <- fw[[fn]]; if (all(is.na(cv))) next
    cw <- .winsor_z(cv, 2.5)
    score_vec <- score_vec + as.numeric(w[fn]) * cw
  }
  fw[, Score_Defense := score_vec]
  fw[, def_z := .zc(Score_Defense)]
  fw[, .(sig_date=SD, Ticker, def_z)]
}

## ---- full def_z panel across all sig_dates (regime-aware) -------------------
.build_defz <- function(defense_spec, regime_map=NULL){
  sds <- sort(unique(.ED$PANEL$sig_date))
  out <- vector("list", length(sds))
  for (i in seq_along(sds)){
    SD <- sds[i]
    spec <- defense_spec
    if (!is.null(regime_map)){
      reg <- .ED$AP[Date==SD, regime_state][1]
      if (!is.na(reg) && !is.null(regime_map[[reg]])) spec <- regime_map[[reg]]
    }
    out[[i]] <- .recon_defz_one(SD, spec)
  }
  rbindlist(out, use.names=TRUE, fill=TRUE)
}

## ---- carrier walk-forward (GRID) : base_book_gross per month from score_eff -----
## Logic verbatim from RAW version; forward returns/liquidity sourced from precomputed grid.
## Only sig_dates present in BOTH score_dt and grid$window are evaluated (the walk needs a
## next-window boundary; grid$window already encodes start/end per sig_label). w_prev chained.
.carrier_book <- function(score_dt){
  G <- .ED$GRID
  win <- G$window
  fwd <- G$fwd; setkey(fwd, sig_label, Ticker)
  adv <- G$adv; setkey(adv, sig_label, Ticker)
  ## per-window start/end lookup by exact sig_label (Date) match
  win_map <- setNames(win$end_d, as.character(win$sig_label))
  win_sigs <- win$sig_label
  sig_dates <- sort(unique(score_dt[!is.na(score_eff), Date]))
  sig_dates <- sig_dates[sig_dates %in% win_sigs]
  mret <- vector("list", length(sig_dates)); w_prev <- NULL
  for (i in seq_along(sig_dates)){
    sig_label <- sig_dates[i]
    end_d <- win_map[[as.character(sig_label)]]
    if (is.null(end_d) || is.na(end_d)) next
    end_d <- as.Date(end_d, origin="1970-01-01")
    panel_t <- score_dt[Date==sig_label & !is.na(score_eff)]
    if (!nrow(panel_t)) next
    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -score_eff)
    N_elig <- nrow(panel_t); N_tgt <- min(20L, N_elig)
    if (N_tgt < 15L && N_elig >= 15L) N_tgt <- 15L
    if (N_tgt < 5L) next
    picks <- panel_t[seq_len(N_tgt)]
    alpha_t <- setNames(picks$score_eff, picks$Ticker)
    ## liquidity: grid ADV for this window (binary search on keyed sig_label)
    sl <- sig_label
    liq_data <- adv[J(sl), .(Ticker, ADV), nomatch=NULL]
    liquid <- liq_data[ADV >= 2e8, Ticker]
    tk_liq <- intersect(names(alpha_t), liquid)
    if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)
    alpha_liq <- alpha_t[tk_liq]
    if (is.null(names(alpha_liq)) || length(alpha_liq) < 5L) next
    ub_use <- if (identical(regime_i,"CRISIS")) 0.10 else 0.20
    w_raw <- tryCatch(
      linear_tilt_to_penalty_qd(alpha_liq, lambda=1.5, w_prev=w_prev, phi=3.0, lb=0, ub=ub_use),
      error=function(e) linear_tilt_qd(alpha_liq, lambda=1.5, lb=0, ub=ub_use))
    names(w_raw) <- names(alpha_liq)
    w_risk <- normalize_long_only(w_raw, lb=0, ub=ub_use, target_sum=1)
    ## forward returns: grid fwd for this window (binary search on keyed sig_label)
    sret <- fwd[J(sl), .(Ticker, ret_fwd), nomatch=NULL]
    held <- data.table(Ticker=names(w_risk), weight_strategy=as.numeric(w_risk))
    held <- merge(held, sret, by="Ticker", all.x=TRUE); held[is.na(ret_fwd), ret_fwd:=0]
    mret[[i]] <- data.table(decision_date=sig_label, eval_date=end_d, regime=regime_i,
                            n_held=nrow(held), port_ret_gross_recon=sum(held$weight_strategy*held$ret_fwd))
    w_prev <- setNames(as.numeric(w_risk), names(w_risk))
  }
  rbindlist(mret, use.names=TRUE, fill=TRUE)
}

## ---- MAIN ------------------------------------------------------------------
eval_defense <- function(defense_spec, regime_map=NULL, label="cand"){
  ed_init()
  ## 1. def_z_new
  defz <- .build_defz(defense_spec, regime_map)
  ## 2. score_eff_new = 0.65*stored_core_z + 0.35*def_z_new
  sc <- merge(.ED$AP[, .(Date, Ticker, score_core_z, regime_state, stored_defz=score_defense_z, stored_eff=score_eff)],
              defz[, .(Date=sig_date, Ticker, def_z)], by=c("Date","Ticker"), all.x=TRUE)
  sc[, score_eff := 0.65*score_core_z + 0.35*def_z]
  ## 3. carrier walk-forward -> base_book_gross
  cb <- .carrier_book(sc[, .(Date, Ticker, score_eff, regime_state)])
  ## 4. join stored overlay (beta_R05 x m4) by anchor month; ret_noL4
  cb[, realized_ym := format(eval_date, "%Y-%m")]
  cb[, decision_ym := format(decision_date, "%Y-%m")]
  # 5-panel keyed by realized_ym; base_book_gross indexed by eval_date realized month
  mp <- merge(.ED$P5, cb[, .(realized_ym, base_gross=port_ret_gross_recon)], by="realized_ym", all.x=TRUE)
  setorder(mp, realized_ym)
  # use RECON base_gross where available, else book ret_orig (edge months)
  mp[, ret_orig_use := ifelse(is.finite(base_gross), base_gross, ret_orig_book)]
  COST <- 0.0015
  mp[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill=1.0))]
  mp[, ret_noL4 := beta_R05*m4*ret_orig_use - dR05*COST]
  mp <- mp[is.finite(ret_noL4)]
  ## 5. benchmark anchored cumulation on pinned IKS200
  a <- mp$anchor_date; bmw <- rep(NA_real_, nrow(mp)); bm_x <- .ED$BM_X
  for (i in 2:nrow(mp)){ seg <- bm_x[index(bm_x) > a[i-1] & index(bm_x) <= a[i]]; if (nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
  bmw[1] <- 0
  ## 6. contract shape + metrics
  RID <- paste0("ED_",label); SID <- RID
  pr <- data.table(run_id=RID, strategy_id=SID, date=mp$anchor_date, frequency="monthly",
                   ret_gross=mp$ret_noL4, ret_net=mp$ret_noL4, risk_free_ret=0,
                   excess_ret_net=mp$ret_noL4, turnover=NA_real_, cost_ret=0,
                   cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
  br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=mp$anchor_date,
                   benchmark_ret=bmw, benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)),
                   risk_free_ret=0, benchmark_excess_ret=bmw, frequency="monthly")
  nav_v <- cumprod(1 + pr$ret_net)
  nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly",
                        nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
  hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
  metrics <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
  bcmp    <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
  gv <- function(dt, mn){ v <- dt[metric_name==mn]$metric_value; if(length(v)) v[1] else NA_real_ }
  x_net <- xts(pr$ret_net, order.by=pr$date)
  SR_geo <- as.numeric(table.AnnualizedReturns(x_net, scale=12)[3,1])
  PORT_t <- bcmp[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1]
  IR     <- bcmp[metric_name=="Information_Ratio"]$active_value[1]
  MDD    <- gv(metrics, "MDD"); CALMAR <- gv(metrics, "Calmar"); CAGR <- gv(metrics, "CAGR")
  ## 7. episode active (book active = strat cum - bench cum over episode window)
  epi <- .ED$EPI; mp2 <- copy(mp); mp2[, ym := realized_ym]
  epi_out <- rbindlist(lapply(seq_len(nrow(epi)), function(k){
    pk <- epi$peak_ym[k]; tr <- epi$trough_ym[k]
    w <- mp2[ym >= pk & ym <= tr]
    if (!nrow(w)) return(data.table(episode=epi$name[k], strat_cum=NA_real_, bench_cum=NA_real_, active=NA_real_))
    sc_cum <- prod(1+w$ret_noL4)-1
    bc_cum <- prod(1+ifelse(is.na(bmw[match(w$realized_ym, mp$realized_ym)]),0,bmw[match(w$realized_ym, mp$realized_ym)]))-1
    data.table(episode=epi$name[k], strat_cum=sc_cum, bench_cum=bc_cum, active=sc_cum-bc_cum)
  }), fill=TRUE)
  ## 8. oos_retention via essence_score v2
  bt_stub <- list(period_returns=pr, benchmark_returns=br,
                  metrics=metrics, benchmark_compare=bcmp,
                  drawdowns=data.table(), nav=nav_tbl)
  es <- tryCatch(essence_score(bt_stub, n_trials_cumulative=1, selection_type="chain",
                               oos_stat_version="v2"), error=function(e) NULL)
  oos_ret <- if (!is.null(es)) es$oos_retention %||% NA_real_ else NA_real_
  list(
    label=label, n_periods=nrow(pr),
    SR=SR_geo, MDD=MDD, calmar=CALMAR, CAGR=CAGR, PORT_t=PORT_t, IR=IR,
    oos_retention=oos_ret,
    defz=defz, score_eff=sc[, .(Date, Ticker, score_eff, def_z, stored_defz, stored_eff, score_core_z)],
    monthly=mp[, .(realized_ym, anchor_date, regime5, beta_R05, m4, ret_orig_use, ret_orig_book, ret_noL4)],
    benchmark=data.table(realized_ym=mp$realized_ym, bmw=bmw),
    episodes=epi_out, metrics=metrics, benchmark_compare=bcmp
  )
}

cat("[eval_defense.R] Loaded — eval_defense(defense_spec, regime_map=NULL, label=)\n")
