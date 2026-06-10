# =============================================================================
# driver_in04_lo_A.R — IN04 Net Equity Issuance LONG-ONLY top-25 (★Part A 단독, 가벼운 driver)
#   ★ driver_valearn_lo.R를 그대로 복사 + factor 소스만 fe_single(FACTOR_NAME=IN04)로 교체.
#     2-part 통합 driver(driver_in04_lo.R)는 Part B(다축 상관 daily LS leg 재구성)가
#     full daily Ret 패널(rd_daily)을 무거운 load_month_factors 루프 내내 co-resident로
#     유지 → load_rawdata 직후 비결정 OOM. ★ 본 driver엔 상관(Part B) 코드 일절 없음.
#     valearn_lo가 완주한 그 가벼운 Return.portfolio 구조 그대로(LS leg 재구성 없음).
#
#   ★ OOM fix 정합: fe_single은 universe(.mem) 산출 직후 RAWDATA(fe_env 바인딩)를 rm —
#     본 driver는 me_panel(forward 1M 보유수익)을 fe_single source *이전에* 구성해
#     fe_single의 RAWDATA 해제가 me_panel 구성을 깨지 않도록 한다(가벼운 단일 패스).
#
#   ★ 측정 = build_bt_result(10-component, metric_type=backtested) + audit + essence_score.
#            자체합성 금지(Return.portfolio/PerformanceAnalytics 표준함수만).
#   ★ 등재 = register_module(v8.1 등급무관) → STR_IN04_top25 / module_catalog.
#   ★ governor/book_state 미사용(measurement+register만). WT-id 금지.
#
#   ★ 판정: long-only OOS retention 양수(0.5+)면 value(LO OOS -0.517 붕괴)와 결정적 차이
#           = 진짜 직교 슬리브. 붕괴면 LS-only(value형 long-only 벽 재확인).
#
#   호출(PowerShell run_in_background, -f 금지, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/driver_in04_lo_A.R')"
#   출력: stage_artifacts/alpha_search/in04_top25_longonly_A_result.json
#         + 04_Research/strategies/STR_IN04_top25/sim_result.rds (register_module)
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
}))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

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
STRAT_ID    <- "STR_IN04_top25"
COMMISSION  <- 0.0015                                       # 15bps round-trip (cost_model v2.3_kr_retail_15bps)
FE_PATH     <- file.path(INFRA, "alpha_search", "fe_single.R")
IN04_F      <- "IN04_Net_Equity_Issuance"
N_CAP       <- 25L

# ★ fe_single: 단일 factor(IN04) Z_Score_Aligned. N marker 없음 → driver가 top-N_CAP 선택.
Sys.setenv(FACTOR_NAME = IN04_F)
cat(sprintf("[IN04-LO-A] fe=%s | FACTOR_NAME=%s N_CAP=%d | strat=%s | START=%s\n",
            FE_PATH, IN04_F, N_CAP, STRAT_ID, START_DATE))

# ---- 1. Data ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]

# ---- 2. 월말 패널 + 종목 forward 1M 보유수익 (★ fe_single source 이전에 구성 —
#         fe_single이 RAWDATA를 rm해도 me_panel은 독립 유지. lookahead 없음: C2) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
RAWDATA[, .ym := NULL]
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # forward 1M (C2 safe)
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]               # 실현일 nd
setkey(me_panel, Ticker, Date)

# ---- 3. signal (fe_single: universe 산출 후 RAWDATA 해제 → factor loop RAWDATA-free) ----
#   fe_single은 전역 RAWDATA를 참조해 .mem(멤버십+유동성 2e8) 산출 후 RAWDATA를 rm.
#   본 driver는 me_panel을 이미 분리했으므로 무영향. (가벼운 단일 패스 — Part B 없음.)
source(FE_PATH)   # -> FACTORS(Date, Ticker, Score)   [N marker 없음 → driver top-N_CAP]
stopifnot(exists("FACTORS"), is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
FACTORS <- FACTORS[Date >= START_DATE]
gc(FALSE)
cat(sprintf("[IN04-LO-A] FACTORS rows=%d | signal months=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

sig_dates <- sort(unique(FACTORS$Date)); sig_dates <- sig_dates[sig_dates %in% me_dates]

# ---- 4. LONG leg: 매월 top-N_CAP(=25) EW -> wide -> Return.portfolio (표준함수) ----
sel_exec <- function(d) d   # 시그널=월말, 실행=익영업일 근사(보유수익은 forward 1M로 PIT-safe)
build_long_top25 <- function() {
  L <- vector("list", length(sig_dates)); HOLD <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FACTORS[Date == d & is.finite(Score)]; if (nrow(fd) < 10L) next
    setorder(fd, -Score)
    sel <- head(fd, min(N_CAP, nrow(fd)))                  # top-25 by Score (IN04 높을수록 우월=저발행)
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]                                       # equal-weight long-only
    L[[i]]    <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
    HOLD[[i]] <- data.table(Signal_Date = d, Exec_Date = sel_exec(d), Ticker = mp$Ticker,
                            Weight = 1/nrow(mp), Score = sel[match(mp$Ticker, Ticker), Score])
  }
  list(legs = rbindlist(Filter(Negate(is.null), L)),
       hold = rbindlist(Filter(Negate(is.null), HOLD)))
}
bl   <- build_long_top25(); lg <- bl$legs; hold <- bl$hold
stopifnot(nrow(lg) > 0)

Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
dts <- Rw$Date
Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = dts)
Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = dts)
gross_x <- Return.portfolio(R = Rx, weights = Wx)            # 매기간 EW rebalance, gross 월간 시계열
colnames(gross_x) <- "gross"

# ---- 4b. NET = gross - turnover*commission (one-way fraction; 첫달 전량진입=1.0) ----
to_mat <- as.matrix(Ww[, -1, with = FALSE]); to_dates <- Ww$Date
to_vec <- numeric(nrow(to_mat)); to_vec[1] <- 1.0
for (i in 2:nrow(to_mat)) to_vec[i] <- sum(abs(to_mat[i, ] - to_mat[i - 1, ])) / 2
nav_m <- merge(data.table(Date = index(gross_x), gross = as.numeric(gross_x)),
               data.table(Date = to_dates, turnover = to_vec), by = "Date", all.x = TRUE)
nav_m[is.na(turnover), turnover := 0]
nav_m[, Strategy_Ret := gross - turnover * COMMISSION]      # net 월간 수익 (cost 차감, 자체합성 아님)
setorder(nav_m, Date)

# ---- 5. 월간 benchmark: 실행월 d -> 실현월 nd 구간 daily BM_Ret 복리 (strategy 실현일 정렬) ----
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
me_idx <- data.table(d = me_dates, nd = shift(me_dates, 1L, type = "lead"))[!is.na(nd)]
bm_month <- vector("list", nrow(me_idx))
for (i in seq_len(nrow(me_idx))) {
  d <- me_idx$d[i]; nd <- me_idx$nd[i]
  seg <- bm_d[Date > d & Date <= nd, BM_Ret]; if (length(seg) < 1L) next
  bm_month[[i]] <- data.table(Date = nd, BM_Ret_m = prod(1 + seg) - 1)  # 구간복리(Return.cumulative 동등)
}
bm_mdt <- rbindlist(Filter(Negate(is.null), bm_month))
nav_m <- merge(nav_m, bm_mdt, by = "Date", all.x = TRUE)
nav_m[is.na(BM_Ret_m), BM_Ret_m := 0]
nav_m[, NAV := cumprod(1 + Strategy_Ret)]                   # net NAV (cumprod = 표준 누적)

# ---- 6. sim_result-like 구성 (build_bt_result + register_module 스키마, 월간) ----
strategy_xts <- xts(nav_m$Strategy_Ret, order.by = nav_m$Date); names(strategy_xts) <- "Strategy"
bm_xts       <- xts(nav_m$BM_Ret_m,     order.by = nav_m$Date); names(bm_xts) <- "Benchmark"
DAILY_NAV_DT <- data.table(Date = nav_m$Date, NAV = nav_m$NAV, NAV_gross = cumprod(1 + nav_m$gross),
                           Strategy_Ret = nav_m$Strategy_Ret)
sim_result <- list(
  DAILY_NAV_DT  = DAILY_NAV_DT,
  PORTFOLIO_LOG = data.table(Signal_Date = sig_dates[sig_dates %in% me_dates]),
  HOLDINGS_LOG  = hold,
  strategy_xts  = strategy_xts,
  bm_xts        = bm_xts
)

# ---- 7. build_bt_result (월간 계약) -> audit -> essence_score ----
strategy_spec <- list(
  strategy_id = STRAT_ID, strategy_name = "IN04 Net Equity Issuance long-only top25",
  strategy_family = "net_equity_issuance_anomaly",
  signal_description = "IN04 Net Equity Issuance Z_Score_Aligned; top-25 EW long-only (issuance anomaly: 저발행=우월)",
  universe_rule = "K200_KQ150 membership + 20d ADV>=2e8 (PIT time-varying)",
  rebalance_frequency = "monthly", signal_date_rule = "month_end",
  execution_date_rule = "month_end_signal_t_plus_1", weighting_method = "equal_weight",
  max_position_weight = 0.20, max_leverage = 1.0, cash_rule = "fully_invested",
  cost_model = "v2.3_kr_retail_15bps", missing_data_rule = "drop", risk_controls = "long_only",
  lookahead_prevention = "forward_1M_hold + t-1 liquidity + factor DB Usable_Date",
  survivorship_bias_control = "PIT membership panel"
)
run_id <- paste0("IN04_LO_A_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
bt <- build_bt_result(
  sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = STRAT_ID, strategy_version = "v1.0",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 15, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150", code_version = "driver_in04_lo_A", created_by_agent = "AlphaSearch"
)
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = NULL)         # 1알파 직교검증 → DSR 부적용(n_trials=NULL)

# ---- 8. register_module (v8.1 등급무관) ----
register_module(sim_result, STRAT_ID, grade = es$grade, origin_mode = "alpha_search",
                role = "core", meta = list(strategy_idea = "IN04 Net Equity Issuance long-only top25 (직교 슬리브 후보)",
                                           factor = IN04_F, n_cap = N_CAP))

# ---- 9. 측정 요약 (연율 SR/MDD/CAGR + essence grade + OOS retention + Carhart4 t + 종목수) ----
M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
gm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
sharpe <- gm("Sharpe"); cagr <- gm("CAGR"); mdd <- gm("MDD"); calmar <- gm("Calmar")
net_ir <- gbc("Information_Ratio"); port_t <- gbc("Portfolio_Alpha_t_NW_lag3"); excess_cum <- gbc("Excess_Total_Return")
oos_ret_lo <- es$essence$oos_retention %||% NA_real_
n_hold <- if (nrow(hold)) round(mean(hold[, .N, by = Signal_Date]$N), 1) else NA_real_

# Carhart4 (long-only net 시계열 vs KR factor returns)
c4t <- NA_real_; c4a <- NA_real_
mf <- tryCatch({
  if (exists("run_multifactor_regression") && exists("load_kr_factor_returns"))
    run_multifactor_regression(strategy_xts, bm_xts = bm_xts, factor_dt = load_kr_factor_returns())
  else NULL
}, error = function(e) { cat("[IN04-LO-A] Carhart4 회귀 생략:", conditionMessage(e), "\n"); NULL })
if (!is.null(mf) && !is.null(mf$Carhart4)) { c4t <- mf$Carhart4$alpha_tstat; c4a <- mf$Carhart4$alpha * 12 * 100 }

# 판정: long-only OOS retention >=0.5 (value LO -0.517 붕괴 대조)
oos_lo_pass <- is.finite(oos_ret_lo) && oos_ret_lo >= 0.5

cat(sprintf("[IN04-LO-A-DONE] %s | n_months=%d | Sharpe=%.3f CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f | net_IR=%.3f PORT_t=%.3f | OOS_ret(LO)=%.3f (>=0.5=%s) | Carhart4 a=%.2f%%/yr t=%.3f | avg_N=%.1f | excess_cum=%.2f%% | GRADE=%s (%s)\n",
            STRAT_ID, nrow(nav_m), sharpe, cagr*100, mdd*100, calmar, net_ir, port_t, oos_ret_lo, oos_lo_pass,
            c4a, c4t, n_hold, excess_cum*100, es$grade, es$reasons))

out <- list(
  experiment = "IN04 Net Equity Issuance LONG-ONLY top-25 (Part A 단독, 2-part 통합 driver OOM 우회 — 가벼운 Return.portfolio driver)",
  factor = IN04_F, strategy_id = STRAT_ID, run_id = run_id,
  metric_type = "backtested", universe = "K200_KQ150", start_date = as.character(START_DATE),
  ls_screen_prior = list(carhart4_t = 2.8297, oos_retention = 1.9196, long_leg_sharpe = 0.7545,
                         note = "LS 1차 통과 — 본 driver가 long-only 운용 판정(Part A 단독)"),
  weights = list(n_cap = N_CAP, weighting = "equal_weight"),
  n_months = nrow(nav_m), avg_n_holdings = n_hold,
  annualized = list(sharpe = round(sharpe,4), cagr_pct = round(cagr*100,3),
                    mdd_pct = round(mdd*100,3), calmar = round(calmar,4)),
  oos_retention_lo = round(oos_ret_lo, 4),
  oos_lo_pass = oos_lo_pass,
  active_vs_kospi200 = list(net_ir = round(net_ir,4), portfolio_alpha_t_nw_lag3 = round(port_t,4),
                            excess_total_return_pct = round(excess_cum*100,3)),
  carhart4 = list(alpha_ann_pct = round(c4a,3), alpha_t = round(c4t,4)),
  essence = list(grade = es$grade, hard_fail = es$hard_fail, reasons = es$reasons, detail = es$essence),
  vs_value_lo_reference = "value(BM) long-only OOS retention -0.517 붕괴 (대조군). LO OOS 양수면 결정적 차이=진짜 직교.",
  registered = "04_Research/strategies/STR_IN04_top25/sim_result.rds + module_catalog.json",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(out, file.path(OUT_DIR, "in04_top25_longonly_A_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] in04_top25_longonly_A_result.json\n")
