# =============================================================================
# factor_engine_fq081_dupont_indrel.R — FQ-081 arm C
#   DuPont ΔPM / ΔATO 를 KRX 업종내 상대 위치로 조건화 (업종 demean + 수준×변화 교호)
#   결합 = 확장창 Fama-MacBeth (과거 실현 횡단면만 — 계수 자체가 PIT)
#
# ── PIT 근거 (C1 / C4 / C6 / C14) ────────────────────────────────────────────
#  * 재무 원천 = .cache/fundamental_merged.parquet 의 Factor_Date.
#    이 컬럼에는 공시 지연이 이미 반영되어 있다 (실측 2026-08-02):
#      분기(Period 03/06/09) = Period_Date + 45일  (5/15, 8/14, 11/14)
#      연간(Period 12)       = Period_Date + 90일  (= 익년 3/31)
#    → C4 요구(annual 익년 3/31, quarterly 45일+) 를 원천 단계에서 충족.
#      본 엔진은 Period_Date 를 신호시점으로 쓰지 않고 Factor_Date 만 쓴다.
#  * 모든 as-of 결합은 Factor_Date <= 신호일. 1년전 vintage 는 Factor_Date <=
#    (신호일 - 365일). 미래 vintage 는 어떤 경로로도 들어오지 않는다 (roll = TRUE).
#  * 월간 수익률은 RAWDATA 의 stored Ret 복리 (Close/shift 재계산 금지 —
#    Close-hole artifact 회피). forward 수익(ret_fwd)은 t+1 월 실현분이며
#    신호 산출에는 절대 쓰지 않고, Fama-MacBeth 계수 추정에만 쓰되
#    "이미 실현이 끝난 달(m <= t-1)" 로 엄격히 제한한다.
#  * 횡단면 표준화는 각 신호월 내부에서만 (전표본 통계 미사용).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressPackageStartupMessages({ library(arrow); library(dplyr) })

.fq_cache <- local({
  if (exists("CACHE_DIR", inherits = TRUE) &&
      file.exists(file.path(get("CACHE_DIR", inherits = TRUE), "fundamental_merged.parquet")))
    return(get("CACHE_DIR", inherits = TRUE))
  for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), getwd())) {
    if (nzchar(p) && file.exists(file.path(p, ".cache", "fundamental_merged.parquet")))
      return(file.path(gsub("\\\\", "/", p), ".cache"))
  }
  stop("[fq081] fundamental_merged.parquet not found")
})

# ---- 1. 재무 vintage (PM / ATO 수준) ---------------------------------------
#   Factor_Date = 공시 가능일 (지연 반영 완료, 위 주석 참조). lag 추가 불필요.
.fq_f <- as.data.table(
  open_dataset(file.path(.fq_cache, "fundamental_merged.parquet"), format = "parquet") %>%
    select(Ticker, Period, Factor_Date, Item, Value, Source) %>%
    filter(Item %in% c("Revenue", "NetIncome", "TotalAssets")) %>%
    collect()
)
.fq_f <- .fq_f[!is.na(Ticker) & !is.na(Factor_Date) & is.finite(Value)]
.fq_f[, Factor_Date := as.Date(Factor_Date)]
# C4 lag 근거: Factor_Date 는 이미 공시지연 반영분 (분기 lag +45일 / 연간 lag +90일 = 익년 3/31).
#   아래 줄은 flow 정의(분기 누적 vs 연간)만 구분하며, 시점 lag 를 다시 만들지 않는다.
.fq_f[, .is_annual := (Source == "DART" & substr(Period, 5L, 6L) == "12")]  # lag 는 Factor_Date 에 반영됨

.fq_w <- dcast(.fq_f, Ticker + Period + Factor_Date + .is_annual ~ Item,
               value.var = "Value", fun.aggregate = function(x) x[1])
setorder(.fq_w, Ticker, Factor_Date)
# TTM: 분기 원천은 과거 4개 관측 합(align="right" = 과거만), 연간 원천은 그대로
.fq_w[, .rev4 := frollsum(Revenue,   4L, align = "right"), by = Ticker]
.fq_w[, .ni4  := frollsum(NetIncome, 4L, align = "right"), by = Ticker]
.fq_w[, .TTM_Rev := fifelse(.is_annual, Revenue,   .rev4)]
.fq_w[, .TTM_NI  := fifelse(.is_annual, NetIncome, .ni4)]
.fq_w <- .fq_w[is.finite(.TTM_Rev) & .TTM_Rev > 0 & is.finite(.TTM_NI) &
                 is.finite(TotalAssets) & TotalAssets > 0]
.fq_w[, PM  := pmax(pmin(.TTM_NI / .TTM_Rev, 2), -2)]
.fq_w[, ATO := pmax(pmin(.TTM_Rev / TotalAssets, 6), 0)]
.fq_vint <- unique(.fq_w[, .(Ticker, .jd = Factor_Date, vintage = Factor_Date, PM, ATO)],
                   by = c("Ticker", ".jd"))
setkey(.fq_vint, Ticker, .jd)

# ---- 2. 월간 패널 (stored Ret 복리 · 업종 · 신호일) -------------------------
RAWDATA[, .ym := format(Date, "%Y%m")]
.fq_mon <- RAWDATA[, .(
  sig_date = max(Date),
  ret_m    = prod(1 + fifelse(is.finite(Ret), Ret, 0)) - 1,
  Sector   = last(Sector[!is.na(Sector)]),
  liq_ok   = any(LiqPass %in% TRUE)
), by = .(Ticker, .ym)]
setorder(.fq_mon, Ticker, .ym)
.fq_mon[, .ymi := as.integer(substr(.ym, 1, 4)) * 12L + as.integer(substr(.ym, 5, 6))]
# 다음 달 실현 수익 (연속월만 유효 — 상장폐지/정지 갭 건너뜀 금지)
.fq_mon[, ret_fwd := shift(ret_m, -1L), by = Ticker]
.fq_mon[, .ymi_nx := shift(.ymi, -1L), by = Ticker]
.fq_mon[!is.na(.ymi_nx) & .ymi_nx != .ymi + 1L, ret_fwd := NA_real_]

# ---- 3. as-of 결합: 현재 vintage / 1년전 vintage ----------------------------
.fq_roll <- function(ref_dates) {
  k <- data.table(Ticker = .fq_mon$Ticker, .ym = .fq_mon$.ym, .jd = ref_dates)
  setorder(k, Ticker, .jd)
  .fq_vint[k, roll = TRUE, on = .(Ticker, .jd)][, .(Ticker, .ym, vintage, PM, ATO)]
}
.fq_cur <- .fq_roll(.fq_mon$sig_date)
.fq_lag <- .fq_roll(.fq_mon$sig_date - 365L)
setnames(.fq_cur, c("vintage", "PM", "ATO"), c("v_cur", "PM_cur", "ATO_cur"))
setnames(.fq_lag, c("vintage", "PM", "ATO"), c("v_lag", "PM_lag", "ATO_lag"))
.fq_d <- merge(.fq_mon, .fq_cur, by = c("Ticker", ".ym"), all.x = TRUE)
.fq_d <- merge(.fq_d,   .fq_lag, by = c("Ticker", ".ym"), all.x = TRUE)
# 신선도 가드 550일 (좀비 vintage 차단)
.fq_d[!is.na(v_cur) & as.integer(sig_date - v_cur) > 550L, c("PM_cur", "ATO_cur") := NA_real_]
.fq_d[!is.na(v_lag) & as.integer((sig_date - 365L) - v_lag) > 550L, c("PM_lag", "ATO_lag") := NA_real_]
# 1년 사이 갱신이 없으면 변화량 미정의
.fq_d[, dPM  := fifelse(!is.na(v_cur) & !is.na(v_lag) & v_cur != v_lag, PM_cur  - PM_lag,  NA_real_)]
.fq_d[, dATO := fifelse(!is.na(v_cur) & !is.na(v_lag) & v_cur != v_lag, ATO_cur - ATO_lag, NA_real_)]
# PIT self-assert (하드) — vintage 가 신호일을 넘지 않는지 실행 시 확인
stopifnot(all(.fq_d$v_cur <= .fq_d$sig_date, na.rm = TRUE))
stopifnot(all(.fq_d$v_lag <= (.fq_d$sig_date - 365L), na.rm = TRUE))

# ---- 4. 횡단면 피처 (신호월 내부 winsorized z — 전표본 통계 미사용) --------
.fq_z <- function(x) {
  ok <- is.finite(x)
  if (sum(ok) < 5L) return(rep(NA_real_, length(x)))
  q <- stats::quantile(x[ok], c(0.01, 0.99), names = FALSE)
  y <- pmax(pmin(x, q[2]), q[1])
  s <- stats::sd(y[ok])
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (y - mean(y[ok])) / s
}
.fq_d <- .fq_d[liq_ok == TRUE & !is.na(Sector) &
                 is.finite(dPM) & is.finite(dATO) & is.finite(PM_cur) & is.finite(ATO_cur)]
# 업종내 z (KRX 27 업종, 표본 5 미만 업종은 NA)
.fq_d[, `:=`(i_dPM  = if (.N >= 5L) .fq_z(dPM)     else NA_real_,
             i_dATO = if (.N >= 5L) .fq_z(dATO)    else NA_real_,
             i_PM   = if (.N >= 5L) .fq_z(PM_cur)  else NA_real_,
             i_ATO  = if (.N >= 5L) .fq_z(ATO_cur) else NA_real_),
      by = .(.ym, Sector)]
# 교호항: 업종내 경쟁위치(수준) × 업종내 변화 → 월내 재표준화
.fq_d[, x_PM  := i_dPM  * i_PM]
.fq_d[, x_ATO := i_dATO * i_ATO]
.fq_d[, `:=`(x_PM = .fq_z(x_PM), x_ATO = .fq_z(x_ATO)), by = .ym]

.FQ_FEATS <- c("i_dPM", "i_dATO", "i_PM", "i_ATO", "x_PM", "x_ATO")
.fq_D <- .fq_d[complete.cases(.fq_d[, .FQ_FEATS, with = FALSE]),
               c(".ym", ".ymi", "sig_date", "Ticker", "ret_fwd", .FQ_FEATS), with = FALSE]

# ---- 5. 확장창 Fama-MacBeth 결합 -------------------------------------------
#   월 m 의 횡단면 기울기는 m+1 월 수익이 실현된 뒤에야 계산 가능하므로,
#   신호월 t 에서는 m <= t-1 인 달의 기울기 평균만 사용한다 (미래 미참조).
.fq_fit <- .fq_D[is.finite(ret_fwd)]
.fq_beta <- .fq_fit[, {
  if (.N >= 30L) {
    .X <- as.matrix(.SD[, .FQ_FEATS, with = FALSE])
    .cf <- tryCatch(stats::coef(stats::lm.fit(cbind(1, .X), ret_fwd)), error = function(e) NULL)
    if (is.null(.cf) || any(!is.finite(.cf))) as.list(setNames(rep(NA_real_, length(.FQ_FEATS)), .FQ_FEATS))
    else as.list(setNames(.cf[-1], .FQ_FEATS))
  } else as.list(setNames(rep(NA_real_, length(.FQ_FEATS)), .FQ_FEATS))
}, by = .ymi, .SDcols = c("ret_fwd", .FQ_FEATS)]
.fq_beta <- .fq_beta[complete.cases(.fq_beta)]
setorder(.fq_beta, .ymi)

.fq_months <- sort(unique(.fq_D$.ymi))
.fq_coef <- rbindlist(lapply(.fq_months, function(tt) {
  b <- .fq_beta[.ymi <= tt - 1L]
  if (nrow(b) < 36L) return(NULL)
  as.data.table(c(list(.ymi = tt), lapply(b[, .FQ_FEATS, with = FALSE], mean)))
}))

.fq_M <- merge(.fq_D, .fq_coef, by = ".ymi", suffixes = c("", ".b"))
.fq_M[, .Score := 0]
for (.f in .FQ_FEATS) .fq_M[, .Score := .Score + get(.f) * get(paste0(.f, ".b"))]

FACTORS <- .fq_M[is.finite(.Score), .(Date = sig_date, Ticker, Score = .Score)]

RAWDATA[, .ym := NULL]
cat(sprintf("[fq081_arm_C] FACTORS rows=%d | signal months=%d | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$Date), max(FACTORS$Date)))
