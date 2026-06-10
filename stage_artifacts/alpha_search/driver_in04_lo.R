# =============================================================================
# driver_in04_lo.R — IN04 Net Equity Issuance 직교 후보 심화 검증
#   (도훈 "풀 부족" 지적 결실 — LS 스크리닝 유일 직교 후보 IN04 long-only 운용 판정)
#
#   IN04 (순주식발행, Loughran-Ritter / Daniel-Titman issuance anomaly):
#     LS 1차 통과 (Carhart4 t +2.83, OOS retention +1.92, long-leg SR 0.7545).
#     재무 기반(가격/밸류 축 밖) → 진짜 직교 슬리브 후보. 본 driver가 2축 심화:
#       Part A. ★ long-only top25 운용 검증 (★핵심 판정 — value는 LO OOS −0.517 붕괴)
#       Part B. 다축 상관 확정 (IN04 LS vs value(BM) LS / STR_1715 / 풀 주요 모듈)
#                <0.3 이면 진짜 직교(1st eigenmode 무관). EP 오판 교훈: 한 축만 낮은 건 함정.
#
#   ★ 측정 = build_bt_result(10-component, metric_type=backtested) + audit + essence_score.
#            자체합성 금지(Return.portfolio/PerformanceAnalytics 표준함수만).
#   ★ 등재 = register_module(v8.1 등급무관) → STR_IN04_top25 / module_catalog.
#   ★ governor/book_state 미사용(measurement+register만, 편입 도훈 confirm). WT-id 금지.
#
# ===== PIT (C1~C15) =====
#   - 시그널: fe factor DB IN04 Z_Score_Aligned (C13 NEGATE/FLIP 없음, C14 Usable_Date<=sig,
#     C15 load_month_factors 경유). C4: issuance 재무 lag는 factor DB 빌드 단계 반영.
#   - 보유: 월말 시그널 d → forward 1M(다음 월말 실현). 동일시점 순환참조 없음(C2).
#   - 유동성/멤버십: 20일 평균 거래대금(과거 윈도우) 2e8 + K200∪KQ150 시변 멤버십.
#
#   ★ OOM fix: 회계 factor는 RAWDATA를 universe 산출 + forward 수익 구성에만 사용.
#     factor 일괄로딩(254월) 동안 RAWDATA를 slim 유지. (fe_single OOM v2 패턴 정합)
#
#   호출(PowerShell, -f 금지, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/driver_in04_lo.R')"
#   출력: stage_artifacts/alpha_search/in04_top25_longonly_result.json
#         + 04_Research/strategies/STR_IN04_top25/sim_result.rds (register_module)
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(zoo); library(PerformanceAnalytics); library(jsonlite)
}))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                       # load_rawdata, get_execution_date
source(file.path(INFRA, "factor_portfolios.R"))                      # run_multifactor_regression
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))       # load_month_factors
source(file.path(INFRA, "contracts", "backtest_result_contract.R"))  # build_bt_result
source(file.path(INFRA, "contracts", "audit_bt_result.R"))           # audit_bt_result
source(file.path(INFRA, "contracts", "essence_score.R"))             # essence_score
source(file.path(INFRA, "contracts", "register_module.R"))           # register_module

OUT_DIR    <- file.path(PROJ, "stage_artifacts", "alpha_search")
START_DATE <- as.Date("2005-01-01")
STRAT_ID   <- "STR_IN04_top25"
COMMISSION <- 0.0015
N_CAP      <- 25L
DECILE_FRAC<- 0.10
IN04_F     <- "IN04_Net_Equity_Issuance"
VAL_F      <- "V01_BM"
ANN        <- sqrt(12)
sharpe_ann <- function(x) { x <- x[is.finite(x)]; s <- sd(x); if (!is.finite(s) || s <= 0) return(NA_real_); mean(x)/s*ANN }

cat(sprintf("[IN04-LO] factor=%s | N_CAP=%d | strat=%s | START=%s\n", IN04_F, N_CAP, STRAT_ID, START_DATE))

# ---- 1. RAWDATA (universe + forward 수익 구성) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
all_dates <- sort(unique(RAWDATA$Date))

# slim universe panel (멤버십 + 유동성 2e8, PIT 과거 윈도우)
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd_slim, Ticker, Date)
.rd_slim[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")
me_dates <- me_dates[me_dates >= .fdb_min]
.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
mem <- .rd_slim[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(.rd_slim); gc(FALSE)

# ---- 2. 월별 IN04 + V01_BM Z_Score_Aligned (universe 한정, full dt 즉시 폐기 — L-534/OOM) ----
#   ★ 두 factor를 한 번의 월별 루프에서 동시 추출 → parquet 중복 read 회피(IN04 LS + value LS 둘 다 산출).
in04_list <- vector("list", length(me_dates)); val_list <- vector("list", length(me_dates))
for (i in seq_along(me_dates)) {
  d <- me_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  fi <- fdt[Factor_Name == IN04_F & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  fv <- fdt[Factor_Name == VAL_F  & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  rm(fdt)
  if (nrow(fi) >= 20L) { fi[, Date := d]; in04_list[[i]] <- fi[, .(Date, Ticker, Score)] }
  if (nrow(fv) >= 20L) { fv[, Date := d]; val_list[[i]]  <- fv[, .(Date, Ticker, Score)] }
  if (i %% 24L == 0L) gc(FALSE)
}
FAC_IN04 <- rbindlist(Filter(Negate(is.null), in04_list), use.names = TRUE)
FAC_VAL  <- rbindlist(Filter(Negate(is.null), val_list),  use.names = TRUE)
rm(in04_list, val_list); gc(FALSE)
FAC_IN04 <- FAC_IN04[Date >= START_DATE]; FAC_VAL <- FAC_VAL[Date >= START_DATE]
cat(sprintf("[IN04-LO] FAC_IN04 months=%d rows=%d | FAC_VAL months=%d rows=%d\n",
            uniqueN(FAC_IN04$Date), nrow(FAC_IN04), uniqueN(FAC_VAL$Date), nrow(FAC_VAL)))

# ---- 3. 월말 패널 + forward 1M 보유수익 (d 편입결정 -> nd 실현; lookahead 없음) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
# section 4(LS daily leg)용 daily Ret 보존 (slim) — full RAWDATA는 이후 해제
rd_daily <- RAWDATA[Date >= START_DATE & is.finite(Ret), .(Date, Ticker, Ret)]
RAWDATA[, .ym := NULL]; rm(RAWDATA); gc(FALSE)
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # forward 1M (C2 safe)
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]
setkey(me_panel, Ticker, Date)

# =============================================================================
# PART A — ★ long-only top25 (핵심 판정)
# =============================================================================
sig_dates <- sort(unique(FAC_IN04$Date)); sig_dates <- sig_dates[sig_dates %in% me_dates]
build_long_top25 <- function() {
  L <- vector("list", length(sig_dates)); HOLD <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FAC_IN04[Date == d & is.finite(Score)]; if (nrow(fd) < 10L) next
    setorder(fd, -Score)
    sel <- head(fd, min(N_CAP, nrow(fd)))                  # top-25 by Score (IN04 높을수록 우월=발행 적음)
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]                                       # equal-weight long-only
    L[[i]]    <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
    HOLD[[i]] <- data.table(Signal_Date = d, Exec_Date = d, Ticker = mp$Ticker,
                            Weight = 1/nrow(mp), Score = sel[match(mp$Ticker, Ticker), Score])
  }
  list(legs = rbindlist(Filter(Negate(is.null), L)), hold = rbindlist(Filter(Negate(is.null), HOLD)))
}
bl <- build_long_top25(); lg <- bl$legs; hold <- bl$hold
stopifnot(nrow(lg) > 0)

Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
dts <- Rw$Date
Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = dts)
Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = dts)
gross_x <- Return.portfolio(R = Rx, weights = Wx); colnames(gross_x) <- "gross"   # 표준함수

# NET = gross - turnover*commission
to_mat <- as.matrix(Ww[, -1, with = FALSE]); to_dates <- Ww$Date
to_vec <- numeric(nrow(to_mat)); to_vec[1] <- 1.0
for (i in 2:nrow(to_mat)) to_vec[i] <- sum(abs(to_mat[i, ] - to_mat[i - 1, ])) / 2
nav_m <- merge(data.table(Date = index(gross_x), gross = as.numeric(gross_x)),
               data.table(Date = to_dates, turnover = to_vec), by = "Date", all.x = TRUE)
nav_m[is.na(turnover), turnover := 0]
nav_m[, Strategy_Ret := gross - turnover * COMMISSION]
setorder(nav_m, Date)

# 월간 benchmark: 실행월 d -> 실현월 nd 구간 daily BM_Ret 복리 (strategy 실현일 정렬)
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
me_idx <- data.table(d = me_dates, nd = shift(me_dates, 1L, type = "lead"))[!is.na(nd)]
bm_month <- vector("list", nrow(me_idx))
for (i in seq_len(nrow(me_idx))) {
  d <- me_idx$d[i]; nd <- me_idx$nd[i]
  seg <- bm_d[Date > d & Date <= nd, BM_Ret]; if (length(seg) < 1L) next
  bm_month[[i]] <- data.table(Date = nd, BM_Ret_m = prod(1 + seg) - 1)   # 구간복리(Return.cumulative 동등)
}
bm_mdt <- rbindlist(Filter(Negate(is.null), bm_month))
nav_m <- merge(nav_m, bm_mdt, by = "Date", all.x = TRUE)
nav_m[is.na(BM_Ret_m), BM_Ret_m := 0]
nav_m[, NAV := cumprod(1 + Strategy_Ret)]

# build_bt_result (월간) -> audit -> essence
strategy_xts <- xts(nav_m$Strategy_Ret, order.by = nav_m$Date); names(strategy_xts) <- "Strategy"
bm_xts       <- xts(nav_m$BM_Ret_m,     order.by = nav_m$Date); names(bm_xts) <- "Benchmark"
DAILY_NAV_DT <- data.table(Date = nav_m$Date, NAV = nav_m$NAV, NAV_gross = cumprod(1 + nav_m$gross),
                           Strategy_Ret = nav_m$Strategy_Ret)
sim_result <- list(DAILY_NAV_DT = DAILY_NAV_DT,
                   PORTFOLIO_LOG = data.table(Signal_Date = sig_dates[sig_dates %in% me_dates]),
                   HOLDINGS_LOG = hold, strategy_xts = strategy_xts, bm_xts = bm_xts)

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
  survivorship_bias_control = "PIT membership panel")
run_id <- paste0("IN04_LO_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
bt <- build_bt_result(sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = STRAT_ID, strategy_version = "v1.0",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 15, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150", code_version = "driver_in04_lo", created_by_agent = "AlphaSearch")
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = NULL)   # 1알파 직교검증 → DSR 부적용

# register_module (v8.1 등급무관)
register_module(sim_result, STRAT_ID, grade = es$grade, origin_mode = "alpha_search",
                role = "core", meta = list(strategy_idea = "IN04 Net Equity Issuance long-only top25 (직교 슬리브 후보)",
                                           factor = IN04_F, n_cap = N_CAP))

# Part A 측정 요약
M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
gm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
sharpe <- gm("Sharpe"); cagr <- gm("CAGR"); mdd <- gm("MDD"); calmar <- gm("Calmar")
net_ir <- gbc("Information_Ratio"); port_t <- gbc("Portfolio_Alpha_t_NW_lag3"); excess_cum <- gbc("Excess_Total_Return")
oos_ret_lo <- es$essence$oos_retention %||% NA_real_
n_hold <- if (nrow(hold)) round(mean(hold[, .N, by = Signal_Date]$N), 1) else NA_real_

# Carhart4 (long-only net vs KR factor returns)
c4t <- NA_real_; c4a <- NA_real_
mf_lo <- tryCatch(run_multifactor_regression(strategy_xts, bm_xts = bm_xts, factor_dt = load_kr_factor_returns()),
                  error = function(e) { cat("[IN04-LO] Carhart4(LO) 생략:", conditionMessage(e), "\n"); NULL })
if (!is.null(mf_lo) && !is.null(mf_lo$Carhart4)) { c4t <- mf_lo$Carhart4$alpha_tstat; c4a <- mf_lo$Carhart4$alpha * 12 * 100 }

cat(sprintf("[IN04-LO-A-DONE] %s | n_months=%d | Sharpe=%.3f CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f | net_IR=%.3f PORT_t=%.3f | OOS_ret(LO)=%.3f | Carhart4 a=%.2f%%/yr t=%.3f | avg_N=%.1f | excess_cum=%.2f%% | GRADE=%s\n",
            STRAT_ID, nrow(nav_m), sharpe, cagr*100, mdd*100, calmar, net_ir, port_t, oos_ret_lo, c4a, c4t,
            n_hold, excess_cum*100, es$grade))

# =============================================================================
# PART B — 다축 상관 (IN04 LS vs value(BM) LS / STR_1715 / 풀 주요 모듈)
# =============================================================================
# IN04 LS + value(BM) LS 월간 시계열 구성 (long top-decile − short bottom-decile, EW)
setkey(rd_daily, Ticker, Date)
build_leg_daily <- function(FAC, side) {
  sd <- sort(unique(FAC$Date)); sd <- sd[sd %in% me_dates]
  dl <- vector("list", length(sd))
  for (i in seq_along(sd)) {
    d <- sd[i]; md <- FAC[Date == d & is.finite(Score)]; n <- nrow(md); if (n < 20L) next
    k <- max(2L, as.integer(ceiling(n * DECILE_FRAC)))
    setorder(md, -Score)
    picks <- if (side == "long") head(md$Ticker, k) else tail(md$Ticker, k)
    exec_date <- get_execution_date(d, all_dates); if (is.na(exec_date)) next
    next_exec <- if (i < length(sd)) get_execution_date(sd[i + 1L], all_dates) else NA_Date_
    hold_end  <- if (!is.na(next_exec)) all_dates[all_dates < next_exec] else all_dates
    hold_end  <- max(hold_end[hold_end >= exec_date], exec_date)
    sub <- rd_daily[Ticker %in% picks & Date >= exec_date & Date <= hold_end, .(Date, Ticker, Ret)]
    if (!nrow(sub)) next
    w <- dcast(sub, Date ~ Ticker, value.var = "Ret"); setorder(w, Date)
    rmat <- as.matrix(w[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = w$Date)
    pr <- tryCatch(Return.portfolio(rx, weights = rep(1/ncol(rx), ncol(rx)), rebalance_on = NA), error = function(e) NULL)
    if (is.null(pr)) next
    dl[[i]] <- data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1]))
  }
  out <- rbindlist(Filter(Negate(is.null), dl), use.names = TRUE)
  if (!nrow(out)) return(NULL); setorder(out, Date); out[, .(Ret = mean(Ret)), by = Date]
}
to_monthly_ym <- function(dt) {   # 표준: apply.monthly + Return.cumulative -> ym keyed
  x <- xts(dt$Ret, order.by = dt$Date); m <- apply.monthly(x, Return.cumulative)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[, 1]))
}
ls_monthly <- function(FAC) {
  ld <- build_leg_daily(FAC, "long"); sd <- build_leg_daily(FAC, "short")
  if (is.null(ld) || is.null(sd)) return(NULL)
  m <- merge(ld[, .(Date, L = Ret)], sd[, .(Date, S = Ret)], by = "Date", all = TRUE)
  m[!is.finite(L), L := 0]; m[!is.finite(S), S := 0]; m[, Ret := L - S]; setorder(m, Date)
  to_monthly_ym(m[, .(Date, Ret)])
}
in04_ls_m <- ls_monthly(FAC_IN04); setnames(in04_ls_m, "ret", "in04_ls")
val_ls_m  <- ls_monthly(FAC_VAL);  if (!is.null(val_ls_m)) setnames(val_ls_m, "ret", "val_ls")
rm(rd_daily); gc(FALSE)

# STR_1715 월간 net 수익 (CSV)
str1715_path <- file.path(PROJ, "04_Research", "strategies", "STR_1715_WT016_Iter31_GridBestProd",
                          "output", "03_period_returns.csv")
s1715 <- tryCatch({
  z <- fread(str1715_path); z[, ym := format(as.Date(date), "%Y-%m")]; z[, .(ym, str1715 = ret_net)]
}, error = function(e) { cat("[IN04-LO] STR_1715 CSV 로드 실패:", conditionMessage(e), "\n"); NULL })

# 풀 주요 모듈 월간 수익 (sim_result.rds Strategy_Ret -> 월간)
pool_ids <- c("STR_1439_1047_to_fix", "STR_1033_nco", "STR_1550_consensus_core_alpha",
              "STR_1393_esbr_sue_adaptive", "STR_1562_gerber_dcc_hrp_c11fix")
pool_monthly <- function(sid) {
  p <- file.path(PROJ, "04_Research", "strategies", sid, "sim_result.rds")
  if (!file.exists(p)) return(NULL)
  sr <- tryCatch(readRDS(p), error = function(e) NULL); if (is.null(sr)) return(NULL)
  dn <- sr$DAILY_NAV_DT
  if (is.null(dn) || !all(c("Date", "Strategy_Ret") %in% names(dn))) return(NULL)
  dn <- as.data.table(dn); dn[, Date := as.Date(Date)]
  x <- xts(dn$Strategy_Ret, order.by = dn$Date)
  m <- apply.monthly(x, function(z) prod(1 + z[is.finite(z)]) - 1)   # 구간복리(Return.cumulative 동등)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[, 1]))
}

# 상관 계산 (공통 ym 교집합, IN04 LS 기준)
cor_pair <- function(a_dt, a_col, b_dt, b_col) {
  if (is.null(a_dt) || is.null(b_dt)) return(NA_real_)
  m <- merge(a_dt[, .(ym, a = get(a_col))], b_dt[, .(ym, b = get(b_col))], by = "ym")
  m <- m[is.finite(a) & is.finite(b)]; if (nrow(m) < 24L) return(NA_real_)
  as.numeric(cor(m$a, m$b))
}
corr_results <- list(
  vs_value_bm_ls = list(corr = round(cor_pair(in04_ls_m, "in04_ls", val_ls_m, "val_ls"), 4),
                        n = if (!is.null(val_ls_m)) nrow(merge(in04_ls_m, val_ls_m, by = "ym")) else 0L),
  vs_STR_1715    = list(corr = round(cor_pair(in04_ls_m, "in04_ls", s1715, "str1715"), 4),
                        n = if (!is.null(s1715)) nrow(merge(in04_ls_m, s1715, by = "ym")) else 0L)
)
for (sid in pool_ids) {
  pm <- pool_monthly(sid)
  corr_results[[paste0("vs_", sid)]] <- list(
    corr = round(cor_pair(in04_ls_m, "in04_ls", pm, "ret"), 4),
    n = if (!is.null(pm)) nrow(merge(in04_ls_m, pm, by = "ym")) else 0L)
}
cat("\n[IN04-LO-B] 다축 상관 (IN04 LS 기준):\n")
for (nm in names(corr_results)) cat(sprintf("  %-32s corr=%7s  n=%d\n", nm,
     format(corr_results[[nm]]$corr), corr_results[[nm]]$n))

# 판정
multi_axis_corrs <- sapply(corr_results, function(z) z$corr)
max_abs_corr <- suppressWarnings(max(abs(multi_axis_corrs), na.rm = TRUE))
ortho_corr_pass <- is.finite(max_abs_corr) && max_abs_corr < 0.30
oos_lo_pass     <- is.finite(oos_ret_lo) && oos_ret_lo >= 0.5    # value는 LO서 -0.517 붕괴
true_ortho      <- ortho_corr_pass && oos_lo_pass

# =============================================================================
# 저장 + 보고
# =============================================================================
out <- list(
  experiment = "IN04 Net Equity Issuance 직교 후보 심화 (Part A long-only top25 + Part B 다축 상관)",
  factor = IN04_F, strategy_id = STRAT_ID, run_id = run_id,
  metric_type = "backtested", universe = "K200_KQ150", start_date = as.character(START_DATE),
  ls_screen_prior = list(carhart4_t = 2.8297, oos_retention = 1.9196, long_leg_sharpe = 0.7545,
                         note = "LS 1차 통과 — 본 driver가 long-only 운용 + 다축 상관 심화"),
  part_A_long_only_top25 = list(
    n_months = nrow(nav_m), avg_n_holdings = n_hold, weighting = "equal_weight", n_cap = N_CAP,
    annualized = list(sharpe = round(sharpe,4), cagr_pct = round(cagr*100,3),
                      mdd_pct = round(mdd*100,3), calmar = round(calmar,4)),
    oos_retention = round(oos_ret_lo, 4),
    active_vs_kospi200 = list(net_ir = round(net_ir,4), portfolio_alpha_t_nw_lag3 = round(port_t,4),
                              excess_total_return_pct = round(excess_cum*100,3)),
    carhart4 = list(alpha_ann_pct = round(c4a,3), alpha_t = round(c4t,4)),
    essence = list(grade = es$grade, hard_fail = es$hard_fail, reasons = es$reasons),
    vs_value_lo_reference = "value(BM) long-only OOS retention -0.517 붕괴 (대조군)"),
  part_B_multi_axis_corr = corr_results,
  verdict = list(
    ortho_corr_pass = ortho_corr_pass, max_abs_corr = round(max_abs_corr, 4),
    oos_lo_pass = oos_lo_pass, oos_retention_lo = round(oos_ret_lo, 4),
    true_orthogonal_source = true_ortho,
    interpretation = if (true_ortho)
        "진짜 새 직교원 — 다축 상관<0.3 + long-only OOS 양수 (value와 결정적 차이; single-sleeve long-only 불가 결론 갱신)"
      else if (!oos_lo_pass)
        "long-only 붕괴 — value처럼 LS-only (long-only 제약 벽 재확인; issuance도 못 넘음)"
      else
        "다축 상관 >=0.3 — 한 축 이상서 1st eigenmode 공유(EP 오판형 비직교 가능)"),
  registered = "04_Research/strategies/STR_IN04_top25/sim_result.rds + module_catalog.json",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))
write_json(out, file.path(OUT_DIR, "in04_top25_longonly_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("\n[IN04-LO-VERDICT] true_orthogonal=%s | max_abs_corr=%.3f (<0.3=%s) | OOS_ret(LO)=%.3f (>=0.5=%s)\n",
            true_ortho, max_abs_corr, ortho_corr_pass, oos_ret_lo, oos_lo_pass))
cat("[SAVED] in04_top25_longonly_result.json\n")
