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

  # Load expanding beta accumulator from .fdb_env if available (builder-level cache)
  inv13_beta_cache_key <- "INV13_BETA_ACC"
  inv13_beta_acc <- if (exists(".fdb_env", envir=.GlobalEnv) &&
                          exists(inv13_beta_cache_key,
                                 envir=get(".fdb_env", envir=.GlobalEnv))) {
    get(".fdb_env", envir=.GlobalEnv)[[inv13_beta_cache_key]]
  } else {
    list(SxY=0, Sxx=0, n_months=0L)
  }

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

    # Expanding beta (C1: uses only data strictly before sig_date)
    # beta_t = shift(SxY/Sxx, 1) — we use builder-cached accumulator + lag
    # At this call, inv13_beta_acc reflects data up to PREVIOUS month (shift=1)
    SxY_cum <- inv13_beta_acc$SxY + sum(inv_snap$z_F * inv_snap$z_I, na.rm=TRUE)
    Sxx_cum <- inv13_beta_acc$Sxx + sum(inv_snap$z_I^2, na.rm=TRUE)
    n_cum   <- inv13_beta_acc$n_months + 1L

    # Use LAGGED beta (beta from previous accumulation state) — C1 strict lag
    beta_lagged <- if (inv13_beta_acc$n_months >= 60L && inv13_beta_acc$Sxx > 1e-10) {
      inv13_beta_acc$SxY / inv13_beta_acc$Sxx
    } else {
      NA_real_  # burn-in: 60 months not yet reached
    }

    if (is.na(beta_lagged)) return(NULL)  # burn-in period

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
      error = function(e) NULL
    )
    if (!is.null(res13) && nrow(res13) > 0L) {
      inv13_results[[lb_info[2]]] <- res13
    }
  }

  # Update accumulator in .fdb_env for next month's call (C1: expanding window)
  if (exists(".fdb_env", envir=.GlobalEnv)) {
    # Compute current month's pooled z-scores for accumulator update (using 21d default)
    inv_acc_snap <- tryCatch({
      inv[, {
        n <- .N
        rf <- frollsum(Foreign,    n=21L, na.rm=TRUE, align="right")
        ri <- frollsum(Individual, n=21L, na.rm=TRUE, align="right")
        .(roll_F=rf[n], roll_I=ri[n])
      }, by=Ticker]
    }, error=function(e) NULL)

    if (!is.null(inv_acc_snap)) {
      inv_acc_snap <- inv_acc_snap[!is.na(roll_F) & !is.na(roll_I)]
      if (nrow(inv_acc_snap) >= 20L) {
        zscore_cs <- function(x) {
          m <- mean(x,na.rm=TRUE); s <- sd(x,na.rm=TRUE)
          if (is.na(s)||s<1e-12) return(rep(NA_real_,length(x))); (x-m)/s
        }
        inv_acc_snap[, z_F := zscore_cs(roll_F)]
        inv_acc_snap[, z_I := zscore_cs(roll_I)]
        inv_acc_snap <- inv_acc_snap[!is.na(z_F) & !is.na(z_I)]
        new_SxY <- inv13_beta_acc$SxY + sum(inv_acc_snap$z_F * inv_acc_snap$z_I, na.rm=TRUE)
        new_Sxx <- inv13_beta_acc$Sxx + sum(inv_acc_snap$z_I^2, na.rm=TRUE)
        new_n   <- inv13_beta_acc$n_months + 1L
        assign(inv13_beta_cache_key,
               list(SxY=new_SxY, Sxx=new_Sxx, n_months=new_n),
               envir=get(".fdb_env", envir=.GlobalEnv))
      }
    }
  }

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
