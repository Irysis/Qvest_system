# =============================================================================
# replication_harness.R — 논문 충실구현 시뮬레이터 (v10 2026-08-29 신설 · 2026-09-24 집행 규약 인자화)
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
# ★집행 규약 exec_price (2026-09-24 · 플랜 P0-04 · 감사 D4-01 critical ·
#   결정 레지스터 06_Registry/decision_register.json id=EXEC-PRICE — 도훈 2026-09-23
#   "close_t1 — 익일 종가(정본 backtest_harness 와 같은 의미) · 실현 가능성 논거").
#   시그널 d(월말) → 집행일 exec = get_execution_date(d) = 익월 첫 거래일(backtest_harness.R:316).
#   비중은 d 시점 확정(forward 정보 무사용). 규약은 **무엇을 어느 가격에 사느냐**만 가른다:
#   - "close_d_legacy" : 2026-08-29 초판 동작 그대로(비트 동일 — 재현·민감도 전용).
#       보유창 [exec, next_exec). RAWDATA Ret = Close_t/Close_{t-1}−1 이라 새 보유가 집행일 수익
#       Close[exec]/Close[exec−1]−1 을 가진다 = **시그널일 종가 체결 근사**(동일봉 · D4-01).
#       (구 주석 "보유 (exec, next_exec)" 는 코드와 달랐다 — 코드는 exec 당일을 포함했다.)
#       비용 기장 = exec 행 가산 차감 Rn = Rg − Σ|Δw|·c.
#   - "close_t1" : 새 보유를 Close[exec] 에 산다 — 정본 run_monthly_simulation 과 같은 의미
#       (:1079-1085 (prev,exec] 구간 NAV 는 **옛 보유** · :1299-1316 Close[exec] 로 매수).
#       보유창 (exec, next_exec] — 집행일 수익은 직전 보유가 **드리프트 비중**으로 가진다
#       (Return.portfolio 창 안 buy-and-hold 가 드리프트를 처리한다). 마지막 창 = (exec_last, 끝].
#       비용 기장 = exec 종가 체결 시 현금 차감 → 새 보유 첫 날(exec 다음 거래일) 수익에 곱으로:
#       Rn = (1 − Σ|Δw|·c)(1 + Rg) − 1. 정본 :1333 cash = total_val − total_cost 와 같은 NAV 경로다
#       (NAV_{exec+1} = (V_exec − C)(1 + r)). 첫 집행일 exec_1 에는 보유가 없어 수익 행이 없다.
#   - "open_t1" : 새 보유를 Open[exec] 에 산다(민감도 전용 — RAWDATA Open 의 수정주가 정합이 미검증).
#       집행일 수익을 겹밤 r_on = Open/Close_prev−1(직전 보유) 과 장중 r_id = Close/Open−1(새 보유)로
#       가르고, 같은 날 두 행은 곱으로 합친다. 비용 기장 = exec 시가 체결 → 새 보유 첫 행(exec 장중)에 곱.
#       ★가드: 겹밤 갭이 일일 가격제한폭(constraint_defaults.json::execution.open_t1_overnight_limit)을
#       넘으면 Open 미수정 이음매로 보고 그 종목·날은 close_t1 처리(r_on = Ret · r_id = 0 — 새 보유에
#       집행일 수익을 주지 않는 보수 쪽) 후 diagnostics$open_guard 에 센다.
#   기본값은 **하드코딩하지 않는다** — exec_price = NULL 이면 constraint_defaults.json::execution.exec_price
#   를 읽는다(rep_exec_price_default). 설정이 없거나 값이 허용 밖이면 멈춘다(기본값을 지어내지 않는다).
#
# 비용 모델: 리밸별 레그 Σ|Δw_target| × commission (v2.4 delta 정신의 비중판 — 목표 비중 간 차이).
#   첫 리밸은 Σ|w| × commission (초기 매수). 월중 drift 대비 target 차이의 근사임을
#   diagnostics$cost_model 에 라벨, 규약별 기장 방식은 cost_model_version 에 싣는다. commission=0 = gross.
#
# 입력:
#   WEIGHTS = data.table(Date [시그널일], Ticker, Weight [부호 포함, 논문 그대로])
#     Σ|w| 스케일 자유 (예: 롱온리 Σw=1 / 데실 L-S 는 long Σ=+1, short Σ=−1).
#   exec_price = NULL(설정 기본값) | "close_d_legacy" | "close_t1" | "open_t1" (open_t1 은 RAWDATA$Open 필요)
# 반환: run_monthly_simulation 계열 인터페이스 —
#   list(strategy_xts, DAILY_NAV_DT(Date,NAV,NAV_gross), bm_xts,
#        PORTFOLIO_LOG(Signal_Date,Exec_Date,N_Long,N_Short,GL,GS,Turnover,Cost_Date),
#        HOLDINGS_LOG(Date,Ticker,Weight,Leg), diagnostics(n_max·exec_price·cost_booking 등),
#        strategy_gross_xts (P0-03 — 비용 전 일간 수익 Rg · 첫 행 포함), cost_model_version)
#   → build_bt_result() 가 그대로 소비 가능(ret_gross 는 strategy_gross_xts 를 우선 쓴다).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics)
})

# ── 집행 규약 설정 해석 ─────────────────────────────────────────────────────────
.REP_EXEC_PRICES <- c("close_d_legacy", "close_t1", "open_t1")

# 이 파일의 위치(자기 우선) — 설정을 **같은 체크아웃**에서 찾는다(worktree 에서 main 설정을 읽지 않게).
#   source() 는 프레임에 ofile, sys.source() 는 file 을 남긴다. 이름이 이 파일인 것만 채택한다
#   (중첩 source 의 바깥 스크립트를 자기로 오인하지 않게).
.REP_SELF <- local({
  hit <- ""
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- tryCatch(sys.frame(i), error = function(e) NULL)
    if (is.null(fr)) next
    for (nm in c("ofile", "file")) {
      v <- tryCatch(get0(nm, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && !is.na(v) &&
          grepl("replication_harness\\.R$", v)) { hit <- v; break }
    }
    if (nzchar(hit)) break
  }
  if (nzchar(hit) && !grepl("^([A-Za-z]:)?[/\\\\]", hit)) hit <- file.path(getwd(), hit)
  hit
})

# constraint_defaults.json::execution 블록. 경로 = QVEST_CONSTRAINT_DEFAULTS(명시 레버 — 검사가 사본을
#   가리킬 때) > 이 파일 기준 루트 > CLAUDE_PROJECT_DIR > QM_ROOT > getwd. 명시 레버가 가리키는 파일이
#   없으면 폴백하지 않고 멈춘다(레버를 조용히 무시하면 검사가 운영 설정을 잰다).
rep_execution_config <- function() {
  ov <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", "")
  if (nzchar(ov)) {
    if (!file.exists(ov)) stop(sprintf("[replication] QVEST_CONSTRAINT_DEFAULTS=%s 가 없다 — 폴백하지 않는다", ov))
    path <- ov
  } else {
    roots <- c(if (nzchar(.REP_SELF)) dirname(dirname(dirname(.REP_SELF))) else character(0),
               Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
    roots <- roots[nzchar(roots)]
    cands <- file.path(roots, "02_Infrastructure", "worktask", "constraint_defaults.json")
    path <- cands[file.exists(cands)][1]
    if (is.na(path)) stop("[replication] constraint_defaults.json 을 찾지 못했다 — exec_price 를 명시하거나 QM_ROOT 를 확인")
  }
  cfg <- tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE),
                  error = function(e) stop(sprintf("[replication] %s 파싱 실패: %s", path, conditionMessage(e))))
  ex <- cfg[["execution"]]
  if (!is.list(ex))
    stop(sprintf("[replication] %s 에 execution 블록이 없다 — 집행 규약 기본값을 지어내지 않는다(fail-closed)", path))
  attr(ex, "source") <- path
  ex
}

rep_exec_price_default <- function() {
  ex <- rep_execution_config()
  ep <- ex[["exec_price"]]
  if (!is.character(ep) || length(ep) != 1L || is.na(ep) || !ep %in% .REP_EXEC_PRICES)
    stop(sprintf("[replication] %s::execution.exec_price='%s' — 허용값 %s (fail-closed)",
                 attr(ex, "source"), paste(format(ep), collapse = ","), paste(.REP_EXEC_PRICES, collapse = "/")))
  ep
}

rep_resolve_exec_price <- function(exec_price = NULL) {
  if (is.null(exec_price) || !length(exec_price) || (length(exec_price) == 1L && is.na(exec_price)))
    return(rep_exec_price_default())
  ep <- as.character(exec_price)
  if (length(ep) != 1L || !ep %in% .REP_EXEC_PRICES)
    stop(sprintf("[replication] exec_price='%s' — 허용값 %s", paste(ep, collapse = ","),
                 paste(.REP_EXEC_PRICES, collapse = "/")))
  ep
}

# 규약별 비용 기장 라벨 — manifest cost_model_version(P0-03)·measurement_regime 에 실린다.
rep_cost_model_version <- function(exec_price) switch(exec_price,
  close_d_legacy = "replication_weight_delta_v1/exec_day_additive",
  close_t1       = "replication_weight_delta_v1/first_hold_day_multiplicative",
  open_t1        = "replication_weight_delta_v1/exec_open_multiplicative",
  stop(sprintf("[replication] 미지 exec_price: %s", exec_price)))

# 규약 진술 — strategy_spec$lookahead_prevention 을 **실제 인자에서** 만든다(P0-04).
rep_exec_statement <- function(exec_price) switch(exec_price,
  close_d_legacy = paste0("집행 close_d_legacy — 새 보유가 집행일(익월 첫 거래일) 수익 Close[exec]/Close[exec-1]-1 을 가짐",
                          " = 시그널일 종가 체결 근사(동일봉 · 감사 D4-01 · PIT C2 위험) — 재현·민감도 전용"),
  close_t1       = paste0("집행 close_t1 — 시그널일 d 확정 비중을 익월 첫 거래일 종가 Close[exec] 에 체결 · 새 보유 수익 (exec, next_exec]",
                          " · 집행일 수익은 직전 보유(PIT C2 동일봉 체결 없음 · 정본 backtest_harness 와 같은 의미)"),
  open_t1        = paste0("집행 open_t1 — 익월 첫 거래일 시가 Open[exec] 체결 · 집행일 겹밤=직전 보유 · 장중=새 보유",
                          "(PIT C2 동일봉 체결 없음) · Open 수정주가 정합 미검증 — 민감도 전용"),
  stop(sprintf("[replication] 미지 exec_price: %s", exec_price)))

# open_t1 겹밤 한도 — 날짜별 일일 가격제한폭(설정 정본). 한도를 넘는 갭 = 수정 이음매.
.rep_overnight_limit <- function(dates) {
  sch <- rep_execution_config()[["open_t1_overnight_limit"]]
  if (is.null(sch) || !all(c("from", "limit") %in% names(sch)))
    stop("[replication] open_t1: constraint_defaults.json::execution.open_t1_overnight_limit 부재 — 가드 없이 돌지 않는다")
  sch <- data.table(from = as.Date(sch$from), limit = as.numeric(sch$limit))
  setorder(sch, from)
  idx <- findInterval(as.numeric(as.Date(dates)), as.numeric(sch$from))
  out <- rep(NA_real_, length(dates)); out[idx > 0L] <- sch$limit[idx[idx > 0L]]
  out
}

run_replication_simulation <- function(RAWDATA, BM_DT, WEIGHTS,
                                       commission = 0.0015,
                                       start_date = "2005-01-01",
                                       exec_price = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  exec_price <- rep_resolve_exec_price(exec_price)
  stopifnot(is.data.table(WEIGHTS), all(c("Date", "Ticker", "Weight") %in% names(WEIGHTS)))
  W <- copy(WEIGHTS)
  if (!inherits(W$Date, "Date")) W[, Date := as.Date(Date)]
  W <- W[is.finite(Weight) & Weight != 0]
  if (!is.null(start_date)) W <- W[Date >= as.Date(start_date)]
  if (nrow(W) == 0L) stop("[replication] WEIGHTS 가 비었습니다 (start_date 이후 0건).")

  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  all_dates <- sort(unique(RAWDATA$Date))
  sig_dates <- sort(unique(W$Date))

  # ── open_t1: 집행일 수익 분할표 (Date, Ticker, r_on, r_id, ok) ──
  #   Close_prev = Close/(1+Ret) (Ret 정의 그대로) → r_on = Open(1+Ret)/Close − 1, r_id = Close/Open − 1,
  #   (1+r_on)(1+r_id) = 1+Ret. 가드 불통과(Open 결측·비양수·겹밤 갭 > 제한폭) = r_on := Ret, r_id := 0.
  SPLIT <- NULL
  og <- list(n_checked = 0L, n_flagged = 0L)
  if (identical(exec_price, "open_t1")) {
    if (!all(c("Open", "Close") %in% names(RAWDATA)))
      stop("[replication] exec_price=open_t1 은 RAWDATA$Open·Close 가 필요하다")
    ex_all <- unique(as.Date(vapply(sig_dates, function(s) as.numeric(get_execution_date(s, all_dates)), numeric(1))))
    ex_all <- ex_all[!is.na(ex_all)]
    SPLIT <- RAWDATA[Date %in% ex_all & is.finite(Ret), .(Date, Ticker, Ret, Open, Close)]
    SPLIT[, lim := .rep_overnight_limit(Date)]
    SPLIT[, r_on := Open * (1 + Ret) / Close - 1]
    SPLIT[, r_id := Close / Open - 1]
    SPLIT[, ok := is.finite(Open) & is.finite(Close) & Open > 0 & Close > 0 &
                  is.finite(r_on) & is.finite(r_id) & is.finite(lim) & abs(r_on) <= lim + 1e-9]
    SPLIT[ok == FALSE, `:=`(r_on = Ret, r_id = 0)]
  }

  # ── 레그별 일간 수익 (Return.portfolio — 비중 비례 정규화, drift 표준 처리) ──
  .leg_daily <- function(md, side) {
    wv <- if (side == "long") md[Weight > 0] else md[Weight < 0]
    if (nrow(wv) == 0L) return(NULL)
    gross <- sum(abs(wv$Weight))
    sub <- RAWDATA[Ticker %in% wv$Ticker & Date >= wv$win_lo[1] & Date <= wv$win_hi[1] &
                     is.finite(Ret), .(Date, Ticker, Ret)]
    if (nrow(sub) == 0L) return(NULL)
    if (!is.null(SPLIT)) {                     # open_t1 — 창 경계일 수익 분할
      f1 <- wv$split_first[1]; l1 <- wv$split_last[1]
      if (!is.na(f1)) { s <- SPLIT[Date == f1]; j <- match(sub[Date == f1]$Ticker, s$Ticker)
                        sub[Date == f1, Ret := s$r_id[j]]
                        og$n_checked <<- og$n_checked + length(j); og$n_flagged <<- og$n_flagged + sum(!s$ok[j]) }
      if (!is.na(l1)) { s <- SPLIT[Date == l1]; j <- match(sub[Date == l1]$Ticker, s$Ticker)
                        sub[Date == l1, Ret := s$r_on[j]]
                        og$n_checked <<- og$n_checked + length(j); og$n_flagged <<- og$n_flagged + sum(!s$ok[j]) }
    }
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
    # 보유창 — 규약이 가르는 유일한 자리 (위 헤더 참조)
    if (identical(exec_price, "close_d_legacy")) {
      hold_pool <- if (!is.na(next_exec)) all_dates[all_dates < next_exec] else all_dates
      hold_pool <- hold_pool[hold_pool >= exec_date]
    } else if (identical(exec_price, "close_t1")) {
      hold_pool <- if (!is.na(next_exec)) all_dates[all_dates <= next_exec] else all_dates
      hold_pool <- hold_pool[hold_pool > exec_date]
    } else {                                   # open_t1 — [exec(장중), next_exec(겹밤)]
      hold_pool <- if (!is.na(next_exec)) all_dates[all_dates <= next_exec] else all_dates
      hold_pool <- hold_pool[hold_pool >= exec_date]
    }
    if (!length(hold_pool)) next
    hold_end <- max(hold_pool)
    cost_date <- if (identical(exec_price, "close_d_legacy")) exec_date else min(hold_pool)
    md[, win_lo := min(hold_pool)]; md[, win_hi := hold_end]
    if (identical(exec_price, "open_t1")) {
      md[, split_first := exec_date]
      md[, split_last := if (!is.na(next_exec) && next_exec == hold_end) next_exec else as.Date(NA)]
    }

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

    # 비용: 리밸 1회, Σ|Δw_target| × commission (부재 종목 = 0 — 신규 편입/전량 청산 포함)
    cur_w <- setNames(md$Weight, md$Ticker)
    to_val <- if (is.null(prev_w)) {
      sum(abs(cur_w))                     # 초기 매수: Σ|w|
    } else {
      allt <- union(names(prev_w), names(cur_w))
      a <- cur_w[allt];  a[is.na(a)] <- 0
      b <- prev_w[allt]; b[is.na(b)] <- 0
      sum(abs(a - b))
    }
    if (identical(exec_price, "close_d_legacy")) {
      # 초판 그대로(비트 동일) — exec 행 가산 차감
      dd[, cost := 0]
      dd[Date == exec_date, cost := to_val * commission]
      dd[, Rn := Rg - cost]
    } else {
      # t1 — 체결 시 현금 차감을 새 보유 첫 행에 곱으로 기장 (정본 NAV 경로와 동일)
      .k <- to_val * commission
      dd[, Rn := Rg]
      if (.k != 0) dd[Date == cost_date, Rn := (1 - .k) * (1 + Rg) - 1]
    }
    prev_w <- cur_w

    daily_list[[i]] <- dd[, .(Date, Rg, Rn)]
    port_log[[i]] <- data.table(Signal_Date = d, Exec_Date = exec_date,
                                N_Long = sum(md$Weight > 0), N_Short = sum(md$Weight < 0),
                                GL = GL, GS = GS, Turnover = to_val, Cost_Date = cost_date)
    hold_log[[i]] <- data.table(Date = exec_date, Ticker = md$Ticker,
                                Weight = md$Weight,
                                Leg = ifelse(md$Weight > 0, "long", "short"))
  }

  D <- rbindlist(Filter(Negate(is.null), daily_list), use.names = TRUE)
  if (nrow(D) == 0L) stop("[replication] 시뮬레이션 산출 0일 — WEIGHTS/RAWDATA 정합 확인.")
  setorder(D, Date)
  n_overlap <- sum(duplicated(D$Date))
  D <- if (identical(exec_price, "open_t1")) {
    D[, .(Rg = prod(1 + Rg) - 1, Rn = prod(1 + Rn) - 1), by = Date]   # 집행일 겹밤(옛)·장중(새) 합성
  } else {
    D[, .(Rg = mean(Rg), Rn = mean(Rn)), by = Date]   # 경계 중복일 평균 (선례 동일 · 창이 서로소라 항등)
  }

  nav <- copy(D)
  nav[, NAV := cumprod(1 + Rn)]        # NAV 누적 (build_benchmark_returns 관용)
  nav[, NAV_gross := cumprod(1 + Rg)]

  bm <- BM_DT[Date %in% D$Date & is.finite(BM_Ret), .(Date, BM_Ret)]
  setorder(bm, Date)

  plog <- rbindlist(Filter(Negate(is.null), port_log), use.names = TRUE)
  hlog <- rbindlist(Filter(Negate(is.null), hold_log), use.names = TRUE)
  n_by_reb <- hlog[, .(n = uniqueN(Ticker)), by = Date]

  if (identical(exec_price, "open_t1") && og$n_flagged > 0L)
    cat(sprintf("[replication][WARN] open_t1 가드: 집행일 경계 %d행 중 %d행이 가격제한폭 초과 겹밤 갭/Open 결측 — close_t1 처리\n",
                og$n_checked, og$n_flagged))

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
      cost_model = "weight_delta_approx",
      exec_price = exec_price,
      holding_window = switch(exec_price, close_d_legacy = "[exec, next_exec)",
                              close_t1 = "(exec, next_exec]", open_t1 = "[exec intraday, next_exec overnight]"),
      cost_booking = switch(exec_price, close_d_legacy = "exec_date additive (Rn = Rg - c)",
                            close_t1 = "first holding day multiplicative (Rn = (1-c)(1+Rg)-1)",
                            open_t1 = "exec_date intraday multiplicative (Rn = (1-c)(1+Rg)-1)"),
      n_overlap_days = n_overlap,
      open_guard = if (identical(exec_price, "open_t1")) og else NULL
    ),
    strategy_gross_xts = xts(D$Rg, order.by = D$Date),
    cost_model_version = rep_cost_model_version(exec_price)
  )
}

cat("[replication_harness.R] Loaded (v10 · exec_price 인자화 2026-09-24) — run_replication_simulation(RAWDATA, BM_DT, WEIGHTS, commission, start_date, exec_price)\n")
