# daily_fdb_pre_c11_specimens.R — 일간 Factor DB 의 PIT C11·C1 수리 **이전** 식(위반 표본 · 운영 코드 아님)
#
# 출처: 2026-09-24 수리 직전 운영 파일(git HEAD 7ea5d8377 시점, md5 phase6 791f5fa0… · phase7 b4523cd2… · phase9b cdbf15c4…)
#   factor_db_daily_phase6.R:73-98(VIX 같은 날짜 roll 결합 · V-09) · :218-230(D08 전 이력 복제 · C1)
#   factor_db_daily_phase7.R:254-316(RE10/RE13 전표본 frank · 같은 날짜 roll · RE14 행 shift(12) · V-12)
#   factor_db_daily_phase9b.R:64-68(RE04 종목별 전표본 frank · C1)
# 용도: 08_Tests/factor_db/test_daily_fdb_pit_c11.R 의 위반 주입 — 이 식으로 같은 검사를 돌리면 **빨개져야** 한다.
#   식 본문은 원문 그대로 두고 함수 껍데기만 씌웠다(입력·출력 이름만 맞춤). 고치지 말 것 — 표본이다.

suppressWarnings(suppressMessages(library(data.table)))

# phase6:73-96 — RW(Date,Ticker,...) 에 VIX 열을 붙인다(같은 날짜 roll)
pre_c11_vix_join <- function(RW, .macro) {
  .macro <- as.data.table(.macro)
  .macro[, Date := as.Date(Date)]
  .vix_d <- if ("Series_ID" %in% names(.macro) && "VIXCLS" %in% .macro[["Series_ID"]]) {
    .macro[Series_ID == "VIXCLS" & !is.na(Value), .(VIX = last(Value)), by = Date]
  } else if ("VIX" %in% .macro[["Series"]]) {
    .macro[Series == "VIX" & !is.na(Value), .(VIX = last(Value)), by = Date]
  } else NULL
  if (!is.null(.vix_d) && nrow(.vix_d) > 0L) {
    setkey(.vix_d, Date)
    # ffill VIX across all RAWDATA dates (carry-forward weekend/holiday)
    .all_dates <- data.table(Date = sort(unique(RW[["Date"]])))
    .vix_filled <- .vix_d[.all_dates, on = "Date", roll = TRUE]
    RW <- merge(RW, .vix_filled, by = "Date", all.x = TRUE)
    setkey(RW, Ticker, Date)
  }
  RW
}

# phase6:218-230 — 종목 1개의 ret·bm 벡터 → D08(전 이력 1계수 복제)
pre_c11_d08 <- function(ret, bm) {
  m <- length(ret)
  bm_sd_loc <- sd(bm, na.rm=TRUE)
  if (!is.na(bm_sd_loc) && bm_sd_loc > 1e-8) {
    tail_mask <- !is.na(bm) & abs(bm) > 2*bm_sd_loc
    if (sum(tail_mask) >= 60L) {
      f <- tryCatch(lm.fit(cbind(1, bm[tail_mask]), ret[tail_mask]),
                    error = function(e) NULL)
      if (!is.null(f)) rep(-as.numeric(f$coefficients[2L]), m) else rep(NA_real_, m)
    } else rep(NA_real_, m)
  } else rep(NA_real_, m)
}

# phase7:258-309 — macro_fred 표(.m_p7) · 한국 날짜 → MACRO_F(Date, RE10, RE11, RE13, RE14)
pre_c11_macro_f <- function(.m_p7, kr_dates) {
  .m_p7 <- as.data.table(.m_p7)
  .m_p7[, Date := as.Date(Date)]
  .m_p7 <- .m_p7[!is.na(Value)]
  .ewma_d <- function(x, halflife = 21) {
    alpha <- 1 - exp(-log(2) / halflife)
    n <- length(x); out <- rep(NA_real_, n)
    if (n == 0L) return(out)
    out[1] <- x[1]
    for (k in 2:n) {
      if (is.na(x[k])) out[k] <- out[k-1]
      else if (is.na(out[k-1])) out[k] <- x[k]
      else out[k] <- alpha * x[k] + (1-alpha) * out[k-1]
    }
    out
  }
  .all_dates <- data.table(Date = sort(unique(as.Date(kr_dates))))
  MACRO_F <- copy(.all_dates)
  .vix <- .m_p7[Series_ID == "VIXCLS", .(VIX = last(Value)), by = Date]
  if (nrow(.vix) > 0L) {
    setorder(.vix, Date)
    .vix[, RE10_VIX_Pctile := -frank(VIX, ties.method = "average") / .N]
    .vix[, vix_chg := c(NA_real_, diff(log(VIX)))]
    .vix[!is.finite(vix_chg), vix_chg := NA_real_]
    .vix[, RE11_VIX_Change_EWMA := -.ewma_d(vix_chg, 21)]
    MACRO_F <- .vix[, .(Date, RE10_VIX_Pctile, RE11_VIX_Change_EWMA)][MACRO_F,
                     on = "Date", roll = TRUE]
  }
  .hy <- .m_p7[Series_ID == "BAMLH0A0HYM2", .(HY = last(Value)), by = Date]
  if (nrow(.hy) > 0L) {
    setorder(.hy, Date)
    .hy[, RE13_Credit_Spread_Pctile := -frank(HY, ties.method = "average") / .N]
    MACRO_F <- .hy[, .(Date, RE13_Credit_Spread_Pctile)][MACRO_F,
                     on = "Date", roll = TRUE]
  }
  .cpi <- .m_p7[Series_ID == "CPIAUCSL", .(CPI = last(Value)), by = Date]
  if (nrow(.cpi) > 0L) {
    setorder(.cpi, Date)
    .cpi[, RE14_Inflation_YoY := -(CPI / shift(CPI, 12) - 1)]
    MACRO_F <- .cpi[, .(Date, RE14_Inflation_YoY)][MACRO_F,
                     on = "Date", roll = TRUE]
  }
  MACRO_F[order(Date)]
}

# phase9b:64-68 — 종목 1개의 ret·bm·mrs → RE04(종목별 전표본 frank 로 고변동 플래그)
pre_c11_re04 <- function(ret, bm, mrs) {
  mrs_pctile <- fifelse(!is.na(mrs), frank(mrs, ties.method = "average") / sum(!is.na(mrs)), NA_real_)
  hi_vol_ret <- fifelse(!is.na(mrs_pctile) & mrs_pctile > 0.7, ret, NA_real_)
  hi_vol_bm <- fifelse(!is.na(mrs_pctile) & mrs_pctile > 0.7, bm, NA_real_)
  roll_beta_cpp(hi_vol_ret, hi_vol_bm, 252L)
}
