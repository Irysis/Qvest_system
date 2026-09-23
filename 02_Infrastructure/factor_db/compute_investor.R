#==============================================================================
# Factor DB — Investor Flow Factors (INV01~INV13)
#
# compute_investor(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class or character "YYYY-MM-DD")
#   FUND:       not used (signature kept for consistency)
#   CONSENSUS:  not used (signature kept for consistency)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# Data source: .fdb_env$INVESTOR  (investor_wide.parquet, preloaded by builder)
#              Fallback: .cache/investor_stock/investor_wide.parquet
#   Columns: Date, Ticker, Foreign, Individual, Institutional, OtherCorp
#   Unit:    daily net buy amount (KRW), positive = net buy, negative = net sell
#
# PIT: Date < sig_date (strict t-1 lag, C2 compliant)
#      Size normalization also uses t-1 most recent value
#
# Factors:
#   INV01  Foreign_NetBuy_20d             frollsum(Foreign,20) / Size
#   INV02  Foreign_NetBuy_60d             frollsum(Foreign,60) / Size
#   INV03  Inst_NetBuy_20d                frollsum(Institutional,20) / Size
#   INV04  Inst_NetBuy_60d                frollsum(Institutional,60) / Size
#   INV05  Foreign_Momentum               roll_F20 / roll_F60 - 1  (acceleration)
#   INV06  Inst_Momentum                  roll_I20 / roll_I60 - 1
#   INV07  Retail_Contrarian              -1 * frollsum(Individual,20) / Size
#   INV08  Foreign_Inst_Agreement         sign(F20)*sign(I20)*min(|F20|,|I20|) / Size
#   INV09  Flow_Persistence               fraction of last 20 days with F+I > 0
#   INV10  Smart_Money_Flow               rollsum(F+I,20) / rollsum(|F|+|I|+|Ind|,20)
#   INV11  Foreign_Concentration          1 if Foreign_20d >= 90th pct (cross-sectional)
#   INV12  Supply_Demand_Imbalance        rollmean((F+I-Ind)/(|F|+|I|+|Ind|), 20)
#   INV13  Foreign_Resid_Individual_{n}d  residual_t(i) = z_F_t(i) - beta_t * z_I_t(i)
#          beta_t = expanding-window no-intercept OLS (burn-in 60 months, C1 strict lag)
#          ★2026-09-24: beta 누산기는 매 호출 sig 월 이전 월말들로부터 자체 계산한다
#            (.inv13_beta_asof — 세션 메모리 누산기 폐기. 아래 INV13 블록 설명 참조)
#          Variants: 21d / 63d / 126d lookback window for rolling z-score computation
#          Reference: Choe-Kho-Stulz (2005 RFS), Fama-MacBeth (1973) orthogonalization
#
# References:
#   Gompers & Metrick (2001) "Institutional Investors and Equity Prices"
#   Yan & Zhang (2009) "Institutional Trade Persistence and Long-Term Equity Returns"
#   Barber & Odean (2000) "Trading Is Hazardous to Your Wealth"
#   Choe, Kho & Stulz (2005) "Do Domestic Investors Have an Edge?" RFS
#   Fama & MacBeth (1973) "Risk, Return, and Equilibrium" JPE
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

#------------------------------------------------------------------------------
# INV13 expanding beta — 누산기 자체 계산 (2026-09-24 DATA-INV13-ACC · 도훈 결정 "수리+재빌드+가드 보강")
#
# 구판 결함: beta 누산기를 .fdb_env$INV13_BETA_ACC(세션 메모리)에서 읽고 없으면 0 에서
#   시작했다. 일일 증분 빌드는 세션당 1~2개월만 빌드하므로 누산 월수가 60 에 못 닿아
#   INV13 3종이 202608~ 영구 결손(tryCatch 가 삼켜 무경보). 반대로 60 을 넘긴 세션에서
#   과거 달을 다시 빌드하면 **미래 달 증분이 beta 에 섞였다**(잠재 C1). 값이 세션 순서에
#   의존했다.
#
# 규약 (구판 저장값에서 재도출 — 202606 저장 INV13 을 R²=1.0000·잔차 sd≈2e-15 로 재현):
#   · 월말 ME_j = 빌더 거래일 달력(.fdb_env$trading_dates = RAWDATA 날짜 — build_factor_db_monthly
#     가 sig 를 고르는 바로 그 달력)의 달별 마지막 거래일.
#   · 월 j 증분 = Date < ME_j 인 종목별 마지막 행의 21일 순매수 합(외국인 F·개인 I) → 횡단면 z →
#     dSxY = Σ z_F·z_I , dSxx = Σ z_I²  (유효 종목 ≥ 20 일 때만 1개월로 센다 — 구판 값 그대로).
#   · sig 가 속한 달을 k 라 하면 beta_k = Σ_{j<k} dSxY / Σ_{j<k} dSxx (증분 월수 ≥ 60 일 때만 —
#     구판 burn-in 그대로). = 구판 shift(1) 한 달 lag: sig 월 자신의 증분은 들어가지 않는다.
#   ★달력은 투자자 패널 날짜가 아니라 빌더 달력이어야 한다 — 202412 월말이 RAWDATA 12-27 /
#     투자자 12-30 으로 갈려, 투자자 달력은 beta 가 4e-4 어긋난다(2026-09-24 실측). 달력을 못
#     구하면 대체하지 않고 INV13 을 내지 않는다(경고).
# PIT(C1): 입력을 sig 월 첫날 m0 이전으로 잘라(as-of) 계산한다 → 모든 증분 데이터 < ME_j < m0 ≤ sig.
# 캐시(.fdb_env$INV13_BETA_CACHE): 키 = sig 월 · as-of 패널 지문 · 달력 지문. 같은 키면 입력이
#   같으므로 값이 같다(순수 메모이제이션 — 세션 순서 무관). 적중해도 '포함 증분이 전부 sig 월
#   이전'을 다시 단정하고, 어긋나면 버리고 재계산한다.
# 상설 검사: 08_Tests/factor_db/test_inv13_beta_asof.R
#------------------------------------------------------------------------------
.inv13_zs <- function(x) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  (x - m) / s
}

# 빌더 거래일 달력. 빌더 밖 단독 실행이면 RAWDATA.parquet 의 Date 열(같은 달력)로 대체.
.inv13_trading_dates <- function() {
  if (exists(".fdb_env", envir = .GlobalEnv)) {
    fe <- get(".fdb_env", envir = .GlobalEnv)
    if (exists("trading_dates", envir = fe, inherits = FALSE) && length(fe$trading_dates) > 0L)
      return(sort(unique(as.Date(fe$trading_dates))))
  }
  p <- if (exists("RAWDATA_CACHE")) RAWDATA_CACHE
       else if (exists("CACHE_DIR")) file.path(CACHE_DIR, "RAWDATA.parquet")
       else file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                      ".cache", "RAWDATA.parquet")
  if (!file.exists(p)) return(NULL)
  sort(unique(as.Date(arrow::read_parquet(p, col_select = "Date", mmap = FALSE)$Date)))
}

# as-of 단정 — 포함된 증분의 월말이 전부 sig 월 첫날 이전인가 (sig 보다 앞선가)
.inv13_asof_ok <- function(e, m0, sig_d) {
  if (is.null(e) || !identical(as.Date(e$cut), as.Date(m0))) return(FALSE)
  if (is.na(e$last_me)) return(e$n_months == 0L)
  e$last_me < m0 && e$last_me < sig_d && e$ym_max < format(sig_d, "%Y%m")
}

# 캐시 키 — sig 월 · as-of 패널(x) 지문 · 달력(me) 지문
.inv13_cache_key <- function(ym_k, x, me) {
  paste(ym_k, nrow(x), uniqueN(x$Ticker),
        sprintf("%.17g", sum(as.numeric(x$Date))),
        sprintf("%.17g", sum(x$Foreign, na.rm = TRUE)),
        sprintf("%.17g", sum(x$Individual, na.rm = TRUE)),
        sum(is.na(x$Foreign)), sum(is.na(x$Individual)),
        nrow(me), sprintf("%.17g", sum(as.numeric(me$me))), sep = "|")
}

#' @param inv  data.table(Ticker, Date, Foreign, Individual, ...) — 호출자가 이미 Date < sig 로 자른 패널
#' @return list(beta, n_months, SxY, Sxx, last_me, ym_max, cut, sig_ym, cached)
.inv13_beta_asof <- function(inv, sig_d, trading_dates = .inv13_trading_dates(),
                             use_cache = TRUE) {
  sig_d <- as.Date(sig_d)
  m0    <- as.Date(format(sig_d, "%Y-%m-01"))   # as-of 컷: sig 월 첫날. 이 날 이후는 보지 않는다
  ym_k  <- format(sig_d, "%Y%m")
  if (is.null(trading_dates) || length(trading_dates) == 0L)
    stop("INV13 월말 달력 미해결(.fdb_env$trading_dates·RAWDATA.parquet 부재) — 투자자 패널 달력으로 대체하지 않는다")
  cal <- as.Date(trading_dates)
  cal <- cal[!is.na(cal) & cal < m0]
  me  <- data.table(Date = cal)[, .(me = max(Date)), by = .(ym = format(Date, "%Y%m"))][order(ym)]
  x   <- inv[Date < m0, .(Ticker, Date, Foreign, Individual)]
  out <- list(beta = NA_real_, n_months = 0L, SxY = 0, Sxx = 0, last_me = as.Date(NA),
              ym_max = NA_character_, cut = m0, sig_ym = ym_k, cached = FALSE)
  if (nrow(me) == 0L || nrow(x) == 0L) return(out)
  setorder(x, Ticker, Date)                     # 지문(부동소수 합)이 입력 행 순서에 흔들리지 않게 먼저 정렬

  fe <- if (isTRUE(use_cache) && exists(".fdb_env", envir = .GlobalEnv))
          get(".fdb_env", envir = .GlobalEnv) else NULL
  key <- .inv13_cache_key(ym_k, x, me)
  if (!is.null(fe) && exists("INV13_BETA_CACHE", envir = fe, inherits = FALSE)) {
    hit <- fe$INV13_BETA_CACHE[[key]]
    if (!is.null(hit)) {
      if (.inv13_asof_ok(hit, m0, sig_d)) { hit$cached <- TRUE; return(hit) }
      warning(sprintf("[compute_investor] INV13 캐시 as-of 단정 위반(sig=%s · 캐시 last_me=%s) — 폐기 후 재계산",
                      sig_d, format(hit$last_me)), call. = FALSE)
    }
  }

  x[, `:=`(rf = frollsum(Foreign,    n = 21L, na.rm = TRUE, align = "right"),
           ri = frollsum(Individual, n = 21L, na.rm = TRUE, align = "right")), by = Ticker]
  x <- x[, .(Ticker, Date, rf, ri)]
  setkey(x, Ticker, Date)
  g <- CJ(Ticker = unique(x$Ticker), k = seq_len(nrow(me)))
  g[, Date := me$me[k] - 1L]                    # Date <= ME_j - 1  ⇔  Date < ME_j
  j <- x[g, on = .(Ticker, Date), roll = Inf, nomatch = 0L]
  j <- j[!is.na(rf) & !is.na(ri)]
  inc <- j[, if (.N < 20L) list(dSxY = NA_real_, dSxx = NA_real_) else {
               zF <- .inv13_zs(rf); zI <- .inv13_zs(ri); ok <- !is.na(zF) & !is.na(zI)
               list(dSxY = sum(zF[ok] * zI[ok]), dSxx = sum(zI[ok]^2))
             }, by = k][order(k)]
  inc <- inc[!is.na(dSxY)]
  if (nrow(inc) > 0L) {
    out$n_months <- nrow(inc)
    out$SxY      <- sum(inc$dSxY)
    out$Sxx      <- sum(inc$dSxx)
    out$last_me  <- max(me$me[inc$k])
    out$ym_max   <- max(me$ym[inc$k])
  }
  if (!.inv13_asof_ok(out, m0, sig_d))
    stop(sprintf("INV13 as-of 단정 위반 — 증분 월말 %s 가 sig 월(%s) 이전이 아니다", format(out$last_me), ym_k))
  out$beta <- if (out$n_months >= 60L && out$Sxx > 1e-10) out$SxY / out$Sxx else NA_real_
  if (!is.null(fe)) {
    if (!exists("INV13_BETA_CACHE", envir = fe, inherits = FALSE)) assign("INV13_BETA_CACHE", list(), envir = fe)
    cc <- get("INV13_BETA_CACHE", envir = fe); cc[[key]] <- out
    assign("INV13_BETA_CACHE", cc, envir = fe)
  }
  out
}

compute_investor <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)

  # ── 빈 결과 템플릿 ────────────────────────────────────────────────────────
  empty_result <- function() {
    data.table(
      Ticker      = character(),
      Factor_Name = character(),
      Raw_Value   = numeric()
    )
  }

  # ── Investor 데이터 로드 ───────────────────────────────────────────────────
  # 우선순위 1: builder가 사전 로드한 .fdb_env$INVESTOR
  # 우선순위 2: parquet 직접 로드 (standalone 실행 시 fallback)
  inv <- NULL

  if (exists(".fdb_env", envir = .GlobalEnv) &&
      exists("INVESTOR", envir = get(".fdb_env", envir = .GlobalEnv)) &&
      !is.null(get(".fdb_env", envir = .GlobalEnv)$INVESTOR)) {

    inv <- copy(get(".fdb_env", envir = .GlobalEnv)$INVESTOR)

  } else {
    # Fallback: config.R에서 CACHE_DIR을 참조하거나 경로 직접 구성
    inv_path <- if (exists("CACHE_DIR")) {
      file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet")
    } else {
      file.path(
        Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
        ".cache", "investor_stock", "investor_wide.parquet"
      )
    }
    if (!file.exists(inv_path)) {
      warning("[compute_investor] investor_wide.parquet not found: ", inv_path)
      return(empty_result())
    }
    suppressPackageStartupMessages(library(arrow))
    inv <- as.data.table(arrow::read_parquet(inv_path))
  }

  if (is.null(inv) || nrow(inv) == 0L) {
    warning("[compute_investor] INVESTOR data is empty.")
    return(empty_result())
  }

  # ── PIT 필터: t-1 lag (C2 준수) ───────────────────────────────────────────
  # sig_date 당일 거래주체 데이터는 사용 불가 → strict less-than
  inv[, Date := as.Date(Date)]
  inv <- inv[Date < sig_d]

  if (nrow(inv) == 0L) {
    warning("[compute_investor] No investor data before ", sig_d)
    return(empty_result())
  }

  setorder(inv, Ticker, Date)

  # ── Size 정규화: t-1 기준 각 Ticker 최신값 ────────────────────────────────
  raw <- if (is.data.table(RAWDATA)) RAWDATA else as.data.table(RAWDATA)
  raw[, Date := as.Date(Date)]
  size_dt <- raw[Date < sig_d & !is.na(Size) & Size > 0,
                 .SD[.N],
                 by = Ticker,
                 .SDcols = "Size"]
  size_dt <- size_dt[, .(Ticker, Size)]

  # ── 최소 관측 요건 ────────────────────────────────────────────────────────
  MIN_OBS_20 <- 15L   # 20일 윈도우: 최소 15일 실데이터
  MIN_OBS_60 <- 45L   # 60일 윈도우: 최소 45일 실데이터

  # ── 롤링 집계 (by=Ticker, frollsum = data.table C 구현) ─────────────────
  # NA 포함 처리를 위해 na.rm=TRUE + align="right"
  inv[, `:=`(
    roll_F20  = frollsum(Foreign,       n = 20L, na.rm = TRUE, align = "right"),
    roll_F60  = frollsum(Foreign,       n = 60L, na.rm = TRUE, align = "right"),
    roll_I20  = frollsum(Institutional, n = 20L, na.rm = TRUE, align = "right"),
    roll_I60  = frollsum(Institutional, n = 60L, na.rm = TRUE, align = "right"),
    roll_Ind20 = frollsum(Individual,   n = 20L, na.rm = TRUE, align = "right")
  ), by = Ticker]

  # INV10 / INV12용 추가 롤링 항목
  inv[, smart_num  := Foreign + Institutional]
  inv[, smart_den  := abs(Foreign) + abs(Institutional) + abs(Individual)]
  inv[, sdi_num    := Foreign + Institutional - Individual]
  inv[, sdi_den    := abs(Foreign) + abs(Institutional) + abs(Individual)]

  inv[, `:=`(
    roll_smart_num  = frollsum(smart_num,  n = 20L, na.rm = TRUE, align = "right"),
    roll_smart_den  = frollsum(smart_den,  n = 20L, na.rm = TRUE, align = "right"),
    roll_sdi_num    = frollsum(sdi_num,    n = 20L, na.rm = TRUE, align = "right"),
    roll_sdi_den    = frollsum(sdi_den,    n = 20L, na.rm = TRUE, align = "right")
  ), by = Ticker]

  # INV09: Flow_Persistence — 20일 중 (F+I > 0)인 일수 비율
  inv[, smart_pos := as.integer(!is.na(Foreign) & !is.na(Institutional) &
                                  (Foreign + Institutional) > 0)]
  inv[, roll_persist := frollsum(smart_pos, n = 20L, na.rm = TRUE, align = "right"),
      by = Ticker]

  # 관측 수 카운트 (NA 제거 후 실유효 행 수)
  inv[, n_F  := frollsum(!is.na(Foreign),       n = 20L, align = "right"), by = Ticker]
  inv[, n_F60 := frollsum(!is.na(Foreign),       n = 60L, align = "right"), by = Ticker]
  inv[, n_I  := frollsum(!is.na(Institutional), n = 20L, align = "right"), by = Ticker]
  inv[, n_I60 := frollsum(!is.na(Institutional), n = 60L, align = "right"), by = Ticker]
  inv[, n_Ind := frollsum(!is.na(Individual),   n = 20L, align = "right"), by = Ticker]

  # ── 각 Ticker 최신값(sig_date 직전) 추출 ─────────────────────────────────
  latest <- inv[, .SD[.N], by = Ticker]

  # ── Size 병합 ─────────────────────────────────────────────────────────────
  dt <- merge(latest, size_dt, by = "Ticker", all.x = TRUE)

  # size_safe: 0이거나 NA이면 NA (나누기 보호)
  dt[, size_safe := fifelse(!is.na(Size) & Size > 0, Size, NA_real_)]

  # ── 팩터 계산 ─────────────────────────────────────────────────────────────

  # INV01: Foreign_NetBuy_20d = frollsum(Foreign, 20) / Size
  dt[, INV01 := fifelse(
    !is.na(roll_F20) & !is.na(size_safe) & n_F >= MIN_OBS_20,
    roll_F20 / size_safe,
    NA_real_
  )]

  # INV02: Foreign_NetBuy_60d = frollsum(Foreign, 60) / Size
  dt[, INV02 := fifelse(
    !is.na(roll_F60) & !is.na(size_safe) & n_F60 >= MIN_OBS_60,
    roll_F60 / size_safe,
    NA_real_
  )]

  # INV03: Inst_NetBuy_20d = frollsum(Institutional, 20) / Size
  dt[, INV03 := fifelse(
    !is.na(roll_I20) & !is.na(size_safe) & n_I >= MIN_OBS_20,
    roll_I20 / size_safe,
    NA_real_
  )]

  # INV04: Inst_NetBuy_60d = frollsum(Institutional, 60) / Size
  dt[, INV04 := fifelse(
    !is.na(roll_I60) & !is.na(size_safe) & n_I60 >= MIN_OBS_60,
    roll_I60 / size_safe,
    NA_real_
  )]

  # INV05: Foreign_Momentum = roll_F20 / roll_F60 - 1 (가속도)
  #   분모(60d)가 0에 가까우면 NA. 부호 보존을 위해 절댓값 기준 필터링.
  dt[, INV05 := fifelse(
    !is.na(roll_F20) & !is.na(roll_F60) &
      abs(roll_F60) > 1e8 &               # ~1억원 이상 거래 있어야 의미 있음
      n_F >= MIN_OBS_20 & n_F60 >= MIN_OBS_60,
    roll_F20 / roll_F60 - 1,
    NA_real_
  )]

  # INV06: Inst_Momentum = roll_I20 / roll_I60 - 1
  dt[, INV06 := fifelse(
    !is.na(roll_I20) & !is.na(roll_I60) &
      abs(roll_I60) > 1e8 &
      n_I >= MIN_OBS_20 & n_I60 >= MIN_OBS_60,
    roll_I20 / roll_I60 - 1,
    NA_real_
  )]

  # INV07: Retail_Contrarian = -1 * frollsum(Individual, 20) / Size
  #   개인 매수 = 역신호 (Barber & Odean 2000)
  dt[, INV07 := fifelse(
    !is.na(roll_Ind20) & !is.na(size_safe) & n_Ind >= MIN_OBS_20,
    -1 * roll_Ind20 / size_safe,
    NA_real_
  )]

  # INV08: Foreign_Inst_Agreement = sign(F20) * sign(I20) * min(|F20|, |I20|) / Size
  #   외국인과 기관이 같은 방향이면 양수, 반대면 음수. 크기는 작은 쪽 기준.
  dt[, INV08 := fifelse(
    !is.na(roll_F20) & !is.na(roll_I20) & !is.na(size_safe) &
      n_F >= MIN_OBS_20 & n_I >= MIN_OBS_20,
    {
      s_F <- sign(roll_F20)
      s_I <- sign(roll_I20)
      min_abs <- pmin(abs(roll_F20), abs(roll_I20))
      s_F * s_I * min_abs / size_safe
    },
    NA_real_
  )]

  # INV09: Flow_Persistence = 20일 중 (F+I > 0)인 일수 / 20
  #   스마트머니가 얼마나 일관되게 매수했는지 (0~1)
  dt[, INV09 := fifelse(
    !is.na(roll_persist) & n_F >= MIN_OBS_20,
    roll_persist / 20,
    NA_real_
  )]

  # INV10: Smart_Money_Flow = rollsum(F+I, 20) / rollsum(|F|+|I|+|Ind|, 20)
  #   전체 거래 중 스마트머니 순방향 비율 (-1 ~ 1)
  dt[, INV10 := fifelse(
    !is.na(roll_smart_num) & !is.na(roll_smart_den) &
      roll_smart_den > 1e8 &
      n_F >= MIN_OBS_20 & n_Ind >= MIN_OBS_20,
    roll_smart_num / roll_smart_den,
    NA_real_
  )]

  # INV11: Foreign_Concentration — 크로스섹셔널 상위 10% → 1, 나머지 → 0
  #   전체 universe에서 외국인 20d 순매수 규모가 상위 10%이면 집중 매수 신호
  inv11_valid <- dt[!is.na(roll_F20) & n_F >= MIN_OBS_20, .(Ticker, roll_F20)]
  if (nrow(inv11_valid) >= 10L) {
    cutoff_90 <- quantile(inv11_valid$roll_F20, probs = 0.9, na.rm = TRUE)
    inv11_valid[, INV11 := fifelse(roll_F20 >= cutoff_90, 1, 0)]
    dt <- merge(dt, inv11_valid[, .(Ticker, INV11)], by = "Ticker", all.x = TRUE)
  } else {
    dt[, INV11 := NA_real_]
  }

  # INV12: Supply_Demand_Imbalance = rollmean((F+I-Ind) / (|F|+|I|+|Ind|), 20)
  #   분자: 스마트머니 - 개인  /  분모: 전체 거래대금 합산
  #   분모가 극히 작으면 의미 없음 → 1억원 이상 필터
  dt[, INV12 := fifelse(
    !is.na(roll_sdi_num) & !is.na(roll_sdi_den) &
      roll_sdi_den > 1e8 &
      n_F >= MIN_OBS_20 & n_Ind >= MIN_OBS_20,
    roll_sdi_num / roll_sdi_den,
    NA_real_
  )]

  # ── Inf / NaN 방어 ─────────────────────────────────────────────────────────
  factor_cols <- c("INV01", "INV02", "INV03", "INV04",
                   "INV05", "INV06", "INV07", "INV08",
                   "INV09", "INV10", "INV11", "INV12")

  for (fc in factor_cols) {
    if (fc %in% names(dt)) {
      set(dt, j = fc,
          value = fifelse(is.finite(dt[[fc]]), dt[[fc]], NA_real_))
    }
  }

  # ── INV13: Foreign_Resid_Individual (3 lookback variants) ─────────────────
  # PIT: all data strictly < sig_date (C2). Expanding beta with burn-in 60m (C1).
  # beta_t = shift(cumsum(z_F * z_I) / cumsum(z_I^2), 1L) — no-intercept OLS, lag 1
  # Variants: 21d / 63d / 126d rolling window for z_F / z_I cross-section z-score base
  # Reference: Choe-Kho-Stulz (2005), Fama-MacBeth (1973)
  inv13_results <- list()

  # ★2026-09-24 DATA-INV13-ACC — 구판은 beta 누산기를 .fdb_env$INV13_BETA_ACC(세션 메모리)에서
  #   읽고 없으면 0 에서 시작했다(일일 빌드 = 영구 결손 · 60 초과 세션의 과거 달 재빌드 = 미래 달 증분
  #   혼입). 이제 sig 월 이전 월말들로부터 매 호출 자체 계산한다 — 값은 세션 순서와 무관하다.
  inv13_beta <- tryCatch(
    .inv13_beta_asof(inv, sig_d),
    error = function(e) {
      warning(sprintf("[compute_investor] INV13 beta 산출 실패 — INV13 미배출 (sig=%s): %s",
                      sig_d, conditionMessage(e)), call. = FALSE)
      NULL
    })

  # Compute cross-section z-scores at sig_date for each lookback window
  # Using full inv data (already filtered Date < sig_d)
  inv13_compute_variant <- function(lb_days, variant_suffix) {
    # Rolling sum over lb_days per ticker → month-end snapshot
    inv_lb <- inv[, .(
      roll_F  = frollsum(Foreign,    n=lb_days, na.rm=TRUE, align="right"),
      roll_I  = frollsum(Individual, n=lb_days, na.rm=TRUE, align="right"),
      n_F     = frollsum(!is.na(Foreign),    n=lb_days, align="right"),
      n_I     = frollsum(!is.na(Individual), n=lb_days, align="right")
    ), by=Ticker]
    # Use last row per ticker (most recent before sig_date)
    snap <- inv[, .SD[.N], by=Ticker, .SDcols=character(0)]
    snap <- inv[, .(Date=last(Date)), by=Ticker]  # just ticker list
    snap[, `:=`(
      roll_F = inv_lb$roll_F[match(snap$Ticker, inv[, last(Ticker), by=Ticker]$Ticker)],
      roll_I = inv_lb$roll_I[match(snap$Ticker, inv[, last(Ticker), by=Ticker]$Ticker)]
    )]

    # Simpler: take last value per ticker from inv after adding rolling cols
    inv_snap <- inv[, {
      n <- .N
      rf <- frollsum(Foreign,    n=lb_days, na.rm=TRUE, align="right")
      ri <- frollsum(Individual, n=lb_days, na.rm=TRUE, align="right")
      .(roll_F=rf[n], roll_I=ri[n],
        n_F=sum(!is.na(Foreign[pmax(1,n-lb_days+1):n])),
        n_I=sum(!is.na(Individual[pmax(1,n-lb_days+1):n])))
    }, by=Ticker]

    min_obs <- as.integer(lb_days * 0.75)
    inv_snap <- inv_snap[n_F >= min_obs & n_I >= min_obs &
                           !is.na(roll_F) & !is.na(roll_I)]
    if (nrow(inv_snap) < 20L) return(NULL)

    # Cross-section winsorize 1~99%
    winsor_cs <- function(x) {
      q <- quantile(x, probs=c(0.01,0.99), na.rm=TRUE)
      pmax(pmin(x, q[2]), q[1])
    }
    inv_snap[, roll_F := winsor_cs(roll_F)]
    inv_snap[, roll_I := winsor_cs(roll_I)]

    # Cross-section z-score (C13: Z_Score_Aligned pattern)
    zscore_cs <- function(x) {
      m <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
      if (is.na(s) || s < 1e-12) return(rep(NA_real_, length(x)))
      (x - m) / s
    }
    inv_snap[, z_F := zscore_cs(roll_F)]
    inv_snap[, z_I := zscore_cs(roll_I)]
    inv_snap <- inv_snap[!is.na(z_F) & !is.na(z_I)]
    if (nrow(inv_snap) < 20L) return(NULL)

    # Expanding beta (C1): .inv13_beta_asof() 가 sig 월 이전 월말 증분만으로 계산한 값.
    #   한 달 lag — sig 월 자신의 증분은 포함하지 않는다(구판 shift(1) 규약과 동일).
    beta_lagged <- if (!is.null(inv13_beta)) inv13_beta$beta else NA_real_

    if (is.na(beta_lagged)) return(NULL)  # burn-in(증분 월수 < 60) 또는 beta 산출 실패(경고 발행됨)

    inv_snap[, residual := z_F - beta_lagged * z_I]
    inv_snap[, Raw_Value := residual]

    data.table(
      Ticker      = inv_snap$Ticker,
      Factor_Name = paste0("INV13_Foreign_Resid_Individual_", variant_suffix),
      Raw_Value   = inv_snap$Raw_Value
    )
  }

  # 3 lookback variants: 21d / 63d / 126d
  for (lb_info in list(c(21L, "21d"), c(63L, "63d"), c(126L, "126d"))) {
    res13 <- tryCatch(
      inv13_compute_variant(as.integer(lb_info[1]), lb_info[2]),
      error = function(e) {
        warning(sprintf("[compute_investor] INV13_%s 산출 실패 (sig=%s): %s",
                        lb_info[2], sig_d, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    if (!is.null(res13) && nrow(res13) > 0L) {
      inv13_results[[lb_info[2]]] <- res13
    }
  }

  # (2026-09-24) 구판의 .fdb_env$INV13_BETA_ACC 갱신 블록 제거 — beta 누산기는 더 이상 세션 상태가
  #   아니다(.inv13_beta_asof 가 매 호출 sig 이전 월말들로부터 계산). 빌드 순서가 값을 바꾸지 않는다.

  # ── Inf / NaN 방어 (INV13) ────────────────────────────────────────────────
  inv13_all <- if (length(inv13_results) > 0L) {
    rbindlist(inv13_results, use.names=TRUE)
  } else NULL

  # ── Long format으로 변환 ───────────────────────────────────────────────────
  factor_names <- c(
    "INV01_Foreign_NetBuy_20d",
    "INV02_Foreign_NetBuy_60d",
    "INV03_Inst_NetBuy_20d",
    "INV04_Inst_NetBuy_60d",
    "INV05_Foreign_Momentum",
    "INV06_Inst_Momentum",
    "INV07_Retail_Contrarian",
    "INV08_Foreign_Inst_Agreement",
    "INV09_Flow_Persistence",
    "INV10_Smart_Money_Flow",
    "INV11_Foreign_Concentration",
    "INV12_Supply_Demand_Imbalance"
  )

  results <- list()
  for (i in seq_along(factor_cols)) {
    fc    <- factor_cols[i]
    fname <- factor_names[i]
    if (fc %in% names(dt)) {
      sub <- dt[!is.na(get(fc)), .(Ticker, Factor_Name = fname, Raw_Value = get(fc))]
      if (nrow(sub) > 0L) results[[fname]] <- sub
    }
  }

  if (!is.null(inv13_all) && nrow(inv13_all) > 0L) {
    results[["INV13"]] <- inv13_all[is.finite(Raw_Value)]
  }

  if (length(results) == 0L) return(empty_result())

  out <- rbindlist(results, use.names = TRUE)
  return(out)
}
