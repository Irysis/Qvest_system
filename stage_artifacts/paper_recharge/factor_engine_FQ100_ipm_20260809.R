# =============================================================================
# factor_engine_FQ100_ipm_20260809.R — FQ-100: 업종-중립 순이익률 수준 (i_PM)
#
# 가설: 업종내 demean 한 순이익률 *수준*(i_PM)은 2005-2015 / 2016+ 양 시대에서
#       동일한 크기의 횡단면 순위력을 유지한다(감쇠 없음).
#       FQ-081이 검증한 '변화(ΔPM)' 축과 별개의 PORT_t 전이 검증.
#
# 신호: PM_level = TTM NetIncome / TTM Revenue (업종 demean → Z-score)
#
# ── PIT 근거 (C1 / C4 / C6 / C14 / C15) ──────────────────────────────────────
#  * 원천: fundamental_merged.parquet의 Factor_Date = 공시 지연 반영 완료
#      분기(Period 03/06/09): Factor_Date = Period_Date + 45일
#      연간(Period 12):       Factor_Date = Period_Date + 90일 (= 익년 3/31)
#    → C4 충족. 본 엔진은 Period_Date가 아닌 Factor_Date만 신호시점으로 사용.
#  * C15: Factor DB parquet(.cache/factor_db/) 직접 읽기 금지.
#    본 엔진은 fundamental_merged.parquet(원천 재무데이터)에서 PM을 직접 계산.
#    이는 Factor DB 파일이 아니므로 C15 미해당.
#  * 업종 demean: Sector는 RAWDATA에서 신호월 시점값 사용 (PIT 동일 시점 허용).
#  * as-of 결합: Factor_Date <= 신호월 말일 (과거 vintage만 사용).
#  * C1: 횡단면 표준화(업종내 mean/sd)는 각 신호월 내부에서만 (전표본 통계 미사용).
#  * C6: RAWDATA 유동성 필터(LiqPass)가 사전 적용됨.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
})

# ---- 0. 루트 경로 확인 ----
.fe_root <- local({
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""),
              Sys.getenv("QM_ROOT", ""),
              getwd())) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure", "config.R")))
      return(normalizePath(p, winslash = "/", mustWork = FALSE))
  }
  stop("[FQ100] project root not found")
})

.cache_dir <- local({
  cands <- c(
    if (exists("CACHE_DIR", inherits = TRUE)) get("CACHE_DIR", inherits = TRUE) else NULL,
    file.path(.fe_root, ".cache")
  )
  for (p in cands) {
    if (!is.null(p) && nzchar(p) &&
        file.exists(file.path(p, "fundamental_merged.parquet")))
      return(p)
  }
  stop("[FQ100] fundamental_merged.parquet not found")
})

# ---- 1. 재무 vintage (PM 수준) ──────────────────────────────────────────────
#   Factor_Date = 공시 가능일 (C4 lag 반영 완료). 추가 lag 불필요.
.f_raw <- as.data.table(
  open_dataset(
    file.path(.cache_dir, "fundamental_merged.parquet"),
    format = "parquet"
  ) %>%
    select(Ticker, Period, Factor_Date, Item, Value, Source) %>%
    filter(Item %in% c("Revenue", "NetIncome")) %>%
    collect()
)
.f_raw <- .f_raw[!is.na(Ticker) & !is.na(Factor_Date) & is.finite(Value)]
.f_raw[, Factor_Date := as.Date(Factor_Date)]

# ── 연간/분기 구분 (flow 정의. lag는 Factor_Date에 이미 반영) ──────────────
.f_raw[, .is_annual := (Source == "DART" & substr(Period, 5L, 6L) == "12")]

# ── 피벗 후 TTM 계산 ──────────────────────────────────────────────────────────
.f_w <- dcast(.f_raw, Ticker + Period + Factor_Date + .is_annual ~ Item,
              value.var = "Value", fun.aggregate = function(x) x[1L])
setorder(.f_w, Ticker, Factor_Date)

# TTM: 분기 원천 = 4개 분기 합, 연간 = 그대로
.f_w[, .rev4 := frollsum(Revenue,   4L, align = "right"), by = Ticker]
.f_w[, .ni4  := frollsum(NetIncome, 4L, align = "right"), by = Ticker]
.f_w[, .TTM_Rev := fifelse(.is_annual, Revenue,   .rev4)]
.f_w[, .TTM_NI  := fifelse(.is_annual, NetIncome, .ni4)]

# ── PM 수준 (TTM 기준, 이상값 winsorize) ─────────────────────────────────────
.f_w <- .f_w[is.finite(.TTM_Rev) & .TTM_Rev > 0 & is.finite(.TTM_NI)]
.f_w[, PM := pmax(pmin(.TTM_NI / .TTM_Rev, 2.0), -2.0)]
.f_vint <- unique(.f_w[, .(Ticker, .jd = Factor_Date, PM)], by = c("Ticker", ".jd"))
setkey(.f_vint, Ticker, .jd)

# ---- 2. 월간 패널 (Sector + 신호일 + 유동성) ─────────────────────────────────
RAWDATA[, .ym := format(Date, "%Y%m")]
.mon <- RAWDATA[, .(
  sig_date = max(Date),
  Sector   = last(Sector[!is.na(Sector)]),
  liq_ok   = any(LiqPass %in% TRUE)
), by = .(Ticker, .ym)]
setorder(.mon, Ticker, .ym)
# 유동성 통과 + Sector 있는 행만
.mon <- .mon[liq_ok == TRUE & !is.na(Sector) & nzchar(Sector)]

# ---- 3. As-of 결합: Factor_Date <= sig_date 최신 vintage ────────────────────
#   C4 준수: Factor_Date(공시 가능일)가 sig_date(월말) 이하인 가장 최근 vintage.
setkey(.mon, Ticker, sig_date)

.join_asof <- function(mon_dt, vint_dt) {
  # Ticker × 신호일별 as-of 결합 (Factor_Date <= sig_date의 최신 PM)
  result_list <- vector("list", nrow(mon_dt))
  tickers <- unique(mon_dt$Ticker)
  for (tk in tickers) {
    m_tk  <- mon_dt[Ticker == tk]
    v_tk  <- vint_dt[Ticker == tk]
    if (nrow(v_tk) == 0L) next
    for (i in seq_len(nrow(m_tk))) {
      sd <- m_tk$sig_date[i]
      vv <- v_tk[.jd <= sd]
      if (nrow(vv) == 0L) next
      best <- vv[.N]  # 가장 최근 Factor_Date (setorder로 정렬)
      result_list[[length(result_list) - length(result_list) + i]] <- data.table(
        Ticker   = tk,
        sig_date = sd,
        PM       = best$PM
      )
    }
  }
  rbindlist(Filter(Negate(is.null), result_list), use.names = TRUE)
}

# 위 루프는 종목 수가 많을 때 느리므로 data.table rolling join으로 교체
setkey(.f_vint, Ticker, .jd)
.mon[, .sd := sig_date]  # rolling join용 복사

# rolling join: by Ticker, 가장 가까운 Factor_Date <= sig_date
.joined <- .f_vint[.mon, roll = TRUE, on = .(Ticker, .jd = .sd)]
# 결과: i 컬럼 = mon 컬럼, x 컬럼 = vint 컬럼
# .joined에 PM이 채워진 행만 사용
.joined <- .joined[!is.na(PM)]

# ---- 4. 업종-중립화 (C1: 횡단면 demean, 신호월 내부만) ─────────────────────
#   각 신호월 × Sector 내부에서 PM을 demean+scale (= Z_Sector 등가).
#   C1: 전표본 통계 미사용 — 해당 월의 횡단면 통계만.
.joined[, sector_mean := mean(PM, na.rm = TRUE), by = .(sig_date, Sector)]
.joined[, sector_sd   := sd(PM,   na.rm = TRUE), by = .(sig_date, Sector)]

# 업종 sd가 0이면 스코어 0 처리 (단일 종목 업종 등)
.joined[, i_PM := fifelse(
  is.finite(sector_sd) & sector_sd > 1e-9,
  (PM - sector_mean) / sector_sd,
  0.0
)]

# ---- 5. 전체 횡단면 z-score (이상값 추가 winsorize) ─────────────────────────
.joined[, cs_mean := mean(i_PM, na.rm = TRUE), by = sig_date]
.joined[, cs_sd   := sd(i_PM,   na.rm = TRUE), by = sig_date]
.joined[, Score := fifelse(
  is.finite(cs_sd) & cs_sd > 1e-9,
  pmax(pmin((i_PM - cs_mean) / cs_sd, 3.0), -3.0),
  0.0
)]

# ---- 6. FACTORS 산출 ────────────────────────────────────────────────────────
FACTORS <- .joined[
  is.finite(Score),
  .(Date = sig_date, Ticker, Score)
]
setorder(FACTORS, Date, Ticker)

# 정리
RAWDATA[, .ym := NULL]

cat(sprintf(
  "[FQ100-ipm] FACTORS rows=%d | signal dates=%d | avg N/month=%.0f\n",
  nrow(FACTORS),
  uniqueN(FACTORS$Date),
  if (nrow(FACTORS)) nrow(FACTORS) / max(uniqueN(FACTORS$Date), 1L) else 0
))
