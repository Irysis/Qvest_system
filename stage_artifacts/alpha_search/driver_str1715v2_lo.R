# =============================================================================
# driver_str1715v2_lo.R — STR_1715 v2 (Core consensus + Defense + Value) LONG-ONLY top-25
#   목적: run_alpha_search의 run_monthly_simulation 파이프라인 OOM 회피 →
#         driver_valearn_lo.R처럼 sim 파이프라인 없이 Return.portfolio(표준함수)로
#         LONG-only 월간 시계열만 산출 + 계약 경유 측정/등재.
#   ★ driver_valearn_lo.R 복제(build_long + Return.portfolio + net=gross-turnover*15bps).
#   ★ 측정 = build_bt_result(10-component, metric_type=backtested) + audit_bt_result
#            + essence_score(measurement-graduation 권위 등급). 자체합성 금지(표준함수만).
#   ★ 등재 = register_module(v8.1 등급무관) → 04_Research/strategies/STR_str1715v2/
#            sim_result.rds(DAILY_NAV_DT[Date,Strategy_Ret]+bm_xts) + module_catalog.
#   ★ 가설: STR_1715(Core 0.65 + Defense 0.35, OOS 0.91 · SR1.50)엔 value 0%.
#           value(V01_BM 직교 LS t3.28) 축을 Core+Defense에 30% 삽입하면 OOS robust + SR1.50 위?
#           대조: valearn(value+earnings-rev 2축, OOS −0.517 · SR0.713) / STR_1715(OOS 0.91 · SR1.50).
#   호출(PowerShell run_in_background, -f 금지, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/driver_str1715v2_lo.R')"
#   출력: stage_artifacts/alpha_search/str1715v2_top25_longonly_result.json
#         + 04_Research/strategies/STR_str1715v2/sim_result.rds (register_module)
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
}))
PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))            # load_rawdata
source(file.path(INFRA, "factor_portfolios.R"))           # run_multifactor_regression / load_kr_factor_returns
source(file.path(INFRA, "contracts", "backtest_result_contract.R"))  # build_bt_result
source(file.path(INFRA, "contracts", "audit_bt_result.R"))           # audit_bt_result
source(file.path(INFRA, "contracts", "essence_score.R"))             # essence_score
source(file.path(INFRA, "contracts", "register_module.R"))           # register_module

OUT_DIR     <- file.path(PROJ, "stage_artifacts", "alpha_search")
START_DATE  <- as.Date("2005-01-01")
STRAT_ID    <- "STR_str1715v2"
COMMISSION  <- 0.0015                                       # 15bps round-trip (cost_model v2.3_kr_retail_15bps)
FE_PATH     <- file.path(INFRA, "alpha_search", "fe_str1715v2.R")

# ★ STR_1715 v2 3-sleeve long-only top-25: Core0.45 / Defense0.25 / Value0.30, N_CAP=25
.WC <- Sys.getenv("W_C", "0.45"); .WD <- Sys.getenv("W_D", "0.25"); .WV <- Sys.getenv("W_V", "0.30")
Sys.setenv(W_C = .WC, W_D = .WD, W_V = .WV, N_CAP = "25")
cat(sprintf("[STR1715V2-LO] fe=%s | W_C=%s W_D=%s W_V=%s N_CAP=25 | strat=%s\n",
            FE_PATH, .WC, .WD, .WV, STRAT_ID))

# ---- 1. Data + signal (fe: RAWDATA 전역 사용, 중복로드 없음) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
source(FE_PATH)   # -> FACTORS(Date, Ticker, Score, N)  ★ N = decile∩N_CAP=25 (fe_str1715v2 산출)
stopifnot(exists("FACTORS"), is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
has_N <- "N" %in% names(FACTORS)
FACTORS <- FACTORS[Date >= START_DATE]
cat(sprintf("[STR1715V2-LO] FACTORS rows=%d | signal months=%d | tickers=%d | has_N=%s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker), has_N))

# ---- 2. 월말 패널 + 종목 forward 1M 보유수익 (d 편입결정 -> nd 실현; lookahead 없음) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
RAWDATA[, .ym := NULL]; rm(RAWDATA); gc(FALSE)
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # forward 1M (C2 안전)
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]               # 실현일 nd
setkey(me_panel, Ticker, Date)

sig_dates <- sort(unique(FACTORS$Date)); sig_dates <- sig_dates[sig_dates %in% me_dates]

# ---- 3. LONG leg: 매월 top-N(fe의 N = decile∩cap25) EW -> wide -> Return.portfolio (표준함수) ----
sel_exec <- function(d) d   # 시그널=월말, 실행=익영업일 근사(보유수익은 forward 1M로 이미 PIT-safe)
build_long <- function() {
  L <- vector("list", length(sig_dates)); HOLD <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FACTORS[Date == d]; if (nrow(fd) < 10L) next
    n_sel <- if (has_N) as.integer(fd$N[1]) else max(5L, as.integer(ceiling(nrow(fd) * 0.10)))
    n_sel <- min(n_sel, nrow(fd))
    setorder(fd, -Score)
    sel <- head(fd, n_sel)                                   # top-N by Score (fe N: decile∩25)
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]                                        # equal-weight (long-only EW 규약)
    L[[i]]    <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
    HOLD[[i]] <- data.table(Signal_Date = d, Exec_Date = sel_exec(d), Ticker = mp$Ticker,
                            Weight = 1/nrow(mp), Score = sel[match(mp$Ticker, Ticker), Score])
  }
  list(legs = rbindlist(Filter(Negate(is.null), L)),
       hold = rbindlist(Filter(Negate(is.null), HOLD)))
}

bl   <- build_long()
lg   <- bl$legs
hold <- bl$hold
stopifnot(nrow(lg) > 0)

Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
dts <- Rw$Date
Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = dts)
Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = dts)
gross_x <- Return.portfolio(R = Rx, weights = Wx)            # 매기간 EW rebalance, gross 월간 시계열
colnames(gross_x) <- "gross"

# ---- 3b. NET = gross - turnover*commission (rebalance마다 holding set 교체비용; 표준 차감) ----
to_w <- dcast(lg, Date ~ Ticker, value.var = "w", fill = 0)
to_mat <- as.matrix(to_w[, -1, with = FALSE]); to_dates <- to_w$Date
to_vec <- numeric(nrow(to_mat))
to_vec[1] <- 1.0
for (i in 2:nrow(to_mat)) to_vec[i] <- sum(abs(to_mat[i, ] - to_mat[i - 1, ])) / 2
to_dt   <- data.table(Date = to_dates, turnover = to_vec)
g_dt    <- data.table(Date = index(gross_x), gross = as.numeric(gross_x))
nav_m   <- merge(g_dt, to_dt, by = "Date", all.x = TRUE)
nav_m[is.na(turnover), turnover := 0]
nav_m[, Strategy_Ret := gross - turnover * COMMISSION]      # net 월간 수익 (cost 차감, 자체합성 아님)
setorder(nav_m, Date)

# ---- 4. 월간 benchmark: (직전 월말, nd] 구간 daily BM_Ret 복리 (strategy 실현일 정렬) ----
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
me_idx <- data.table(d = me_dates, nd = shift(me_dates, 1L, type = "lead"))[!is.na(nd)]
bm_month <- vector("list", nrow(me_idx))
for (i in seq_len(nrow(me_idx))) {
  d <- me_idx$d[i]; nd <- me_idx$nd[i]
  seg <- bm_d[Date > d & Date <= nd, BM_Ret]
  if (length(seg) < 1L) next
  bm_month[[i]] <- data.table(Date = nd, BM_Ret_m = prod(1 + seg) - 1)  # 구간복리(Return.cumulative 동등)
}
bm_mdt <- rbindlist(Filter(Negate(is.null), bm_month))
nav_m <- merge(nav_m, bm_mdt, by = "Date", all.x = TRUE)
nav_m[is.na(BM_Ret_m), BM_Ret_m := 0]
nav_m[, NAV := cumprod(1 + Strategy_Ret)]                   # net NAV (cumprod = 표준 누적; bt_result도 동일)

# ---- 5. sim_result-like 구성 (build_bt_result + register_module 스키마 충족, 월간) ----
strategy_xts <- xts(nav_m$Strategy_Ret, order.by = nav_m$Date); names(strategy_xts) <- "Strategy"
bm_xts       <- xts(nav_m$BM_Ret_m,     order.by = nav_m$Date); names(bm_xts) <- "Benchmark"
DAILY_NAV_DT <- data.table(Date = nav_m$Date, NAV = nav_m$NAV, NAV_gross = cumprod(1 + nav_m$gross),
                           Strategy_Ret = nav_m$Strategy_Ret)
HOLDINGS_LOG <- hold
PORTFOLIO_LOG<- data.table(Signal_Date = sig_dates[sig_dates %in% me_dates])

sim_result <- list(
  DAILY_NAV_DT  = DAILY_NAV_DT,
  PORTFOLIO_LOG = PORTFOLIO_LOG,
  HOLDINGS_LOG  = HOLDINGS_LOG,
  strategy_xts  = strategy_xts,
  bm_xts        = bm_xts
)

# ---- 6. build_bt_result (월간 계약) -> audit -> essence_score ----
strategy_spec <- list(
  strategy_id = STRAT_ID, strategy_name = "STR_1715 v2: Core consensus + Defense + Value 3-sleeve long-only top25",
  strategy_family = "multi_sleeve_consensus_defense_value",
  signal_description = paste0("Sleeve Core(earnings-rev consensus C01+C02+C04+C06 2단계위계 z, w=", .WC,
                              ") + Sleeve Defense(Q07+M08+Q25 2단계위계 z, w=", .WD,
                              ") + Sleeve Value(V01_BM z, w=", .WV, "); top-25 EW long-only"),
  universe_rule = "K200_KQ150 membership + 20d ADV>=2e8 (PIT time-varying)",
  rebalance_frequency = "monthly", signal_date_rule = "month_end",
  execution_date_rule = "month_end_signal_t_plus_1", weighting_method = "equal_weight",
  max_position_weight = 0.20, max_leverage = 1.0, cash_rule = "fully_invested",
  cost_model = "v2.3_kr_retail_15bps", missing_data_rule = "drop",
  risk_controls = "long_only", lookahead_prevention = "forward_1M_hold + t-1 liquidity + factor DB Usable_Date",
  survivorship_bias_control = "PIT membership panel"
)
run_id <- paste0("STR1715V2_LO_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
bt <- build_bt_result(
  sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = STRAT_ID, strategy_version = "v2.0",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 15, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150", code_version = "driver_str1715v2_lo",
  created_by_agent = "AlphaSearch"
)
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = NULL)         # 1알파 검증 → DSR 부적용(n_trials=NULL)

# ---- 7. register_module (v8.1 등급무관) ----
register_module(sim_result, STRAT_ID, grade = es$grade, origin_mode = "alpha_search",
                role = "core", meta = list(strategy_idea = "STR_1715 v2 Core+Defense+Value 3-sleeve long-only top25",
                                           w_C = as.numeric(.WC), w_D = as.numeric(.WD), w_V = as.numeric(.WV), n_cap = 25))

# ---- 8. 측정 요약 (연율 SR/MDD/CAGR + OOS retention + essence grade + Carhart4 t + 종목수 + active vs KOSPI200) ----
M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
gm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
sharpe <- gm("Sharpe"); cagr <- gm("CAGR"); mdd <- gm("MDD"); calmar <- gm("Calmar")
net_ir <- gbc("Information_Ratio"); port_t <- gbc("Portfolio_Alpha_t_NW_lag3")
excess_cum <- gbc("Excess_Total_Return"); n_hold <- if (nrow(hold)) round(mean(hold[, .N, by = Signal_Date]$N), 1) else NA_real_

# ---- 8b. OOS retention (★핵심): IS/OOS split Sharpe 비율. essence$essence에 있으면 그대로, 없으면 50/50 split 산출 ----
oos_ret <- tryCatch({
  v <- es$essence$oos_retention
  if (!is.null(v) && is.finite(v)) as.numeric(v) else NA_real_
}, error = function(e) NA_real_)
if (!is.finite(oos_ret)) {
  # fallback: 시간순 50/50 split, active(=strategy-bm) Sharpe OOS/IS (annualized 동일분모라 ratio는 동일)
  r_all  <- nav_m$Strategy_Ret - nav_m$BM_Ret_m
  n_all  <- length(r_all)
  if (n_all >= 24) {
    half <- floor(n_all/2)
    is_r  <- r_all[1:half]; oos_r <- r_all[(half+1):n_all]
    sr_is  <- mean(is_r,  na.rm=TRUE)/sd(is_r,  na.rm=TRUE)
    sr_oos <- mean(oos_r, na.rm=TRUE)/sd(oos_r, na.rm=TRUE)
    oos_ret <- if (is.finite(sr_is) && abs(sr_is) > 1e-8) sr_oos / sr_is else NA_real_
  }
}

# Carhart4 t (long-only net 시계열 vs KR factor returns) — 가능 시
c4t <- NA_real_; c4a <- NA_real_
mf <- tryCatch({
  if (exists("run_multifactor_regression") && exists("load_kr_factor_returns"))
    run_multifactor_regression(strategy_xts, bm_xts = bm_xts, factor_dt = load_kr_factor_returns())
  else NULL
}, error = function(e) { cat("[STR1715V2-LO] Carhart4 회귀 생략:", conditionMessage(e), "\n"); NULL })
if (!is.null(mf) && !is.null(mf$Carhart4)) { c4t <- mf$Carhart4$alpha_tstat; c4a <- mf$Carhart4$alpha * 12 * 100 }

cat(sprintf("[STR1715V2-LO-DONE] %s | n_months=%d | Sharpe=%.3f CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f | net_IR=%.3f PORT_t=%.3f | OOS_retention=%.3f | Carhart4 a=%.2f%%/yr t=%.3f | avg_N=%.1f | excess_cum=%.2f%% | GRADE=%s (%s)\n",
            STRAT_ID, nrow(nav_m), sharpe, cagr*100, mdd*100, calmar, net_ir, port_t, oos_ret, c4a, c4t,
            n_hold, excess_cum*100, es$grade, es$reasons))

out <- list(
  experiment = "STR_1715 v2 (Core consensus + Defense + Value) LONG-ONLY top-25 (run_alpha_search OOM 우회 — 가벼운 Return.portfolio driver)",
  strategy_id = STRAT_ID, fe_path = FE_PATH, run_id = run_id,
  metric_type = "backtested", universe = "K200_KQ150",
  weights = list(w_C = as.numeric(.WC), w_D = as.numeric(.WD), w_V = as.numeric(.WV),
                 n_cap = 25, weighting = "equal_weight"),
  start_date = as.character(START_DATE), n_months = nrow(nav_m), avg_n_holdings = n_hold,
  annualized = list(sharpe = round(sharpe,4), cagr_pct = round(cagr*100,3),
                    mdd_pct = round(mdd*100,3), calmar = round(calmar,4)),
  oos_retention = round(oos_ret, 4),
  active_vs_kospi200 = list(net_ir = round(net_ir,4), portfolio_alpha_t_nw_lag3 = round(port_t,4),
                            excess_total_return_pct = round(excess_cum*100,3)),
  carhart4 = list(alpha_ann_pct = round(c4a,3), alpha_t = round(c4t,4)),
  comparison = list(
    valearn   = list(oos_retention = -0.517, sharpe = 0.713, note = "value+earnings-rev 2축 long-only"),
    str_1715  = list(oos_retention = 0.91,   sharpe = 1.50,  note = "Core consensus + Defense (value 0%)")
  ),
  essence = list(grade = es$grade, hard_fail = es$hard_fail, reasons = es$reasons, detail = es$essence),
  registered = "04_Research/strategies/STR_str1715v2/sim_result.rds + module_catalog.json",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(out, file.path(OUT_DIR, "str1715v2_top25_longonly_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] str1715v2_top25_longonly_result.json\n")
