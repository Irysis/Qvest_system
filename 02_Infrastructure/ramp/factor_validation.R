## factor_validation.R — RAMP Gate 4 (3차): 순수팩터 후보 실측 검증 + 승인
## 룰 §4 (alpha-research). 각 순수팩터(neutralized_z)를 canonical_screen_bt()로 → top-N EW long-only net 15bps.
## 산출: rank_ic_ir_oos, net_quintile_spread_oos, cost_drag, DSR (metric_type=backtested via canonical_screen).
## approve_factors() = config gate4_pure_factor.approve_rule 충족분만 status=approved + lineage.
##
## ★실측-only: 모든 성능수치 canonical_screen_bt 경유. prod/cumprod 자체합성 금지.

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")
# contract 함수(build_benchmark_compare)를 먼저 명시 source — canonical_screen_bt가
# sys.frame 상대경로로 자동 source 하나 간접 source 시 해석 실패 → 명시 보장.
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

#==============================================================================
# 1. 월별 forward 1M 수익 + 벤치마크 (rawdata에서 PIT-aligned 구성)
#    sig_date(t)의 신호 → t→t+1M 실현수익. 자체합성 아님: 일별 Ret을 월구간 단순누적은
#    피하고, '월말 종가 대비 다음 월말 종가' 변화율(실현 forward return)을 직접 산출.
#==============================================================================
#==============================================================================
# [FQ-181 2026-08-09] 유동성 자(ruler) 이원화 수리
#
# 결함(확정): 구판은 주석에 "20d ADV at t-1" 이라 써 놓고 `adv = Vol0 * Close0`
#   (= 월말 **당일 1일치** 거래대금)를 계산했다. 헌법 정의(CLAUDE.md Production
#   Constraints · .claude/rules/pit.md C10)는 **20일 평균 거래대금 >= 2e8**이다.
#   두 자의 상관 0.929 · 판정 불일치 2.61% · 실선별 top-25 중 3.04%가 20일-자 미달.
#   → 자는 헌법이 이미 정의했으므로 선택 문제가 아니다. 구현을 헌법에 맞춘다.
#
# ★규약 (자 라벨 의무 — 두 자 병존 기간):
#   이 함수의 `liq_dt` 를 소비하는 모든 산출물은 반환값 `liq_ruler`(= liq_dt 의
#   attr "liq_ruler")를 **그대로 기록**해야 한다. 자 라벨 없는 유동성 수치를
#   서로 비교하거나 인용하지 말 것 — 교정 전후 산출물은 서로 다른 자로 잰 값이다.
#
# ★입력 형태가 자를 결정한다 (2026-08-09 census 실측):
#   호출부 149건 중 103건(69%)이 rawdata 를 **월말 거래일만으로 slim** 해서 넘긴다
#   (`rawdata[Date %in% .me]` — asof_close 전체스캔 회피 목적). 월말 행만 있는
#   패널에서는 20일 평균을 **원리적으로 계산할 수 없다**(일간 관측이 입력에 없다).
#   그런 입력에 `frollmean(.,20)` 을 걸면 20 *개월* 평균이 나온다 — 조용히 틀린 값.
#   ⇒ 함수가 입력 관측단위를 **실측**해서 분기하고, 계산 불가일 때는 라벨로 자백한다.
#   ⇒ NA 로 비우지 않는다: canonical_screen_bt 는 `is.na(adv) | adv >= liq_min` 이라
#     NA 가 **통과**한다(= 제약 완화 방향). 결손을 정상값으로 내려앉히지 않는다.
#==============================================================================

#' 20일 평균 거래대금(t-1 기준) — 일간 패널에서만 계산 가능
#'
#' 창 = 신호일 **직전 거래일까지의 20 거래일** (당일 미포함, C10 t-1 PIT).
#' 워밍업(종목의 첫 20 거래일)은 NA 로 비우지 않고 **가용 일수만큼의 확장평균**으로
#' 채운다 — NA 는 하류에서 필터를 통과해버리므로(위 규약) 결손을 완화로 바꾸지 않는다.
#' i >= 20 구간에서는 adaptive 창 폭이 20 으로 고정되어 표준 frollmean(.,20) 과 동일하다.
#' @param daily data.table(Date, Ticker, Vol, Close) 일간 패널
#' @param at_dates 값을 뽑을 날짜(월말 거래일). NULL 이면 전 구간 반환.
#' @param basis_reset [2026-09-07] data.table(Ticker, Date) — **조정기준 단절**로 거래대금
#'        시계열에 계단이 남은 자리. 그 날짜에서 평균 창을 **재시작**한다.
#'        NULL(기본) = 레지스트리(06_Registry/basis_break_registry.json)에서 자동 적재.
#'        빈 data.table 을 넘기면 기준 인지 없이 구판과 동일하게 돈다.
#' @return data.table(Date, Ticker, adv) — attr "liq_basis_aware"(logical),
#'         "liq_basis_resets"(적용된 재시작 지점 수)
#'
#' ─── [2026-09-07] 기준 인지 (구멍 A) ────────────────────────────────────────
#' 거래대금 = Close x Vol 이고 분할은 Close 를 x k · Vol 을 x 1/k 로 움직이므로
#' **거래대금은 원리적으로 기준 불변**이다(실측 확인: 단절 창 TV 비율 q50 0.867 vs
#' 무작위 대조 0.916 — 사실상 동일). 그래서 가격 레벨은 **건드리지 않는다** —
#' 레벨만 재척도하면 그 상쇄가 깨져 거래대금이 배수만큼 틀어진다.
#' 남는 것은 **한쪽 다리만 재척도된** 잔여(전기간 107건)이고, 그 자리에서만 창을
#' 재시작한다. 이는 이 함수가 이미 종목의 첫 20거래일에 쓰는 adaptive 확장창과
#' **같은 기전**이다 — "같은 기준 위의 관측만 평균한다".
#' ★NA 로 비우지 않는 이유는 위 규약 그대로다: NA 는 하류에서 필터를 **통과**한다.
#' ★킬 스위치: QVEST_LIQ_BASIS_AWARE=0 이면 자동 적재를 끄고 구판과 동일하게 돈다.
build_adv20_t1 <- function(daily, at_dates = NULL, basis_reset = NULL) {
  stopifnot(all(c("Date", "Ticker", "Vol", "Close") %in% names(daily)))
  DV <- data.table::as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  data.table::setorder(DV, Ticker, Date)

  # ── 기준 재시작 지점 해석 ──────────────────────────────────────────────────
  #    부재를 조용히 "단절 없음" 으로 읽지 않는다: 적재 여부·건수를 attr 로 자백한다.
  .off <- identical(Sys.getenv("QVEST_LIQ_BASIS_AWARE", "1"), "0")
  if (is.null(basis_reset) && !.off) {
    basis_reset <- tryCatch({
      if (!exists("liq_basis_reset_points", mode = "function")) {
        .p <- c(file.path(gsub("\\\\", "/", Sys.getenv("QM_ROOT", "")),
                          "02_Infrastructure/data/liquidity_basis.R"),
                file.path(gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", "")),
                          "02_Infrastructure/data/liquidity_basis.R"))
        .p <- .p[nzchar(.p) & file.exists(.p)]
        if (length(.p)) source(.p[1])
      }
      if (exists("liq_basis_reset_points", mode = "function"))
        liq_basis_reset_points() else NULL
    }, error = function(e) NULL)
  }
  n_reset <- 0L
  if (!is.null(basis_reset) && NROW(basis_reset)) {
    R <- data.table::as.data.table(basis_reset)
    rk <- paste0(R$Ticker, "|", as.character(as.Date(R$Date)))
    DV[, .rst := paste0(Ticker, "|", as.character(Date)) %chin% rk]
    n_reset <- sum(DV$.rst)
    DV[, .seg := cumsum(.rst), by = Ticker]     # 단절마다 구간 번호가 오른다
  } else {
    DV[, .seg := 0L]
  }

  # adaptive: 창 폭 = min(누적 관측수, 20). 그 다음 shift(1) 로 당일을 창에서 제외한다.
  # ★by 에 .seg 가 들어가면 단절에서 창이 재시작한다 — 신규 상장과 같은 취급.
  DV[, adv := data.table::shift(
        data.table::frollmean(dval, n = pmin(seq_len(.N), 20L),
                              adaptive = TRUE, na.rm = TRUE), 1L), by = .(Ticker, .seg)]
  # ★단절 **당일**은 새 구간의 첫 행이라 shift(1) 이 NA 를 낸다. NA 는 하류에서
  #   필터를 통과하므로(완화) 그대로 두면 안 된다 — 직전 구간의 마지막 값도 쓸 수 없다
  #   (다른 기준이다). 그 하루는 **당일 거래대금**으로 채운다: 같은 기준 위의
  #   유일한 관측이고, C10(당일 거래량 미사용)은 shift 로 이미 지켜진 뒤 새 기준의
  #   첫 관측만 남은 경계 사례다. 완화가 아니라 가장 보수적인 가용값이다.
  if (n_reset > 0L) DV[.rst == TRUE & is.na(adv), adv := dval]

  res <- if (is.null(at_dates)) DV[, .(Date, Ticker, adv)]
         else DV[Date %in% as.Date(at_dates), .(Date, Ticker, adv)]
  data.table::setattr(res, "liq_basis_aware", n_reset > 0L)
  data.table::setattr(res, "liq_basis_resets", n_reset)
  res[]
}

#==============================================================================
# [FQ-232 2026-08-10] 월말-slim 입력에서도 헌법 자(20일 평균) 복원 — 주입 경로
#
# FQ-181 은 "일간 입력이면 헌법 자, slim 이면 DEGRADED + 자백"까지 갔다. 남은 것은
#   slim 경로 자체의 복원이다. slim 관용구의 원인은 `asof_close()` 의 전체스캔이지
#   유동성이 아니다 — 즉 **호출부는 slim 직전까지 일간 패널을 손에 들고 있다**
#   (실측: `RAW <- read_parquet(...); RAWME <- RAW[Date %in% ME]; rm(RAW)`).
#   ⇒ 자를 복원하는 데 새 I/O 가 필요 없다. 20일 평균을 **slim 하기 전에** 계산해
#     넘기면 된다(실측 비용: 일간 14,059,013행에서 build_adv20_t1 3.2초).
#
# ★기본 동작 무변경: `liq_daily = NULL`(기본)이면 FQ-181 판본과 **동일 분기·동일 값**.
#   자를 바꾸는 것은 호출부의 명시적 선택이며, 그래야 과거 판정과의 비교가 깨지지 않는다.
#
# ★사용법 (호출부 2줄 추가, 추가 I/O 0):
#     ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
#     RAWME <- RAW[Date %in% ME]; rm(RAW)
#     fwd   <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
#
# ★자 라벨은 이제 소비 지점에서도 읽힌다: `canonical_screen_bt()` 가
#   attr(liq_dt,'liq_ruler') 를 읽어 반환값 `liq_ruler` 로 기록하고 DEGRADED 면 경고한다.
#   (FQ-181 은 라벨을 *발행*만 했고 읽는 소비자가 0 이었다 — "자가 신고는 하는데
#    아무도 안 읽는" 상태. 발행과 소비는 별개의 배선이다.)
#==============================================================================

#' liq_daily 인자 해석 — 무엇을 받았고 그것이 어떤 자인가를 **정체 검사**로 판정
#'
#' 존재 검사(NULL 아님)로 정체 검사를 대체하지 않는다: 컬럼 구성을 실측해 분기하고,
#' 어느 갈래에도 해당하지 않으면 **조용히 통과시키지 않고 stop** 한다.
#' @param liq_daily NULL | data.frame(Date,Ticker,Vol,Close) | data.frame(Date,Ticker,adv) | 경로
#' @param at_dates 월말 거래일 벡터
#' @return NULL 또는 list(tbl = data.table(Date,Ticker,adv), source = <chr>)
.resolve_liq_daily <- function(liq_daily, at_dates) {
  if (is.null(liq_daily)) return(NULL)
  src <- NA_character_
  if (is.character(liq_daily) && length(liq_daily) == 1L) {
    p <- liq_daily
    if (!file.exists(p)) stop("build_monthly_forward_returns: liq_daily 경로 부재 — ", p)
    ext <- tolower(tools::file_ext(p))
    D <- if (ext == "parquet") {
      if (!requireNamespace("arrow", quietly = TRUE))
        stop("build_monthly_forward_returns: liq_daily parquet 인데 arrow 미설치")
      as.data.table(arrow::read_parquet(p, col_select = c("Date", "Ticker", "Vol", "Close")))
    } else if (ext == "rds") as.data.table(readRDS(p))
    else stop("build_monthly_forward_returns: liq_daily 확장자 미지원 — ", ext)
    liq_daily <- D; src <- "injected_path"
  }
  if (!is.data.frame(liq_daily))
    stop("build_monthly_forward_returns: liq_daily 형식 미지원 — ", class(liq_daily)[1])
  D <- as.data.table(liq_daily)
  nm <- names(D)
  if (all(c("Date", "Ticker", "Vol", "Close") %in% nm)) {
    tbl <- build_adv20_t1(D[, .(Date, Ticker, Vol, Close)], at_dates = at_dates)
    if (is.na(src)) src <- "injected_daily"
  } else if (all(c("Date", "Ticker", "adv") %in% nm)) {
    tbl <- as.data.table(D)[, .(Date = as.Date(Date), Ticker, adv)]
    tbl <- tbl[Date %in% as.Date(at_dates)]
    src <- "injected_adv20"
  } else {
    stop("build_monthly_forward_returns: liq_daily 컬럼이 (Date,Ticker,Vol,Close) 도 ",
         "(Date,Ticker,adv) 도 아님 — 실제 [", paste(nm, collapse = ", "), "]")
  }
  if (!nrow(tbl))
    stop("build_monthly_forward_returns: liq_daily 해석 결과 0행 — ",
         "at_dates 와 패널 날짜가 어긋났을 개연(월말 거래일 불일치).")
  data.table::setkeyv(tbl, c("Date", "Ticker"))
  list(tbl = tbl, source = src)
}

#' @param liq_daily [FQ-232] 유동성 자 복원용 입력. NULL(기본) = 동작 무변경.
#'        허용 형태 3종: ①일간 data.table(Date,Ticker,Vol,Close) ②사전계산
#'        data.table(Date,Ticker,adv) — build_adv20_t1() 산출 ③parquet/rds 경로.
#' @param liq_strict [FQ-232] TRUE 면 자가 DEGRADED 로 떨어질 때 경고가 아니라 stop.
#'        NULL(기본) 이면 환경변수 QVEST_LIQ_RULER_STRICT(1/true) 를 따르고, 없으면 FALSE.
#' @return list(returns_dt(Date=sig월말, Ticker, Ret_1m=forward), bench_dt(Date, BM_Ret),
#'              liq_dt(Date, Ticker, adv), ret_firewall_dropped, liq_ruler, liq_ruler_source)
build_monthly_forward_returns <- function(rawdata, sig_dates, liq_daily = NULL,
                                          liq_strict = NULL) {
  # 각 종목 월말 종가 → 다음 월말 종가 forward return
  sig_dates <- sort(as.Date(sig_dates))
  out <- list(); bench <- list(); liq <- list()
  n_ret_firewall <- 0L   # [R44] monthly Ret_1m sanity 격리 카운트
  # 월말 거래일 매핑
  asof_close <- function(d) {
    sub <- rawdata[Date <= d]
    if (nrow(sub) == 0) return(NULL)
    md <- max(sub$Date)
    rawdata[Date == md]
  }

  # ── [FQ-181] 입력 관측단위 실측 → 유동성 자 결정 ───────────────────────────
  #   판정 지표: 캘린더월당 고유 거래일 수의 중앙값. 일간 패널 ~21, 월말-slim = 1.
  .udates <- sort(unique(as.Date(rawdata$Date)))
  .dpm_med <- if (length(.udates)) {
    stats::median(as.integer(table(format(.udates, "%Y-%m"))))
  } else 0
  .has_px <- all(c("Vol", "Close") %in% names(rawdata))
  .daily_ok <- (.dpm_med >= 15) && .has_px
  # 월말 앵커(= 각 sig_date 이하 최종 거래일). 주입/자체계산 양 경로가 같은 앵커를 쓴다.
  .md <- unique(vapply(sig_dates, function(d) {
    v <- .udates[.udates <= d]
    if (length(v)) as.character(max(v)) else NA_character_
  }, character(1)))
  .md <- as.Date(.md[!is.na(.md)])
  adv_tbl <- NULL; liq_ruler_source <- NA_character_
  # ── [FQ-232] ①주입 경로 우선(명시가 암시를 이긴다) ─────────────────────────
  .inj <- .resolve_liq_daily(liq_daily, .md)
  if (!is.null(.inj)) {
    adv_tbl <- .inj$tbl
    liq_ruler <- if (isTRUE(attr(adv_tbl, "liq_basis_aware", exact = TRUE)))
                   "adv20_t1_basis_aware" else "adv20_t1"   # [2026-09-07 구멍 A]
    liq_ruler_source <- .inj$source
    # 주입 패널이 실제로 이 측정창을 덮는가 — 존재 검사가 아니라 **덮개 실측**.
    .cov <- mean(as.character(.md) %in% as.character(unique(adv_tbl$Date)))
    if (.cov < 1) {
      warning(sprintf(paste0(
        "build_monthly_forward_returns: liq_daily 가 월말 앵커의 %.1f%%만 덮음(%d/%d) — ",
        "미덮인 달은 adv 결측이 되고 canonical_screen_bt 의 is.na(adv) 규칙상 **통과**한다 ",
        "(결손이 완화로 내려앉음). vintage 불일치 의심."),
        100 * .cov, sum(as.character(.md) %in% as.character(unique(adv_tbl$Date))), length(.md)),
        call. = FALSE)
    }
    cat(sprintf(paste0("[build_monthly_forward_returns] [FQ-232] 유동성 자 복원: ",
      "liq_ruler='adv20_t1' (source=%s) · 앵커 덮개 %.1f%% (%d행)\n"),
      liq_ruler_source, 100 * .cov, nrow(adv_tbl)))
  } else if (.daily_ok) {
    # ── ②입력이 일간이면 자체 계산(FQ-181 경로, 불변) ────────────────────────
    liq_ruler <- "adv20_t1"          # 헌법 정의 — 20일 평균 거래대금, 당일 미포함
    liq_ruler_source <- "input_daily"
    adv_tbl <- build_adv20_t1(rawdata[Date <= max(sig_dates), .(Date, Ticker, Vol, Close)],
                              at_dates = .md)
    # ★[2026-09-07 구멍 A] 기준 인지가 실제로 물렸으면 **자 이름이 달라진다**.
    #   이 파일의 규약이 "자 라벨 없는 유동성 수치를 서로 비교하지 말 것" 이므로,
    #   창을 재시작한 판과 안 한 판은 같은 이름을 쓰면 안 된다.
    if (isTRUE(attr(adv_tbl, "liq_basis_aware", exact = TRUE)))
      liq_ruler <- "adv20_t1_basis_aware"
    data.table::setkeyv(adv_tbl, c("Date", "Ticker"))
  } else {
    # ── ③계산 불가 — 자백 경로(FQ-181). 조용히 쓰지 않는다 ───────────────────
    liq_ruler <- "adv1_sameday_DEGRADED"   # 20일 자 계산 불가 — 구판과 동일한 1일치
    liq_ruler_source <- "degraded_slim"
    .strict <- if (is.null(liq_strict)) {
      isTRUE(tolower(Sys.getenv("QVEST_LIQ_RULER_STRICT", "")) %in% c("1", "true", "yes"))
    } else isTRUE(liq_strict)
    .msg <- sprintf(paste0(
      "[build_monthly_forward_returns] ★유동성 자 저하(FQ-181/232): 입력 패널의 캘린더월당 ",
      "거래일 중앙값 = %.0f (일간 아님%s).\n",
      "  20일 평균 거래대금을 입력에서 계산할 수 없어 **월말 1일치 Vol*Close** 로 대체합니다.\n",
      "  → liq_ruler='adv1_sameday_DEGRADED'. 헌법 자(20일 평균)로 재려면 ",
      "liq_daily= 인자로 일간 패널 또는 build_adv20_t1() 산출을 넘기십시오(FQ-232).\n"),
      .dpm_med, if (!.has_px) ", Vol/Close 결측" else "")
    if (.strict) stop(.msg, "  [QVEST_LIQ_RULER_STRICT 활성 — 경고가 아니라 중단]")
    cat(.msg)
    warning("build_monthly_forward_returns: liq_ruler='adv1_sameday_DEGRADED' ",
            "— 월말-slim 입력이라 20일 평균 거래대금 계산 불가. liq_daily= 로 복원 가능 ",
            "(FQ-181/FQ-232)", call. = FALSE)
  }
  for (i in seq_len(length(sig_dates) - 1L)) {
    d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
    c0 <- asof_close(d0); c1 <- asof_close(d1)
    if (is.null(c0) || is.null(c1)) next
    m <- merge(c0[, .(Ticker, Close0 = Close, K200, KQ150, Vol0 = Vol, Size0 = Size)],
               c1[, .(Ticker, Close1 = Close)], by = "Ticker")
    m <- m[(K200 == TRUE | KQ150 == TRUE) & !is.na(Close0) & Close0 > 0 & !is.na(Close1)]
    m[, Ret_1m := Close1 / Close0 - 1]
    # [R44 2026-07-15, WT-D20260715_013] monthly Ret_1m sanity — 물리불가 격리(월 >+500% /
    #   <-100%). clean 유니버스 월 |fwd| 최대 ~2.47(R43 census) ≪ 5.0 → 미발화·parity 보장.
    .bad <- is.finite(m$Ret_1m) & (m$Ret_1m > 5.0 | m$Ret_1m < -1.0)
    if (any(.bad)) { n_ret_firewall <- n_ret_firewall + sum(.bad); m <- m[!.bad] }
    out[[length(out) + 1L]] <- m[, .(Date = d0, Ticker, Ret_1m)]
    # [FQ-181] liquidity = 20일 평균 거래대금(t-1). 계산 불가 입력이면 1일치로 저하 + 라벨.
    if (!is.null(adv_tbl)) {
      md0 <- c0$Date[1L]
      .a <- adv_tbl[.(md0, m$Ticker), .(adv), on = c("Date", "Ticker")]$adv
      liq[[length(liq) + 1L]] <- data.table(Date = d0, Ticker = m$Ticker, adv = .a)
    } else {
      liq[[length(liq) + 1L]] <- m[, .(Date = d0, Ticker, adv = Vol0 * Close0)]
    }
    # benchmark forward return = 유니버스 시총(Size)가중 forward return (실측 cross-section,
    #   compounding 없는 단일구간 가중평균 — KOSPI200∪KQ150 cap-weighted market proxy).
    bm_w <- if (sum(!is.na(m$Size0) & m$Size0 > 0) > 0)
      stats::weighted.mean(m$Ret_1m, w = ifelse(is.na(m$Size0), 0, m$Size0), na.rm = TRUE)
    else mean(m$Ret_1m, na.rm = TRUE)
    bench[[length(bench) + 1L]] <- data.table(Date = d0, BM_Ret = bm_w)
  }
  if (n_ret_firewall > 0)
    cat(sprintf("[build_monthly_forward_returns] Ret_1m sanity 방화벽: %d 물리불가 월수익 격리(>+500%%/<-100%%).\n", n_ret_firewall))
  liq_out <- if (length(liq)) rbindlist(liq) else data.table()
  # [FQ-181] 자 라벨을 데이터에 붙여 보낸다 — 소비자가 list 를 풀어 liq_dt 만 넘겨도
  #   라벨이 따라가도록. (반환 list 의 liq_ruler 와 동일 값, 이중 경로)
  data.table::setattr(liq_out, "liq_ruler", liq_ruler)
  data.table::setattr(liq_out, "liq_ruler_source", liq_ruler_source)  # [FQ-232] 출처도 동행
  list(
    returns_dt = if (length(out)) rbindlist(out) else data.table(),
    bench_dt = if (length(bench)) rbindlist(bench) else data.table(),
    liq_dt = liq_out,
    ret_firewall_dropped = n_ret_firewall,  # [R44] 격리 카운트(진단)
    liq_ruler = liq_ruler,                  # [FQ-181] 자 라벨(기록 의무 — 상단 규약)
    liq_ruler_source = liq_ruler_source     # [FQ-232] input_daily/injected_*/degraded_slim
  )
}

#==============================================================================
# 2. 단일 순수팩터 검증 (canonical_screen_bt 경유)
#==============================================================================
#' @param scores_dt data.table(signal_date, security_id, factor_id, neutralized_z) for ONE factor
#' @param fwd list from build_monthly_forward_returns
#' @return list(factor_id, n_months, rank_ic_mean, rank_ic_ir, net_quintile_spread, cost_drag,
#'              net_sr, portfolio_alpha_t, dsr, metric_type)
validate_factor <- function(scores_dt, fwd, top_n = 20L, cost_bps = 15) {
  fid <- scores_dt$factor_id[1]
  # canonical_screen 입력: Date, Ticker, score (= neutralized_z, higher=better)
  sc <- scores_dt[, .(Date = as.Date(signal_date), Ticker = security_id, score = neutralized_z)]
  sc <- sc[!is.na(score)]
  ret <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
  bench <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
  liq <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]

  cs <- tryCatch(
    canonical_screen_bt(sc, ret, bench, top_n = top_n, cost_bps_oneway = cost_bps,
                        liq_dt = liq, liq_min = 2e8,
                        run_id = paste0("ramp_pf_", fid), strategy_id = paste0("PF_", fid)),
    error = function(e) list(metric_type = "error", note = conditionMessage(e)))

  # rank IC (cross-sectional spearman of score vs forward return), per month
  ic_dt <- merge(sc, ret, by = c("Date", "Ticker"))
  ic_by_m <- ic_dt[, {
    if (.N >= 10 && stats::sd(score) > 0 && stats::sd(Ret_1m) > 0)
      .(ic = stats::cor(score, Ret_1m, method = "spearman"))
    else .(ic = NA_real_)
  }, by = Date]
  rank_ic_mean <- mean(ic_by_m$ic, na.rm = TRUE)
  rank_ic_sd <- stats::sd(ic_by_m$ic, na.rm = TRUE)
  n_ic <- sum(!is.na(ic_by_m$ic))
  rank_ic_ir <- if (!is.na(rank_ic_sd) && rank_ic_sd > 0) rank_ic_mean / rank_ic_sd else NA_real_

  # net quintile spread (top quintile - bottom quintile, net) — canonical_screen은 top-N만이므로
  #   별도 quintile long-short(검증 진단; long-only 운용 아님, 신호력 측정용)
  qspread <- ic_dt[, {
    if (.N >= 10 && stats::sd(score) > 0) {
      q <- cut(frank(score), breaks = 5, labels = FALSE)
      top <- mean(Ret_1m[q == 5], na.rm = TRUE); bot <- mean(Ret_1m[q == 1], na.rm = TRUE)
      .(spread = top - bot)
    } else .(spread = NA_real_)
  }, by = Date]
  net_quintile_spread <- mean(qspread$spread, na.rm = TRUE) - (cost_bps / 1e4)  # net 근사(1 leg cost)

  # cost drag = turnover_annual * cost (이미 canonical_screen net 반영; drag = gross_sr - net 영향 proxy)
  cost_drag <- if (!is.null(cs$turnover_annual) && !is.na(cs$turnover_annual))
    cs$turnover_annual * (cost_bps / 1e4) else NA_real_

  # DSR (deflated sharpe) — 단일팩터 검증, n_trials는 호출자 집계. 여기선 SR 기록만.
  net_sr <- cs$net_sr %||% NA_real_

  list(
    factor_id = fid,
    metric_type = if (identical(cs$metric_type, "canonical_screen")) "backtested" else (cs$metric_type %||% "error"),
    n_months = cs$n_months %||% 0L,
    n_ic_months = n_ic,
    rank_ic_mean = rank_ic_mean,
    rank_ic_ir = rank_ic_ir,
    net_quintile_spread_oos = net_quintile_spread,
    cost_drag = cost_drag,
    net_sr = net_sr,
    portfolio_alpha_t_nw = cs$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    information_ratio = cs$information_ratio %||% NA_real_,
    turnover_annual = cs$turnover_annual %||% NA_real_,
    note = cs$note %||% NA_character_
  )
}

#==============================================================================
# 3. 승인 정책 (config gate4_pure_factor.approve_rule)
#==============================================================================
#' @param metrics_dt data.table from validate_factor rows
#' @param econ_labels named (factor_id -> economic_rationale present TRUE/FALSE)
#' @return data.table(factor_id, ..., status[approved/rejected], reject_reason, lineage)
approve_factors <- function(metrics_dt, config, econ_present = NULL) {
  ar <- config$gate4_pure_factor$approve_rule
  m <- copy(metrics_dt)
  m[, econ_ok := if (is.null(econ_present)) TRUE else (factor_id %in% names(econ_present)[unlist(econ_present)])]
  m[, rule_ic := !is.na(rank_ic_ir) & rank_ic_ir >= (ar$rank_ic_ir_oos_min %||% 0)]
  m[, rule_spread := !is.na(net_quintile_spread_oos) & net_quintile_spread_oos >= (ar$net_quintile_spread_oos_min %||% 0)]
  m[, rule_cost := is.na(cost_drag) | cost_drag <= (ar$cost_drag_max %||% 0.05)]
  m[, rule_metric := metric_type == "backtested"]
  m[, status := fifelse(econ_ok & rule_ic & rule_spread & rule_cost & rule_metric, "approved", "rejected")]
  m[, reject_reason := fifelse(status == "approved", NA_character_,
      paste0(
        fifelse(!econ_ok, "no_econ_rationale;", ""),
        fifelse(!rule_ic, "rank_ic_ir<min;", ""),
        fifelse(!rule_spread, "spread<min;", ""),
        fifelse(!rule_cost, "cost_drag>max;", ""),
        fifelse(!rule_metric, "metric_type!=backtested;", "")))]
  m[, lineage := paste0("source_signal=factor_db:", factor_id,
                        "; neutralizers=sector+log_mktcap+beta+vol+liquidity(FWL)")]
  m[]
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[factor_validation.R] Loaded — build_monthly_forward_returns / build_adv20_t1 / validate_factor / approve_factors\n")
