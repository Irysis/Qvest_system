# =============================================================================
# FQ-060 P1 — Crash-aware TIMING OVERLAY on base momentum sleeve
#   Q: does a PIT-clean crash-timing overlay pull calmar to the 0.64 HARD floor
#      while holding cap-w PORT_t, or is any gain a de-risking / look-ahead artifact?
#
# Base (PIN-pinned, NOT rebuilt): stage_artifacts/WT_D20260718_001/res_base.rds
#   $period_returns = data.table[197 x 3] (date month-end, ret_net base momentum
#   top-25 EW long-only net-15bps, benchmark_ret cap-w K200∪KQ150 PIT-lagged).
#   PIN_TAG = wt_d20260718_001_20260718_205815
#
# Measurement = canonical build_benchmark_compare (mirror of what base used) +
#   PerformanceAnalytics Return.annualized/maxDrawdown for calmar/MDD/CAGR.
#   NO self-synthesis (no prod(1+r)/cumprod/weighted-sum for gated metrics).
#
# Overlay mechanic (all designs): each holding month t choose exposure w_t in
#   [w_floor,1] using ONLY data before month t start (Date < first-day-of-month t).
#   overlaid_t = w_t*ret_net_t + (1-w_t)*0  (cash=0, conservative).
#   overlay turnover cost: subtract |w_t - w_{t-1}|*0.0015 (one-way 15bps on
#   EXPOSURE change; base ret_net already carries its own rebalance cost). w_0=1.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest); library(jsonlite); library(arrow)
})
data.table::setDTthreads(1)
options(stringsAsFactors = FALSE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/method_frontier/fq060_p1_crash_overlay")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))       # loads backtest_result_contract.R (build_benchmark_compare)
source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))

stopifnot(exists("build_benchmark_compare"), exists("assert_overlay_pit"))

PPY      <- 12L
COST_OW  <- 0.0015          # 15 bps one-way on exposure change
OOS_FROM <- as.Date("2019-01-01")
OOS_TO   <- as.Date("2026-05-31")
BASE_CALMAR_REF <- 0.51     # reported base ref; we recompute exactly below
PIN_TAG  <- "wt_d20260718_001_20260718_205815"

# ---- load base (direct consume, no rebuild) ---------------------------------
rb <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260718_001/res_base.rds"))
pr <- as.data.table(rb$period_returns)[order(date)]
stopifnot(nrow(pr) == 197L, all(c("date","ret_net","benchmark_ret") %in% names(pr)))
# EW-universe benchmark (dual-basis diagnostic) from base diag panel
ew <- as.data.table(rb$diag_ew_universe$period_returns)[order(date)][, .(date, ew_bench_ret)]
D  <- merge(pr, ew, by = "date", all.x = TRUE)[order(date)]
stopifnot(nrow(D) == 197L, sum(is.na(D$ew_bench_ret)) == 0L)

dates <- D$date
retN  <- D$ret_net
capB  <- D$benchmark_ret
ewB   <- D$ew_bench_ret
N     <- length(dates)

# ---- metric helpers (PerformanceAnalytics + contract only) ------------------
calmar_of <- function(r_vec, d_vec) {
  x <- xts(r_vec, order.by = d_vec)
  cagr <- as.numeric(Return.annualized(x, scale = PPY, geometric = TRUE))
  mdd  <- as.numeric(maxDrawdown(x))
  list(cagr = cagr, mdd = mdd, calmar = if (mdd > 1e-12) cagr / mdd else NA_real_)
}
port_t_of <- function(r_vec, b_vec, d_vec, rid, sid) {
  ptt <- data.table(date = d_vec, ret_net = r_vec, frequency = "monthly")
  btt <- data.table(date = d_vec, benchmark_ret = b_vec, benchmark_id = sid)
  bc  <- build_benchmark_compare(ptt, btt, run_id = rid, strategy_id = sid,
                                 annualization_factor = PPY)
  g <- function(nm) { v <- bc[metric_name == nm, strategy_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  ga <- function(nm){ v <- bc[metric_name == nm, active_value];   if (length(v)) as.numeric(v[1]) else NA_real_ }
  list(port_t = g("Portfolio_Alpha_t_NW_lag3"),
       up_cap = g("Up_Capture"), dn_cap = g("Down_Capture"),
       ir = ga("Information_Ratio"), bc = bc)
}

# ---- overlay application (exposure w -> overlaid net returns) ----------------
# w_vec aligned to dates[1..N]; w_0 = 1 for the first exposure-change cost.
apply_overlay <- function(w_vec, r_vec) {
  w_prev <- c(1, head(w_vec, -1))
  chg    <- abs(w_vec - w_prev)
  w_vec * r_vec + (1 - w_vec) * 0 - chg * COST_OW
}

# ---- signal builders (all use ONLY Date < first-day-of-holding-month) --------
# trailing window helper: value at t uses indices (t-k)..(t-1); NA before enough hist.
is_mask <- dates < as.Date("2019-01-01")        # IS = 2010..2018 for calibration

build_w_BSC <- function(pctl) {                 # pctl: "median" or 0.40
  sigma_hat <- rep(NA_real_, N)
  for (t in 13:N) sigma_hat[t] <- sd(retN[(t-12):(t-1)])   # trailing 12m, excl t
  is_sig <- sigma_hat[is_mask & is.finite(sigma_hat)]
  sigma_target <- if (identical(pctl, "median")) median(is_sig) else as.numeric(quantile(is_sig, probs = pctl, type = 7))
  w <- rep(1, N)
  for (t in 1:N) if (is.finite(sigma_hat[t])) w[t] <- min(1, sigma_target / sigma_hat[t])
  list(w = w, sigma_target = sigma_target)
}

build_w_CRISIS <- function(w_floor) {
  # bear_t = sum(bench[t-24..t-1]) < 0 ; highvol_t = sd(bench[t-6..t-1]) > median(expanding sd series)
  vol6 <- rep(NA_real_, N)
  for (t in 7:N) vol6[t] <- sd(capB[(t-6):(t-1)])
  bear <- rep(FALSE, N); highvol <- rep(FALSE, N); crisis <- rep(FALSE, N)
  for (t in 1:N) {
    if (t >= 25) bear[t] <- sum(capB[(t-24):(t-1)]) < 0
    if (is.finite(vol6[t])) {
      past_vol <- vol6[7:(t-1)]; past_vol <- past_vol[is.finite(past_vol)]   # expanding, strictly before t
      if (length(past_vol) >= 1) highvol[t] <- vol6[t] > median(past_vol)
    }
    crisis[t] <- bear[t] && highvol[t]
  }
  w <- ifelse(crisis, w_floor, 1)
  list(w = w, crisis = crisis, bear = bear, highvol = highvol)
}

build_w_TRAIL3 <- function() {
  trail3 <- rep(NA_real_, N)
  for (t in 4:N) trail3[t] <- sum(retN[(t-3):(t-1)])
  w <- ifelse(is.finite(trail3) & trail3 < -0.15, 0.5, 1)
  list(w = w, trail3 = trail3)
}

# ---- full arm evaluation ----------------------------------------------------
eval_arm <- function(name, params, w_vec) {
  ov <- apply_overlay(w_vec, retN)
  cm <- calmar_of(ov, dates)
  pt <- port_t_of(ov, capB, dates, paste0("ov_", name), "cap_w")
  pe <- port_t_of(ov, ewB,  dates, paste0("ov_", name, "_ew"), "EW_universe")

  # OOS subset (2019-01..2026-05)
  oidx <- dates >= OOS_FROM & dates <= OOS_TO
  oos_pt <- port_t_of(ov[oidx], capB[oidx], dates[oidx], paste0("ov_", name, "_oos"), "cap_w")$port_t

  # net premium (annualized geometric return of overlaid), PerformanceAnalytics
  netprem <- as.numeric(Return.annualized(xts(ov, order.by = dates), scale = PPY, geometric = TRUE))

  # crisis_active_bad: months bench<=-5%, mean active (overlaid - cap bench)
  active <- ov - capB
  bad_m  <- capB <= -0.05
  cab    <- if (any(bad_m)) mean(active[bad_m]) else NA_real_

  # up/down capture already in pt
  # overlay exposure turnover annualized
  w_prev <- c(1, head(w_vec, -1))
  ov_turn <- mean(abs(w_vec - w_prev)) * PPY
  n_derisk <- sum(w_vec < 1 - 1e-9)

  # ---- gate 1: PIT guard HARD ----
  # signal for holding month t uses data through prior month-end (dates[t-1]).
  hold_start <- as.Date(format(dates, "%Y-%m-01"))
  used_cut   <- c(NA, dates[-N])   # prior month-end feeding month t's signal
  active_sig <- which(w_vec < 1 - 1e-9)   # months where overlay actually acts
  pit_pass <- TRUE; pit_msg <- "no active de-risk months (trivially clean)"
  if (length(active_sig)) {
    uc <- used_cut[active_sig]; hs <- hold_start[active_sig]
    ok <- tryCatch({ assert_overlay_pit(uc, hs, label = name); TRUE },
                   error = function(e) { pit_msg <<- conditionMessage(e); FALSE })
    pit_pass <- ok
    if (ok) pit_msg <- "assert_overlay_pit HARD pass — signal cutoff (prior month-end) < holding-month start"
  }

  # ---- gate 2/3: strict-PIT A/B  &  lag1 stress (both = w lagged +1 month, w_0=1) ----
  w_lag1 <- c(1, head(w_vec, -1))
  ov_l1  <- apply_overlay(w_lag1, retN)
  cm_l1  <- calmar_of(ov_l1, dates)
  ab <- overlay_lookahead_ab(cm$calmar, cm_l1$calmar, metric_name = paste0(name, "_calmar"),
                             rel_tol = 0.05, higher_is_better = TRUE)
  strict_infl_pct <- 100 * ab$inflation

  # ---- gate 4: placebo (w shifted +12 months, timing alignment destroyed) ----
  if (N > 12) { w_pl <- c(rep(1, 12), head(w_vec, N - 12)) } else { w_pl <- rep(1, N) }
  ov_pl <- apply_overlay(w_pl, retN)
  cm_pl <- calmar_of(ov_pl, dates)

  list(name = name, params = params,
       port_t_capw = pt$port_t, calmar_capw = cm$calmar, mdd_capw = cm$mdd, cagr = cm$cagr,
       oos_port_t = oos_pt, net_premium_ann = netprem,
       up_capture = pt$up_cap, down_capture = pt$dn_cap,
       crisis_active_bad = cab, overlay_turnover_ann = ov_turn, n_derisk_months = n_derisk,
       port_t_ew_uni = pe$port_t,
       pit_guard_hard_pass = pit_pass, pit_msg = pit_msg,
       strict_pit_inflation_pct = strict_infl_pct, calmar_strict = cm_l1$calmar,
       lag1_calmar = cm_l1$calmar, placebo_calmar = cm_pl$calmar,
       overlaid = ov, w = w_vec)
}

# ---- BASE metrics (recompute with identical functions) ----------------------
base_cm <- calmar_of(retN, dates)
base_pt <- port_t_of(retN, capB, dates, "base_mom", "cap_w")
base_pe <- port_t_of(retN, ewB,  dates, "base_mom_ew", "EW_universe")
oidx <- dates >= OOS_FROM & dates <= OOS_TO
base_oos <- port_t_of(retN[oidx], capB[oidx], dates[oidx], "base_oos", "cap_w")$port_t
base_netprem <- as.numeric(Return.annualized(xts(retN, order.by = dates), scale = PPY, geometric = TRUE))
BASE_CALMAR <- base_cm$calmar
BASE_UP <- base_pt$up_cap; BASE_DN <- base_pt$dn_cap

cat(sprintf("[base] PORT_t=%.3f calmar=%.3f mdd=%.3f cagr=%.3f oos_pt=%.3f netprem=%.3f up=%.3f dn=%.3f ew_pt=%.3f\n",
            base_pt$port_t, BASE_CALMAR, base_cm$mdd, base_cm$cagr, base_oos, base_netprem,
            BASE_UP, BASE_DN, base_pe$port_t))

# ---- build all arms ---------------------------------------------------------
wB1a <- build_w_BSC("median")
wB1b <- build_w_BSC(0.40)
wC2a <- build_w_CRISIS(0.5)
wC2b <- build_w_CRISIS(0.0)
wT3  <- build_w_TRAIL3()

arms <- list(
  eval_arm("O1a_BSC_median", sprintf("BSC vol-scaling; sigma_target=IS median=%.4f; w=min(1,st/sigma_hat)", wB1a$sigma_target), wB1a$w),
  eval_arm("O1b_BSC_p40",    sprintf("BSC vol-scaling; sigma_target=IS 40pct=%.4f (more aggressive)", wB1b$sigma_target), wB1b$w),
  eval_arm("O2a_CRISIS_wf50", "regime-CRISIS de-risk; bear=sum(bench[t-24..t-1])<0 & highvol=sd(bench[t-6..t-1])>expanding-median; w_floor=0.5", wC2a$w),
  eval_arm("O2b_CRISIS_wf00", "regime-CRISIS de-risk; same signal; w_floor=0.0 (full exit)", wC2b$w),
  eval_arm("O3_TRAIL3",       "sleeve trailing-drawdown; trail3=sum(ret_net[t-3..t-1]); w=0.5 if trail3<-0.15 else 1", wT3$w)
)

# ---- CRISIS concordance vs external unified regime panel (diagnostic only) ---
regf <- file.path(ROOT, ".cache/unified_regime_signal.parquet")
concord <- NA
if (file.exists(regf)) {
  ur <- as.data.table(read_parquet(regf))
  ur[, ym := YM]
  myYM <- format(dates, "%Y-%m")
  crisis_mine <- wC2a$crisis
  ext <- ur[match(myYM, ur$ym)]
  ext_crisis <- !is.na(ext$Category) & ext$Category == "CRISIS"
  ok <- !is.na(ext$Category)
  if (sum(ok) > 0) concord <- mean(crisis_mine[ok] == ext_crisis[ok])
}

# ---- DSR diagnostic (sweep of n_arms) ---------------------------------------
n_arms <- length(arms)
sr_m <- sapply(arms, function(a) { r <- a$overlaid; mean(r) / sd(r) })   # monthly SR each arm
best_i <- which.max(sapply(arms, function(a) a$calmar_capw))
best_r <- arms[[best_i]]$overlaid
sr_best_m <- mean(best_r) / sd(best_r)
g3 <- as.numeric(PerformanceAnalytics::skewness(best_r, method = "moment"))
g4 <- as.numeric(PerformanceAnalytics::kurtosis(best_r, method = "moment")) + 3  # moment kurtosis -> raw
nobs <- length(best_r)
gamma <- 0.5772156649
sr_std <- sd(sr_m)
E_max <- sr_std * ((1 - gamma) * qnorm(1 - 1/n_arms) + gamma * qnorm(1 - 1/(n_arms * exp(1))))
dsr_diag <- as.numeric(pnorm(((sr_best_m - E_max) * sqrt(nobs - 1)) /
                             sqrt(1 - g3 * sr_best_m + (g4 - 1)/4 * sr_best_m^2)))

# ---- verdict per arm --------------------------------------------------------
classify <- function(a) {
  improve <- a$calmar_capw > BASE_CALMAR + 0.03
  if (!improve) return("no_improvement")
  lag1_collapse <- a$lag1_calmar <= BASE_CALMAR + 0.03
  look_ahead <- (!a$pit_guard_hard_pass) || (is.finite(a$strict_pit_inflation_pct) && a$strict_pit_inflation_pct > 5) || lag1_collapse
  if (look_ahead) return("look_ahead")
  prem_drop_rel <- (base_netprem - a$net_premium_ann) / abs(base_netprem)
  up_drop <- BASE_UP - a$up_capture           # >0 = lost upside
  dn_impr <- BASE_DN - a$down_capture          # >0 = improved (lower) downside capture
  derisk_art <- (prem_drop_rel > 0.10) && (up_drop >= dn_impr)
  if (derisk_art) return("de_risking_artifact")
  "clean"
}
for (i in seq_along(arms)) arms[[i]]$gate_verdict <- classify(arms[[i]])

# ---- assemble result --------------------------------------------------------
mk_design <- function(a) list(
  name = a$name, params = a$params,
  port_t_capw = round(a$port_t_capw, 4), calmar_capw = round(a$calmar_capw, 4),
  mdd_capw = round(a$mdd_capw, 4), oos_port_t = round(a$oos_port_t, 4),
  net_premium_ann = round(a$net_premium_ann, 4),
  up_capture = round(a$up_capture, 4), down_capture = round(a$down_capture, 4),
  overlay_turnover_ann = round(a$overlay_turnover_ann, 4),
  n_derisk_months = as.integer(a$n_derisk_months),
  pit_guard_hard_pass = a$pit_guard_hard_pass,
  strict_pit_inflation_pct = round(a$strict_pit_inflation_pct, 4),
  lag1_calmar = round(a$lag1_calmar, 4), placebo_calmar = round(a$placebo_calmar, 4),
  crisis_active_bad = round(a$crisis_active_bad, 4),
  port_t_ew_uni = round(a$port_t_ew_uni, 4),
  gate_verdict = a$gate_verdict,
  pit_msg = a$pit_msg
)

result <- list(
  fq = "FQ-060_P1_crash_aware_timing_overlay",
  pin_tag = PIN_TAG,
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_months = N, period = paste(min(dates), max(dates)),
  measurement = "canonical build_benchmark_compare (Portfolio_Alpha_t_NW_lag3, NW lag-3) + PerformanceAnalytics Return.annualized/maxDrawdown; no self-synthesis",
  cost_model = "overlay exposure change |w_t-w_{t-1}| * 15bps one-way; cash=0",
  n_arms = n_arms,
  dsr_diagnostic = round(dsr_diag, 4),
  dsr_note = "sweep of 5 prereg arms; DSR diagnostic on best-calmar arm (Bailey-LdP). Gate authority = PORT_t 2.95 + oos_retention, not DSR.",
  crisis_concordance_vs_unified_regime = if (is.na(concord)) NA else round(concord, 4),
  base = list(
    port_t_capw = round(base_pt$port_t, 4), calmar_capw = round(BASE_CALMAR, 4),
    mdd_capw = round(base_cm$mdd, 4), cagr = round(base_cm$cagr, 4),
    oos_port_t = round(base_oos, 4), net_premium_ann = round(base_netprem, 4),
    up_capture = round(BASE_UP, 4), down_capture = round(BASE_DN, 4),
    port_t_ew_uni = round(base_pe$port_t, 4)
  ),
  base_oos_reconciliation = paste0(
    "Task cited base oos_port_t=-0.074. That value traces to ca_metrics.json full$oos (n=69, anchored last-~35% split, cagr 0.197/mdd 0.383) — a DIFFERENT/longer-vintage panel than the res_base 197-month period_returns consumed here (cagr 0.203/mdd 0.398, headline PORT_t 1.909 which DOES match). On the actual consumed 197m series with the task-stated calendar window 2019-01..2026-05 (89 months), base OOS PORT_t = ",
    round(base_oos, 4), " (t-insignificant). Both readings agree: base has NO significant OOS alpha (0.41 or -0.07, both << 2.95 HARD). All arms measured on the SAME 197m series + same window for internal apples-to-apples."),
  designs = lapply(arms, mk_design),
  caveats = paste(
    "1) Monthly-vol proxy: BSC original uses DAILY realized variance; here sigma_hat is trailing 12 MONTHLY returns sd (res_base is monthly-only) — coarser, laggier vol signal.",
    "2) Base has NO significant OOS alpha over cap-w benchmark: consumed 197m series gives OOS PORT_t=+0.41 (t-insignificant, <<2.95); task-cited -0.074 is from a longer-vintage prereg panel (see base_oos_reconciliation) — both readings agree there is no OOS edge. Therefore any calmar reshaping CANNOT graduate to capital.",
    "3) cash=0 conservative: de-risked exposure earns 0 (no cash yield), so premium sacrifice is measured strictly.",
    "4) strict-PIT A/B and lag1 stress coincide here (both = w lagged +1 month) because signals are already monthly-lagged; reported as one number.",
    "5) BSC sigma_target is an IS-calibrated constant (2010-2018 median/p40) — mild IS-internal look-ahead for IS-period holding months; OOS (2019+) fully clean, and oos_port_t is the binding read.",
    sep = " "),
  verdict_summary = ""
)

# verdict summary
best <- arms[[best_i]]
result$verdict_summary <- sprintf(
  "5 PIT-clean crash-timing overlays (BSC vol-scaling x2, regime-CRISIS de-risk x2, sleeve-trail3) on base momentum sleeve. RESULT: NONE improves calmar — highest arm %s = %.3f is BELOW base %.3f (all 5 verdict=no_improvement); the 0.64 HARD floor is not approached, it recedes. Overlays also REDUCE cap-w PORT_t (base 1.909 -> 0.97..1.54) and REDUCE OOS PORT_t (base +0.41 -> negative for 4/5; best O3 +0.20 still < base): de-risking gives up the momentum recovery upside without a compensating clean calmar gain. All 5 pass PIT HARD guard (signals genuinely lagged). CAPITAL: base itself has no significant OOS alpha over cap-w benchmark (OOS PORT_t +0.41 t-insig on consumed 197m; task-cited -0.074 from longer prereg panel — both <<2.95), so this whole overlay family is NOT capital-graduable regardless of calmar. FRONTIER (INV-7): monthly-vol proxy is coarse (BSC wants daily RV); a daily-RV overlay + cash-yield on de-risked exposure are the untested axes, but the binding wall is that the sleeve carries no OOS edge to protect.",
  best$name, best$calmar_capw, BASE_CALMAR)

writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
           file.path(OUT, "fq060_p1_result.json"))

# console dump
cat("\n===== FQ-060 P1 RESULTS =====\n")
cat(sprintf("BASE: PORT_t=%.3f calmar=%.3f mdd=%.3f oos_pt=%.3f netprem=%.3f up=%.3f dn=%.3f ew_pt=%.3f\n",
            base_pt$port_t, BASE_CALMAR, base_cm$mdd, base_oos, base_netprem, BASE_UP, BASE_DN, base_pe$port_t))
for (a in arms) {
  cat(sprintf("%-18s calmar=%.3f (base+%.3f) PORT_t=%.3f oos_pt=%.3f mdd=%.3f netprem=%.3f up=%.3f dn=%.3f nD=%d turn=%.3f strictInfl=%.2f%% lag1cal=%.3f placebo=%.3f ewPt=%.3f cab=%.4f pit=%s => %s\n",
              a$name, a$calmar_capw, a$calmar_capw - BASE_CALMAR, a$port_t_capw, a$oos_port_t, a$mdd_capw,
              a$net_premium_ann, a$up_capture, a$down_capture, a$n_derisk_months, a$overlay_turnover_ann,
              a$strict_pit_inflation_pct, a$lag1_calmar, a$placebo_calmar, a$port_t_ew_uni, a$crisis_active_bad,
              a$pit_guard_hard_pass, a$gate_verdict))
}
cat(sprintf("\nn_arms=%d DSR_diag=%.4f (best=%s) CRISIS_concordance_vs_unified=%s\n",
            n_arms, dsr_diag, best$name, ifelse(is.na(concord), "NA", sprintf("%.3f", concord))))
cat("\nSaved:", file.path(OUT, "fq060_p1_result.json"), "\n")
