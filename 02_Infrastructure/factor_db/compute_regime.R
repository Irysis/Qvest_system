#==============================================================================
# compute_regime.R -- Regime + Macro Factor Module (RE01~RE16, MA03~MA07 · MA01/MA02 퇴역)
#
# compute_regime(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals (for macro sensitivity beta estimation)
#   CONSENSUS:  not used
#
# External data:
#   .cache/macro_fred.parquet — 22 macro series (Date, Series, Value)
#   ECOS data if available
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Date <= sig_date. Expanding window.
#   ★C11 (2026-09-24 수리 · 판정서 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md
#   V-01·V-13·⑤-2 · decision_register PIT-C11-REMEDIATION 안 B · PIT-C11-CONVENTIONS ③):
#   구판 주석 "C11 compliant" 는 거짓이었다 — 전 계열을 `Date <= sig_d - 1`(미국 관측일 1일) 하나로
#   걸러, 월간 CPIAUCSL·INDPRO 의 신호월(M-01 라벨) 관측을 공표(라벨 +38~54일) 전에 썼다.
#   지금은 **계열별 가용일**로 거른다: 관측의 가용일 <= sig_d 인 행만 MACRO 에 남는다.
#     가용일 = 02_Infrastructure/data/fred_availability.R::fred_avail_date (S0 가용시점 층)
#     규칙   = 06_Registry/fred_availability_rules.json (계열별 상한 · 근거 = 판정서 ② 행) — 이 파일에 오프셋 없음
#     결정   = 월말 sig_d 한국 종가(판정서 ② 원칙 (a)·(c): close_d_legacy 가 가장 이른 집행이라 가장 엄격)
#   규칙 없는 계열·금지 계열(DEXKOUS)은 제외(fail-closed · 로그). 도우미 적재 실패 = MACRO 없음(해외 계열
#   팩터 미산출 → emission_guard 회귀 경보). 값은 최신 빈티지(ALFRED 미적용 — 안 C) → C1·C11 잔여 위험.
#   RE14·MA07 의 YoY = 날짜 기준 12개월 변화(CPIAUCSL 2025-10 관측 부재 — 행 기준 shift(12) 금지).
#   MA01·MA02 = 퇴역(decision_register PIT-C11-MA0102) — 산출 중지.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

#------------------------------------------------------------------------------
# PIT C11 가용시점 층 연결 (2026-09-24 · S0 기반 fred_availability.R 경유 — 자체 오프셋 없음)
#------------------------------------------------------------------------------
.CR_C11 <- new.env(parent = emptyenv())   # 도우미 env · 가용일 주석 캐시(세션 1회)

# 이 파일 자신의 경로 — source() 프레임의 ofile(없으면 NA · sys.source 적재 등)
.CR_SELF <- local({
  f <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    o <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
    if (!is.null(o) && nzchar(o)) { f <- o; break }
  }
  if (is.na(f)) NA_character_ else normalizePath(f, winslash = "/", mustWork = FALSE)
})

# 도우미 위치: 이 파일의 형제 data/ > FUNC_PATH/data > CLAUDE_PROJECT_DIR > QM_ROOT(r-portability 금칙 ④ — CPD 먼저).
#   정체 확인 = fred_avail_date 정의.
.cr_c11_env <- function() {
  if (!is.null(.CR_C11$fa)) return(.CR_C11$fa)
  cands <- c(if (!is.na(.CR_SELF)) file.path(dirname(dirname(.CR_SELF)), "data", "fred_availability.R"),
             if (exists("FUNC_PATH")) file.path(FUNC_PATH, "data", "fred_availability.R"),
             file.path(Sys.getenv("CLAUDE_PROJECT_DIR", ""), "02_Infrastructure", "data", "fred_availability.R"),
             file.path(Sys.getenv("QM_ROOT", ""), "02_Infrastructure", "data", "fred_availability.R"))
  cands <- unique(cands[nzchar(cands) & file.exists(cands)])
  if (!length(cands))
    stop("fred_availability.R 미발견 — C11 가용시점 층 없이 해외 계열 결합 불가(fail-closed)")
  fa <- new.env(parent = globalenv())
  source(cands[1], local = fa)
  if (!exists("fred_avail_date", envir = fa, inherits = FALSE))
    stop("fred_availability.R 에 fred_avail_date 없음: ", cands[1])
  .CR_C11$fa <- fa
  .CR_C11$helper_path <- cands[1]
  fa
}

# 한국 거래일 달력: CACHE_DIR/trading_calendar.parquet(빌더와 같은 데이터 루트) + 달력 끝 뒤의 RAWDATA
# 거래일(가격이 있는 평일 = 실제 거래일 — fred_asof_join(extend_calendar=TRUE) 와 같은 규약).
.cr_c11_calendar <- function(fa, extra_kr_dates = NULL) {
  p <- if (exists("CACHE_DIR")) file.path(CACHE_DIR, "trading_calendar.parquet") else NULL
  cal <- fa$fred_kr_calendar(p)
  ex <- sort(unique(as.Date(extra_kr_dates)))
  ex <- ex[!is.na(ex) & ex > max(cal) & as.POSIXlt(ex)$wday %in% 1:5]
  if (length(ex)) cal <- sort(unique(c(cal, ex)))
  cal
}

#' 계열별 as-of 이력: 가용일(fred_avail_date) <= sig_d 인 관측만. 한 결정 시점에 필요한 것은
#' 최신값 하나가 아니라 **그 시점까지 가용한 이력 전체**(분위·YoY·월 회귀)라 결합 대신 이력 필터다
#' — 같은 규칙 엔진(fred_asof_join 과 동일한 .fa_avail_core)이다.
.cr_c11_asof <- function(dt, sig_d, macro_path, extra_kr_dates = NULL) {
  fa  <- .cr_c11_env()
  RL  <- fa$fred_avail_rules()
  cal <- .cr_c11_calendar(fa, extra_kr_dates)
  fi  <- file.info(macro_path)
  key <- paste(normalizePath(macro_path, winslash = "/", mustWork = FALSE), fi$size,
               as.numeric(fi$mtime), RL$md5, length(cal), as.integer(max(cal)))
  if (!identical(.CR_C11$ann_key, key)) {
    parts <- list(); dropped <- character(0)
    for (s in unique(dt$Series)) {
      sub <- dt[Series == s]
      av <- tryCatch(fa$fred_avail_date(s, sub$Date, kr_calendar = cal, rules = RL),
                     error = function(e) {
                       dropped <<- c(dropped, sprintf("%s(%s)", s, conditionMessage(e)))
                       NULL
                     })
      if (is.null(av)) next
      sub[, avail_date := av]
      parts[[s]] <- sub
    }
    .CR_C11$ann <- rbindlist(parts, use.names = TRUE, fill = TRUE)
    .CR_C11$ann_key <- key
    .CR_C11$dropped <- dropped
    meta <- fa$fred_avail_rules_meta()
    .CR_C11$regime_key <- meta$regime_key
    cat(sprintf("[compute_regime] C11 가용일 결합: %s · 계열 %d종 · 제외 %d종%s\n",
                meta$regime_key, length(parts), length(dropped),
                if (length(dropped)) paste0(" — ", paste(dropped, collapse = " | ")) else ""))
  }
  ann <- .CR_C11$ann
  if (is.null(ann) || !nrow(ann)) return(ann)
  out <- ann[!is.na(avail_date) & avail_date <= sig_d]
  out[, avail_date := NULL]
  out
}

# 계열 우선순위 선택(섞지 않는다) + 달력월당 마지막 관측 — 날짜 기준 YoY 의 전제(월 키 유일).
.cr_pick_series <- function(M, ids) {
  for (s in ids) {
    x <- M[Series == s & !is.na(Value)]
    if (nrow(x)) {
      setorder(x, Date)
      x[, ym_key_ := as.integer(format(Date, "%Y")) * 12L + as.integer(format(Date, "%m"))]
      x <- x[, .SD[.N], by = ym_key_]
      x[, ym_key_ := NULL]
      setorder(x, Date)
      return(x)
    }
  }
  M[0L]
}

# 날짜 기준 12개월 변화 — 같은 달력월 12개월 전 관측과의 비. 그 관측이 없으면 NA(행 기준 shift 금지).
.cr_yoy_by_date <- function(Date, Value) {
  k <- as.integer(format(Date, "%Y")) * 12L + as.integer(format(Date, "%m"))
  if (anyDuplicated(k)) stop(".cr_yoy_by_date: 달력월 중복 — .cr_pick_series 를 먼저 거쳐라")
  b <- match(k - 12L, k)
  Value / Value[b] - 1
}

compute_regime <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ---- Price data prep (PIT: Date <= sig_date) ----
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setkey(rd, Ticker, Date)

  MIN_OBS <- 120L

  # ---- BM daily returns ----
  bm_daily <- unique(rd[!is.na(BM_Ret), .(Date, BM_Ret)])
  setorder(bm_daily, Date)

  # ---- Macro data loading ----
  # Robust path resolution: prefer CACHE_DIR from config.R, then env var, then auto-detect
  macro_path <- if (exists("CACHE_DIR")) {
    file.path(CACHE_DIR, "macro_fred.parquet")
  } else {
    candidates <- c(
      Sys.getenv("QUANT_CACHE", unset = ""),
      file.path(Sys.getenv("QUANT_ROOT", unset = ""), ".cache"),
      "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache",
      "C:/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache",
      file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache")
    )
    candidates <- candidates[nchar(candidates) > 0 & dir.exists(candidates)]
    if (length(candidates) > 0) file.path(candidates[1], "macro_fred.parquet")
    else "macro_fred.parquet"
  }
  MACRO <- NULL
  if (file.exists(macro_path)) {
    MACRO <- tryCatch({
      if (requireNamespace("arrow", quietly = TRUE)) {
        # mmap=FALSE: macro_fred 는 일간 체인이 덮어쓰는 파일 — 매핑을 쥐면 Windows 에서 교체가 막힌다
        dt <- as.data.table(arrow::read_parquet(macro_path, mmap = FALSE))
        dt[, Date := as.Date(Date)]
        # Series column: legacy macro_fred used FRED codes (VIXCLS) directly,
        # but new schema uses Series_ID for codes and Series for human names.
        # Align: if Series_ID present, prefer it (so existing == "VIXCLS" matches).
        if ("Series_ID" %in% names(dt) && any(!is.na(dt[["Series_ID"]]))) {
          dt[, Series := fifelse(!is.na(Series_ID) & nchar(Series_ID) > 0,
                                  Series_ID, Series)]
        }
        dt <- dt[!is.na(Value) & !is.na(Date)]
        # Deduplicate (Series, Date) — guard against Cartesian merges downstream
        setorder(dt, Series, Date)
        dt <- unique(dt, by = c("Series", "Date"), fromLast = TRUE)
        # ★C11 (판정서 V-01·V-13·⑤-2): 구판 공통 필터 `Date <= sig_d - 1L` 대체 —
        #   계열별 가용일 <= sig_d 인 관측만(가용일 규칙 = fred_availability_rules.json).
        .cr_c11_asof(dt, sig_d, macro_path, extra_kr_dates = unique(rd$Date))
      } else NULL
    }, error = function(e) {
      # ★침묵 금지 — 구판은 NULL 만 돌려 해외 계열 팩터가 조용히 사라졌다
      cat(sprintf("[compute_regime] !!! MACRO 적재 실패 — 해외 계열 팩터 미산출(fail-closed): %s\n",
                  conditionMessage(e)))
      NULL
    })
  }

  # ---- Helper: EWMA ----
  .ewma <- function(x, halflife = 21) {
    alpha <- 1 - exp(-log(2) / halflife)
    n <- length(x)
    out <- rep(NA_real_, n)
    if (n == 0L) return(out)
    out[1] <- x[1]
    for (i in 2:n) {
      if (is.na(x[i])) {
        out[i] <- out[i - 1]
      } else if (is.na(out[i - 1])) {
        out[i] <- x[i]
      } else {
        out[i] <- alpha * x[i] + (1 - alpha) * out[i - 1]
      }
    }
    out
  }

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
  }

  # ==========================================================================
  # REGIME FACTORS (RE01~RE16) — Market-level, applied to each ticker as
  # cross-sectional sensitivity (beta) to regime indicators
  # ==========================================================================

  # ---- RE01: Market Return EWMA 21d ----
  if (nrow(bm_daily) >= 21L) {
    bm_daily[, mkt_ewma := .ewma(BM_Ret, halflife = 21)]
    mkt_ewma_val <- bm_daily[Date == max(Date)]$mkt_ewma
    if (length(mkt_ewma_val) > 0L && !is.na(mkt_ewma_val)) {
      # Cross-sectional: each ticker gets market-level signal
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE01"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE01_Mkt_EWMA_21d",
          Raw_Value = mkt_ewma_val
        )
      }
    }
  }

  # ---- RE02: Market Volatility Regime (expanding percentile of 21d realized vol) ----
  if (nrow(bm_daily) >= 42L) {
    # frollsum-based rolling SD (replaces frollapply + sd: O(N) vs O(N*window))
    .roll_sd_bm <- function(x, n) {
      m <- length(x)
      if (m < n) return(rep(NA_real_, m))
      s1 <- suppressWarnings(frollsum(x,   n=n, fill=NA_real_, align="right", na.rm=FALSE))
      s2 <- suppressWarnings(frollsum(x^2, n=n, fill=NA_real_, align="right", na.rm=FALSE))
      vx <- (s2 - s1^2 / n) / (n - 1L)
      sqrt(pmax(vx, 0))
    }
    bm_daily[, mkt_vol21 := .roll_sd_bm(BM_Ret, 21L)]
    last_vol <- bm_daily[Date == max(Date)]$mkt_vol21
    if (length(last_vol) > 0L && !is.na(last_vol)) {
      # Expanding percentile (PIT compliant)
      all_vols <- bm_daily[!is.na(mkt_vol21) & Date <= sig_d]$mkt_vol21
      pctile <- mean(all_vols <= last_vol, na.rm = TRUE)
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE02"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE02_Vol_Regime_Pctile",
          Raw_Value = -pctile  # negate: high vol = bad
        )
      }
    }
  }

  # ---- RE03: Market Drawdown Regime ----
  if (nrow(bm_daily) >= 21L) {
    bm_daily[, cum_bm := cumprod(1 + fifelse(is.na(BM_Ret), 0, BM_Ret))]
    bm_daily[, cum_max_bm := cummax(cum_bm)]
    bm_daily[, dd_bm := (cum_bm - cum_max_bm) / cum_max_bm]
    last_dd <- bm_daily[Date == max(Date)]$dd_bm
    if (length(last_dd) > 0L && !is.na(last_dd)) {
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE03"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE03_Mkt_Drawdown",
          Raw_Value = last_dd  # negative = drawdown, positive = near peak
        )
      }
    }
  }

  # ---- RE04~RE09: Stock-level sensitivity to market regime ----
  # Pre-join bm_daily signals to rd → single by=Ticker pass (replaces lapply).
  bm_cols <- c("Date", "BM_Ret")
  if ("mkt_vol21" %in% names(bm_daily)) bm_cols <- c(bm_cols, "mkt_vol21")
  if ("dd_bm"     %in% names(bm_daily)) bm_cols <- c(bm_cols, "dd_bm")

  rd_regime <- merge(
    rd[!is.na(Ret), .(Ticker, Date, Ret)],
    bm_daily[, ..bm_cols],
    by = "Date", all.x = TRUE
  )
  rd_regime <- rd_regime[!is.na(Ret) & !is.na(BM_Ret)]
  setkey(rd_regime, Ticker, Date)

  has_vol21 <- "mkt_vol21" %in% names(rd_regime)
  has_dd    <- "dd_bm"     %in% names(rd_regime)

  regime_betas <- rd_regime[, {
    n <- .N
    re04 <- re05 <- re06 <- re07 <- re08 <- re09 <- NA_real_
    if (n >= MIN_OBS) {
      # RE04/RE05: conditional beta on vol regime
      if (has_vol21 && sum(!is.na(mkt_vol21)) > 0L) {
        vol_med   <- median(mkt_vol21, na.rm = TRUE)
        hv_ok <- !is.na(mkt_vol21) & mkt_vol21 >  vol_med
        lv_ok <- !is.na(mkt_vol21) & mkt_vol21 <= vol_med
        if (sum(hv_ok) >= 30L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[hv_ok]), Ret[hv_ok]), error=function(e) NULL)
          if (!is.null(f)) re04 <- -f$coefficients[2L]
        }
        if (sum(lv_ok) >= 30L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[lv_ok]), Ret[lv_ok]), error=function(e) NULL)
          if (!is.null(f)) re05 <- -f$coefficients[2L]
        }
        if (!is.na(re04) && !is.na(re05)) re06 <- re04 - re05
      }
      # RE07: Crisis beta (market DD < -5%)
      if (has_dd) {
        cr_ok <- !is.na(dd_bm) & dd_bm < -0.05
        if (sum(cr_ok) >= 20L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[cr_ok]), Ret[cr_ok]), error=function(e) NULL)
          if (!is.null(f)) re07 <- -f$coefficients[2L]
        }
      }
      # RE08: Down-market excess return
      dn_ok <- !is.na(BM_Ret) & BM_Ret < 0
      if (sum(dn_ok) >= 30L)
        re08 <- mean(Ret[dn_ok] - BM_Ret[dn_ok], na.rm = TRUE)
      # RE09: Up/Down capture ratio
      up_ok <- !is.na(BM_Ret) & BM_Ret > 0
      if (sum(up_ok) >= 30L && sum(dn_ok) >= 30L) {
        up_cap  <- mean(Ret[up_ok], na.rm=TRUE) / mean(BM_Ret[up_ok], na.rm=TRUE)
        dn_cap  <- mean(Ret[dn_ok], na.rm=TRUE) / mean(BM_Ret[dn_ok], na.rm=TRUE)
        if (!is.na(dn_cap) && abs(dn_cap) > 1e-8) re09 <- up_cap / dn_cap
      }
    }
    list(RE04=re04, RE05=re05, RE06=re06, RE07=re07, RE08=re08, RE09=re09)
  }, by = Ticker]

  # Unpack regime_betas into results list
  .add_re <- function(col, fname) {
    sub <- regime_betas[!is.na(get(col)), .(Ticker, Factor_Name=fname, Raw_Value=get(col))]
    if (nrow(sub) > 0) results[[fname]] <<- sub
  }
  .add_re("RE04", "RE04_HighVol_Beta")
  .add_re("RE05", "RE05_LowVol_Beta")
  .add_re("RE06", "RE06_Beta_Asymmetry")
  .add_re("RE07", "RE07_Crisis_Beta")
  .add_re("RE08", "RE08_Down_Market_Excess")
  .add_re("RE09", "RE09_Capture_Ratio")

  # ==========================================================================
  # RE10~RE16: VIX-based regime indicators (if macro data available)
  # ==========================================================================
  if (!is.null(MACRO) && nrow(MACRO) > 0L) {
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)

    # ---- RE10: VIX Level (expanding percentile) ----
    vix_dt <- MACRO[Series == "VIXCLS" & !is.na(Value)]
    if (nrow(vix_dt) >= 21L) {
      setorder(vix_dt, Date)
      last_vix <- vix_dt[Date == max(Date)]$Value
      if (length(last_vix) > 0L) {
        vix_pctile <- mean(vix_dt$Value <= last_vix, na.rm = TRUE)
        results[["RE10"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE10_VIX_Pctile",
          Raw_Value = -vix_pctile  # high VIX = bad
        )
      }

      # ---- RE11: VIX Change EWMA 21d ----
      vix_dt[, vix_ret := c(NA, diff(log(Value)))]
      vix_dt[, vix_ewma := .ewma(vix_ret, halflife = 21)]
      last_ewma <- vix_dt[Date == max(Date)]$vix_ewma
      if (length(last_ewma) > 0L && !is.na(last_ewma)) {
        results[["RE11"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE11_VIX_Change_EWMA",
          Raw_Value = -last_ewma  # rising VIX = bad
        )
      }
    }

    # ---- RE12: VIX Rolling Quantile Regime (3-state) ----
    if (nrow(vix_dt) >= 252L) {
      setorder(vix_dt, Date)
      last_vix <- vix_dt[Date == max(Date)]$Value
      # Trailing 252d quantiles
      trailing <- vix_dt[Date >= (sig_d - 365)]$Value
      q33 <- quantile(trailing, 0.33, na.rm = TRUE)
      q67 <- quantile(trailing, 0.67, na.rm = TRUE)
      regime_state <- if (last_vix <= q33) 1 else if (last_vix <= q67) 0 else -1
      results[["RE12"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "RE12_VIX_Regime_3State",
        Raw_Value = regime_state  # 1=low vol, 0=mid, -1=high
      )
    }

    # ---- RE13: Credit Spread (High Yield OAS) ----
    hy_dt <- MACRO[Series %in% c("BAMLH0A0HYM2", "BAMLH0A0HYM2EY") & !is.na(Value)]
    if (nrow(hy_dt) >= 21L) {
      setorder(hy_dt, Date)
      last_hy <- hy_dt[Date == max(Date)]$Value
      if (length(last_hy) > 0L) {
        hy_pctile <- mean(hy_dt$Value <= last_hy, na.rm = TRUE)
        results[["RE13"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE13_Credit_Spread_Pctile",
          Raw_Value = -hy_pctile  # wide spread = bad
        )
      }
    }

    # ---- RE14: Inflation Regime (CPI YoY expanding percentile) ----
    # ★2026-09-24 (판정서 V-13 · decision_register PIT-C11-CONVENTIONS ③):
    #   ① 신호월 관측을 더는 쓰지 않는다 — 가용일 필터는 위 MACRO 적재에서(CPIAUCSL 규칙).
    #   ② YoY = **날짜 기준 12개월 변화**. 구판 shift(12) 는 행 기준이라 CPIAUCSL 2025-10 관측
    #      부재(셧다운 — BLS 미공표) 뒤로 13개월 변화가 됐다. 12개월 전 같은 달 관측이 없으면 NA.
    #   ③ CPIAUCSL·CPIAUCNS 를 섞지 않는다(우선순위 첫 계열만).
    cpi_dt <- .cr_pick_series(MACRO, c("CPIAUCSL", "CPIAUCNS"))
    if (nrow(cpi_dt) >= 13L) {
      cpi_dt[, cpi_yoy := .cr_yoy_by_date(Date, Value)]
      cpi_dt <- cpi_dt[!is.na(cpi_yoy)]
      if (nrow(cpi_dt) > 0L) {
        last_cpi <- cpi_dt[Date == max(Date)]$cpi_yoy
        if (length(last_cpi) > 0L) {
          # High inflation = regime signal
          results[["RE14"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "RE14_Inflation_YoY",
            Raw_Value = -last_cpi  # high inflation = bad for equities
          )
        }
      }
    }

    # ---- RE15: Cross-Sectional Breadth (% of stocks with positive returns) ----
    # Market-internal breadth indicator
    breadth_dt <- rd[Date >= (sig_d - 21L) & Date <= sig_d & !is.na(Ret)]
    if (nrow(breadth_dt) > 0L) {
      breadth <- breadth_dt[, .(pct_positive = mean(Ret > 0, na.rm = TRUE)), by = Date]
      last_breadth <- mean(breadth$pct_positive, na.rm = TRUE)
      results[["RE15"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "RE15_Market_Breadth_21d",
        Raw_Value = last_breadth  # higher breadth = healthier market
      )
    }

    # ---- RE16: Canary Momentum Signal proxy ----
    # Use S&P 500 + VIX as canary: if S&P momentum negative, defensive signal
    sp_dt <- MACRO[Series %in% c("SP500", "GSPC") & !is.na(Value)]
    if (nrow(sp_dt) >= 63L) {
      setorder(sp_dt, Date)
      last_sp <- sp_dt[Date == max(Date)]$Value
      sp_63d  <- sp_dt[Date <= (sig_d - 63)]
      if (nrow(sp_63d) > 0L) {
        sp_mom <- last_sp / sp_63d[Date == max(Date)]$Value - 1
        if (length(sp_mom) > 0L && !is.na(sp_mom)) {
          canary_signal <- fifelse(sp_mom < 0, -1, 1)
          results[["RE16"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "RE16_Canary_Signal",
            Raw_Value = canary_signal
          )
        }
      }
    }
  }

  # ==========================================================================
  # MACRO FACTORS (MA01~MA07) — Stock-level beta to macro variables
  # ==========================================================================
  if (!is.null(MACRO) && nrow(MACRO) > 0L) {
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)

    # Prepare monthly stock returns for macro regression
    rd_monthly <- rd[, .(monthly_ret = prod(1 + Ret, na.rm = TRUE) - 1),
                     by = .(Ticker, YM = format(Date, "%Y-%m"))]

    # ---- Helper: compute beta to a macro series for each ticker ----
    .macro_beta <- function(macro_series_name, factor_name) {
      ms <- MACRO[Series == macro_series_name & !is.na(Value)]
      if (nrow(ms) < 12L) return(NULL)
      setorder(ms, Date)
      ms[, YM := format(Date, "%Y-%m")]
      # Aggregate to monthly (last value per YM) — guards against daily series cartesian merge
      ms <- ms[, .SD[.N], by = YM]
      setorder(ms, YM)
      # Monthly change in macro variable
      ms[, macro_chg := Value - shift(Value, 1)]
      ms <- ms[!is.na(macro_chg), .(YM, macro_chg)]

      merged <- merge(rd_monthly, ms, by = "YM", all.x = TRUE, allow.cartesian = FALSE)
      merged <- merged[!is.na(monthly_ret) & !is.na(macro_chg)]

      if (nrow(merged) < 12L) return(NULL)

      betas <- merged[, {
        if (.N >= 12L) {
          fit <- tryCatch(lm.fit(cbind(1, macro_chg), monthly_ret), error = function(e) NULL)
          if (!is.null(fit)) {
            .(beta = fit$coefficients[2])
          } else {
            .(beta = NA_real_)
          }
        } else {
          .(beta = NA_real_)
        }
      }, by = Ticker]

      betas <- betas[!is.na(beta)]
      if (nrow(betas) == 0L) return(NULL)
      betas[, .(Ticker, Factor_Name = factor_name, Raw_Value = beta)]
    }

    # ---- MA01·MA02: 퇴역 (2026-09-24 · decision_register PIT-C11-MA0102 · 판정서 V-01·⑥-5) ----
    #   구판은 INDPRO·CPIAUCSL 신호월(M-01) 관측을 공표 전에 써서 월 회귀 약 12쌍 중 마지막 쌍이
    #   미래 정보였다(MA01 = L1 20칸 오염). 공표분만 쓰면 현 창(최근 12개월·최소 12관측)으로는
    #   202608·202003 이 산출 불가(n<12) — 창 재정의 대신 퇴역을 택했다(도훈 결정).
    #   산출 중지 · factor_registry.json lifecycle.status = "retired" · 06_Registry/pit_quarantine.json
    #   격리는 그대로 둔다. ★이름 재사용 금지 — 저장 이력(2005-01~2026-09)은 오염판이다.

    # ---- MA03: Interest Rate Sensitivity (10Y Treasury) ----
    ma03 <- .macro_beta("GS10", "MA03_Rate_Sensitivity")
    if (is.null(ma03)) ma03 <- .macro_beta("DGS10", "MA03_Rate_Sensitivity")
    if (!is.null(ma03)) results[["MA03"]] <- ma03

    # ---- MA04: Yield Curve Sensitivity (10Y-2Y spread) ----
    ys10 <- MACRO[Series %in% c("GS10", "DGS10") & !is.na(Value)]
    ys2  <- MACRO[Series %in% c("GS2", "DGS2") & !is.na(Value)]
    if (nrow(ys10) > 0L && nrow(ys2) > 0L) {
      setorder(ys10, Date); setorder(ys2, Date)
      ys10[, YM := format(Date, "%Y-%m")]
      ys2[, YM := format(Date, "%Y-%m")]
      # Monthly aggregate (last value per YM) — guards Cartesian merge
      ys10_m <- ys10[, .(y10 = last(Value)), by = YM]
      ys2_m  <- ys2[,  .(y2  = last(Value)), by = YM]
      yc <- merge(ys10_m, ys2_m, by = "YM")
      setorder(yc, YM)
      yc[, spread := y10 - y2]
      yc[, spread_chg := spread - shift(spread, 1)]
      yc <- yc[!is.na(spread_chg)]
      if (nrow(yc) >= 12L) {
        merged_yc <- merge(rd_monthly, yc[, .(YM, macro_chg = spread_chg)], by = "YM", all.x = TRUE, allow.cartesian = FALSE)
        merged_yc <- merged_yc[!is.na(monthly_ret) & !is.na(macro_chg)]
        if (nrow(merged_yc) >= 12L) {
          betas_yc <- merged_yc[, {
            if (.N >= 12L) {
              fit <- tryCatch(lm.fit(cbind(1, macro_chg), monthly_ret), error = function(e) NULL)
              if (!is.null(fit)) .(beta = fit$coefficients[2]) else .(beta = NA_real_)
            } else .(beta = NA_real_)
          }, by = Ticker]
          betas_yc <- betas_yc[!is.na(beta)]
          if (nrow(betas_yc) > 0L) {
            results[["MA04"]] <- betas_yc[, .(Ticker, Factor_Name = "MA04_YieldCurve_Sensitivity", Raw_Value = beta)]
          }
        }
      }
    }

    # ---- MA05: Monetary Policy Momentum (1Y change in 2Y yield) ----
    ys2_mp <- MACRO[Series %in% c("GS2", "DGS2") & !is.na(Value)]
    if (nrow(ys2_mp) >= 252L) {
      setorder(ys2_mp, Date)
      last_y2 <- ys2_mp[Date == max(Date)]$Value
      y2_1y   <- ys2_mp[Date <= (sig_d - 365)]
      if (nrow(y2_1y) > 0L) {
        y2_1y_val <- y2_1y[Date == max(Date)]$Value
        mp_mom <- last_y2 - y2_1y_val
        if (length(mp_mom) > 0L && !is.na(mp_mom)) {
          results[["MA05"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "MA05_MonetaryPolicy_Mom",
            Raw_Value = -mp_mom  # rising yields = tightening = bad for equities
          )
        }
      }
    }

    # ---- MA06: Risk Sentiment (1Y equity market return) ----
    # Threshold 240 (was 252): a 365-calendar-day window holds 242~253 KR
    # trading days depending on holidays. 252 was too strict for recent years
    # (more KR holidays) -> MA06 silently dropped 2012-10 onward. 240 still
    # guarantees ~11.5 months of data for a 1Y market-return reading.
    # PIT-safe: still uses only past 365-day window. (build-gap fix 2026-05-29)
    if (nrow(bm_daily) >= 240L) {
      bm_1y <- bm_daily[Date >= (sig_d - 365)]
      if (nrow(bm_1y) > 0L) {
        mkt_1y_ret <- prod(1 + bm_1y$BM_Ret, na.rm = TRUE) - 1
        results[["MA06"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "MA06_Risk_Sentiment_1Y",
          Raw_Value = mkt_1y_ret
        )
      }
    }

    # ---- MA07: Business Cycle Composite ----
    # Combine GDP + CPI momentum into composite
    # ★2026-09-24 (판정서 V-13 · PIT-C11-CONVENTIONS ③): RE14 와 같은 수리 — 가용일 필터(적재에서)
    #   + 날짜 기준 12개월 변화 + 계열 비혼합. INDPRO 는 공표 +54일 상한(규칙 파일).
    ma07_parts <- list()
    gdp_dt <- .cr_pick_series(MACRO, c("INDPRO", "A191RL1Q225SBEA"))
    if (nrow(gdp_dt) >= 13L) {
      gdp_dt[, gdp_yoy := .cr_yoy_by_date(Date, Value)]
      last_gdp <- gdp_dt[!is.na(gdp_yoy)][Date == max(Date)]$gdp_yoy
      if (length(last_gdp) > 0L) ma07_parts[["gdp"]] <- last_gdp
    }
    cpi_dt2 <- .cr_pick_series(MACRO, c("CPIAUCSL", "CPIAUCNS"))
    if (nrow(cpi_dt2) >= 13L) {
      cpi_dt2[, cpi_yoy := .cr_yoy_by_date(Date, Value)]
      last_cpi2 <- cpi_dt2[!is.na(cpi_yoy)][Date == max(Date)]$cpi_yoy
      if (length(last_cpi2) > 0L) ma07_parts[["cpi"]] <- last_cpi2
    }
    if (length(ma07_parts) >= 1L) {
      # 50/50 GDP growth + (-CPI inflation)
      gdp_val <- if (!is.null(ma07_parts[["gdp"]])) ma07_parts[["gdp"]] else 0
      cpi_val <- if (!is.null(ma07_parts[["cpi"]])) -ma07_parts[["cpi"]] else 0
      bc_composite <- 0.5 * gdp_val + 0.5 * cpi_val
      results[["MA07"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "MA07_BusinessCycle_Composite",
        Raw_Value = bc_composite
      )
    }
  } else {
    # No macro data -- mark as DATA_NEEDED
    # DATA_NEEDED: macro_fred.parquet for MA03~MA07, RE10~RE16 (MA01·MA02 퇴역)
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)
  }

  # ---- Combine all ----
  if (length(results) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_regime.R loaded (RE01~RE16, MA03~MA07 · MA01/MA02 retired · C11 avail layer)\n")
