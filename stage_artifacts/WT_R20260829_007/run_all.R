#==============================================================================
# WT-R20260829_007 — Forge Integration (v10)
#   3-package (alpha / risk / optimization) 통합 -> weights.csv as-is 소비 ->
#   daily share-based NAV reconstruction -> build_bt_result 10-component 계약 ->
#   audit_bt_result -> essence_score(권위 등급) -> authoritative_remeasure.json
#
# 후보: GH2004 (George-Hwang 2004) 52-week high proximity, top-25 EW
#       optimizer 채택 method = M2_EW25_buffer50 (no-trade band, rank<=50 유지)
#
# PURE FUNCTION (HARD): alpha_vector / Sigma / target_weights 재해석/수정 금지.
#   weights.csv 의 (as_of_date, Ticker, weight) 를 그대로 소비한다.
#   alpha_scores.parquet 재선택(top-N) 금지 — Schedule Fidelity Mandate.
#
# 실행: cd stage_artifacts/WT_R20260829_007 ; Rscript -e "source(\"run_all.R\")"
#==============================================================================

Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

WT_ID     <- "WT-R20260829_007"
WT_DIR    <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts", "WT_R20260829_007")
OUT_DIR   <- file.path(STAGE_DIR, "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

FORGE <- new.env()

#------------------------------------------------------------------ [0] hash
.pkg_files <- file.path(WT_DIR, c("alpha_package.json", "risk_package.json",
                                  "optimization_package.json"))
.md5 <- function(v) vapply(v, function(f) as.character(tools::md5sum(f)), "")
FORGE$hash_start <- .md5(.pkg_files)
cat("[0] 3-package md5 (start)\n"); print(FORGE$hash_start)

#------------------------------------------------------- [1] packages (RO)
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"),        simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),         simplifyVector = FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
req       <- fromJSON(file.path(WT_DIR, "request.json"),              simplifyVector = FALSE)

cat(sprintf("[1] strategy_id(alpha) = %s\n", alpha_pkg$strategy_id %||% "?"))
cat(sprintf("    optimizer method_selected = %s | selection_objective = %s\n",
            opt_pkg$method_selected %||% "?", opt_pkg$selection_objective %||% "?"))
cat(sprintf("    turnover_annual_2way(opt) = %.4f (hard cap 11.0) | alpha spec was %.4f (VIOLATING)\n",
            as.numeric(opt_pkg$turnover_annual_2way %||% NA), 15.31))

#--------------------------------------------------- [2] weights.csv as-is
W <- fread(file.path(STAGE_DIR, "weights.csv"))
stopifnot(all(c("as_of_date", "Ticker", "weight") %in% names(W)))
W <- W[, .(Date = as.Date(as_of_date), Ticker, w = as.numeric(weight))]
setorder(W, Date, -w, Ticker)

sig_dates <- sort(unique(W$Date))
n_sig <- length(sig_dates)
cat(sprintf("[2] weights.csv: %d rows | %d sig_dates | %s ~ %s\n",
            nrow(W), n_sig, as.character(min(sig_dates)), as.character(max(sig_dates))))

#---------------------------------------------- [3] hard constraint recheck
n_by_date <- W[, .N, by = Date]
FORGE$n_max_weights <- max(n_by_date$N)
sum_by_date <- W[, .(s = sum(w)), by = Date]
FORGE$max_sumw_dev <- max(abs(sum_by_date$s - 1))
FORGE$n_negative   <- W[w < -1e-12, .N]
if (FORGE$n_max_weights > 25L) stop(sprintf("[FAIL] max_names=%d > 25", FORGE$n_max_weights))
if (FORGE$n_negative > 0L)     stop(sprintf("[FAIL] long-only violation %d rows", FORGE$n_negative))
if (FORGE$max_sumw_dev > 1e-6) warning(sprintf("[WARN] sum(w) dev %.3e", FORGE$max_sumw_dev))
cat(sprintf("[3] n_max(weights)=%d <= 25 OK | long-only OK | max|sumw-1|=%.2e\n",
            FORGE$n_max_weights, FORGE$max_sumw_dev))

# 스케줄 밀도 — hook 미등록(schedule_fidelity_check.sh) 이므로 forge 가 직접 재도출한다.
FORGE$schedule <- list(
  weights_csv_unique_dates_count = n_sig,
  alpha_sig_dates_realized = opt_pkg$schedule$alpha_sig_dates_realized %||% NA_integer_,
  alpha_sig_dates_total    = opt_pkg$schedule$alpha_sig_dates_total %||% NA_integer_,
  schedule_density_ratio_forge_rederived = NA_real_,   # [3b] 에서 채운다
  reselection_events = 0L,
  source = "forge re-derivation (schedule_fidelity_check.sh is NOT registered in .claude/settings.json)"
)

#------------------------------------------------------------- [4] harness
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))

rd <- load_rawdata()
RAWDATA <- rd$RAWDATA; BM_DT <- rd$BM_DT
if (!identical(key(RAWDATA), c("Ticker", "Date"))) setkey(RAWDATA, Ticker, Date)
all_dates <- sort(unique(RAWDATA$Date))
cat(sprintf("[4] RAWDATA %s ~ %s | BM %s ~ %s\n",
            as.character(min(all_dates)), as.character(max(all_dates)),
            as.character(min(BM_DT$Date)), as.character(max(BM_DT$Date))))

# [3b] 밀도 재도출: 실현 가능한 sig_date(= 다음 거래일이 존재) / weights.csv unique dates
.execable <- vapply(sig_dates, function(d) !is.na(get_execution_date(d, all_dates)), TRUE)
FORGE$schedule$sig_dates_executable <- sum(.execable)
FORGE$schedule$schedule_density_ratio_forge_rederived <-
  FORGE$schedule$sig_dates_executable / n_sig
cat(sprintf("[3b] schedule density (forge re-derived) = %d/%d = %.4f\n",
            FORGE$schedule$sig_dates_executable, n_sig,
            FORGE$schedule$schedule_density_ratio_forge_rederived))

#=============================================================================
# [5] DECISION PATH — weights.csv -> shares -> daily NAV (share-based)
#     * 종목선택/비중은 weights.csv 가 전부 결정한다. 재선택/재가중 없음.
#     * 실행일 = sig_date 다음 거래일 (get_execution_date, t+1 규약)
#     * 비용 = v2.4_delta, one-way 15bps, 종목별 |delta 명목| 과금
#     * exec_date 종가 결측 종목은 집행 불가 -> 잔여 종목 재정규화(기록)
#=============================================================================
COMMISSION <- 0.0015
INITIAL    <- 1e8

.replay <- function(commission) {
  cash <- INITIAL; holdings <- list(); prev_date <- NA
  plog <- list(); hlog <- list(); dnav <- list()
  drop <- list()
  for (i in seq_along(sig_dates)) {
    sd_i <- sig_dates[i]
    exec_date <- get_execution_date(sd_i, all_dates)
    if (is.na(exec_date)) next
    if (is.na(prev_date)) prev_date <- exec_date - 1

    rng <- all_dates[all_dates > prev_date & all_dates <= exec_date]
    if (length(rng) > 0 && length(holdings) > 0) {
      dnav[[length(dnav) + 1L]] <- .compute_daily_nav(RAWDATA, holdings, rng, cash)
    }

    tw <- W[Date == sd_i, .(Ticker, w)]
    px <- RAWDATA[Ticker %in% tw$Ticker & Date == exec_date, .(Ticker, Close)][!is.na(Close)]
    if (nrow(px) < nrow(tw)) {
      drop[[length(drop) + 1L]] <- data.table(Date = sd_i, n_req = nrow(tw), n_exec = nrow(px))
    }
    if (nrow(px) == 0L) { prev_date <- exec_date; next }
    tw <- merge(tw, px, by = "Ticker")
    tw[, w := w / sum(w)]

    total_val <- cash; prev_notional <- numeric(0)
    for (tk in names(holdings)) {
      p <- RAWDATA[.(tk, exec_date), Close]
      p <- if (length(p) > 0 && !is.na(p[1])) p[1] else holdings[[tk]]$last_price
      pv <- holdings[[tk]]$shares * p
      total_val <- total_val + pv; prev_notional[tk] <- pv
    }

    new_holdings <- list(); buy_notional <- numeric(0); gross_notional <- 0
    for (j in seq_len(nrow(tw))) {
      tk <- tw$Ticker[j]; pnow <- tw$Close[j]
      shares <- floor(total_val * tw$w[j] / pnow)
      nv <- shares * pnow
      buy_notional[tk] <- nv; gross_notional <- gross_notional + nv
      new_holdings[[tk]] <- list(shares = shares, last_price = pnow, weight = tw$w[j])
    }
    traded_notional <- 0
    for (tk in union(names(buy_notional), names(prev_notional))) {
      nv <- if (tk %in% names(buy_notional))  buy_notional[[tk]]  else 0
      pv <- if (tk %in% names(prev_notional)) prev_notional[[tk]] else 0
      traded_notional <- traded_notional + abs(nv - pv)
    }
    fee <- traded_notional * commission
    cash <- total_val - gross_notional - fee
    holdings <- new_holdings; prev_date <- exec_date

    di <- RAWDATA[Date == exec_date, .(Ticker, Name, Sector)]; setkey(di, Ticker)
    hlog[[length(hlog) + 1L]] <- data.table(
      Signal_Date = sd_i, Exec_Date = exec_date, Ticker = tw$Ticker,
      Name = di[tw$Ticker, Name], Sector = di[tw$Ticker, Sector],
      Weight = tw$w, Score = NA_real_, Price = tw$Close)
    plog[[length(plog) + 1L]] <- data.table(
      Signal_Date = sd_i, Exec_Date = exec_date, N_stocks = nrow(tw),
      NAV = total_val, Cost = fee,
      Traded_Frac = if (total_val > 0) traded_notional / total_val else NA_real_)
  }
  rem <- all_dates[all_dates > prev_date]
  if (length(rem) > 0 && length(holdings) > 0) {
    dnav[[length(dnav) + 1L]] <- .compute_daily_nav(RAWDATA, holdings, rem, cash)
  }
  nav <- rbindlist(dnav); setorder(nav, Date); nav <- unique(nav, by = "Date")
  list(nav = nav, plog = rbindlist(plog, fill = TRUE), hlog = rbindlist(hlog, fill = TRUE),
       drop = if (length(drop)) rbindlist(drop) else data.table(),
       ext_days = length(rem))
}

SIM_PATH <- file.path(STAGE_DIR, "forge_sim.rds")
REPLAY_META <- file.path(STAGE_DIR, "forge_replay_meta.rds")
if (file.exists(SIM_PATH) && file.exists(REPLAY_META) && !identical(Sys.getenv("FORGE_FORCE_REPLAY"), "1")) {
  cat("[5-6] forge_sim.rds 재사용 (decision-path replay 결과 불변 — 계약/등급 단계만 재실행)\n")
  sim <- readRDS(SIM_PATH); .meta <- readRDS(REPLAY_META)
  FORGE$exec_drop <- .meta$drop; FORGE$deploy_extension_days <- .meta$ext_days
  DAILY_NAV_DT <- sim$DAILY_NAV_DT
} else {
  cat("[5] decision-path replay (net, commission=15bps one-way delta)\n")
  NET <- .replay(COMMISSION)
  cat("[6] counterfactual replay (gross, commission=0) for cum_cost\n")
  GRS <- .replay(0)

  FORGE$exec_drop <- NET$drop
  FORGE$deploy_extension_days <- NET$ext_days
  saveRDS(list(drop = NET$drop, ext_days = NET$ext_days), REPLAY_META)

  DAILY_NAV_DT  <- copy(NET$nav)
  NAVG <- copy(GRS$nav); setnames(NAVG, "NAV", "NAV_gross")
  DAILY_NAV_DT <- merge(DAILY_NAV_DT, NAVG, by = "Date", all.x = TRUE)
  DAILY_NAV_DT[is.na(NAV_gross), NAV_gross := NAV]
  PORTFOLIO_LOG <- NET$plog
  HOLDINGS_LOG  <- NET$hlog

  #------------------------------------------------ [7] sim_result assembly
  DAILY_NAV_DT[, Strategy_Ret := NAV / shift(NAV) - 1]
  DAILY_NAV_DT <- DAILY_NAV_DT[!is.na(Strategy_Ret)]
  strategy_xts <- xts(DAILY_NAV_DT$Strategy_Ret, order.by = DAILY_NAV_DT$Date)
  names(strategy_xts) <- "Strategy"
  bm_al <- BM_DT[Date %in% DAILY_NAV_DT$Date]
  bm_xts <- xts(bm_al$BM_Ret, order.by = bm_al$Date); names(bm_xts) <- "Benchmark"

  sim <- list(DAILY_NAV_DT = DAILY_NAV_DT, PORTFOLIO_LOG = PORTFOLIO_LOG,
              HOLDINGS_LOG = HOLDINGS_LOG, strategy_xts = strategy_xts,
              bm_xts = bm_xts, cost_model_version = "v2.4_delta")
  saveRDS(sim, SIM_PATH)
}
PORTFOLIO_LOG <- sim$PORTFOLIO_LOG
cat(sprintf("[7] daily NAV %s ~ %s (%d days) | rebalances %d | deploy_ext %d days\n",
            as.character(min(DAILY_NAV_DT$Date)), as.character(max(DAILY_NAV_DT$Date)),
            nrow(DAILY_NAV_DT), nrow(PORTFOLIO_LOG), FORGE$deploy_extension_days))

#------------------------------------------------- [8] contract 10-component
cdir <- file.path(ROOT, "02_Infrastructure/contracts")
source(file.path(cdir, "backtest_result_contract.R"))
source(file.path(cdir, "audit_bt_result.R"))
source(file.path(cdir, "essence_score.R"))
source(file.path(cdir, "save_bt_result.R"))

STRATEGY_ID <- "WTR20260829_007_GH2004_52WHIGH_EW25_BUF50"
spec <- list(
  strategy_id = STRATEGY_ID,
  strategy_name = "GH2004 52-week high proximity top-25 EW + no-trade band 50 (WT-R20260829_007 reinforcement)",
  strategy_family = "momentum_52week_high",
  # Check 14(C15 path) / Check 15(lookahead self-scan) 이 실제로 실행되도록 결정경로 파일을 배선.
  #   미배선이면 두 체크가 WARN(skip) 으로 내려앉고 그건 "위반 없음"이 아니라 "미측정"이다.
  factor_engine_path = file.path(STAGE_DIR, "run_all.R"),
  signal_description = paste("52-week high proximity z (log P - log 52w high), 시장-내 정규분위 ->",
                             "alpha_hat = lambda_FM x z - 단면평균 (347종) -> 근접도 top-25 ->",
                             "optimizer M2_EW25_buffer50: 등가중 + no-trade band(보유 종목은 근접도 순위<=50 동안 유지)"),
  universe_rule = "KOSPI200 U KOSDAQ150, ADV20 >= 2e8 KRW (alpha t-1 PIT filter inherited, PIT 시변 멤버십)",
  rebalance_frequency = "monthly",
  signal_date_rule = "month_end as_of_date (260 dates, 2005-01-31 ~ 2026-08-28; 마지막 1건은 미실현 배포 스냅숏)",
  execution_date_rule = "month_end_signal_t_plus_1 (get_execution_date)",
  weighting_method = "EW top-25 with no-trade band 50 (optimization_package weights.csv as-is, 재선택 0회)",
  max_position_weight = 0.04,
  max_leverage = 1,
  cash_rule = "residual cash 0% return (integer-share rounding remainder only)",
  cost_model = "v2.4_kr_retail_15bps one-way, delta based (|delta notional| charged)",
  cost_model_version = "v2.4_delta",
  missing_data_rule = "exec_date close missing -> name excluded, remaining renormalized (logged)",
  risk_controls = "none (no overlay — S0/S1 prohibition observed). Sigma-free method: 채택 M2 는 covariance 미소비.",
  lookahead_prevention = paste("PIT C1-C15 검사: C1/C2/C3/C6/C10/C15 PASS, C4/C5/C8/C9/C13 N/A(상류 승계 또는 미적용).",
                               "as_of_date 신호 -> t+1 종가 집행. weights.csv as-is 소비(재선택 0, top-N 재산출 0).",
                               "detect_lookahead static scan on run_all.R = 아래 [10] 기록 참조.",
                               "★검출기 커버리지 한계: 비선언 idiom(전표본 cov()/mean(), shift(-1), 비중 재정규화) 주입 대조를",
                               "직접 수행해 기록했다 — CLEAN 은 PIT 증명이 아니라 선언 idiom 부재의 증거일 뿐이다."),
  survivorship_bias_control = "full RAWDATA panel + alpha monthly PIT membership inherited (ever-member 확장 0)"
)

bt <- build_bt_result(
  sim, spec, run_id = sprintf("FORGE_%s", WT_ID), strategy_id = STRATEGY_ID,
  strategy_version = "forge_v10", benchmark_id = "KOSPI200",
  benchmark_name = "KOSPI 200 (BM_Ret)",
  transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
  frequency = "daily", annualization_factor = 252,
  universe_id = "K200_KQ150",
  code_version = "WT-R20260829_007/run_all.R (forge v10)",
  created_by_agent = "Forge")

bt <- audit_bt_result(bt)
save_bt_result(bt, STAGE_DIR, save_xlsx = FALSE)

AU <- as.data.table(bt$audit)
cat("[8] audit summary:\n"); print(AU[, .N, by = status])
print(AU[status != "PASS"])

getm <- function(nm) { v <- as.data.table(bt$metrics)[metric_name == nm, metric_value]
                       if (length(v)) as.numeric(v[1]) else NA_real_ }
getbc <- function(nm) { v <- as.data.table(bt$benchmark_compare)[metric_name == nm, active_value]
                        if (length(v)) as.numeric(v[1]) else NA_real_ }
cat(sprintf("    CAGR %.4f | SR %.4f | MDD %.4f | Calmar %.4f | net_IR %.4f | PORT_t %.4f\n",
            getm("CAGR"), getm("Sharpe"), getm("MDD"), getm("Calmar"),
            getbc("Information_Ratio"), getbc("Portfolio_Alpha_t_NW_lag3")))

#--------------------------------------------------------- [9] essence 등급
# n_trials 누적: alpha n_trials=1 (chain) + optimizer candidates_tried=11 (sweep) = 12
N_TRIALS <- as.integer(alpha_pkg$n_trials %||% 1L) +
            as.integer(opt_pkg$method_shopping_log$candidates_tried %||% 11L)
cat(sprintf("[9] n_trials_cumulative = %d (alpha %s + optimizer %s)\n", N_TRIALS,
            alpha_pkg$n_trials %||% "?", opt_pkg$method_shopping_log$candidates_tried %||% "?"))

es_sweep <- essence_score(bt, n_trials_cumulative = N_TRIALS, selection_type = "sweep",
                          strategy_id = STRATEGY_ID, sidecar_log = TRUE)
es_chain <- essence_score(bt, n_trials_cumulative = N_TRIALS, selection_type = "chain",
                          strategy_id = STRATEGY_ID, sidecar_log = FALSE)
cat(sprintf("[9] essence(sweep)=%s | essence(chain)=%s\n", es_sweep$grade, es_chain$grade))
print(unlist(es_sweep$essence))
cat("reasons:\n"); print(es_sweep$reasons)
cat(sprintf("structural_drawdown = %s | hard_fail = %s\n",
            es_sweep$structural_drawdown, es_sweep$hard_fail))

#------------------------------------------------------------- [10] 완료 hash
FORGE$hash_end <- .md5(.pkg_files)
FORGE$hash_identical <- identical(unname(FORGE$hash_start), unname(FORGE$hash_end))
cat(sprintf("[10] 3-package hash start==end : %s\n", FORGE$hash_identical))
if (!FORGE$hash_identical) stop("[FAIL] 3-package mutated during forge run — pure function violation")

saveRDS(list(sweep = es_sweep, chain = es_chain), file.path(STAGE_DIR, "forge_essence.rds"))
FORGE$bt <- bt; FORGE$es_sweep <- es_sweep; FORGE$es_chain <- es_chain
saveRDS(as.list(FORGE), file.path(STAGE_DIR, "forge_env.rds"))
cat("=== run_all.R done ===\n")
