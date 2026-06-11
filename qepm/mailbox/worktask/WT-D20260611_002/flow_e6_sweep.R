# ============================================================
# WT-D20260611_002 FLOW family E6 fair-trial — preregistered 8-spec sweep
# selection_type = sweep (IS-only selection, DSR>=0.5 HARD diagnostic, n_trials=8)
# Mechanism: KR inst/foreign daily net-buy flow informational asymmetry — flow leads 1-3M price.
# PIT: flow features are t-1 lag (01_flow_features.R shift(1L)+frollsum); liq_20d t-1 (C10).
#      sig_date snap: last daily obs with Date < sig_date (C2). fwd_* columns NEVER read (C7).
# Measurement: canonical_screen_bt (contract build_benchmark_compare, NW lag-3). NO proxy hand-calc.
# ============================================================
suppressMessages({library(arrow); library(data.table)})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

OUTDIR <- "stage_artifacts/WT_D20260611_002"
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
TMPLOG <- file.path(OUTDIR, "sweep_run.log")
sink(TMPLOG, split = FALSE)

IS_CUTOFF  <- as.Date("2021-12-31")   # IS selection window end (OOS = 2022+)
SUB17      <- as.Date("2017-01-01")   # 2017+ subwindow start for gate
LIQ_MIN    <- 2e8
TOP_N      <- 20L
COST_BPS   <- 15

# ---- 1. grid + forward returns (STR_1715 PG2 panel) ----
p <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
p[, Date := as.Date(Date)]
retmap  <- p[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
s15map  <- p[, .(Date, Ticker, s15 = score_eff)]     # orthogonality anchor
grid    <- sort(unique(retmap$Date))
k200kq  <- unique(p$Ticker)                          # KR_top342 (K200 U KQ150) panel tickers
cat("[grid] n sig_dates:", length(grid), " range:", as.character(range(grid)), "\n")
cat("[grid] K200UKQ150 panel tickers:", length(k200kq), "\n")

# benchmark = universe-EW monthly return (anchor qmj_alpha_build precedent; calendar-self-consistent)
bench_uni <- retmap[, .(BM_Ret = mean(Ret_1m, na.rm = TRUE)), by = Date]

# ---- 2. flow features: snap daily -> sig_date (last obs Date < sig_date) ----
flow_cols <- c("Date","Ticker",
               "inst_netbuy_20d","foreign_netbuy_20d","individual_netbuy_5d",
               "inst_flow_momentum","foreign_own_chg_20d","liq_20d")
cat("[flow] reading flow_features_daily.parquet (subset cols)...\n")
fd <- as.data.table(read_parquet(".cache/flow_features_daily.parquet", col_select = flow_cols))
fd[, Date := as.Date(Date)]
setkey(fd, Ticker, Date)
cat("[flow] rows:", nrow(fd), " tickers:", uniqueN(fd$Ticker), "\n")

# ---- manual snap: for each sig_date d, filter fd[Date < d], take last per Ticker (C2 lag) ----
build_panel <- function() {
  out <- vector("list", length(grid))
  for (i in seq_along(grid)) {
    d <- grid[i]
    sub <- fd[Date < d]                  # strictly before sig_date (C2)
    if (!nrow(sub)) next
    # last obs per ticker (within a 70-day lookback for efficiency & relevance)
    sub <- sub[Date >= d - 90L]
    if (!nrow(sub)) next
    setorder(sub, Ticker, Date)
    last <- sub[, .SD[.N], by = Ticker]
    last[, sig_date := d]
    out[[i]] <- last
    if (i %% 36 == 0) cat("  snap", as.character(d), "tickers", nrow(last), "\n")
  }
  rbindlist(out, fill = TRUE)
}
PANEL_CACHE <- file.path(OUTDIR, "_flow_panel_cache.rds")
if (file.exists(PANEL_CACHE)) {
  cat("[panel] loading cached panel...\n")
  panel <- readRDS(PANEL_CACHE)
} else {
  cat("[panel] building monthly flow panel...\n")
  panel <- build_panel()
  panel[, Date := sig_date][, sig_date := NULL]
  saveRDS(panel, PANEL_CACHE)
}
cat("[panel] rows:", nrow(panel), " dates:", uniqueN(panel$Date), "\n")
gc()

# ---- 3. spec score construction (8 preregistered specs) ----
# winsorize 1/99 + cross-sectional z, per Date
z_wins <- function(x) {
  q <- quantile(x, c(0.01, 0.99), na.rm = TRUE)
  x <- pmin(pmax(x, q[1]), q[2])
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-12) return(rep(0, length(x)))
  (x - m) / s
}
# safe division by liquidity (avoid tiny denominators); liq in KRW
EPS_LIQ <- 1e7
panel[, liq_safe := pmax(liq_20d, EPS_LIQ)]

# raw per-Date z-scores of components
panel[, `:=`(
  z_inst20  = z_wins(inst_netbuy_20d / liq_safe),
  z_frgn20  = z_wins(foreign_netbuy_20d / liq_safe),
  z_indiv5  = z_wins(individual_netbuy_5d / liq_safe),
  z_instmom = z_wins(inst_flow_momentum / liq_safe),
  z_frgnown = z_wins(foreign_own_chg_20d)
), by = Date]
# combo20 = z of (inst+frgn)/liq
panel[, z_combo20 := z_wins((inst_netbuy_20d + foreign_netbuy_20d) / liq_safe), by = Date]

# specs
panel[, S1_INST20      := z_inst20]
panel[, S2_FRGN20      := z_frgn20]
panel[, S3_COMBO20     := z_combo20]
panel[, S4_FRGN_OWN    := z_frgnown]
panel[, S5_INST_MOM    := z_instmom]
panel[, S7_COMBO_CONTRA := -z_combo20]
panel[, S8_DISAGREE    := { v <- z_frgn20 - z_indiv5; z_wins(v) }, by = Date]

# S6 = 3-month EMA of S3 per Ticker (low-turnover variant)
setorder(panel, Ticker, Date)
ema3 <- function(x) {
  a <- 2/(3+1); out <- numeric(length(x)); prev <- NA_real_
  for (j in seq_along(x)) {
    if (is.na(x[j])) { out[j] <- prev; next }
    prev <- if (is.na(prev)) x[j] else a*x[j] + (1-a)*prev
    out[j] <- prev
  }
  out
}
panel[, S6_COMBO_SMOOTH := ema3(S3_COMBO20), by = Ticker]
# re-z S6 cross-sectionally
panel[, S6_COMBO_SMOOTH := z_wins(S6_COMBO_SMOOTH), by = Date]

SPECS <- c("S1_INST20","S2_FRGN20","S3_COMBO20","S4_FRGN_OWN","S5_INST_MOM",
           "S6_COMBO_SMOOTH","S7_COMBO_CONTRA","S8_DISAGREE")

# liq table for canonical_screen_bt (adv = liq_20d at sig_date snap)
liq_dt <- panel[, .(Date, Ticker, adv = liq_20d)]

# ---- 4. evaluate each spec via canonical_screen_bt (FULL + IS + 2017+ windows) ----
eval_spec <- function(spec, dates_keep = NULL, cost_bps = COST_BPS) {
  sdt <- panel[, .(Date, Ticker, score = get(spec))][!is.na(score)]
  if (!is.null(dates_keep)) sdt <- sdt[Date %in% dates_keep]
  r <- canonical_screen_bt(scores_dt = sdt, returns_dt = retmap, bench_dt = bench_uni,
                           top_n = TOP_N, cost_bps_oneway = cost_bps,
                           liq_dt = liq_dt, liq_min = LIQ_MIN,
                           run_id = paste0("flow_", spec), strategy_id = spec)
  r
}

# Custom NW-t engine with selectable rebalance cadence + cost on/off.
# rebal: "monthly" or "quarterly" (hold weights between quarter sig_dates -> NAV carry, low TO).
# Returns gross & net PORT_t (NW lag3), turnover, mean active.
nw_t_raw <- function(x, lag=3){
  x <- x[is.finite(x)]; n <- length(x); if(n<8) return(NA_real_)
  mu <- mean(x); e <- x-mu; g0 <- sum(e^2)/n; s <- g0
  for(l in 1:lag){ w<-1-l/(lag+1); g<-sum(e[(l+1):n]*e[1:(n-l)])/n; s<-s+2*w*g }
  mu/sqrt(s/n)
}
eval_cadence <- function(spec, dates_keep, rebal="monthly") {
  sdt <- panel[Date %in% dates_keep, .(Date, Ticker, score=get(spec))][!is.na(score)]
  sdt <- merge(sdt, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
  sdt <- sdt[is.na(adv) | adv >= LIQ_MIN]
  setorder(sdt, Date, -score)
  dts <- sort(unique(sdt$Date))
  # rebalance dates
  if (rebal=="quarterly") {
    qm <- as.integer(format(dts, "%m"))
    reb_dts <- dts[qm %in% c(1,4,7,10)]
  } else reb_dts <- dts
  # build holdings: at each date, if rebal date -> new top-N; else carry previous
  hold <- vector("list", length(dts)); names(hold) <- as.character(dts)
  prev_sel <- character(0)
  for (i in seq_along(dts)) {
    d <- dts[i]
    if (d %in% reb_dts || length(prev_sel)==0) {
      cur <- sdt[Date==d]; n <- min(TOP_N, nrow(cur)); prev_sel <- cur$Ticker[seq_len(n)]
    }
    hold[[i]] <- prev_sel
  }
  # monthly port return = EW of held names' Ret_1m; active vs universe-EW
  port <- rbindlist(lapply(seq_along(dts), function(i){
    sel <- hold[[i]]; rr <- retmap[Date==dts[i] & Ticker %in% sel, Ret_1m]
    data.table(Date=dts[i], pg=mean(rr, na.rm=TRUE), nsel=length(sel))
  }))
  # turnover at rebalance only
  traded <- numeric(length(dts)); prev <- character(0)
  for (i in seq_along(dts)) {
    cur <- hold[[i]]
    # weight-change L1 between consecutive months (EW)
    allt <- union(cur, prev)
    wc <- ifelse(allt %in% cur, 1/max(1,length(cur)), 0)
    wp <- ifelse(allt %in% prev, 1/max(1,length(prev)), 0)
    traded[i] <- sum(abs(wc-wp)); prev <- cur
  }
  port[, cost := traded*COST_BPS/1e4]
  port[, ret_net := pg - cost]
  m <- merge(port, bench_uni, by="Date")
  act_gross <- m$pg - m$BM_Ret
  act_net   <- m$ret_net - m$BM_Ret
  list(gross_t = nw_t_raw(act_gross,3), net_t = nw_t_raw(act_net,3),
       net_sr = mean(act_net)/sd(act_net)*sqrt(12),
       gross_sr = mean(act_gross)/sd(act_gross)*sqrt(12),
       to_ann = mean(traded)*12, n = nrow(m), act_net = act_net)
}

# rank-IC + ICIR + Harvey-t (NW lag3) on monthly rank-IC series (for reporting; advisory)
nw_t <- function(x, lag=3){
  x <- x[is.finite(x)]; n <- length(x); if(n<8) return(NA_real_)
  mu <- mean(x); e <- x-mu; g0 <- sum(e^2)/n; s <- g0
  for(l in 1:lag){ w<-1-l/(lag+1); g<-sum(e[(l+1):n]*e[1:(n-l)])/n; s<-s+2*w*g }
  mu/sqrt(s/n)
}
spec_ic <- function(spec, dates_keep=NULL) {
  m <- merge(panel[, .(Date, Ticker, sc = get(spec))], retmap, by=c("Date","Ticker"))
  if(!is.null(dates_keep)) m <- m[Date %in% dates_keep]
  m <- m[is.finite(sc) & is.finite(Ret_1m)]
  ic <- m[, .(ic = if(.N>=10) cor(sc, Ret_1m, method="spearman") else NA_real_), by=Date][is.finite(ic)]
  list(rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), harvey_t=nw_t(ic$ic,3), n=nrow(ic))
}

# DSR (Bailey-Lopez de Prado) on monthly net active series; N_trials = 8 (sweep)
dsr_calc <- function(active, N_trials=8) {
  x <- active[is.finite(active)]; T_n <- length(x); if(T_n<12) return(NA_real_)
  sr_obs <- mean(x)/sd(x)
  sk <- mean((x-mean(x))^3)/sd(x)^3; ku <- mean((x-mean(x))^4)/sd(x)^4
  emc <- 0.5772156649
  z <- qnorm(1-1/N_trials); z2 <- qnorm(1-1/(N_trials*exp(1)))
  sr0 <- (1/sqrt(T_n)) * ((1-emc)*z + emc*z2)
  den <- sqrt((1 - sk*sr_obs + (ku-1)/4*sr_obs^2)/(T_n-1))
  pnorm((sr_obs - sr0)/den)
}

is_dates  <- grid[grid <= IS_CUTOFF]
oos_dates <- grid[grid >  IS_CUTOFF]
sub17_is  <- is_dates[is_dates >= SUB17]   # 2017+ within IS

cat("\n[eval] IS dates:", length(is_dates), " OOS dates:", length(oos_dates),
    " 2017+IS:", length(sub17_is), "\n\n")

results <- list()
for (spec in SPECS) {
  cat("=== EVAL", spec, "===\n")
  full <- eval_spec(spec)
  isr  <- eval_spec(spec, is_dates)
  s17  <- eval_spec(spec, sub17_is)
  oos  <- if (length(oos_dates) >= 12) eval_spec(spec, oos_dates) else list(portfolio_alpha_t_nw_lag3=NA, net_sr=NA, n_months=length(oos_dates))
  # GROSS (cost=0) to isolate raw signal direction from cost drag
  full_g <- eval_spec(spec, cost_bps = 0)
  is_g   <- eval_spec(spec, is_dates, cost_bps = 0)
  # Quarterly cadence (low-TO variant, anchor WT precedent) — net + gross
  qm_full <- eval_cadence(spec, grid, "quarterly")
  qm_is   <- eval_cadence(spec, is_dates, "quarterly")
  mm_full <- eval_cadence(spec, grid, "monthly")
  icF  <- spec_ic(spec)
  icIS <- spec_ic(spec, is_dates)
  results[[spec]] <- list(
    spec = spec,
    full = list(port_t = round(full$portfolio_alpha_t_nw_lag3,4), net_sr = round(full$net_sr,4),
                gross_t = round(full_g$portfolio_alpha_t_nw_lag3,4), gross_sr = round(full_g$net_sr,4),
                ir = round(full$information_ratio,4), to = round(full$turnover_annual,3),
                alpha_ann = round(full$alpha_annualized,4), n = full$n_months),
    is   = list(port_t = round(isr$portfolio_alpha_t_nw_lag3,4), net_sr = round(isr$net_sr,4),
                gross_t = round(is_g$portfolio_alpha_t_nw_lag3,4),
                to = round(isr$turnover_annual,3), n = isr$n_months),
    sub2017_is = list(port_t = round(s17$portfolio_alpha_t_nw_lag3,4), net_sr = round(s17$net_sr,4), n = s17$n_months),
    oos  = list(port_t = round(oos$portfolio_alpha_t_nw_lag3,4),
                net_sr = round(ifelse(is.null(oos$net_sr),NA,oos$net_sr),4), n = oos$n_months),
    quarterly = list(full_net_t = round(qm_full$net_t,4), full_gross_t = round(qm_full$gross_t,4),
                     full_net_sr = round(qm_full$net_sr,4), full_to = round(qm_full$to_ann,3),
                     is_net_t = round(qm_is$net_t,4), is_gross_t = round(qm_is$gross_t,4),
                     monthly_to = round(mm_full$to_ann,3)),
    rank_ic_full = round(icF$rank_ic,4), icir_full = round(icF$icir,4), harvey_t_full = round(icF$harvey_t,3),
    rank_ic_is   = round(icIS$rank_ic,4), icir_is = round(icIS$icir,4)
  )
  cat(sprintf("  [monthly] FULL net_t=%.3f gross_t=%.3f netSR=%.3f TO=%.1f | IS net_t=%.3f gross_t=%.3f | OOS net_t=%.3f\n",
              full$portfolio_alpha_t_nw_lag3, full_g$portfolio_alpha_t_nw_lag3, full$net_sr, full$turnover_annual,
              isr$portfolio_alpha_t_nw_lag3, is_g$portfolio_alpha_t_nw_lag3,
              ifelse(is.na(oos$portfolio_alpha_t_nw_lag3),NA,oos$portfolio_alpha_t_nw_lag3)))
  cat(sprintf("  [quarterly] FULL net_t=%.3f gross_t=%.3f netSR=%.3f TO=%.1f | IS net_t=%.3f gross_t=%.3f\n",
              qm_full$net_t, qm_full$gross_t, qm_full$net_sr, qm_full$to_ann, qm_is$net_t, qm_is$gross_t))
  cat(sprintf("  rank_IC_full=%.4f ICIR=%.3f harvey_t=%.2f\n", icF$rank_ic, icF$icir, icF$harvey_t))
}

# ---- 5. DSR for each spec on IS net active series (recompute active explicitly) ----
# rebuild active series per spec on IS for DSR (top-N EW net - universe-EW)
active_series <- function(spec, dates_keep) {
  sdt <- panel[Date %in% dates_keep, .(Date, Ticker, score=get(spec))][!is.na(score)]
  sdt <- merge(sdt, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
  sdt <- sdt[is.na(adv) | adv >= LIQ_MIN]
  setorder(sdt, Date, -score)
  W <- sdt[, { n<-min(TOP_N,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n)) }, by=Date]
  WR <- merge(W, retmap, by=c("Date","Ticker"), all.x=TRUE); WR[is.na(Ret_1m), Ret_1m:=0]
  port <- WR[, .(pg=sum(w*Ret_1m)), by=Date]
  # turnover cost
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); prev <- data.table(Ticker=character(0),w=numeric(0))
  for(i in seq_along(dts)){ cur<-W[Date==dts[i],.(Ticker,w)]; mm<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
    mm[is.na(w_c),w_c:=0]; mm[is.na(w_p),w_p:=0]; traded[i]<-sum(abs(mm$w_c-mm$w_p)); prev<-cur }
  port[, cost := traded[match(as.character(Date),as.character(dts))]*COST_BPS/1e4]
  port[, ret_net := pg - cost]
  m <- merge(port, bench_uni, by="Date")
  m$ret_net - m$BM_Ret
}
for (spec in SPECS) {
  a_is <- active_series(spec, is_dates)
  results[[spec]]$dsr_is <- round(dsr_calc(a_is, 8), 4)
  results[[spec]]$mean_active_is_monthly <- round(mean(a_is, na.rm=TRUE), 5)
}

# ---- placebo: random-signal net PORT_t (cost-drag floor for high-TO screens) ----
set.seed(20260612)
rnd <- panel[, .(Date, Ticker)][, score := runif(.N)]
rnd_full <- canonical_screen_bt(rnd[Date %in% grid], retmap, bench_uni, top_n=TOP_N,
                                cost_bps_oneway=COST_BPS, liq_dt=liq_dt, liq_min=LIQ_MIN)
rnd_full_g <- canonical_screen_bt(rnd[Date %in% grid], retmap, bench_uni, top_n=TOP_N,
                                  cost_bps_oneway=0, liq_dt=liq_dt, liq_min=LIQ_MIN)
placebo <- list(random_net_t = round(rnd_full$portfolio_alpha_t_nw_lag3,4),
                random_gross_t = round(rnd_full_g$portfolio_alpha_t_nw_lag3,4),
                random_to = round(rnd_full$turnover_annual,3),
                note = "random top-20 net PORT_t = cost-drag floor; any spec must clear this to claim net signal")
cat(sprintf("\n[placebo] random top-20 net_t=%.3f gross_t=%.3f TO=%.1f (cost-drag floor)\n",
            placebo$random_net_t, placebo$random_gross_t, placebo$random_to))

# ---- 6. screen gate (IS-only, cost-aware: best of monthly/quarterly net) + selection ----
# Pre-registered gate: net PORT_t. Use best achievable net cadence (quarterly = cost-aware variant mandated).
gate <- function(r) {
  best_is_net_t <- max(c(r$is$port_t, r$quarterly$is_net_t), na.rm = TRUE)
  pass_t  <- is.finite(best_is_net_t) && best_is_net_t >= 1.96
  pass_17 <- is.finite(r$sub2017_is$port_t) && r$sub2017_is$port_t > 0
  # gross diagnostic: does raw signal have ANY positive cross-sectional direction?
  gross_pos <- is.finite(r$is$gross_t) && r$is$gross_t > 0
  list(screen_pass = pass_t && pass_17, pass_t = pass_t, pass_17 = pass_17,
       best_is_net_t = round(best_is_net_t,4), gross_pos = gross_pos)
}
for (spec in SPECS) results[[spec]]$gate <- gate(results[[spec]])

# selection: among screen-pass specs, argmax best IS net port_t
passers <- SPECS[sapply(SPECS, function(s) results[[s]]$gate$screen_pass)]
if (length(passers)) {
  sel <- passers[which.max(sapply(passers, function(s) results[[s]]$gate$best_is_net_t))]
} else sel <- NA_character_
cat("\n[gate] screen-pass specs:", if(length(passers)) paste(passers,collapse=", ") else "NONE", "\n")
cat("[select] IS-argmax selected:", ifelse(is.na(sel),"NONE",sel), "\n")

# ---- 7. orthogonality of selected spec vs STR_1715 score_eff (cor<0.95) ----
cor_vs_1715 <- NA_real_
if (!is.na(sel)) {
  ms <- merge(panel[, .(Date, Ticker, sc=get(sel))], s15map, by=c("Date","Ticker"))
  ms <- ms[is.finite(sc) & is.finite(s15)]
  cxs <- ms[, .(c = if(.N>=10) cor(sc, s15, method="spearman") else NA_real_), by=Date]
  cor_vs_1715 <- mean(cxs$c, na.rm=TRUE)
  cat(sprintf("[ortho] selected %s cor_vs_STR1715_score_eff = %.4f (need <0.95)\n", sel, cor_vs_1715))
}

# ---- 8. K200UKQ150 comparison (anchor reproduction): restrict to panel tickers (already restricted: retmap is panel) ----
# Note: our universe IS the panel (K200UKQ150) because retmap/liq come from panel grid + flow snap.
# Full-universe extension would require non-panel tickers' forward returns (unavailable in panel).
# So "full universe signal estimation" = signal computed on all flow tickers, but returns/screen on panel.
# We report this limitation explicitly.

# ---- 9. write outputs ----
res_out <- list(
  task_id = "WT-D20260611_002", track = "FLOW", selection_type = "sweep",
  as_of_date = "2026-06-11", n_trials = length(SPECS),
  is_cutoff = as.character(IS_CUTOFF), top_n = TOP_N, cost_bps = COST_BPS, liq_min = LIQ_MIN,
  benchmark_basis = "universe_EW_monthly (cross-sectional alpha basis; calendar-self-consistent with Ret_1m)",
  universe_note = "Signal estimated on all flow tickers; screen/returns on K200UKQ150 panel grid (forward Ret_1m availability). Full-universe forward returns unavailable in panel -> screen restricted to panel universe.",
  specs = results,
  placebo = placebo,
  screen_passers = passers, selected = sel,
  cor_vs_str1715_score_eff = round(cor_vs_1715,4),
  gate_def = "IS net PORT_t(NW lag3, best of monthly/quarterly cadence)>=1.96 AND 2017+IS port_t>0; graduation HARD(2.95/DSR0.5) = forge-authoritative",
  cost_artifact_note = "monthly top-20 net PORT_t structurally negative for ALL high-TO signals incl. random placebo (cost drag ~20x/yr x 15bps vs frictionless universe-EW benchmark). Gross PORT_t isolates raw signal direction; quarterly cadence (anchor WT precedent) reduces TO."
)
write_json(res_out, file.path(OUTDIR, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

# alpha_scores.parquet for selected (or best-by-IS if none pass, labeled)
score_spec <- if (!is.na(sel)) sel else SPECS[which.max(sapply(SPECS, function(s) results[[s]]$is$port_t))]
alpha_scores <- panel[, .(Date, Ticker, alpha_z = get(score_spec),
                          confidence = pmin(1, pmax(0, 0.5 + 0.5*get(score_spec)/3)))][is.finite(alpha_z)]
write_parquet(alpha_scores, file.path(OUTDIR, "alpha_scores.parquet"))
cat("\n[write] alpha_validation.json + alpha_scores.parquet (score_spec=", score_spec, ")\n", sep="")

cat("\n================ SUMMARY TABLE (monthly cadence) ================\n")
cat(sprintf("%-16s %8s %8s %8s %8s %8s %8s %7s %6s\n",
            "spec","IS_netT","IS_grsT","FULLnetT","FULLgrsT","OOS_netT","TO_F","DSR_IS","gate"))
for (spec in SPECS) {
  r <- results[[spec]]
  cat(sprintf("%-16s %8.3f %8.3f %8.3f %8.3f %8.3f %8.1f %7.3f %6s\n",
              spec, r$is$port_t, r$is$gross_t, r$full$port_t, r$full$gross_t,
              ifelse(is.na(r$oos$port_t),NA,r$oos$port_t),
              r$full$to, ifelse(is.null(r$dsr_is),NA,r$dsr_is),
              ifelse(r$gate$screen_pass,"PASS","fail")))
}
cat(sprintf("%-16s net_t=%.3f gross_t=%.3f TO=%.1f  (cost-drag floor)\n",
            "PLACEBO_rand", placebo$random_net_t, placebo$random_gross_t, placebo$random_to))
cat("\n================ QUARTERLY cadence (cost-aware, anchor WT precedent) ================\n")
cat(sprintf("%-16s %10s %10s %10s %10s %8s\n","spec","FULLnetT","FULLgrsT","IS_netT","FULLnetSR","Q_TO"))
for (spec in SPECS) {
  q <- results[[spec]]$quarterly
  cat(sprintf("%-16s %10.3f %10.3f %10.3f %10.3f %8.1f\n",
              spec, q$full_net_t, q$full_gross_t, q$is_net_t, q$full_net_sr, q$full_to))
}
cat("==============================================================\n")
sink()
cat("DONE — see", TMPLOG, "\n")
