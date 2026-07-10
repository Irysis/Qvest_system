# 02_harness.R — WT-D20260710_003 joint-design config->metrics harness (sourced)
#
# ROLE BOUNDARY (alpha stage): deterministic sizing rules ONLY (EW / alpha-prop / cap-within / tier /
#   regime-exposure blend). NO covariance matrix estimation, NO optimizer target-weights for admission.
#   HRP/CVaR/ERC/minvar (covariance-based) are DEFERRED to optimizer for a winner — NOT computed here.
# MEASUREMENT: final monthly net-return series routed through contract build_benchmark_compare()
#   (same function canonical_screen_bt/forge use) -> contract-grade PORT_t (NW lag-3). No prod/cumprod
#   self-synthesis of returns. metric_type = "canonical_screen" (generalized-weighting variant).
# Constraints honored per config: long-only, <=25 names, weight [0,0.20], Sum w = 1, 15bps delta cost,
#   liquidity 2e8 (adv20), K200 U KQ150 universe (panel already restricted).

suppressPackageStartupMessages({ library(data.table); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))  # build_benchmark_compare, .nw_t_mean

FAM <- list(
  value    = c("V02_EP","V10_FCF_Yield","V12_Composite_Value"),
  quality  = c("Q01_GPA","Q08_Composite_Quality"),
  momentum = c("M08_Residual_Mom","M09_Composite_Mom"),
  lowrisk  = c("R12_Idiosyncratic_Risk")
)

.zc <- function(x) { s <- sd(x, na.rm=TRUE); if (!is.finite(s) || s<=0) return(x - mean(x,na.rm=TRUE)); (x - mean(x,na.rm=TRUE))/s }

# ---- realized market-vs-EW spread (for regime signal, PIT-safe) ----
# realized return earned in calendar month M = forward Ret_1m recorded at signal month (M - 1 month).
build_regime_signal <- function(bundle) {
  R <- copy(bundle$returns); B <- copy(bundle$bench)
  # earned month = Date + 1 month (Date is signal month; Ret_1m is forward realized)
  addm <- function(d) { d <- as.Date(d); as.Date(paste0(format(d + 32, "%Y-%m"), "-01")) }
  R[, earn := addm(Date)]
  ew <- R[, .(ew_real = mean(Ret_1m, na.rm=TRUE)), by = earn]
  B2 <- copy(B); B2[, earn := addm(Date)]
  bm <- B2[, .(earn, bm_real = BM_Ret)]
  sp <- merge(ew, bm, by = "earn"); setorder(sp, earn)
  sp[, spread := bm_real - ew_real]                    # >0 => mega/cap-w leading
  sp[, spread_tr6 := frollmean(spread, 6, align = "right")]  # trailing 6M realized, known at signal month = earn
  # regime signal usable at SIGNAL month t = trailing spread computed from realized up to month t (earn<=t)
  sp[, .(Date = earn, regime_spread = spread_tr6)]
}

# ---- composite score per month from config ----
build_score <- function(feat, size, cfg) {
  fams <- switch(cfg$factor_design,
    all_ew         = names(FAM),
    value_quality  = c("value","quality"),
    mom_quality    = c("momentum","quality"),
    quality_lowrisk= c("quality","lowrisk"),
    value_mom      = c("value","momentum"),
    cross_family_wtd = names(FAM),
    names(FAM))
  wfam <- if (identical(cfg$factor_design,"cross_family_wtd")) c(value=0.3,quality=0.3,momentum=0.2,lowrisk=0.2) else setNames(rep(1/length(fams), length(fams)), fams)
  X <- copy(feat)
  # within-family EW composite (re-z each factor first per month), then family combine
  fam_cols <- c()
  for (fm in fams) {
    cols <- intersect(FAM[[fm]], names(X))
    if (!length(cols)) next
    for (cc in cols) X[, (cc) := .zc(get(cc)), by = Date]
    fc <- paste0("_fam_", fm)
    X[, (fc) := rowMeans(.SD, na.rm=TRUE), .SDcols = cols]
    X[, (fc) := .zc(get(fc)), by = Date]
    fam_cols <- c(fam_cols, fc)
  }
  X[, score := 0]
  for (fm in fams) { fc <- paste0("_fam_", fm); if (fc %in% names(X)) X[, score := score + wfam[[fm]] * fifelse(is.na(get(fc)), 0, get(fc))] }
  X[, score := .zc(score), by = Date]
  S <- X[, .(Date, Ticker, score)]
  S <- merge(S, size[, .(Date, Ticker, Size)], by = c("Date","Ticker"), all.x = TRUE)
  S <- S[!is.na(score) & !is.na(Size) & Size > 0]
  # exposure control (neutralization) on score, per month cross-section
  ex <- cfg$exposure_ctrl %||% "full"
  if (ex %in% c("size_neutral","residual_ortho")) {
    S[, lsize := log(Size)]
    S[, score := { m <- tryCatch(lm(score ~ lsize)$residuals, error=function(e) score - mean(score)); as.numeric(m) }, by = Date]
  }
  if (ex == "residual_ortho") {
    # additionally strip momentum-family exposure (targets low corr with momentum-heavy incumbent)
    mm <- X[, .(Date, Ticker, mom = get(intersect(paste0("_fam_","momentum"), names(X))[1]) )]
    if ("mom" %in% names(mm)) {
      S <- merge(S, mm, by = c("Date","Ticker"), all.x = TRUE)
      S[is.na(mom), mom := 0]
      S[, score := { m <- tryCatch(lm(score ~ mom)$residuals, error=function(e) score - mean(score)); as.numeric(m) }, by = Date]
    }
  }
  S[, score := .zc(score), by = Date]
  S
}

`%||%` <- function(a,b) if (is.null(a)) b else a

# cap weights (Size) among a held set, capped 0.20, renormalized
.cap_weights <- function(sz) { w <- sz/sum(sz); w <- pmin(w, 0.20); w/sum(w) }
.rank_weights <- function(score) { # alpha-prop: linear rank weights, cap 0.20
  r <- rank(score, ties.method="first"); w <- r/sum(r); w <- pmin(w, 0.20); w/sum(w)
}

# ---- select + weight per month -> W_dt(Date,Ticker,w) ----
build_weights <- function(S, cfg, regime = NULL) {
  top_n <- cfg$top_n %||% 25L
  setorder(S, Date, -Size)
  S[, cap_rank := seq_len(.N), by = Date]
  S[, tier := fifelse(cap_rank<=10L,"MEGA", fifelse(cap_rank<=30L,"MID","OTHER"))]

  sel <- if (identical(cfg$universe_strat,"tier")) {
    q <- cfg$quota  # c(mega, mid, other)
    S[, {
      pick <- function(tt,k){ if(k<=0) return(integer(0)); idx <- which(tier==tt); if(!length(idx)) return(integer(0)); idx[order(-score[idx])][seq_len(min(k,length(idx)))] }
      ii <- c(pick("MEGA",q[1]), pick("MID",q[2]), pick("OTHER",q[3]))
      .SD[ii]
    }, by = Date]
  } else if (identical(cfg$universe_strat,"conc_adaptive")) {
    # H5: N adapts to cross-sectional score dispersion (concentration regime).
    S[, {
      disp <- sd(score, na.rm=TRUE)
      n_t <- if (is.finite(disp)) round(cfg$n_lo + (cfg$n_hi - cfg$n_lo) * pmin(1, pmax(0,(disp - cfg$disp_lo)/(cfg$disp_hi - cfg$disp_lo)))) else top_n
      n_t <- max(cfg$n_lo, min(cfg$n_hi, n_t))
      .SD[order(-score)][seq_len(min(n_t, .N))]
    }, by = Date]
  } else {  # flat
    S[, .SD[order(-score)][seq_len(min(top_n, .N))], by = Date]
  }

  # base weights
  wt <- cfg$weighting %||% "EW"
  Wb <- if (wt == "EW") {
    sel[, .(Ticker, w = 1/.N, tier, Size, score), by = Date]
  } else if (wt == "alpha_prop") {
    sel[, .(Ticker, w = .rank_weights(score), tier, Size, score), by = Date]
  } else if (wt == "cap_within") {
    sel[, .(Ticker, w = .cap_weights(Size), tier, Size, score), by = Date]
  } else if (wt == "tier_weight") {
    tw <- cfg$tier_w %||% c(MEGA=0.4,MID=0.5,OTHER=0.1)
    sel[, {
      present <- names(tw)[names(tw) %in% unique(tier)]
      tot <- sum(tw[present]); alloc <- tw/tot
      w <- numeric(.N)
      for (tt in present) { ii <- which(tier==tt); if(length(ii)) w[ii] <- alloc[[tt]]/length(ii) }
      w <- pmin(w, 0.20); w <- w/sum(w)
      .(Ticker, w = w, tier, Size, score)
    }, by = Date]
  } else sel[, .(Ticker, w = 1/.N, tier, Size, score), by = Date]

  # regime-conditional exposure: blend base weights toward cap-weight of held names
  if (identical(cfg$regime_dyn,"regime_exposure") && !is.null(regime)) {
    Wb <- merge(Wb, regime, by = "Date", all.x = TRUE)
    lam_lo <- cfg$lambda_lo %||% 0.35; lam_hi <- cfg$lambda_hi %||% 1.0
    thr <- cfg$regime_thr %||% 0.0
    Wb[, w_cap := .cap_weights(Size), by = Date]
    # mega-dominant (regime_spread > thr) -> lambda low (closet/cap). dispersed -> lambda high (alpha tilt).
    Wb[, lam := fifelse(is.na(regime_spread), lam_hi,
                        pmax(lam_lo, pmin(lam_hi, lam_hi - (lam_hi-lam_lo)*pmax(0, (regime_spread - thr)/ (cfg$regime_scale %||% 0.02)))))]
    Wb[, w := lam*w + (1-lam)*w_cap, by = Date]
    Wb[, w := w/sum(w), by = Date]
    Wb[, c("w_cap","lam","regime_spread") := NULL]
  }
  Wb[, .(Date, Ticker, w)]
}

# ---- weighted screen -> contract-grade metrics ----
run_weighted_screen <- function(W, bundle, liq_min = 2e8, cost_bps = 15, run_id = "cfg") {
  R <- bundle$returns; B <- bundle$bench; U <- bundle$univ
  # liquidity filter (adv20 at signal month t, C10) — drop names below floor, renorm
  W <- merge(W, U[, .(Date, Ticker, adv20)], by = c("Date","Ticker"), all.x = TRUE)
  W <- W[is.na(adv20) | adv20 >= liq_min]
  W[, w := w/sum(w), by = Date]; W[, adv20 := NULL]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w*Ret_1m)), by = Date]
  # delta-based turnover cost (15bps one-way per traded notional) — same as canonical_screen_bt
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker=character(0), w=numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date==dts[i], .(Ticker,w)]
    m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_c","_p"))
    m[is.na(w_c), w_c:=0]; m[is.na(w_p), w_p:=0]
    traded[i] <- sum(abs(m$w_c - m$w_p)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, ret_net := port_gross - traded*cost_bps/1e4]
  pr <- merge(port[, .(date=Date, ret_net)], B[, .(date=Date, benchmark_ret=BM_Ret)], by="date")
  if (nrow(pr) < 12) return(NULL)
  prt <- data.table(date=pr$date, ret_net=pr$ret_net, frequency="monthly")
  brt <- data.table(date=pr$date, benchmark_ret=pr$benchmark_ret, benchmark_id="KOSPI200")
  bc <- build_benchmark_compare(prt, brt, run_id=run_id, strategy_id=run_id, annualization_factor=12)
  getbc <- function(nm){ v <- bc[metric_name==nm, active_value]; if(!length(v)) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  list(pr = pr, active = active, dates = pr$date,
       port_t = getbc("Portfolio_Alpha_t_NW_lag3"),
       ir = getbc("Information_Ratio"),
       alpha_ann = getbc("Alpha_Annualized"),
       net_sr = mean(active)/sd(active)*sqrt(12),
       turnover_annual = mean(port$traded, na.rm=TRUE)*12,
       n_months = nrow(pr))
}

# calmar + oos_retention diagnostics (PerformanceAnalytics, no self-synthesis)
diag_calmar_oos <- function(net_ret, dates) {
  x <- xts(net_ret, order.by = as.Date(dates))
  cagr <- as.numeric(Return.annualized(x, scale=12, geometric=TRUE))
  mdd  <- as.numeric(maxDrawdown(x))
  calmar <- if (is.finite(mdd) && mdd>0) cagr/mdd else NA_real_
  # oos_retention: anchored 3-split median of net-SR ratio (within-series overfit proxy)
  n <- length(net_ret); sr1 <- function(v){ if(length(v)<6) return(NA); s<-sd(v); if(!is.finite(s)||s<=0) return(NA); mean(v)/s*sqrt(12)}
  rr <- sapply(c(.55,.65,.75), function(f){k<-floor(n*f); if(k<6||n-k<6) return(NA); is_<-sr1(net_ret[1:k]); oo<-sr1(net_ret[(k+1):n]); if(is.na(is_)||is.na(oo)||is_<=0) return(NA); oo/is_})
  list(cagr=cagr, mdd=mdd, calmar=calmar, oos_retention=median(rr, na.rm=TRUE))
}

# book-marginal ΔIR (screening diagnostic, non-binding — final admission = optimizer/governor)
book_marginal <- function(active, dates, bundle, sleeve = 0.15) {
  cand <- data.table(ym = as.integer(format(as.Date(dates),"%Y%m")), a_cand = active)
  inc  <- bundle$inc_active[, .(ym, a_inc = active_inc)]
  m <- merge(cand, inc, by="ym")
  if (nrow(m) < 24) return(list(cor=NA, dIR_sleeve=NA, IR_inc=NA, IR_opt_ceiling=NA, n=nrow(m)))
  ir <- function(v) mean(v)/sd(v)*sqrt(12)
  IR_inc <- ir(m$a_inc); IR_cand <- ir(m$a_cand); rho <- cor(m$a_inc, m$a_cand)
  book_new <- (1-sleeve)*m$a_inc + sleeve*m$a_cand
  dIR <- ir(book_new) - IR_inc
  ceil <- tryCatch(sqrt(pmax(0,(IR_inc^2 - 2*rho*IR_inc*IR_cand + IR_cand^2)/(1-rho^2))), error=function(e) NA)
  list(cor=rho, dIR_sleeve=dIR, IR_inc=IR_inc, IR_cand=IR_cand, IR_opt_ceiling=ceil, n=nrow(m))
}

IS_END  <- as.Date("2018-12-01")
OOS_BEG <- as.Date("2019-01-01")

# ---- top-level: one config -> full metric bundle over a window ----
screen_config <- function(cfg, bundle, regime = NULL, window = c("full","IS","OOS")) {
  window <- match.arg(window)
  feat <- bundle$features; size <- bundle$size
  if (window == "IS")  { feat <- feat[Date <= IS_END]; }
  if (window == "OOS") { feat <- feat[Date >= OOS_BEG]; }
  S <- build_score(feat, size, cfg)
  # liquidity filter BEFORE selection (t-1 adv20, C10) — match canonical_screen_bt semantics
  S <- merge(S, bundle$univ[, .(Date, Ticker, adv20)], by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(adv20) | adv20 >= 2e8]; S[, adv20 := NULL]
  W <- build_weights(S, cfg, regime = regime)
  # enforce hard caps as guard
  W[, w := pmin(w, 0.20), by=Date]; W[, w := w/sum(w), by=Date]
  nmax <- W[, .N, by=Date][, max(N)]
  res <- run_weighted_screen(W, bundle, run_id = cfg$id)
  if (is.null(res)) return(NULL)
  dg <- diag_calmar_oos(res$pr$ret_net, res$pr$date)
  bm <- book_marginal(res$active, res$dates, bundle)
  list(id=cfg$id, H=cfg$H, window=window, n_months=res$n_months, max_names=nmax,
       port_t=res$port_t, ir=res$ir, net_sr=res$net_sr, alpha_ann=res$alpha_ann,
       turnover_annual=res$turnover_annual, calmar=dg$calmar, mdd=dg$mdd, cagr=dg$cagr,
       oos_retention=dg$oos_retention,
       bm_cor=bm$cor, bm_dIR_sleeve=bm$dIR_sleeve, bm_IR_ceiling=bm$IR_opt_ceiling,
       active=res$active, dates=res$dates, pr=res$pr)
}

cat("[harness] loaded — screen_config(), build_score(), build_weights(), run_weighted_screen()\n")
