# =============================================================================
# run_trackd.R — Track D (Cycle 1c) 3-sleeve dynamic allocation measurement
#   Prereg: TRACKD_3SLEEVE_DYNAMIC_PREREG_v1 (FROZEN 2026-06-12)
#
# Engine (Track W trackw_engine.R convention, verbatim where possible):
#   sleeve-level monthly net series ALREADY built (intermediate/sleeve_monthly.csv,
#   sleeve-internal cost embedded). Trials allocate ACROSS the 3 sleeves monthly.
#   Sleeve-blend return = sum_s w_s,t * sleeve_ret_s,t   (3 pre-net series).
#     -> Return.portfolio with the 3-sleeve weight matrix (rebalanced monthly to
#        target). gross = portfolio of 3 sleeve series. sleeve-switch cost =
#        per-sleeve |BOP_t - EOP_{t-1}| * 15bps (delta in sleeve-weight space).
#   PORT_t = build_benchmark_compare Portfolio_Alpha_t_NW_lag3 (forge-identical).
#   DSR = essence_score .essence_dsr (BLdP 2014), n_trials=6 sweep.
#   metric_type = "backtested" (real Return.portfolio composition, no hand synth).
#
# Conditioning signals applied at t-1 (C5): signal of formation month f (= return
#   month r-1) decides the weight used for return month r. expanding thresholds (C1).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics); library(jsonlite)
})
setDTthreads(2)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TD_DIR  <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1c_trackD")
INT_DIR <- file.path(TD_DIR, "intermediate")

suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R")))
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/essence_score.R")))

COMMISSION <- 0.0015
N_TRIALS   <- 6L

# ── load substrate ───────────────────────────────────────────────────────────
S  <- fread(file.path(INT_DIR, "sleeve_monthly.csv"))
S[, `:=`(r_idx = as.Date(r_idx), f_idx = as.Date(f_idx))]
setorder(S, ym)
SP <- fread(file.path(INT_DIR, "value_spread_z.csv"))[, .(f_idx = as.Date(f_idx), spread_z)]
ES <- fread(file.path(INT_DIR, "consensus_esbr_z.csv"))[, .(f_idx = as.Date(f_idx), esbr_z)]
S  <- merge(S, SP, by = "f_idx", all.x = TRUE)
S  <- merge(S, ES, by = "f_idx", all.x = TRUE)
setorder(S, ym)
n <- nrow(S)
cat(sprintf("[load] %d months %s..%s | spread_z non-NA %d | esbr_z non-NA %d\n",
            n, S$ym[1], S$ym[n], sum(!is.na(S$spread_z)), sum(!is.na(S$esbr_z))))

# ── 3-sleeve weight schedule -> portfolio net (Return.portfolio) ─────────────
# W: data.table(ym, core, defense, value) monthly target weights (rows sum to 1).
# IMPORTANT (alignment fix): Return.portfolio with a full-period weight xts treats
#   each weight date as a rebalance anchor and emits returns for periods AFTER the
#   first anchor -> output has N-1 rows (drops month 1). To apply target weight w_t
#   to return month t for ALL N months, we date the WEIGHT xts one month BEFORE the
#   return month (b1_step3 / Track W w_idx<-r_idx-1 convention). Then Return.portfolio
#   aligns weight@(t-1) to return@t and keeps all N return rows. We map outputs back
#   by the RETURNED index (not S$ym) so ym/bm/masks never recycle-misalign.
run_blend <- function(W) {
  stopifnot(nrow(W) == n, all(W$ym == S$ym))
  R  <- xts(as.matrix(S[, .(core = core_ret, defense = def_ret, value = value_ret)]),
            order.by = S$r_idx)
  # weight dates = return dates shifted back ~1 month (formation anchor)
  w_idx <- as.Date(vapply(seq_len(n), function(i)
      as.character(seq(S$r_idx[i], by = "-1 month", length.out = 2)[2]), character(1)))
  Wx <- xts(as.matrix(W[, .(core, defense, value)]), order.by = w_idx)
  pf <- Return.portfolio(R, weights = Wx, verbose = TRUE)
  g <- pf$returns
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  nT <- nrow(g); traded <- numeric(nT)
  traded[1] <- sum(abs(as.numeric(bop[1, ])))
  if (nT > 1) for (i in 2:nT) traded[i] <- sum(abs(as.numeric(bop[i, ]) - as.numeric(eop[i-1, ])))
  cost <- traded * COMMISSION
  # map back by RETURNED index (guarantees alignment; N rows = N months)
  ridx <- as.Date(index(g))
  meta <- S[, .(r_idx, ym, bm_ret, f_idx)]
  o <- data.table(r_idx = ridx, ret_gross = as.numeric(g),
                  traded = traded, ret_net = as.numeric(g) - cost)
  o <- merge(o, meta, by = "r_idx", all.x = TRUE)
  setorder(o, r_idx)
  stopifnot(nrow(o) == n, !any(is.na(o$ym)))
  o
}

# ── window metrics ───────────────────────────────────────────────────────────
.win <- function(m) {
  if (nrow(m) < 12 || all(is.na(m$ret_net)))
    return(list(n=nrow(m), sr=NA_real_, cagr=NA_real_, mdd=NA_real_, calmar=NA_real_, ir=NA_real_))
  x <- xts(m$ret_net, order.by = m$r_idx)
  sr  <- mean(m$ret_net)/sd(m$ret_net)*sqrt(12)
  cag <- as.numeric(Return.annualized(x, scale = 12, geometric = TRUE))
  mdd <- as.numeric(maxDrawdown(x))
  act <- m$ret_net - m$bm_ret
  ir  <- if (sd(act) > 0) mean(act)/sd(act)*sqrt(12) else NA_real_
  list(n=nrow(m), sr=sr, cagr=cag, mdd=mdd, calmar=if(mdd>0) cag/mdd else NA_real_, ir=ir)
}
.portt <- function(m, rid) {
  if (nrow(m) < 12) return(NA_real_)
  prt <- data.table(date = m$r_idx, ret_net = m$ret_net, frequency = "monthly")
  bmt <- data.table(date = m$r_idx, benchmark_ret = m$bm_ret, benchmark_id = "KOSPI200_KQ150_BM")
  bc <- build_benchmark_compare(prt, bmt, run_id = rid, strategy_id = rid, annualization_factor = 12)
  tv <- bc[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value]
  if (length(tv)) as.numeric(tv[1]) else NA_real_
}

# window masks by FORMATION month (f_idx): IS<=2018-12, OOS>=2019-01, 2017+
# masks derived from each trial's OWN f_idx (post-merge alignment safe).
summarise <- function(m, trial_id, w_val_series = NULL) {
  is_mask  <- m$f_idx <= as.Date("2018-12-31")
  oos_mask <- m$f_idx >= as.Date("2019-01-01")
  p17_mask <- m$f_idx >= as.Date("2017-01-01")
  f <- .win(m); i <- .win(m[is_mask]); o <- .win(m[oos_mask]); p7 <- .win(m[p17_mask])
  ptf <- .portt(m, trial_id); pti <- .portt(m[is_mask], paste0(trial_id,"_is"))
  pto <- .portt(m[oos_mask], paste0(trial_id,"_oos"))
  sk <- tryCatch(as.numeric(PerformanceAnalytics::skewness(m$ret_net)), error=function(e) 0)
  ku <- tryCatch(as.numeric(PerformanceAnalytics::kurtosis(m$ret_net, method="moment")), error=function(e) 3)
  dsr <- .essence_dsr(f$sr, f$n, N_TRIALS, skew = sk, kurt = ku, A = 12)
  wv_mean <- if (!is.null(w_val_series)) mean(w_val_series) else NA_real_
  wv_switch <- if (!is.null(w_val_series)) sum(abs(diff(w_val_series)) > 1e-9) else NA_real_
  # sleeve-switch turnover (annualized one-way)
  to_ann <- mean(m$traded/2) * 12
  data.table(
    trial_id = trial_id, n_months = f$n,
    full_sr = f$sr, full_cagr = f$cagr, full_mdd = f$mdd, full_calmar = f$calmar,
    full_ir = f$ir, full_port_t = ptf,
    is_sr = i$sr, is_cagr = i$cagr, is_mdd = i$mdd, is_port_t = pti,
    oos_sr = o$sr, oos_cagr = o$cagr, oos_mdd = o$mdd, oos_port_t = pto,
    p2017_sr = p7$sr, p2017_cagr = p7$cagr, p2017_mdd = p7$mdd,
    dsr_n6 = dsr, skew = sk, kurt = ku,
    sleeve_to_ann = to_ann, w_val_mean = wv_mean, w_val_switches = wv_switch,
    metric_type = "backtested"
  )
}

# =============================================================================
# BASELINE  B_static2: core 65 / defense 35 / value 0
# =============================================================================
W0 <- data.table(ym = S$ym, core = 0.65, defense = 0.35, value = 0.0)
m0 <- run_blend(W0)
B  <- summarise(m0, "B_static2", w_val_series = rep(0, n))
cat(sprintf("[baseline] B_static2 full_SR=%.4f IS_SR=%.4f OOS_SR=%.4f MDD=%.4f PORT_t=%.3f\n",
            B$full_sr, B$is_sr, B$oos_sr, B$full_mdd, B$full_port_t))

# helper: residual core:def = 65:35 given w_val
resid_cd <- function(w_val) {
  rem <- 1 - w_val
  list(core = 0.65 * rem, defense = 0.35 * rem, value = w_val)
}

# =============================================================================
# T1 static w_val=0.10 ; T2 static w_val=0.20
# =============================================================================
mk_static <- function(wv) {
  cd <- resid_cd(wv)
  data.table(ym = S$ym, core = cd$core, defense = cd$defense, value = cd$value)
}
W_T1 <- mk_static(0.10); W_T2 <- mk_static(0.20)
m_T1 <- run_blend(W_T1); m_T2 <- run_blend(W_T2)

# =============================================================================
# conditional w_val builder: w_val_t in {0, on} per month based on signal,
#   residual 65:35. signal is at formation month (already lagged: f_idx = r-1,
#   so using S$<signal>_z at the SAME row is the t-1 value for the return month).
#   Months with NA signal -> w_val=0 (no-position default, conservative).
# =============================================================================
mk_conditional <- function(on_vec, w_on = 0.20) {
  wv <- ifelse(is.na(on_vec) | !on_vec, 0, w_on)
  cd_core <- 0.65 * (1 - wv); cd_def <- 0.35 * (1 - wv)
  list(W = data.table(ym = S$ym, core = cd_core, defense = cd_def, value = wv), wv = wv)
}

# T3: value spread z > +0.5  (cheap value dispersion wide -> tilt to value)
T3 <- mk_conditional(S$spread_z > 0.5, 0.20)
m_T3 <- run_blend(T3$W)

# T4: esbr z < 0  (consensus cycle weak -> value complements starving core)
T4 <- mk_conditional(S$esbr_z < 0, 0.20)
m_T4 <- run_blend(T4$W)

# T5: trailing 12m SR(value) > trailing 12m SR(B_static2 net)  [control]
#   trailing window uses returns of months r-12..r-1 (strictly past, no lookahead).
b_net <- m0$ret_net   # B_static2 net series aligned to S$ym
v_net <- S$value_ret
trail_sr <- function(x, idx, k = 12) {
  if (idx <= k) return(NA_real_)
  w <- x[(idx-k):(idx-1)]
  if (sd(w) <= 0) return(NA_real_)
  mean(w)/sd(w)*sqrt(12)
}
t5_on <- vapply(seq_len(n), function(i) {
  sv <- trail_sr(v_net, i); sb <- trail_sr(b_net, i)
  if (is.na(sv) || is.na(sb)) return(FALSE)
  sv > sb
}, logical(1))
T5 <- mk_conditional(t5_on, 0.20)
m_T5 <- run_blend(T5$W)

# =============================================================================
# T6 risk-based 3-sleeve inverse-vol (36m rolling, t-1), w_val cap 0.30
#   vol_s,t = sd of sleeve s returns over months r-36..r-1 (strictly past).
#   weights = (1/vol) normalized; value capped at 0.30 then renormalize.
#   first 36 months: EW 1/3 fallback.
# =============================================================================
rmat <- as.matrix(S[, .(core = core_ret, defense = def_ret, value = value_ret)])
W_T6 <- data.table(ym = S$ym, core = NA_real_, defense = NA_real_, value = NA_real_)
for (i in seq_len(n)) {
  if (i <= 36) {
    w <- c(1/3, 1/3, 1/3)
  } else {
    win <- rmat[(i-36):(i-1), ]
    vol <- apply(win, 2, sd)
    vol[!is.finite(vol) | vol <= 0] <- max(vol[is.finite(vol) & vol > 0], 1e-6)
    iv <- 1/vol; w <- iv/sum(iv)
    if (w[3] > 0.30) {           # cap value at 0.30, renormalize core/def
      w[3] <- 0.30
      cd <- iv[1:2]/sum(iv[1:2]) * 0.70
      w[1] <- cd[1]; w[2] <- cd[2]
    }
  }
  set(W_T6, i, "core", w[1]); set(W_T6, i, "defense", w[2]); set(W_T6, i, "value", w[3])
}
m_T6 <- run_blend(W_T6)

# =============================================================================
# summarise all
# =============================================================================
res <- rbindlist(list(
  B,
  summarise(m_T1, "T1_static_w10",        rep(0.10, n)),
  summarise(m_T2, "T2_static_w20",        rep(0.20, n)),
  summarise(m_T3, "T3_spread_timing",     T3$wv),
  summarise(m_T4, "T4_consensus_cycle",   T4$wv),
  summarise(m_T5, "T5_control_trailSR",   T5$wv),
  summarise(m_T6, "T6_riskbased_ivol",    W_T6$value)
), fill = TRUE)

# Δ vs baseline
bw <- res[trial_id == "B_static2"]
for (cc in c("full_sr","full_cagr","full_mdd","full_calmar","full_ir","full_port_t",
             "is_sr","is_cagr","oos_sr","oos_cagr","p2017_sr","p2017_cagr")) {
  res[[paste0("d_", cc)]] <- res[[cc]] - bw[[cc]]
}

# alive criteria (vs B_static2): IS dSR>=+0.10 AND OOS dSR>=0 AND full dMDD<=+0.02
res[, alive := (d_is_sr >= 0.10) & (d_oos_sr >= 0) & (d_full_mdd <= 0.02)]
res[trial_id == "B_static2", alive := NA]

fwrite(res, file.path(TD_DIR, "results_trackD.csv"))

# =============================================================================
# T4 aux diagnostic: esbr signal z vs NEXT-month core-sleeve return spearman
#   (does the consensus breadth signal carry info about core performance?)
#   signal at f_idx (row i) -> core return at r_idx (row i, = next month). direct.
# =============================================================================
dd <- S[!is.na(esbr_z)]
sp_core <- suppressWarnings(cor(dd$esbr_z, dd$core_ret, method = "spearman"))
sp_val  <- suppressWarnings(cor(dd$esbr_z, dd$value_ret, method = "spearman"))
# also: does low-esbr regime actually have weaker core?
dd[, esbr_neg := esbr_z < 0]
reg_diag <- dd[, .(n = .N, mean_core = mean(core_ret), mean_val = mean(value_ret),
                   core_sr = mean(core_ret)/sd(core_ret)*sqrt(12),
                   val_sr = mean(value_ret)/sd(value_ret)*sqrt(12)), by = esbr_neg]

t4_aux <- list(
  signal = "esbr market-mean 3m-MA expanding z (t-1)",
  spearman_esbr_z_vs_next_core_ret = round(sp_core, 4),
  spearman_esbr_z_vs_next_value_ret = round(sp_val, 4),
  regime_split_esbr_neg = lapply(seq_len(nrow(reg_diag)), function(i) {
    r <- reg_diag[i]; list(esbr_neg = r$esbr_neg, n = r$n,
      mean_core_ret = round(r$mean_core,5), mean_val_ret = round(r$mean_val,5),
      core_sr = round(r$core_sr,3), val_sr = round(r$val_sr,3))
  }),
  interpretation_note = "mechanism requires: esbr_neg months show WEAKER core AND value picks up slack. metric_type=diagnostic."
)

# DSR summary across trials (sweep n=6)
dsr_tbl <- res[trial_id != "B_static2", .(trial_id, full_sr, dsr_n6)]

out <- list(
  prereg = "TRACKD_3SLEEVE_DYNAMIC_PREREG_v1",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_months = n, window = paste0(S$ym[1], "..", S$ym[n]),
  selection_type = "sweep", n_trials = N_TRIALS, dsr_gate = 0.5,
  metric_type = "backtested",
  sleeve_standalone = list(
    core_sr = round(mean(S$core_ret)/sd(S$core_ret)*sqrt(12),3),
    defense_sr = round(mean(S$def_ret)/sd(S$def_ret)*sqrt(12),3),
    value_sr = round(mean(S$value_ret)/sd(S$value_ret)*sqrt(12),3),
    cor_core_value = round(cor(S$core_ret,S$value_ret),3),
    cor_def_value = round(cor(S$def_ret,S$value_ret),3),
    cor_core_def = round(cor(S$core_ret,S$def_ret),3)
  ),
  baseline = as.list(B),
  trials = lapply(split(res[trial_id != "B_static2"], by = "trial_id"), as.list),
  alive_summary = res[trial_id != "B_static2", .(trial_id, d_is_sr = round(d_is_sr,4),
        d_oos_sr = round(d_oos_sr,4), d_full_mdd = round(d_full_mdd,4), alive)],
  t4_consensus_aux = t4_aux,
  dsr_sweep = lapply(seq_len(nrow(dsr_tbl)), function(i)
    list(trial = dsr_tbl$trial_id[i], full_sr = round(dsr_tbl$full_sr[i],4),
         dsr = round(dsr_tbl$dsr_n6[i],4)))
)
write_json(out, file.path(TD_DIR, "results_trackD.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)

cat("\n================ TRACK D RESULTS ================\n")
print(res[, .(trial_id, full_sr = round(full_sr,3), is_sr = round(is_sr,3), oos_sr = round(oos_sr,3),
              full_mdd = round(full_mdd,3), full_port_t = round(full_port_t,2),
              d_is_sr = round(d_is_sr,3), d_oos_sr = round(d_oos_sr,3),
              d_full_mdd = round(d_full_mdd,3), w_val_mean = round(w_val_mean,3),
              dsr = round(dsr_n6,3), alive)])
cat("\nT4 aux: spearman(esbr_z, next core ret) =", round(sp_core,4),
    " | (esbr_z, next value ret) =", round(sp_val,4), "\n")
print(reg_diag)
cat("\nANY ALIVE:", any(res$alive, na.rm = TRUE), "\n")
cat("RUN_TRACKD_OK\n")
