# =============================================================================
# driver_valearn_lo.R — valearn 0.7/0.3 LONG-ONLY top-25 baseline (가벼운 driver)
#   목적: run_alpha_search의 run_monthly_simulation 파이프라인이 valearn 5팩터 fe에서
#         OOM(3회)으로 죽음 → driver_ls_generic처럼 sim 파이프라인 없이
#         Return.portfolio(표준함수)로 LONG-only 월간 시계열만 산출 + 계약 경유 측정/등재.
#   ★ driver_ls_generic.R의 build_leg("long")+leg_series 로직 재사용(short 불요).
#   ★ 측정 = build_bt_result(10-component, metric_type=backtested) + audit_bt_result
#            + essence_score(measurement-graduation 권위 등급). 자체합성 금지(표준함수만).
#   ★ 등재 = register_module(v8.1 등급무관) → 04_Research/strategies/STR_valearn_70_top25/
#            sim_result.rds(DAILY_NAV_DT[Date,Strategy_Ret]+bm_xts) + module_catalog.
#   호출(PowerShell run_in_background, -f 금지, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/driver_valearn_lo.R')"
#   출력: stage_artifacts/alpha_search/valearn_70_top25_longonly_result.json
#         + 04_Research/strategies/STR_valearn_70_top25/sim_result.rds (register_module)
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
STRAT_ID    <- "STR_valearn_70_top25"
COMMISSION  <- 0.0015                                       # 15bps round-trip (cost_model v2.3_kr_retail_15bps)
FE_PATH     <- file.path(INFRA, "alpha_search", "fe_valearn.R")

# ★ valearn 0.7/0.3 long-only top-25: fe_valearn N_CAP=25 적용 (운용 max25 baseline)
Sys.setenv(W_V = "0.7", W_E = "0.3", N_CAP = "25")
cat(sprintf("[VALEARN-LO] fe=%s | W_V=0.7 W_E=0.3 N_CAP=25 | strat=%s\n", FE_PATH, STRAT_ID))

# ---- 1. Data + signal (fe: RAWDATA 전역 사용, 중복로드 없음) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]
# 유동성 파생컬럼 (run_alpha_search L80-83 표준 재현; fe_valearn 내부서 자체 .AvgTV20도 재계산하나 무해)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
source(FE_PATH)   # -> FACTORS(Date, Ticker, Score, N)  ★ N = decile∩N_CAP=25 (fe_valearn 산출)
stopifnot(exists("FACTORS"), is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
has_N <- "N" %in% names(FACTORS)
FACTORS <- FACTORS[Date >= START_DATE]
cat(sprintf("[VALEARN-LO] FACTORS rows=%d | signal months=%d | tickers=%d | has_N=%s\n",
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
build_long <- function() {
  L <- vector("list", length(sig_dates)); HOLD <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FACTORS[Date == d]; if (nrow(fd) < 10L) next
    n_sel <- if (has_N) as.integer(fd$N[1]) else max(5L, as.integer(ceiling(nrow(fd) * 0.10)))
    n_sel <- min(n_sel, nrow(fd))
    setorder(fd, -Score)
    sel <- head(fd, n_sel)                                   # top-N by Score (논문/fe N: decile∩25)
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]                                        # equal-weight (fe long-only EW 규약)
    L[[i]]    <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
    HOLD[[i]] <- data.table(Signal_Date = d, Exec_Date = sel_exec(d), Ticker = mp$Ticker,
                            Weight = 1/nrow(mp), Score = sel[match(mp$Ticker, Ticker), Score])
  }
  list(legs = rbindlist(Filter(Negate(is.null), L)),
       hold = rbindlist(Filter(Negate(is.null), HOLD)))
}
sel_exec <- function(d) d   # 시그널=월말, 실행=익영업일 근사(보유수익은 forward 1M로 이미 PIT-safe)

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
#   turnover_t = sum(|w_t - w_{t-1}|)/2 (one-way fraction). 첫달은 전량 진입(=1.0).
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

# ---- 4. 월간 benchmark: 실행월 d -> 실현월 nd 구간 daily BM_Ret 복리 (strategy 실현일 정렬) ----
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
# 각 strategy 실현일(nd = 다음 월말)에, (직전 월말, nd] 구간 daily BM 복리수익을 매핑
me_idx <- data.table(d = me_dates, nd = shift(me_dates, 1L, type = "lead"))[!is.na(nd)]
bm_month <- vector("list", nrow(me_idx))
for (i in seq_len(nrow(me_idx))) {
  d <- me_idx$d[i]; nd <- me_idx$nd[i]
  seg <- bm_d[Date > d & Date <= nd, BM_Ret]
  if (length(seg) < 1L) next
  bm_month[[i]] <- data.table(Date = nd, BM_Ret_m = prod(1 + seg) - 1)  # Return.cumulative 동등(구간복리)
}
bm_mdt <- rbindlist(Filter(Negate(is.null), bm_month))
# strategy 실현일과 정렬
nav_m <- merge(nav_m, bm_mdt, by = "Date", all.x = TRUE)
nav_m[is.na(BM_Ret_m), BM_Ret_m := 0]
nav_m[, NAV := cumprod(1 + Strategy_Ret)]                   # net NAV (cumprod = 표준 누적; bt_result도 동일 사용)

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
  strategy_id = STRAT_ID, strategy_name = "valearn 0.7/0.3 long-only top25",
  strategy_family = "value_earnings_revision_multi_sleeve",
  signal_description = "Sleeve V(value BM, w=0.7) + Sleeve E(earnings-rev 4f 2단계위계 z, w=0.3); top-25 EW long-only",
  universe_rule = "K200_KQ150 membership + 20d ADV>=2e8 (PIT time-varying)",
  rebalance_frequency = "monthly", signal_date_rule = "month_end",
  execution_date_rule = "month_end_signal_t_plus_1", weighting_method = "equal_weight",
  max_position_weight = 0.20, max_leverage = 1.0, cash_rule = "fully_invested",
  cost_model = "v2.3_kr_retail_15bps", missing_data_rule = "drop",
  risk_controls = "long_only", lookahead_prevention = "forward_1M_hold + t-1 liquidity + factor DB Usable_Date",
  survivorship_bias_control = "PIT membership panel"
)
run_id <- paste0("VALEARN_LO_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
bt <- build_bt_result(
  sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = STRAT_ID, strategy_version = "v1.0",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 15, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150", code_version = "driver_valearn_lo",
  created_by_agent = "AlphaSearch"
)
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = NULL)         # 1논문/1알파 → DSR 부적용(n_trials=NULL)

# ---- 7. register_module (v8.1 등급무관) ----
register_module(sim_result, STRAT_ID, grade = es$grade, origin_mode = "alpha_search",
                role = "core", meta = list(strategy_idea = "valearn 0.7/0.3 long-only top25 (overlay baseline)",
                                           w_V = 0.7, w_E = 0.3, n_cap = 25))

# ---- 8. 측정 요약 (연율 SR/MDD/CAGR + essence grade + Carhart4 t + 종목수 + active vs KOSPI200) ----
M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
gm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
sharpe <- gm("Sharpe"); cagr <- gm("CAGR"); mdd <- gm("MDD"); calmar <- gm("Calmar")
net_ir <- gbc("Information_Ratio"); port_t <- gbc("Portfolio_Alpha_t_NW_lag3")
excess_cum <- gbc("Excess_Total_Return"); n_hold <- if (nrow(hold)) round(mean(hold[, .N, by = Signal_Date]$N), 1) else NA_real_

# Carhart4 t (long-only net 시계열 vs KR factor returns) — 가능 시
c4t <- NA_real_; c4a <- NA_real_
mf <- tryCatch({
  if (exists("run_multifactor_regression") && exists("load_kr_factor_returns"))
    run_multifactor_regression(strategy_xts, bm_xts = bm_xts, factor_dt = load_kr_factor_returns())
  else NULL
}, error = function(e) { cat("[VALEARN-LO] Carhart4 회귀 생략:", conditionMessage(e), "\n"); NULL })
if (!is.null(mf) && !is.null(mf$Carhart4)) { c4t <- mf$Carhart4$alpha_tstat; c4a <- mf$Carhart4$alpha * 12 * 100 }

cat(sprintf("[VALEARN-LO-DONE] %s | n_months=%d | Sharpe=%.3f CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f | net_IR=%.3f PORT_t=%.3f | Carhart4 a=%.2f%%/yr t=%.3f | avg_N=%.1f | excess_cum=%.2f%% | GRADE=%s (%s)\n",
            STRAT_ID, nrow(nav_m), sharpe, cagr*100, mdd*100, calmar, net_ir, port_t, c4a, c4t,
            n_hold, excess_cum*100, es$grade, es$reasons))

out <- list(
  experiment = "valearn 0.7/0.3 LONG-ONLY top-25 baseline (run_alpha_search OOM 우회 — 가벼운 Return.portfolio driver)",
  strategy_id = STRAT_ID, fe_path = FE_PATH, run_id = run_id,
  metric_type = "backtested", universe = "K200_KQ150",
  weights = list(w_V = 0.7, w_E = 0.3, n_cap = 25, weighting = "equal_weight"),
  start_date = as.character(START_DATE), n_months = nrow(nav_m), avg_n_holdings = n_hold,
  annualized = list(sharpe = round(sharpe,4), cagr_pct = round(cagr*100,3),
                    mdd_pct = round(mdd*100,3), calmar = round(calmar,4)),
  active_vs_kospi200 = list(net_ir = round(net_ir,4), portfolio_alpha_t_nw_lag3 = round(port_t,4),
                            excess_total_return_pct = round(excess_cum*100,3)),
  carhart4 = list(alpha_ann_pct = round(c4a,3), alpha_t = round(c4t,4)),
  essence = list(grade = es$grade, hard_fail = es$hard_fail, reasons = es$reasons, detail = es$essence),
  registered = "04_Research/strategies/STR_valearn_70_top25/sim_result.rds + module_catalog.json",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(out, file.path(OUT_DIR, "valearn_70_top25_longonly_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] valearn_70_top25_longonly_result.json\n")
