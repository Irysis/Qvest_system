# =============================================================================
# fq081_dupont_panel.R — FQ-081 DuPont 산업-상대 조건화 패널 빌더 + 진단
# =============================================================================
# 가설: ΔProfit Margin / ΔAsset Turnover 를 절대값이 아니라 KRX 업종내 상대
#       위치로 조건화하면(업종내 demean + 수준×변화 교호항) 무조건부 fundamental
#       팩터가 실패한 자리에서 신호가 살아난다.
#       (Wu & Jiang, JRFM 19(6):408, 2026 — ΔPM 이 ΔATO 보다 빠르게 평균회귀)
#
# ── PIT 규약 (C1/C4/C6/C14) ────────────────────────────────────────────────
#  * 재무 원천 = .cache/fundamental_merged.parquet.  Factor_Date 컬럼에 **이미
#    공시지연이 반영**되어 있다 (실측 확인 2026-08-02):
#       - Period 03/06/09 (분기) → Factor_Date = Period_Date + 45d (5/15, 8/14, 11/14)
#       - Period 12  (연간/Q4)  → Factor_Date = Period_Date + 90d  (= 익년 3/31)
#    → C4 (annual = 익년 3/31, quarterly 45일+) 정합. 본 스크립트는 Factor_Date 만
#      사용하고 Period_Date 를 신호 시점으로 쓰지 않는다.
#  * 모든 as-of 결합은 Factor_Date <= sig_date (엄격 부등호 아님 — Factor_Date 가
#    이미 공시 가능일이므로 당일 사용 가능).
#  * 1년전 vintage 는 Factor_Date <= sig_date - 365 의 최신값 (미래 미참조).
#  * 월간 수익률은 RAWDATA 의 **stored Ret** 복리 (Close/shift 재계산 금지 —
#    memory reference-rawdata-ret-firewall-20260715: recompute = Close-hole artifact).
#  * forward return(ret_fwd) 은 t+1 월 수익 — 신호(t월말) 이후에만 실현.
#  * Fama-MacBeth 확장창 계수는 **실현이 끝난 월(m <= t-1)** 의 횡단면만 사용.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr)
})
setDTthreads(2)

.fq081_root <- local({
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  for (p in cands) {
    if (nzchar(p) && file.exists(file.path(p, "CLAUDE.md")) &&
        dir.exists(file.path(p, "06_Registry"))) return(gsub("\\\\", "/", p))
  }
  stop("[fq081] project root not found")
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# -----------------------------------------------------------------------------
# 1. 재무 vintage 패널 (PM / ATO 수준 + 1년 변화)
# -----------------------------------------------------------------------------
fq081_build_fundamental_vintages <- function(cache_dir) {
  fp <- file.path(cache_dir, "fundamental_merged.parquet")
  stopifnot(file.exists(fp))
  f <- as.data.table(
    open_dataset(fp, format = "parquet") %>%
      select(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source) %>%
      filter(Item %in% c("Revenue", "NetIncome", "TotalAssets")) %>%
      collect()
  )
  f <- f[!is.na(Ticker) & !is.na(Factor_Date) & is.finite(Value)]
  f[, Factor_Date := as.Date(Factor_Date)]
  f[, q := substr(Period, 5L, 6L)]
  # 원천별 flow 정의: XLSX = 분기 flow(4분기 누적 필요) / DART Period 12 = 연간 flow(그대로)
  f[, is_annual_flow := (Source == "DART" & q == "12")]

  w <- dcast(f, Ticker + Period + Factor_Date + is_annual_flow ~ Item,
             value.var = "Value", fun.aggregate = function(x) x[1])
  setorder(w, Ticker, Factor_Date)
  for (cc in c("Revenue", "NetIncome", "TotalAssets"))
    if (!cc %in% names(w)) w[, (cc) := NA_real_]

  # TTM flow: 분기 원천은 직전 4개 관측 합, 연간 원천은 그대로.
  #   frollsum(align="right") = 과거 4관측(현재 포함) — 미래 미참조.
  w[, rev_roll4 := frollsum(Revenue,   4L, align = "right"), by = Ticker]
  w[, ni_roll4  := frollsum(NetIncome, 4L, align = "right"), by = Ticker]
  w[, TTM_Rev := fifelse(is_annual_flow, Revenue,   rev_roll4)]
  w[, TTM_NI  := fifelse(is_annual_flow, NetIncome, ni_roll4)]

  w <- w[is.finite(TTM_Rev) & TTM_Rev > 0 & is.finite(TTM_NI) &
           is.finite(TotalAssets) & TotalAssets > 0]
  w[, PM  := TTM_NI  / TTM_Rev]
  w[, ATO := TTM_Rev / TotalAssets]
  # 극단 winsor (비율 정의역 방어 — 횡단면 통계 아님, 상수 컷)
  w[, PM  := pmax(pmin(PM,  2), -2)]
  w[, ATO := pmax(pmin(ATO, 6),  0)]
  unique(w[, .(Ticker, Factor_Date, PM, ATO)], by = c("Ticker", "Factor_Date"))
}

# -----------------------------------------------------------------------------
# 2. 월간 유니버스/수익 패널 (stored Ret 복리)
# -----------------------------------------------------------------------------
fq081_build_monthly_panel <- function(cache_dir, end_date = NULL) {
  rd <- as.data.table(
    open_dataset(file.path(cache_dir, "RAWDATA.parquet"), format = "parquet") %>%
      select(Date, Ticker, Close, Vol, Ret, Size, Sector, K200, KQ150) %>%
      collect()
  )
  rd[, Date := as.Date(Date)]
  if (!is.null(end_date)) rd <- rd[Date <= as.Date(end_date)]
  rd[, tv := Close * Vol]
  setorder(rd, Ticker, Date)
  rd[, ym := format(Date, "%Y%m")]

  mon <- rd[, .(
    sig_date = max(Date),
    ret_m    = prod(1 + ifelse(is.finite(Ret), Ret, 0)) - 1,   # stored Ret 복리
    adv      = mean(tv[is.finite(tv)], na.rm = TRUE),
    Size     = last(Size[is.finite(Size)]),
    Sector   = last(Sector[!is.na(Sector)]),
    in_index = any(K200 %in% TRUE | KQ150 %in% TRUE),
    n_days   = .N
  ), by = .(Ticker, ym)]

  setorder(mon, Ticker, ym)
  # forward 1M: 다음 달 실현 수익 (동월 참조 없음)
  mon[, ret_fwd := shift(ret_m, -1L), by = Ticker]
  mon[, ym_next := shift(ym, -1L), by = Ticker]
  # 연속월만 유효 (상장폐지/거래정지 갭 건너뛴 fwd 금지)
  mon[, ym_i := as.integer(substr(ym, 1, 4)) * 12L + as.integer(substr(ym, 5, 6))]
  mon[, ym_next_i := shift(ym_i, -1L), by = Ticker]
  mon[!is.na(ym_next_i) & ym_next_i != ym_i + 1L, ret_fwd := NA_real_]
  mon[, mdate := as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-01"))]
  mon[]
}

fq081_build_benchmark <- function(cache_dir) {
  bm <- as.data.table(read_parquet(file.path(cache_dir, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  bm <- bm[is.finite(BM_Ret)]
  bm[, ym := format(Date, "%Y%m")]
  b <- bm[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = ym]
  b[, mdate := as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-01"))]
  b[]
}

# -----------------------------------------------------------------------------
# 3. as-of 결합: 각 (Ticker, 월) 에 대해 Factor_Date <= sig_date 최신값 +
#    Factor_Date <= sig_date - 365 최신값 (1년전 vintage)
# -----------------------------------------------------------------------------
fq081_asof_join <- function(mon, fv, max_stale_days = 550L) {
  keys <- mon[, .(Ticker, ym, sig_date)]
  fv2 <- copy(fv); setorder(fv2, Ticker, Factor_Date)

  # 2단 roll (현재 vintage / 1년전 vintage) — vintage 컬럼을 별도 보존해 신선도 가드에 사용
  do_roll <- function(ref_dates) {
    k <- data.table(Ticker = keys$Ticker, ym = keys$ym, jd = ref_dates)
    setorder(k, Ticker, jd)
    fvr <- copy(fv2)[, .(Ticker, jd = Factor_Date, vintage = Factor_Date, PM, ATO)]
    setkey(fvr, Ticker, jd)
    res <- fvr[k, roll = TRUE, on = .(Ticker, jd)]
    res[, .(Ticker, ym, vintage, PM, ATO, ref = jd)]
  }

  cur  <- do_roll(keys$sig_date)
  lag1 <- do_roll(keys$sig_date - 365L)
  setnames(cur,  c("vintage", "PM", "ATO"), c("vint_cur", "PM_cur", "ATO_cur"))
  setnames(lag1, c("vintage", "PM", "ATO"), c("vint_lag", "PM_lag", "ATO_lag"))
  cur[,  ref := NULL]; lag1[, ref := NULL]

  j <- merge(mon, cur, by = c("Ticker", "ym"), all.x = TRUE)
  j <- merge(j, lag1, by = c("Ticker", "ym"), all.x = TRUE)
  # 신선도 가드: 550일 초과 stale vintage 는 사용 금지 (좀비값 차단)
  j[!is.na(vint_cur) & as.integer(sig_date - vint_cur) > max_stale_days,
    c("PM_cur", "ATO_cur") := NA_real_]
  j[!is.na(vint_lag) & as.integer((sig_date - 365L) - vint_lag) > max_stale_days,
    c("PM_lag", "ATO_lag") := NA_real_]
  # 동일 vintage 면 변화량 정의 불가(1년 안에 갱신 없음) → NA
  j[, dPM  := fifelse(!is.na(vint_cur) & !is.na(vint_lag) & vint_cur != vint_lag,
                      PM_cur - PM_lag, NA_real_)]
  j[, dATO := fifelse(!is.na(vint_cur) & !is.na(vint_lag) & vint_cur != vint_lag,
                      ATO_cur - ATO_lag, NA_real_)]
  j[]
}

# -----------------------------------------------------------------------------
# 4. 횡단면 피처 (전역 z / 업종내 z / 교호항)
# -----------------------------------------------------------------------------
.wz <- function(x) {                        # winsorized cross-sectional z
  ok <- is.finite(x)
  if (sum(ok) < 5L) return(rep(NA_real_, length(x)))
  q <- stats::quantile(x[ok], c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  y <- pmax(pmin(x, q[2]), q[1])
  s <- stats::sd(y[ok])
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (y - mean(y[ok])) / s
}

fq081_build_features <- function(j, min_sector_n = 5L) {
  d <- j[is.finite(dPM) & is.finite(dATO) & is.finite(PM_cur) & is.finite(ATO_cur)]
  # 전역(무조건부) z
  d[, `:=`(g_dPM  = .wz(dPM),  g_dATO  = .wz(dATO),
           g_PM   = .wz(PM_cur), g_ATO  = .wz(ATO_cur)), by = ym]
  # 업종내 z (KRX 27 업종, 표본 <5 섹터는 NA)
  d[, sec_n := .N, by = .(ym, Sector)]
  d[, `:=`(i_dPM  = if (.N >= min_sector_n) .wz(dPM)  else NA_real_,
           i_dATO = if (.N >= min_sector_n) .wz(dATO) else NA_real_,
           i_PM   = if (.N >= min_sector_n) .wz(PM_cur)  else NA_real_,
           i_ATO  = if (.N >= min_sector_n) .wz(ATO_cur) else NA_real_),
    by = .(ym, Sector)]
  # 교호항: '업종내 경쟁위치(수준)' × '변화' — 업종내 재표준화
  d[, x_PM  := i_dPM  * i_PM]
  d[, x_ATO := i_dATO * i_ATO]
  d[, `:=`(x_PM = .wz(x_PM), x_ATO = .wz(x_ATO)), by = ym]
  d[]
}

# -----------------------------------------------------------------------------
# 5. 확장창 Fama-MacBeth 결합 (PIT: m <= t-1 실현 횡단면만)
# -----------------------------------------------------------------------------
fq081_fm_scores <- function(d, feats, min_months = 36L) {
  D <- d[, c("ym", "ym_i", "Ticker", "ret_fwd", feats), with = FALSE]
  D <- D[complete.cases(D[, c(feats), with = FALSE])]
  fit <- D[is.finite(ret_fwd)]
  # 월별 횡단면 OLS 기울기
  betas <- fit[, {
    if (.N >= 30L) {
      X <- as.matrix(.SD[, feats, with = FALSE])
      cf <- tryCatch(stats::coef(stats::lm.fit(cbind(1, X), ret_fwd)), error = function(e) NULL)
      if (is.null(cf) || any(!is.finite(cf))) as.list(setNames(rep(NA_real_, length(feats)), feats))
      else as.list(setNames(cf[-1], feats))
    } else as.list(setNames(rep(NA_real_, length(feats)), feats))
  }, by = .(ym_i), .SDcols = c("ret_fwd", feats)]
  betas <- betas[complete.cases(betas)]
  setorder(betas, ym_i)

  months <- sort(unique(D$ym_i))
  coefs <- rbindlist(lapply(months, function(t) {
    b <- betas[ym_i <= t - 1L]          # ret_fwd(m) 은 m+1 월말 실현 → m <= t-1 만 사용
    if (nrow(b) < min_months) return(NULL)
    as.data.table(c(list(ym_i = t), lapply(b[, feats, with = FALSE], mean)))
  }))
  if (!nrow(coefs)) return(D[0, .(ym, Ticker, score = numeric(0))])

  M <- merge(D, coefs, by = "ym_i", suffixes = c("", ".b"))
  M[, score := 0]
  for (f in feats) M[, score := score + get(f) * get(paste0(f, ".b"))]
  M[is.finite(score), .(ym, Ticker, score)]
}

fq081_ew_scores <- function(d, feats) {
  D <- d[, c("ym", "Ticker", feats), with = FALSE]
  D <- D[complete.cases(D)]
  D[, score := rowSums(as.matrix(.SD)), .SDcols = feats]
  D[, .(ym, Ticker, score)]
}
