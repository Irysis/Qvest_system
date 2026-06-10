# =============================================================================
# driver_lo_screen.R — 단일 factor LONG-ONLY top25 스크리닝 (★ short 전면 금지)
#   도훈 mandate 2026-06-06: "Short 금지" → 공매도/long-short 측정·운용 전면 폐기.
#   driver_in04_lo.R Part A 방식(long-only top25)을 generic factor로 복제.
#   long-short(LS) 코드 일절 없음 — long leg(top-N EW)만 구성.
#
#   판정(long-only only):
#     ① OOS retention(IS<=2015 vs OOS>=2016 active SR) >= 0.5  → OOS robust 직교 후보
#     ② 다축 상관(value(BM) LO top25 / STR_1715 net) < 0.3     → 1st eigenmode 무관
#     ③ MDD < 30%                                              → 방어 기여 후보(alpha 아니어도 가치)
#
#   ★ 측정 = build_bt_result(10-component, metric_type=backtested) + audit + essence_score.
#            자체합성 금지(Return.portfolio/PerformanceAnalytics 표준함수만, 손계산 cumprod는
#            NAV 표시·구간 BM 복리에 한정 — period return은 Return.portfolio 산출).
#   ★ 등재 = register_module(v8.1 등급무관) → STR_<FACTOR>_LO_top25 / module_catalog.
#   ★ governor/book_state 미사용(measurement+register만, 편입 도훈 confirm). WT-id 금지.
#
# ===== PIT (C1~C15) =====
#   - 시그널: factor DB <FACTOR> Z_Score_Aligned (C13 NEGATE/FLIP 없음·부호 그대로,
#     C14 Usable_Date<=sig, C15 load_month_factors 경유). C4: 재무 lag = factor DB 빌드 단계.
#   - 보유: 월말 시그널 d → forward 1M(다음 월말 실현). 동일시점 순환참조 없음(C2).
#   - 유동성/멤버십: 20일 평균 거래대금(과거 윈도우) 2e8 + K200∪KQ150 시변 멤버십.
#   ★ OOM fix(fe_single v2 정합): 회계/유동성 factor는 RAWDATA를 universe 산출 + forward
#     수익 구성에만 사용. factor 일괄로딩(254월) 전 RAWDATA를 slim 유지·조기 해제.
#
#   환경변수: FACTOR_NAME (필수, factor_registry Factor_Name). STRAT_TAG (선택, 출력 prefix).
#   호출(PowerShell, -f 금지, BOM 없이):
#     $env:FACTOR_NAME='CR01_Sector_Comovement'; Rscript -e "source('stage_artifacts/alpha_search/driver_lo_screen.R')"
#   출력: stage_artifacts/alpha_search/lo_screen/<FACTOR>.json
#         + 04_Research/strategies/STR_<TAG>_LO_top25/sim_result.rds (register_module)
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(zoo); library(PerformanceAnalytics); library(jsonlite)
}))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                       # load_rawdata, get_execution_date
source(file.path(INFRA, "factor_portfolios.R"))                      # run_multifactor_regression, load_kr_factor_returns
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))       # load_month_factors
source(file.path(INFRA, "contracts", "backtest_result_contract.R"))  # build_bt_result
source(file.path(INFRA, "contracts", "audit_bt_result.R"))           # audit_bt_result
source(file.path(INFRA, "contracts", "essence_score.R"))             # essence_score
source(file.path(INFRA, "contracts", "register_module.R"))           # register_module

FACTOR_NAME <- Sys.getenv("FACTOR_NAME", "")
if (!nzchar(FACTOR_NAME)) stop("[driver_lo] FACTOR_NAME 환경변수 미설정.")
STRAT_TAG  <- Sys.getenv("STRAT_TAG", sub("_.*$", "", FACTOR_NAME))   # 예 CR01
STRAT_ID   <- paste0("STR_", FACTOR_NAME, "_LO_top25")
OUT_DIR    <- file.path(PROJ, "stage_artifacts", "alpha_search", "lo_screen")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
START_DATE <- as.Date("2005-01-01")
COMMISSION <- 0.0015
N_CAP      <- 25L
DECILE_FRAC<- 0.10
VAL_F      <- "V01_BM"
ANN        <- sqrt(12)
sharpe_ann <- function(x) { x <- x[is.finite(x)]; s <- sd(x); if (!is.finite(s) || s <= 0) return(NA_real_); mean(x)/s*ANN }

cat(sprintf("\n=== [LO-screen] %s | factor=%s | N_CAP=%d | START=%s ===\n",
            STRAT_ID, FACTOR_NAME, N_CAP, START_DATE))

# ---- 1. RAWDATA 의존도 = 1회 캐시(RDS)에서 로드 (★ OOM 근본 fix 2026-06-06) ----
#   ★ 도훈 mandate: factor 캐시(_factor_cache.rds)로 factor read는 제거했으나, 각 factor run이
#     load_rawdata(13.9M행 arrow)를 반복 read해 batch2 D01에서 비결정 OOM(arrow layer).
#     RAWDATA로 driver가 쓰는 것은 ① universe(.mem) ② me_panel(forward 1M) ③ daily BM_Ret 뿐 —
#     셋 다 factor-무관 → build_lo_rawdata_cache.R가 batch 1회 빌드한 RDS만 로드(arrow read 0회).
#     캐시 빌드 로직은 본 driver와 비트동일(동일 mem/me_panel/PIT) → universe/수익 정합 보장.
#   캐시 없으면 legacy load_rawdata fallback(반복 read OOM risk — build 먼저 실행 권장).
.uni_path <- file.path(OUT_DIR, "_universe_cache.rds")
.mep_path <- file.path(OUT_DIR, "_me_panel_cache.rds")
.bm_path  <- file.path(OUT_DIR, "_bm_cache.rds")
.fdb_min  <- as.Date("2002-08-01")
if (file.exists(.uni_path) && file.exists(.mep_path) && file.exists(.bm_path)) {
  mem      <- readRDS(.uni_path)
  me_panel <- readRDS(.mep_path)   # Date, Ticker, Close, ret_fwd, ret_date (forward 1M 이미 빌드됨)
  bm_d     <- readRDS(.bm_path)    # Date, BM_Ret
  stopifnot(is.data.table(mem),      all(c("Date","Ticker") %in% names(mem)))
  stopifnot(is.data.table(me_panel), all(c("Date","Ticker","Close","ret_fwd","ret_date") %in% names(me_panel)))
  stopifnot(is.data.table(bm_d),     all(c("Date","BM_Ret") %in% names(bm_d)))
  if (!haskey(mem)      || !identical(key(mem),      c("Date","Ticker")))   setkey(mem, Date, Ticker)
  if (!haskey(me_panel) || !identical(key(me_panel), c("Ticker","Date")))   setkey(me_panel, Ticker, Date)
  me_dates <- sort(unique(mem$Date))
  RAWDATA_CACHE_HIT <- TRUE
  cat(sprintf("[LO] ★ RAWDATA cache HIT — arrow read 0회 | mem rows=%d me_panel rows=%d bm rows=%d\n",
              nrow(mem), nrow(me_panel), nrow(bm_d)))
} else {
  cat("[LO] RAWDATA cache MISS — legacy load_rawdata(반복 arrow read, OOM risk). build_lo_rawdata_cache.R 먼저 실행 권장.\n")
  RAWDATA_CACHE_HIT <- FALSE
  res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  if (!inherits(BM_DT$Date,  "Date")) BM_DT[,  Date := as.Date(Date)]
  setorder(RAWDATA, Ticker, Date)

  # slim universe panel (멤버십 + 유동성 2e8, PIT 과거 윈도우)
  .rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
  setorder(.rd_slim, Ticker, Date)
  .rd_slim[, .ym := format(Date, "%Y-%m")]
  me_dates <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
  .rd_slim[, .ym := NULL]
  me_dates <- me_dates[me_dates >= .fdb_min]
  .rd_slim[, .TV := Close * Vol]
  .rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
  mem <- .rd_slim[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
                    !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
  setkey(mem, Date, Ticker)
  rm(.rd_slim); gc(FALSE)

  # me_panel: 월말 Close -> forward 1M (cache MISS 경로에서 즉석 빌드)
  me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
  setorder(me_panel, Ticker, Date)
  me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]
  me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]
  setkey(me_panel, Ticker, Date)
  setorder(BM_DT, Date)
  bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
  rm(RAWDATA, BM_DT); gc(FALSE)
}

# ---- 2. 월별 <FACTOR> + V01_BM Z_Score_Aligned ----
#   ★ OOM 근본 fix (2026-06-06): factor DB 반복 read 제거. batch 시작 전 1회 빌드한 slim
#     캐시(_factor_cache.rds: Date,Ticker,Factor_Name,Z_Score_Aligned, 24 factor만)가 있으면
#     parquet read *0회*로 슬라이스만 함. 캐시는 load_month_factors(d) 출력을 그대로 보존
#     (C13/C14/C15 동일) → 부호/정렬/값 무변. 캐시 없으면 legacy 월별 루프로 fallback.
.cache_path <- file.path(OUT_DIR, "_factor_cache.rds")
if (file.exists(.cache_path)) {
  CACHE <- readRDS(.cache_path)
  stopifnot(is.data.table(CACHE), all(c("Date","Ticker","Factor_Name","Z_Score_Aligned") %in% names(CACHE)))
  if (!haskey(CACHE) || !identical(key(CACHE), c("Factor_Name","Date","Ticker"))) setkey(CACHE, Factor_Name, Date, Ticker)
  FAC     <- CACHE[.(FACTOR_NAME), .(Date, Ticker, Score = Z_Score_Aligned), nomatch = 0L][is.finite(Score)]
  FAC_VAL <- CACHE[.(VAL_F),       .(Date, Ticker, Score = Z_Score_Aligned), nomatch = 0L][is.finite(Score)]
  # universe 정합: 캐시는 빌드 시점 universe로 이미 제한됨(동일 mem 로직) — 추가 필터 불요.
  rm(CACHE); gc(FALSE)
  cat(sprintf("[LO] ★ factor cache HIT (_factor_cache.rds) — parquet read 0회 | FAC rows=%d V01_BM rows=%d\n",
              nrow(FAC), nrow(FAC_VAL)))
} else {
  cat("[LO] factor cache MISS — legacy 월별 load_month_factors 루프(반복 read). build_lo_factor_cache.R 먼저 실행 권장.\n")
  fac_list <- vector("list", length(me_dates)); val_list <- vector("list", length(me_dates))
  for (i in seq_along(me_dates)) {
    d <- me_dates[i]
    uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
    fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
    if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
    ff <- fdt[Factor_Name == FACTOR_NAME & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
    fv <- fdt[Factor_Name == VAL_F       & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
    rm(fdt)
    if (nrow(ff) >= 10L) { ff[, Date := d]; fac_list[[i]] <- ff[, .(Date, Ticker, Score)] }
    if (nrow(fv) >= 20L) { fv[, Date := d]; val_list[[i]] <- fv[, .(Date, Ticker, Score)] }
    if (i %% 24L == 0L) gc(FALSE)
  }
  FAC <- rbindlist(Filter(Negate(is.null), fac_list), use.names = TRUE)
  FAC_VAL <- rbindlist(Filter(Negate(is.null), val_list), use.names = TRUE)
  rm(fac_list, val_list); gc(FALSE)
}
if (!nrow(FAC)) stop(sprintf("[driver_lo] %s: factor DB에 시그널 없음(rows=0).", FACTOR_NAME))
FAC <- FAC[Date >= START_DATE]; FAC_VAL <- FAC_VAL[Date >= START_DATE]
cat(sprintf("[LO] FAC months=%d rows=%d | FAC_VAL months=%d rows=%d\n",
            uniqueN(FAC$Date), nrow(FAC), uniqueN(FAC_VAL$Date), nrow(FAC_VAL)))

# ---- 3. 월말 패널(me_panel) = 캐시에서 이미 로드됨 (forward 1M, lookahead 없음) ----
#   ★ OOM fix: RAWDATA 재참조 제거. me_panel(Date,Ticker,Close,ret_fwd,ret_date)은 §1에서
#     캐시(또는 fallback)로 이미 빌드. rd_daily(daily Ret)는 forward-1M 경로서 미사용 → 폐기.
stopifnot(exists("me_panel"), all(c("ret_fwd","ret_date") %in% names(me_panel)))

# =============================================================================
# ★ long-only top25 빌드 (FACTOR 기준 + value(BM) 대조군 동일 메커니즘)
# =============================================================================
build_long_top25 <- function(FACDT) {
  sig_dates <- sort(unique(FACDT$Date)); sig_dates <- sig_dates[sig_dates %in% me_dates]
  L <- vector("list", length(sig_dates)); HOLD <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FACDT[Date == d & is.finite(Score)]; if (nrow(fd) < 10L) next
    setorder(fd, -Score)                                    # Score 높을수록 우월(Aligned 부호 그대로)
    sel <- head(fd, min(N_CAP, nrow(fd)))                   # top-25 EW
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]
    L[[i]]    <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
    HOLD[[i]] <- data.table(Signal_Date = d, Exec_Date = d, Ticker = mp$Ticker,
                            Weight = 1/nrow(mp), Score = sel[match(mp$Ticker, Ticker), Score])
  }
  list(legs = rbindlist(Filter(Negate(is.null), L)), hold = rbindlist(Filter(Negate(is.null), HOLD)),
       sig_dates = sig_dates)
}

# forward-leg → 월간 net Strategy_Ret (Return.portfolio + turnover net cost)
legs_to_monthly <- function(lg, with_cost = TRUE) {
  if (is.null(lg) || !nrow(lg)) return(NULL)
  Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
  Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
  dts <- Rw$Date
  Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = dts)
  Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = dts)
  gross_x <- Return.portfolio(R = Rx, weights = Wx); colnames(gross_x) <- "gross"
  to_mat <- as.matrix(Ww[, -1, with = FALSE]); to_dates <- Ww$Date
  to_vec <- numeric(nrow(to_mat)); to_vec[1] <- 1.0
  if (nrow(to_mat) >= 2) for (i in 2:nrow(to_mat)) to_vec[i] <- sum(abs(to_mat[i, ] - to_mat[i - 1, ])) / 2
  dt <- merge(data.table(Date = index(gross_x), gross = as.numeric(gross_x)),
              data.table(Date = to_dates, turnover = to_vec), by = "Date", all.x = TRUE)
  dt[is.na(turnover), turnover := 0]
  dt[, Strategy_Ret := if (with_cost) gross - turnover * COMMISSION else gross]
  setorder(dt, Date); dt
}

bl <- build_long_top25(FAC); lg <- bl$legs; hold <- bl$hold; sig_dates <- bl$sig_dates
stopifnot(nrow(lg) > 0)
nav_m <- legs_to_monthly(lg, with_cost = TRUE)

# 월간 benchmark: 실행월 d -> 실현월 nd 구간 daily BM_Ret 복리 (strategy 실현일 정렬)
#   ★ bm_d(daily BM_Ret)는 §1 캐시에서 이미 로드. BM_DT 재참조 제거(OOM fix).
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

# ---- build_bt_result -> audit -> essence ----
strategy_xts <- xts(nav_m$Strategy_Ret, order.by = nav_m$Date); names(strategy_xts) <- "Strategy"
bm_xts       <- xts(nav_m$BM_Ret_m,     order.by = nav_m$Date); names(bm_xts) <- "Benchmark"
DAILY_NAV_DT <- data.table(Date = nav_m$Date, NAV = nav_m$NAV, NAV_gross = cumprod(1 + nav_m$gross),
                           Strategy_Ret = nav_m$Strategy_Ret)
sim_result <- list(DAILY_NAV_DT = DAILY_NAV_DT,
                   PORTFOLIO_LOG = data.table(Signal_Date = sig_dates),
                   HOLDINGS_LOG = hold, strategy_xts = strategy_xts, bm_xts = bm_xts)
strategy_spec <- list(
  strategy_id = STRAT_ID, strategy_name = paste(FACTOR_NAME, "long-only top25"),
  strategy_family = "single_factor_longonly_screen",
  signal_description = paste0(FACTOR_NAME, " Z_Score_Aligned; top-25 EW long-only (short 금지)"),
  universe_rule = "K200_KQ150 membership + 20d ADV>=2e8 (PIT time-varying)",
  rebalance_frequency = "monthly", signal_date_rule = "month_end",
  execution_date_rule = "month_end_signal_t_plus_1", weighting_method = "equal_weight",
  max_position_weight = 0.20, max_leverage = 1.0, cash_rule = "fully_invested",
  cost_model = "v2.3_kr_retail_15bps", missing_data_rule = "drop", risk_controls = "long_only",
  lookahead_prevention = "forward_1M_hold + t-1 liquidity + factor DB Usable_Date",
  survivorship_bias_control = "PIT membership panel")
run_id <- paste0(STRAT_TAG, "_LO_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
bt <- build_bt_result(sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = STRAT_ID, strategy_version = "v1.0",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 15, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150", code_version = "driver_lo_screen", created_by_agent = "AlphaSearch")
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = NULL)   # 1알파 직교검증 → DSR 부적용

register_module(sim_result, STRAT_ID, grade = es$grade, origin_mode = "alpha_search",
                role = "core", meta = list(strategy_idea = paste0(FACTOR_NAME, " long-only top25 (short 금지, 직교/방어 후보)"),
                                           factor = FACTOR_NAME, n_cap = N_CAP))

# 측정 요약
M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
gm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
sharpe <- gm("Sharpe"); cagr <- gm("CAGR"); mdd <- gm("MDD"); calmar <- gm("Calmar")
net_ir <- gbc("Information_Ratio"); port_t <- gbc("Portfolio_Alpha_t_NW_lag3"); excess_cum <- gbc("Excess_Total_Return")
n_hold <- if (nrow(hold)) round(mean(hold[, .N, by = Signal_Date]$N), 1) else NA_real_

# ---- OOS retention (★ 도훈 mandate 정의: IS<=2015 vs OOS>=2016 active SR) ----
#   essence_score는 65/35 split + IS active IR<=0.05이면 NA. 본 mandate는 calendar split의
#   active(전략-BM) SR 비율. active SR = mean(active)/sd(active)*sqrt(12).
nav_m[, active := Strategy_Ret - BM_Ret_m]
nav_m[, yr := as.integer(format(Date, "%Y"))]
sr_is_lo  <- sharpe_ann(nav_m[yr <= 2015, active])
sr_oos_lo <- sharpe_ann(nav_m[yr >= 2016, active])
oos_ret_lo <- if (is.finite(sr_is_lo) && abs(sr_is_lo) > 1e-9) sr_oos_lo / sr_is_lo else NA_real_
oos_ret_essence <- es$essence$oos_retention %||% NA_real_

# Carhart4 (long-only net vs KR factor returns)
c4t <- NA_real_; c4a <- NA_real_
mf_lo <- tryCatch(run_multifactor_regression(strategy_xts, bm_xts = bm_xts, factor_dt = load_kr_factor_returns()),
                  error = function(e) { cat("[LO] Carhart4 생략:", conditionMessage(e), "\n"); NULL })
if (!is.null(mf_lo) && !is.null(mf_lo$Carhart4)) { c4t <- mf_lo$Carhart4$alpha_tstat; c4a <- mf_lo$Carhart4$alpha * 12 * 100 }

# =============================================================================
# 다축 상관 (long-only only): FACTOR LO월간 vs value(BM) LO월간 / STR_1715 net
# =============================================================================
fac_lo_ym <- { x <- xts(nav_m$Strategy_Ret, order.by = nav_m$Date)
  data.table(ym = format(nav_m$Date, "%Y-%m"), fac = nav_m$Strategy_Ret) }

# value(BM) long-only top25 대조군 (동일 메커니즘 — short 없음)
val_lo_ym <- NULL
if (nrow(FAC_VAL)) {
  blv <- build_long_top25(FAC_VAL)
  if (nrow(blv$legs)) {
    vm <- legs_to_monthly(blv$legs, with_cost = TRUE)
    if (!is.null(vm)) val_lo_ym <- data.table(ym = format(vm$Date, "%Y-%m"), val = vm$Strategy_Ret)
  }
}
gc(FALSE)   # ★ OOM fix: rd_daily 폐기됨(forward-1M me_panel 경로). RAWDATA 미참조.

# STR_1715 월간 net
str1715_path <- file.path(PROJ, "04_Research", "strategies", "STR_1715_WT016_Iter31_GridBestProd",
                          "output", "03_period_returns.csv")
s1715 <- tryCatch({ z <- fread(str1715_path); z[, ym := format(as.Date(date), "%Y-%m")]; z[, .(ym, str1715 = ret_net)]
}, error = function(e) NULL)

cor_pair <- function(a_dt, a_col, b_dt, b_col) {
  if (is.null(a_dt) || is.null(b_dt)) return(NA_real_)
  m <- merge(a_dt[, .(ym, a = get(a_col))], b_dt[, .(ym, b = get(b_col))], by = "ym")
  m <- m[is.finite(a) & is.finite(b)]; if (nrow(m) < 24L) return(NA_real_)
  as.numeric(cor(m$a, m$b))
}
corr_vs_value_lo <- round(cor_pair(fac_lo_ym, "fac", val_lo_ym, "val"), 4)
corr_vs_str1715  <- round(cor_pair(fac_lo_ym, "fac", s1715, "str1715"), 4)

# =============================================================================
# 판정(long-only only) + 저장
# =============================================================================
# OOS robust = retention>=0.5 AND IS·OOS active SR 둘 다 양수(음수/음수 비율 착시 차단)
ax_oos     <- is.finite(oos_ret_lo) && oos_ret_lo >= 0.5 &&
              is.finite(sr_is_lo) && sr_is_lo > 0 && is.finite(sr_oos_lo) && sr_oos_lo > 0
corr_vec   <- c(corr_vs_value_lo, corr_vs_str1715)
max_abs_corr <- suppressWarnings(max(abs(corr_vec), na.rm = TRUE))
ax_ortho   <- is.finite(max_abs_corr) && max_abs_corr < 0.30
ax_defense <- is.finite(mdd) && mdd < 0.30
oos_robust_candidate <- ax_oos && ax_ortho       # OOS robust 직교 후보
defense_candidate    <- ax_defense               # 방어 기여 후보(alpha 아니어도)

out <- list(
  experiment = paste0(FACTOR_NAME, " long-only top25 스크리닝 (★short 금지)"),
  factor = FACTOR_NAME, strategy_id = STRAT_ID, run_id = run_id,
  metric_type = "backtested", universe = "K200_KQ150", start_date = as.character(START_DATE),
  long_only_top25 = list(
    n_months = nrow(nav_m), avg_n_holdings = n_hold, weighting = "equal_weight", n_cap = N_CAP,
    sharpe = round(sharpe,4), cagr_pct = round(cagr*100,3), mdd_pct = round(mdd*100,3), calmar = round(calmar,4),
    oos_retention = round(oos_ret_lo, 4), oos_split = "IS<=2015 / OOS>=2016 active SR",
    active_sr_is = round(sr_is_lo, 4), active_sr_oos = round(sr_oos_lo, 4),
    oos_retention_essence_65_35 = round(oos_ret_essence, 4),
    net_ir = round(net_ir,4), portfolio_alpha_t_nw_lag3 = round(port_t,4),
    excess_total_return_pct = round(excess_cum*100,3),
    carhart4_alpha_ann_pct = round(c4a,3), carhart4_alpha_t = round(c4t,4),
    essence = list(grade = es$grade, hard_fail = es$hard_fail, reasons = es$reasons)),
  multi_axis_corr = list(vs_value_bm_lo = corr_vs_value_lo, vs_STR_1715 = corr_vs_str1715,
                         max_abs_corr = round(max_abs_corr, 4)),
  verdict = list(
    oos_retention_ge_0p5 = ax_oos, ortho_corr_lt_0p3 = ax_ortho, mdd_lt_30 = ax_defense,
    oos_robust_orthogonal_candidate = oos_robust_candidate,
    defense_candidate = defense_candidate,
    interpretation = if (oos_robust_candidate)
        "★ OOS robust 직교 후보 — long-only OOS retention>=0.5 + 다축 상관<0.3"
      else if (defense_candidate)
        "방어 기여 후보 — MDD<30% (alpha 아니어도 tail 기여)"
      else
        "기각 — OOS robust도 방어도 미충족"),
  registered = sprintf("04_Research/strategies/%s/sim_result.rds + module_catalog.json", STRAT_ID),
  short_policy = "LONG_ONLY_ONLY (도훈 mandate 2026-06-06 short 전면 금지)",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))
write_json(out, file.path(OUT_DIR, sprintf("%s.json", FACTOR_NAME)),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

cat(sprintf("\n[LO-DONE] %s | n=%d | Sharpe=%.3f CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f | net_IR=%.3f PORT_t=%.3f | OOS_ret=%.3f | C4 a=%.2f%%/yr t=%.2f | corr(val_lo=%.2f str1715=%.2f) | GRADE=%s | %s\n",
            STRAT_ID, nrow(nav_m), sharpe, cagr*100, mdd*100, calmar, net_ir, port_t, oos_ret_lo, c4a, c4t,
            corr_vs_value_lo %||% NA, corr_vs_str1715 %||% NA, es$grade,
            if (oos_robust_candidate) "OOS_ROBUST_ORTHO" else if (defense_candidate) "DEFENSE_CAND" else "reject"))
cat(sprintf("[SAVED] %s.json\n", FACTOR_NAME))
