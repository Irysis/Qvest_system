# =============================================================================
# stageb_measure.R - Track B Stage B measurement (Composition Search Cycle 2)
#
# Implements VERBATIM the frozen preregistration:
#   04_Research/composition_search/cycle2_trackB/prereg_stageb.json
#   (written 2026-06-12T09:19:58+09:00, FROZEN - no spec/grid/criteria change)
#
# Specs (n_trials cumulative ledger +2 -> 40 with Track V 38):
#   SB1_B1V4_SOLO          : n_fixed=20, band=30                (Track V frozen)
#   SB2_B1V4_PLUS_LIQ2E8   : n_fixed=20, band=30, liq_floor=2e8 (NEW, fresh run)
#
# Order of operations (prereg measurement_plan_order_of_operations):
#   STEP 0 repro gate -> STEP 1 cor gatekeeper (|cor|>=0.30 -> DISQUALIFIED,
#   NO blend grid) -> STEP 2 Return.portfolio blend grid {90/10,85/15,80/20,75/25}
#   -> STEP 3 IS-only argmax dIR commit -> STEP 4 OOS once -> STEP 5 full report.
#
# Data boundary: ALL series truncated at realized month <= 2026-04-30
# (rawdata post 2026-05-01 contaminated, Track R repairing). Label on rows.
# Cost: v2.4_kr_retail_15bps delta (engine). NO self-synthesized compounding:
# Return.portfolio / build_bt_result / build_benchmark_compare only.
# book_state.json is READ-ONLY here. ASCII output only.
# =============================================================================

# ---- STEP 0a: libraries + contracts + engine (s2_common loads frozen inputs) ----
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")
CD <- file.path(PROJ, "02_Infrastructure/contracts")
source(file.path(CD, "audit_bt_result.R"))
source(file.path(CD, "essence_score.R"))

TB  <- file.path(PROJ, "04_Research/composition_search/cycle2_trackB")
dir.create(TB, recursive = TRUE, showWarnings = FALSE)
CUTOFF   <- as.Date("2026-04-30")
CUTOFF_YM <- "2026-04"
N_TRIALS_CUM <- 40L   # Track V 38 + Stage B 2 (prereg ledger)

# load-once with single 60s retry (atomic-swap window during Track R repair)
load_once <- function(fn, desc) {
  tryCatch(fn(), error = function(e) {
    cat(sprintf("[load] %s FAILED (%s) - retry once after 60s\n", desc, conditionMessage(e)))
    Sys.sleep(60); fn()
  })
}

# ---- STEP 0b: inputs (loaded ONCE, held in memory) ----
pan <- load_once(function() {
  as.data.table(read_parquet(file.path(PROJ, "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
}, "factor_panel_7f.parquet")
pan[, Date := as.Date(Date)]
last_d <- max(pan$Date)

# sig grid construction = s2_run_b1.R verbatim
udates <- sort(unique(pan$Date))
umap <- data.table(Date = udates,
  w_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(as.Date(d))), character(1))),
  r_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(seq(as.Date(d), by = "1 month", length.out = 2)[2])), character(1))))
pan <- merge(pan, umap, by = "Date")

ADV[, ym := format(Date, "%Y-%m")]
adv_ym <- ADV[, .(ym, Ticker, adv)]

S1_all <- pan[!is.na(score_eff) & Date < last_d,
              .(Date = w_idx, Ticker, score = score_eff, ret_ok = is.finite(Ret_1m))]
S1_all[, ym := format(Date, "%Y-%m")]
S1_all <- merge(S1_all, adv_ym, by = c("ym", "Ticker"), all.x = TRUE)
S1_all[, ym := NULL]
RET_B1 <- pan[, .(Date = w_idx, Ticker, ret_fwd = Ret_1m, r_idx)]
S1 <- S1_all[Date >= START_DATE]
cat(sprintf("[0b] panel ok: scores %s..%s | adv match %.3f\n",
            format(min(S1$Date)), format(max(S1$Date)), S1[, mean(!is.na(adv))]))

# book L5 realized panel (05_Production READ-ONLY; path in-source only - prereg access_rule)
l5 <- load_once(function() {
  fread("C:/Users/99922/OneDrive/Quant_Module_Moltbot/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
}, "period_returns_layer5.csv")
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
stopifnot(nrow(l5) == 267, max(l5$realized_ym) == "2026-04")

# L5_V2 recomposition integrity (Track O identity, must hold)
l5[, recomp := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
      db_thr * 0.0015 - db_R05_V2 * 0.0015]
l5_resid <- max(abs(l5$recomp - l5$ret_L5_V2))
cat(sprintf("[0b] L5_V2 recomposition max|resid| = %.3e (gate <1e-12)\n", l5_resid))
stopifnot(l5_resid < 1e-12)

# vanilla ret_orig identity check (prereg book_series_sources.vanilla_ret_orig)
ro <- load_once(function() {
  fread(file.path(PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
}, "STR_1715 03_period_returns.csv")
ro[, ym := format(as.Date(date), "%Y-%m")]
roj <- merge(ro[, .(ym, ret_net)], l5[, .(ym = realized_ym, ret_orig)], by = "ym")
ro_resid <- max(abs(roj$ret_net - roj$ret_orig))
cat(sprintf("[0b] ret_orig == STR_1715 ret_net identity: n=%d max|diff| = %.3e\n",
            nrow(roj), ro_resid))

# incumbent baseline (READ-ONLY verify)
bs <- load_once(function() {
  jsonlite::read_json(file.path(PROJ, "qepm/mailbox/governor/book_state.json"))
}, "book_state.json")
stored_ir <- suppressWarnings(as.numeric(bs$incumbent_book_ir))
cat(sprintf("[0b] book_state incumbent_book_ir (stored, gross/flat-era) = %.4f (prereg 1.5754)\n", stored_ir))

# Track V stored series (SB1 reuse cross-check)
tv_store <- load_once(function() {
  readRDS(file.path(RESD, "b1_str1715_vanilla_series.rds"))
}, "b1_str1715_vanilla_series.rds")
stopifnot("B1_V4_band_1p5N" %in% names(tv_store))

# =============================================================================
# STEP 0c: spec runs (trackv_engine, frozen cfgs) + repro gate
# =============================================================================
cat("\n[0c] running SB1 (fresh re-run, repro gate vs Track V 0.9566 4dp)...\n")
r_sb1 <- tv_run_variant("SB1_B1V4_SOLO", S1, RET_B1, BMM, list(n_fixed = 20L, band = 30L))
stopifnot(is.null(r_sb1$error))
sb1_full_sr <- r_sb1$windows$FULL$sr_net
cat(sprintf("[0c] SB1 FULL sr_net = %.4f (target 0.9566)\n", sb1_full_sr))
repro_pass <- isTRUE(abs(sb1_full_sr - 0.9566) < 5e-5)
if (!repro_pass) stop(sprintf("REPRO GATE FAIL: SB1 full sr_net %.4f != 0.9566 - abort before blend math (prereg)", sb1_full_sr))
# cross-check vs stored Track V series
xchk <- merge(r_sb1$series[, .(Date, net_new = net)],
              tv_store$B1_V4_band_1p5N[, .(Date, net_old = net)], by = "Date")
xchk_max <- max(abs(xchk$net_new - xchk$net_old))
cat(sprintf("[0c] SB1 fresh vs stored series: n=%d max|net diff| = %.3e\n", nrow(xchk), xchk_max))

cat("\n[0c] running SB2 (fresh, band=30 + liq_floor=2e8)...\n")
r_sb2 <- tv_run_variant("SB2_B1V4_PLUS_LIQ2E8", S1, RET_B1, BMM,
                        list(n_fixed = 20L, band = 30L, liq_floor = 2e8))
stopifnot(is.null(r_sb2$error))

# cutoff truncation (prereg data_boundary - native end 2026-04, enforced anyway)
for (nm in c("r_sb1", "r_sb2")) {
  s <- get(nm)$series
  n_drop <- s[Date > CUTOFF, .N]
  if (n_drop > 0) cat(sprintf("[0c] %s: dropped %d rows past cutoff\n", nm, n_drop))
}
r_sb1$series <- r_sb1$series[Date <= CUTOFF]
r_sb2$series <- r_sb2$series[Date <= CUTOFF]
l5 <- l5[realized_ym <= CUTOFF_YM]
# recompute window metrics on the truncated series (identical when n_drop=0)
r_sb1$windows <- tv_metrics(r_sb1$series, BMM, "SB1_B1V4_SOLO")
r_sb2$windows <- tv_metrics(r_sb2$series, BMM, "SB2_B1V4_PLUS_LIQ2E8")
cat(sprintf("[0c] cutoff applied: SB1 %s..%s (n=%d) | SB2 %s..%s (n=%d) | L5 n=%d\n",
            format(min(r_sb1$series$Date)), format(max(r_sb1$series$Date)), nrow(r_sb1$series),
            format(min(r_sb2$series$Date)), format(max(r_sb2$series$Date)), nrow(r_sb2$series), nrow(l5)))
cat(sprintf("[0c] SB2 FULL: SRnet=%.4f IS=%.4f OOS=%.4f PORT_t=%.2f IR=%.4f TO1w=%.2fx cost=%.2f%%/yr\n",
            r_sb2$windows$FULL$sr_net, r_sb2$windows$IS$sr_net, r_sb2$windows$OOS$sr_net,
            r_sb2$windows$FULL$port_t_nw, r_sb2$windows$FULL$net_ir,
            r_sb2$windows$FULL$to_oneway_ann, r_sb2$windows$FULL$cost_ann_pct))

# =============================================================================
# Formal scoring: build_bt_result (contract) + audit + essence_score(sweep, 40)
#   sim_result shape = run_tsmom_timing.R monthly precedent.
#   NAV = cumprod value path (contract input construction, tsmom/valearn precedent
#   - not a performance metric; all metrics from contract machinery).
# =============================================================================
mk_bt <- function(series, run_id, spec_note) {
  s <- merge(series, BMM[, .(ym, BM_Ret_m)], by = "ym", all.x = TRUE)
  setorder(s, Date)
  n_bm_na <- s[, sum(is.na(BM_Ret_m))]
  s[is.na(BM_Ret_m), BM_Ret_m := 0]
  ED  <- xts(s$net, order.by = s$Date)
  BMx <- xts(s$BM_Ret_m, order.by = s$Date)
  nav <- cumprod(1 + s$net)
  sim <- list(DAILY_NAV_DT = data.table(Date = s$Date, NAV = nav),
              strategy_xts = ED, bm_xts = BMx,
              HOLDINGS_LOG = list(),
              PORTFOLIO_LOG = data.table(Exec_Date = s$Date))
  spec <- list(strategy_name = run_id,
    signal = "score_eff = 0.65*score_core_z + 0.35*score_defense_z (b1-verified 7-factor, factor_panel_7f)",
    weighting = spec_note,
    rebalance = "monthly (month-end t -> hold t+1)",
    cost_model = "v2.4_kr_retail_15bps delta (cost_t = 0.0015 x sum|dW| both legs, drift-aware)",
    lookahead_prevention = "weights at sig month-end t apply to next return row t+1 (PIT t-1 info only); data_cutoff=2026-04-30")
  bt <- build_bt_result(sim, spec, run_id = run_id, strategy_id = run_id,
    strategy_version = "stageb_v1", benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "K200_KQ150_prod_panel", code_version = "stageb_measure_v1",
    created_by_agent = "trackB-stageB-subagent")
  bt <- audit_bt_result(bt)
  attr(bt, "n_bm_na") <- n_bm_na
  bt
}

cat("\n[formal] SB1 contract scoring...\n")
bt1 <- mk_bt(r_sb1$series, "SB1_B1V4_SOLO", "top-20 EW, holding band 1.5N (hold while rank<=30)")
es1 <- essence_score(bt1, n_trials_cumulative = N_TRIALS_CUM, selection_type = "sweep")
cat("\n[formal] SB2 contract scoring...\n")
bt2 <- mk_bt(r_sb2$series, "SB2_B1V4_PLUS_LIQ2E8", "top-20 EW, band 1.5N AND AvgTV20>=2e8 KRW at selection (PIT t-1)")
es2 <- essence_score(bt2, n_trials_cumulative = N_TRIALS_CUM, selection_type = "sweep")

audit_summary <- function(bt) {
  a <- as.data.table(bt$audit)
  list(n_fail_critical = a[status == "FAIL" & severity == "critical", .N],
       n_fail = a[status == "FAIL", .N], n_warn = a[status == "WARN", .N],
       n_pass = a[status == "PASS", .N])
}
au1 <- audit_summary(bt1); au2 <- audit_summary(bt2)
cat(sprintf("[formal] SB1 audit: crit_fail=%d fail=%d warn=%d pass=%d | grade=%s\n",
            au1$n_fail_critical, au1$n_fail, au1$n_warn, au1$n_pass, es1$grade))
cat(sprintf("[formal] SB2 audit: crit_fail=%d fail=%d warn=%d pass=%d | grade=%s\n",
            au2$n_fail_critical, au2$n_fail, au2$n_warn, au2$n_pass, es2$grade))

# =============================================================================
# STEP 1: correlation gatekeeper (per spec, FULL common window)
# =============================================================================
mk_aligned <- function(series) {
  j <- merge(series[, .(ym, Date, spec_net = net)],
             l5[, .(ym = realized_ym, book_net = ret_L5_V2, ret_orig)],
             by = "ym")                                   # inner join (prereg alignment)
  j <- merge(j, BMM[, .(ym, BM_Ret_m)], by = "ym", all.x = TRUE)
  j[is.na(BM_Ret_m), BM_Ret_m := 0]
  setorder(j, Date)
  j
}
gate1 <- function(j, spec_id) {
  cp <- suppressWarnings(cor(j$spec_net, j$book_net))
  cd <- suppressWarnings(cor(j$spec_net, j$ret_orig))
  pass <- is.finite(cp) && abs(cp) < 0.30
  cat(sprintf("[STEP1] %s: n_common=%d | cor_primary(vs book L5)=%.4f | cor_diag(vs ret_orig)=%.4f -> G1 %s\n",
              spec_id, nrow(j), cp, cd, ifelse(pass, "PASS", "FAIL (DISQUALIFIED_BOOK_MARGINAL)")))
  list(spec_id = spec_id, n_common = nrow(j),
       cor_primary_vs_bookL5 = round(cp, 4), cor_diag_vs_ret_orig = round(cd, 4),
       g1_pass = pass,
       verdict_step1 = ifelse(pass, "ELIGIBLE", "DISQUALIFIED_BOOK_MARGINAL"))
}
al1 <- mk_aligned(r_sb1$series)
al2 <- mk_aligned(r_sb2$series)
g1_sb1 <- gate1(al1, "SB1_B1V4_SOLO")
g1_sb2 <- gate1(al2, "SB2_B1V4_PLUS_LIQ2E8")

# =============================================================================
# windowed contract metrics for any monthly net series (identical machinery all arms)
# =============================================================================
WIN <- list(IS  = c("2005-01-01", "2018-12-31"),
            OOS = c("2019-01-01", "2026-04-30"),
            FULL = c("1900-01-01", "2026-04-30"))
arm_metrics <- function(dt, retcol, run_id, wn) {
  lo <- as.Date(WIN[[wn]][1]); hi <- as.Date(WIN[[wn]][2])
  w <- dt[Date >= lo & Date <= hi]
  if (nrow(w) < 12L) return(list(n_months = nrow(w)))
  r <- w[[retcol]]
  nx <- xts(r, order.by = w$Date)
  prt <- data.table(date = w$Date, ret_net = r, frequency = "monthly")
  brt <- data.table(date = w$Date, benchmark_ret = w$BM_Ret_m, benchmark_id = "KOSPI200")
  bc <- tryCatch(build_benchmark_compare(prt, brt, run_id = paste0(run_id, "_", wn),
                                         strategy_id = run_id, annualization_factor = 12),
                 error = function(e) NULL)
  getbc <- function(nm) {
    if (is.null(bc)) return(NA_real_)
    v <- as.data.table(bc)[metric_name == nm, active_value]
    if (length(v) == 0) NA_real_ else as.numeric(v[1])
  }
  list(n_months = nrow(w),
       sr_net   = round(as.numeric(SharpeRatio.annualized(nx, Rf = 0, scale = 12)), 4),
       cagr_net = round(as.numeric(Return.annualized(nx, scale = 12)), 5),
       mdd_net  = round(as.numeric(maxDrawdown(nx)), 5),
       calmar   = round(as.numeric(Return.annualized(nx, scale = 12)) /
                        max(as.numeric(maxDrawdown(nx)), 1e-9), 4),
       net_ir   = round(getbc("Information_Ratio"), 4),
       port_t_nw = round(getbc("Portfolio_Alpha_t_NW_lag3"), 4),
       alpha_ann = round(getbc("Alpha_Annualized"), 5))
}

# =============================================================================
# STEP 2-4: blend grid (ONLY for G1-pass specs; prereg forking block otherwise)
# =============================================================================
GRID <- c(0.90, 0.85, 0.80, 0.75)   # w_book (FROZEN)
blend_results <- list(); COMMITS <- list()
run_blend_for_spec <- function(j, spec_id) {
  Rx <- xts(as.matrix(j[, .(book = book_net, spec = spec_net)]), order.by = j$Date)
  arm_names <- "BOOK_L5_ONLY"; arm_wb <- 1.0
  series_list <- list(BOOK_L5_ONLY = j[, .(Date, ym, ret = book_net, BM_Ret_m)])
  for (wb in GRID) {
    a_nm <- sprintf("BLEND_%02d_%02d", round(wb * 100), round((1 - wb) * 100))
    pf <- Return.portfolio(R = Rx, weights = c(wb, 1 - wb), rebalance_on = "months")
    bl <- data.table(Date = as.Date(index(pf)), ret = as.numeric(pf))
    bl <- merge(bl, j[, .(Date, ym, BM_Ret_m)], by = "Date")
    setorder(bl, Date)
    series_list[[a_nm]] <- bl
    arm_names <- c(arm_names, a_nm); arm_wb <- c(arm_wb, wb)
  }
  wb_map <- setNames(arm_wb, arm_names)
  # --- STEP 3: IS metrics ONLY -> commit ---
  is_rows <- list()
  for (a_nm in arm_names) {
    m <- arm_metrics(series_list[[a_nm]], "ret", paste0(spec_id, "_", a_nm), "IS")
    is_rows[[a_nm]] <- data.table(arm = a_nm, w_book = wb_map[[a_nm]],
      n_months = m$n_months, ir = m$net_ir, sr = m$sr_net, mdd = m$mdd_net)
  }
  is_tab <- rbindlist(is_rows)
  book_is_ir <- is_tab[arm == "BOOK_L5_ONLY", ir]
  is_tab[, d_ir_samebasis := round(ir - book_is_ir, 4)]
  cand <- is_tab[arm != "BOOK_L5_ONLY"]
  best <- max(cand$d_ir_samebasis, na.rm = TRUE)
  tied <- cand[d_ir_samebasis > best - 0.005]
  winner <- if (nrow(tied) > 1) tied[which.min(mdd), arm] else cand[which.max(d_ir_samebasis), arm]
  commit <- list(committed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                 spec_id = spec_id,
                 rule = "argmax IS delta_IR_samebasis over frozen grid; tie |d|<0.005 -> lower IS MDD",
                 is_table = is_tab, selected = winner,
                 note = "committed BEFORE any OOS value inspected (prereg STEP 3)")
  COMMITS[[spec_id]] <<- commit
  write_json(COMMITS, file.path(TB, "is_selection_commit.json"),
             pretty = TRUE, auto_unbox = TRUE, digits = 8)
  cat(sprintf("[STEP3] %s IS selection COMMITTED: %s (file written before OOS)\n", spec_id, winner))
  # --- STEP 4-5: OOS + FULL for all arms (reporting; selection already locked) ---
  all_rows <- list()
  for (a_nm in arm_names) for (wn in c("IS", "OOS", "FULL")) {
    m <- arm_metrics(series_list[[a_nm]], "ret", paste0(spec_id, "_", a_nm), wn)
    all_rows[[paste(a_nm, wn)]] <- data.table(spec_id = spec_id, arm = a_nm,
      w_book = wb_map[[a_nm]], window = wn,
      n_months = m$n_months, sr_net = m$sr_net, cagr_net = m$cagr_net,
      mdd_net = m$mdd_net, net_ir = m$net_ir, port_t_nw = m$port_t_nw)
  }
  tab <- rbindlist(all_rows)
  for (wn in c("IS", "OOS", "FULL")) {
    bir <- tab[arm == "BOOK_L5_ONLY" & window == wn, net_ir]
    bsr <- tab[arm == "BOOK_L5_ONLY" & window == wn, sr_net]
    tab[window == wn, d_ir_samebasis := round(net_ir - bir, 4)]
    tab[window == wn, d_sr_samebasis := round(sr_net - bsr, 4)]
  }
  list(spec_id = spec_id, table = tab, winner = winner, commit = commit,
       series_list = series_list)
}

eligible <- c(if (g1_sb1$g1_pass) "SB1" else NULL, if (g1_sb2$g1_pass) "SB2" else NULL)
if (length(eligible) == 0) {
  cat("\n[STEP2-4] SKIPPED for BOTH specs - G1 disqualification (prereg forking block: no blend grid measured)\n")
} else {
  if (g1_sb1$g1_pass) blend_results$SB1 <- run_blend_for_spec(al1, "SB1_B1V4_SOLO")
  if (g1_sb2$g1_pass) blend_results$SB2 <- run_blend_for_spec(al2, "SB2_B1V4_PLUS_LIQ2E8")
}

# =============================================================================
# Judgments (G1/G2/G3 per prereg judgment_criteria_preregistered)
# =============================================================================
judge_spec <- function(g1, br) {
  out <- list(G1_correlation = list(pass = g1$g1_pass,
        value = g1$cor_primary_vs_bookL5, bound = 0.30))
  if (!g1$g1_pass) {
    out$G2_delta_ir <- list(pass = NA, note = "not measured - G1 disqualified, blend grid blocked by prereg")
    out$G3_oos_nonworsening <- list(pass = NA, note = "not measured - G1 disqualified")
    out$verdict <- "DISQUALIFIED_BOOK_MARGINAL (G1 fail)"
    return(out)
  }
  w <- br$winner; tab <- br$table
  full_d <- tab[arm == w & window == "FULL", d_ir_samebasis]
  oos_d  <- tab[arm == w & window == "OOS",  d_ir_samebasis]
  oos_ds <- tab[arm == w & window == "OOS",  d_sr_samebasis]
  blend_full_ir <- tab[arm == w & window == "FULL", net_ir]
  out$G2_delta_ir <- list(pass = isTRUE(full_d >= 0.05), value = full_d, threshold = 0.05,
    parallel_vs_stored_1p5754 = round(blend_full_ir - 1.5754, 4),
    parallel_caveat = "stored 1.5754 = gross/flat-era/full-267m; blend IR = net/v2.4-legs/cutoff window - basis mismatch, governor manual use only")
  out$G3_oos_nonworsening <- list(pass = isTRUE(oos_d >= 0 && oos_ds >= 0),
    oos_d_ir = oos_d, oos_d_sr = oos_ds)
  out$verdict <- if (isTRUE(out$G1_correlation$pass) && isTRUE(out$G2_delta_ir$pass) &&
                     isTRUE(out$G3_oos_nonworsening$pass)) "STAGE_B_PASS"
                 else sprintf("STAGE_B_FAIL (legs: %s)",
                   paste(c(if (!isTRUE(out$G2_delta_ir$pass)) "G2" else NULL,
                           if (!isTRUE(out$G3_oos_nonworsening$pass)) "G3" else NULL), collapse = "+"))
  out
}
jd1 <- judge_spec(g1_sb1, blend_results$SB1)
jd2 <- judge_spec(g1_sb2, blend_results$SB2)
cat(sprintf("\n[JUDGE] SB1: %s\n[JUDGE] SB2: %s\n", jd1$verdict, jd2$verdict))

# =============================================================================
# STEP 5: persist full report (json + csv + rds)
# =============================================================================
es_pack <- function(es) list(grade = es$grade, metric_type = es$metric_type,
  essence = es$essence, n_trials_cumulative = es$n_trials_cumulative,
  selection_type = es$selection_type, dsr_gate_applied = es$dsr_gate_applied,
  oos_stat_version = es$oos_stat_version, oos_retention_splits = es$oos_retention_splits,
  oos_band_status = es$oos_band_status, hard_fail = es$hard_fail, reasons = es$reasons)

spec_window_rows <- function(r, spec_id) {
  rows <- list()
  for (wn in c("FULL", "IS", "OOS")) {
    m <- r$windows[[wn]]
    rows[[wn]] <- data.table(block = "spec_solo", spec_id = spec_id, arm = spec_id,
      w_book = NA_real_, window = wn, n_months = m$n_months, sr_net = m$sr_net,
      cagr_net = m$cagr_net, mdd_net = m$mdd_net, calmar = m$calmar,
      net_ir = m$net_ir, port_t_nw = m$port_t_nw,
      to_oneway_ann = m$to_oneway_ann, cost_ann_pct = m$cost_ann_pct,
      d_ir_samebasis = NA_real_, d_sr_samebasis = NA_real_,
      metric_type = "canonical_screen", data_cutoff = "2026-04-30")
  }
  rbindlist(rows)
}
csv_rows <- rbind(spec_window_rows(r_sb1, "SB1_B1V4_SOLO"),
                  spec_window_rows(r_sb2, "SB2_B1V4_PLUS_LIQ2E8"))
# book L5 arm metrics on each spec's common window (FULL/IS/OOS) - estimated label
for (sp in list(list(al = al1, id = "SB1_B1V4_SOLO"), list(al = al2, id = "SB2_B1V4_PLUS_LIQ2E8"))) {
  for (wn in c("FULL", "IS", "OOS")) {
    dtb <- copy(sp$al); dtb[, ret := book_net]
    m <- arm_metrics(dtb, "ret", paste0("BOOK_L5_on_", sp$id), wn)
    csv_rows <- rbind(csv_rows, data.table(block = "book_L5", spec_id = sp$id,
      arm = "BOOK_L5_ONLY", w_book = 1.0, window = wn, n_months = m$n_months,
      sr_net = m$sr_net, cagr_net = m$cagr_net, mdd_net = m$mdd_net, calmar = m$calmar,
      net_ir = m$net_ir, port_t_nw = m$port_t_nw, to_oneway_ann = NA_real_,
      cost_ann_pct = NA_real_, d_ir_samebasis = NA_real_, d_sr_samebasis = NA_real_,
      metric_type = "estimated", data_cutoff = "2026-04-30"), fill = TRUE)
  }
}
if (length(blend_results) > 0) for (br in blend_results) {
  bt <- copy(br$table)
  bt[, `:=`(block = "blend_grid", calmar = NA_real_, to_oneway_ann = NA_real_,
            cost_ann_pct = NA_real_, metric_type = "estimated", data_cutoff = "2026-04-30")]
  csv_rows <- rbind(csv_rows, bt, fill = TRUE)
}
fwrite(csv_rows, file.path(TB, "stageb_results.csv"))

results <- list(
  task = "Track B Stage B measurement (Composition Search Cycle 2)",
  prereg_file = "04_Research/composition_search/cycle2_trackB/prereg_stageb.json",
  prereg_frozen_at = "2026-06-12T09:19:58+09:00",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  data_cutoff = "2026-04-30",
  data_cutoff_note = "rawdata post 2026-05-01 contaminated (Track R repairing); all series truncated; spec panel ends natively 2026-04",
  cost_model = "v2.4_kr_retail_15bps delta (engine legs); book L5 = production realized legs (mixed basis disclosed)",
  selection_type = "sweep",
  n_trials_cumulative = N_TRIALS_CUM,
  integrity = list(
    repro_gate = list(target = 0.9566, measured = sb1_full_sr, pass = repro_pass,
                      fresh_vs_stored_series_max_abs_net_diff = xchk_max),
    l5_v2_recomposition_max_resid = l5_resid,
    ret_orig_identity_max_diff = ro_resid,
    book_state_incumbent_ir_stored = stored_ir,
    bm_na_filled_sb1 = attr(bt1, "n_bm_na"), bm_na_filled_sb2 = attr(bt2, "n_bm_na")
  ),
  formal_scoring = list(
    note = "build_bt_result(frequency=monthly) + audit_bt_result + essence_score(selection_type=sweep, n_trials=40). Engine series = canonical_screen (trackv_engine); contract metric_type label applies to the bt_result artifact. Prereg no_backtested_claim: forge run_all re-run REQUIRED before any graduation/admission claim.",
    SB1_B1V4_SOLO = c(list(audit = au1), es_pack(es1)),
    SB2_B1V4_PLUS_LIQ2E8 = c(list(audit = au2), es_pack(es2))
  ),
  step1_correlation_gatekeeper = list(SB1_B1V4_SOLO = g1_sb1, SB2_B1V4_PLUS_LIQ2E8 = g1_sb2,
    label = "cor on FULL common window; spec=canonical_screen x book L5=estimated"),
  blend_grid = if (length(blend_results) == 0)
    "NOT MEASURED - both specs DISQUALIFIED at STEP 1 (prereg forking block: |cor|>=0.30 -> no blend grid)"
    else lapply(blend_results, function(b) list(winner = b$winner, table = b$table)),
  judgments = list(SB1_B1V4_SOLO = jd1, SB2_B1V4_PLUS_LIQ2E8 = jd2),
  metric_type_labels = list(spec_series = "canonical_screen", book_L5_series = "estimated",
    blend_arms = "estimated", no_backtested_claim_for_stageB_gates = TRUE),
  book_state_write = "NONE - admission recommendation only; book_state write = Q-Lead + Dohoon manual (charter section 4)"
)
write_json(results, file.path(TB, "stageb_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

saveRDS(list(sb1_series = r_sb1$series, sb2_series = r_sb2$series,
             aligned_sb1 = al1, aligned_sb2 = al2,
             blend_series = if (length(blend_results)) lapply(blend_results, `[[`, "series_list") else NULL,
             bt_sb1 = bt1, bt_sb2 = bt2),
        file.path(TB, "stageb_series.rds"))

cat("\n[done] written:\n")
cat("  ", file.path(TB, "stageb_results.json"), "\n")
cat("  ", file.path(TB, "stageb_results.csv"), "\n")
cat("  ", file.path(TB, "stageb_series.rds"), "\n")
cat("\n[summary]\n")
cat(sprintf("  SB1: grade=%s | cor=%.4f -> %s\n", es1$grade, g1_sb1$cor_primary_vs_bookL5, jd1$verdict))
cat(sprintf("  SB2: grade=%s | cor=%.4f -> %s\n", es2$grade, g1_sb2$cor_primary_vs_bookL5, jd2$verdict))
