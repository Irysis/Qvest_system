# =============================================================================
# replication_harness.R — 논문 충실구현 시뮬레이터 (v10 2026-08-29 신설)
# =============================================================================
# 왜 별도 하네스인가 (도훈 지시 "완전 충실구현 — 롱숏·종목수·비중 논문 그대로"):
#   기존 backtest_harness.R::run_monthly_simulation 은 **주식수 기반 롱 전용**이다 —
#   `shares <- floor(alloc/price)` 로 음수 포지션 표현 불가 + 25종 물리 캡(:1037-1044).
#   그 하네스는 실투형(강화 프로세스 이후) 정본으로 무변경 보존하고, 충실구현은
#   **비중 기반** 경로를 여기서 신설한다.
#
# ★자체합성 금지 계약 준수 (backtest-contract.md · python-policy §4):
#   - leg 내 일간 포트수익 = PerformanceAnalytics::Return.portfolio (월내 drift 표준)
#   - leg 결합(GL·L − GS·S)·월간 집계(apply.monthly + Return.cumulative)는
#     driver_ls_generic.R (2026-06-06) 이 확립한 선례를 그대로 따른다.
#   - NAV 누적 cumprod 는 build_benchmark_returns 와 동일 관용(수익 합성이 아니라 누적).
#
# ★PIT: 시그널 d → 실행 get_execution_date(d) = 다음 거래일(t+1). 보유 (exec, next_exec).
#   leg 종목·비중은 d 시점 확정 — forward 정보 무사용 (driver_ls_generic 규약 동일).
#
# 비용 모델: 리밸일 레그별 Σ|Δw_target| × commission (v2.4 delta 정신의 비중판).
#   첫 리밸은 Σ|w| × commission (초기 매수). 월중 drift 대비 target 차이의 근사임을
#   manifest 에 라벨(`cost_model = "weight_delta_approx"`). commission=0 = gross.
#
# 입력:
#   WEIGHTS = data.table(Date [시그널일], Ticker, Weight [부호 포함, 논문 그대로])
#     Σ|w| 스케일 자유 (예: 롱온리 Σw=1 / 데실 L-S 는 long Σ=+1, short Σ=−1).
# 반환: run_monthly_simulation 계열 인터페이스 —
#   list(strategy_xts, DAILY_NAV_DT(Date,NAV,NAV_gross), bm_xts,
#        PORTFOLIO_LOG(Signal_Date,Exec_Date,N_Long,N_Short,GL,GS,Turnover),
#        HOLDINGS_LOG(Date,Ticker,Weight,Leg), diagnostics(n_max 등))
#   → build_bt_result() 가 그대로 소비 가능.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics)
})

run_replication_simulation <- function(RAWDATA, BM_DT, WEIGHTS,
                                       commission = 0.0015,
                                       start_date = "2005-01-01") {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  stopifnot(is.data.table(WEIGHTS), all(c("Date", "Ticker", "Weight") %in% names(WEIGHTS)))
  W <- copy(WEIGHTS)
  if (!inherits(W$Date, "Date")) W[, Date := as.Date(Date)]
  W <- W[is.finite(Weight) & Weight != 0]
  if (!is.null(start_date)) W <- W[Date >= as.Date(start_date)]
  if (nrow(W) == 0L) stop("[replication] WEIGHTS 가 비었습니다 (start_date 이후 0건).")

  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  all_dates <- sort(unique(RAWDATA$Date))
  sig_dates <- sort(unique(W$Date))

  # ── 레그별 일간 수익 (Return.portfolio — 비중 비례 정규화, drift 표준 처리) ──
  .leg_daily <- function(md, side) {
    wv <- if (side == "long") md[Weight > 0] else md[Weight < 0]
    if (nrow(wv) == 0L) return(NULL)
    gross <- sum(abs(wv$Weight))
    sub <- RAWDATA[Ticker %in% wv$Ticker & Date >= wv$exec[1] & Date <= wv$hold_end[1] &
                     is.finite(Ret), .(Date, Ticker, Ret)]
    if (nrow(sub) == 0L) return(NULL)
    wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
    setorder(wide, Date)
    rmat <- as.matrix(wide[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = wide$Date)
    wnorm <- setNames(abs(wv$Weight) / gross, wv$Ticker)[colnames(rx)]
    wnorm[!is.finite(wnorm)] <- 0
    if (sum(wnorm) <= 0) return(NULL)
    wnorm <- wnorm / sum(wnorm)
    pr <- tryCatch(Return.portfolio(rx, weights = wnorm, rebalance_on = NA),
                   error = function(e) NULL)
    if (is.null(pr)) return(NULL)
    list(ret = data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1])),
         gross = gross)
  }

  daily_list <- vector("list", length(sig_dates))
  port_log <- vector("list", length(sig_dates))
  hold_log <- vector("list", length(sig_dates))
  prev_w <- NULL   # 직전 리밸 target (Ticker → signed Weight) — Δw 비용용

  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    md <- W[Date == d]
    exec_date <- get_execution_date(d, all_dates)
    if (is.na(exec_date)) next
    next_exec <- if (i < length(sig_dates)) get_execution_date(sig_dates[i + 1L], all_dates) else NA
    hold_pool <- if (!is.na(next_exec)) all_dates[all_dates < next_exec] else all_dates
    hold_pool <- hold_pool[hold_pool >= exec_date]
    if (!length(hold_pool)) next
    hold_end <- max(hold_pool)
    md[, exec := exec_date]; md[, hold_end := hold_end]

    L <- .leg_daily(md, "long"); S <- .leg_daily(md, "short")
    if (is.null(L) && is.null(S)) next
    GL <- if (!is.null(L)) L$gross else 0
    GS <- if (!is.null(S)) S$gross else 0

    dd <- data.table(Date = hold_pool)
    dd <- merge(dd, if (!is.null(L)) L$ret[, .(Date, Lr = Ret)] else data.table(Date = hold_pool, Lr = 0),
                by = "Date", all.x = TRUE)
    dd <- merge(dd, if (!is.null(S)) S$ret[, .(Date, Sr = Ret)] else data.table(Date = hold_pool, Sr = 0),
                by = "Date", all.x = TRUE)
    dd[!is.finite(Lr), Lr := 0]; dd[!is.finite(Sr), Sr := 0]
    # 결합 = GL·L − GS·S (driver_ls_generic 선례 — leg 산출은 Return.portfolio, 결합은 선형)
    dd[, Rg := GL * Lr - GS * Sr]

    # 비용: 리밸일(exec) 1회, Σ|Δw_target| × commission (부재 종목 = 0 — 신규 편입/전량 청산 포함)
    cur_w <- setNames(md$Weight, md$Ticker)
    to_val <- if (is.null(prev_w)) {
      sum(abs(cur_w))                     # 초기 매수: Σ|w|
    } else {
      allt <- union(names(prev_w), names(cur_w))
      a <- cur_w[allt];  a[is.na(a)] <- 0
      b <- prev_w[allt]; b[is.na(b)] <- 0
      sum(abs(a - b))
    }
    dd[, cost := 0]
    dd[Date == exec_date, cost := to_val * commission]
    dd[, Rn := Rg - cost]
    prev_w <- cur_w

    daily_list[[i]] <- dd[, .(Date, Rg, Rn)]
    port_log[[i]] <- data.table(Signal_Date = d, Exec_Date = exec_date,
                                N_Long = sum(md$Weight > 0), N_Short = sum(md$Weight < 0),
                                GL = GL, GS = GS, Turnover = to_val)
    hold_log[[i]] <- data.table(Date = exec_date, Ticker = md$Ticker,
                                Weight = md$Weight,
                                Leg = ifelse(md$Weight > 0, "long", "short"))
  }

  D <- rbindlist(Filter(Negate(is.null), daily_list), use.names = TRUE)
  if (nrow(D) == 0L) stop("[replication] 시뮬레이션 산출 0일 — WEIGHTS/RAWDATA 정합 확인.")
  setorder(D, Date)
  D <- D[, .(Rg = mean(Rg), Rn = mean(Rn)), by = Date]   # 경계 중복일 평균 (선례 동일)

  nav <- copy(D)
  nav[, NAV := cumprod(1 + Rn)]        # NAV 누적 (build_benchmark_returns 관용)
  nav[, NAV_gross := cumprod(1 + Rg)]

  bm <- BM_DT[Date %in% D$Date & is.finite(BM_Ret), .(Date, BM_Ret)]
  setorder(bm, Date)

  plog <- rbindlist(Filter(Negate(is.null), port_log), use.names = TRUE)
  hlog <- rbindlist(Filter(Negate(is.null), hold_log), use.names = TRUE)
  n_by_reb <- hlog[, .(n = uniqueN(Ticker)), by = Date]

  list(
    strategy_xts = xts(D$Rn, order.by = D$Date),
    DAILY_NAV_DT = nav[, .(Date, NAV, NAV_gross)],
    bm_xts       = xts(bm$BM_Ret, order.by = bm$Date),
    PORTFOLIO_LOG = plog,
    HOLDINGS_LOG  = hlog,
    diagnostics = list(
      n_max = if (nrow(n_by_reb)) max(n_by_reb$n) else NA_integer_,
      n_min = if (nrow(n_by_reb)) min(n_by_reb$n) else NA_integer_,
      n_rebalances = nrow(plog),
      has_short = any(hlog$Leg == "short"),
      avg_turnover = if (nrow(plog)) mean(plog$Turnover, na.rm = TRUE) else NA_real_,
      commission = commission,
      cost_model = "weight_delta_approx"
    )
  )
}

cat("[replication_harness.R] Loaded (v10) — run_replication_simulation(RAWDATA, BM_DT, WEIGHTS, commission)\n")
