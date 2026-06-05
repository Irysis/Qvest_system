# Residual Momentum — Blitz, Huij & Martens (2011), J. Empirical Finance (논문 원본 스펙)
# -----------------------------------------------------------------------------
# 논문 정확 방법론 (KR long-only 적응 — short 불가이므로 top decile만):
#   1. 월간 (초과)수익을 직전 36개월 FF3(MKT+SMB+HML)에 stock-by-stock OLS 회귀
#      → 잔차 e_{i,s} 추출 (각 종목 자체 36m 시계열 회귀, rolling).
#   2. residual momentum = 잔차의 t-12~t-2 (11개월, 직전 1개월 skip) 평균
#      ÷ 같은 11개월 잔차 표준편차 (정보비율/표준화 형태 — 논문 핵심).
#   3. residual momentum decile 정렬 → top decile equal-weight (long-only).
#      decile 크기는 N 컬럼으로 run_monthly_simulation에 전달 (종목수 임의 제한 안 함).
#   4. 월간 리밸런싱.
#
# KR FF3 팩터: .cache/kr_factor_returns_v2.parquet (MKT/SMB/HML/RF 월간).
#   HML 가용 2002-08~ → 36m 회귀로 최초 잔차 ~2005-08. start_date로 시그널 제한 가능.
#
# PIT (lookahead_detector / data_table_shift_convention 정합):
#   - 36m 회귀 윈도우 = 형성월 t까지의 과거 36개 월간수익 (실현 팩터·실현 수익). C1 회피.
#   - residual momentum 윈도우 = t-12~t-2 (전부 과거 잔차). 직전월(t-1) skip. forward 절대 없음.
#   - 월간 수익은 종목 자체 일간수익의 월내 복리 집계(자산 수익 aggregation, 포트 NAV 합성 아님).
#   - 수동 부호반전(NEGATE/FLIP) 없음. Score = 표준화 잔차모멘텀(높을수록 매수).
# -----------------------------------------------------------------------------
suppressMessages({ library(data.table); library(arrow) })
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 0. KR FF3 월간 팩터 로드 (MKT/SMB/HML/RF) -----------------------------
.cd  <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"), ".cache")
.fcp <- file.path(.cd, "kr_factor_returns_v2.parquet")
stopifnot(file.exists(.fcp))
.FF <- as.data.table(read_parquet(.fcp))[, .(Date = as.Date(Date), MKT, SMB, HML, RF)]
.FF <- .FF[is.finite(MKT) & is.finite(SMB) & is.finite(HML) & is.finite(RF)]
.FF[, ym := format(Date, "%Y-%m")]
setorder(.FF, Date)

# ---- 1. 종목 월간 수익 (일간 Ret 월내 복리 집계 — 자산 수익 aggregation) ----
#   prod(1+r)-1 = 한 종목의 월간 실현수익 (포트폴리오 NAV 합성 아님 → 계약 위반 아님).
#   ★ 시그널 캘린더 = 유니버스 전체 월말 거래일(canonical). 종목별 max(Date) 사용 시
#     중도상장/거래정지 종목의 월중 마지막날이 1-종목 spurious 시그널일을 만든다 → 방지.
.RD <- RAWDATA[is.finite(Ret), .(Date, Ticker, Ret)]
.RD[, ym := format(Date, "%Y-%m")]
.CAL <- RAWDATA[, .(MEnd = max(Date)), by = .(ym = format(Date, "%Y-%m"))]   # 월별 유니버스 월말
.MR <- .RD[, .(MRet = prod(1 + Ret) - 1), by = .(Ticker, ym)]
.MR <- merge(.MR, .CAL, by = "ym")                                          # canonical 월말 부착
setorder(.MR, Ticker, ym)
# 월말 거래대금 유동성 통과 여부 + 시총 (PIT: 형성월(canonical 월말) 시점)
.LP <- RAWDATA[Date %in% .CAL$MEnd, .(Date, Ticker, LiqPass, Size)]
setnames(.LP, "Date", "MEnd")

# ---- 2. 종목별 month-grid 정렬 + FF3 merge (year-month 키) -----------------
#   ★ 36m 회귀창·11-1 lag(shift)이 '캘린더 월'로 정합하도록, 각 종목의 첫~마지막 관측월
#     사이 빠진 월을 NA로 채워 연속 그리드 구성(거래정지 등 결측 흡수). 그래야 shift(2:12)가
#     달력상 t-2..t-12를 정확히 가리킨다(인덱스 점프로 인한 미래/과거 오정렬 방지).
.MR <- merge(.MR, .FF[, .(ym, MKT, SMB, HML, RF)], by = "ym")     # FF3 가용월만(2002-08~)
.allmo <- .FF[order(Date), .(ym, ord = seq_len(.N), FFEnd = Date)]  # FF 월 순서/일자
.MR <- merge(.MR, .allmo[, .(ym, ord)], by = "ym")
.rng <- .MR[, .(o0 = min(ord), o1 = max(ord)), by = Ticker]
.grid <- .rng[, .(ord = seq.int(o0, o1)), by = Ticker]
.grid <- merge(.grid, .allmo[, .(ord, ym, MEnd_cal = FFEnd)], by = "ord")
.MR <- merge(.grid, .MR[, .(Ticker, ym, MRet, MEnd, MKT, SMB, HML, RF)],
             by = c("Ticker", "ym"), all.x = TRUE)
# 결측월 팩터는 FF에서 복원(잔차창 유효성용), MRet 결측월은 NA 유지(잔차 NA→momentum 제외).
.MR <- merge(.MR, .FF[, .(ym, MKTf = MKT, SMBf = SMB, HMLf = HML, RFf = RF)], by = "ym", all.x = TRUE)
.MR[is.na(MKT), `:=`(MKT = MKTf, SMB = SMBf, HML = HMLf, RF = RFf)]
.MR[, c("MKTf","SMBf","HMLf","RFf") := NULL]
.MR[, Excess := MRet - RF]
setorder(.MR, Ticker, ord)
.MR[, midx := seq_len(.N), by = Ticker]   # 종목 내 연속 월 인덱스(달력 정합)

# ---- 3. 36개월 rolling FF3 OLS (stock-by-stock) → 잔차 e_{i,t} -------------
#   각 형성월 t에서 [t-35 .. t] 36개월 윈도우로 Excess ~ MKT+SMB+HML OLS, t월 잔차 산출.
#   윈도우는 t까지의 과거 실현 데이터만 (PIT-safe).
W36 <- 36L
.resid_one <- function(ex, mk, sm, hm) {
  n <- length(ex)
  out <- rep(NA_real_, n)
  if (n < W36) return(out)
  for (t in W36:n) {
    idx <- (t - W36 + 1L):t
    y  <- ex[idx]; X <- cbind(1, mk[idx], sm[idx], hm[idx])
    ok <- is.finite(y) & is.finite(X[,2]) & is.finite(X[,3]) & is.finite(X[,4])
    if (sum(ok) < 30L) next                 # 최소 30개월 유효
    yo <- y[ok]; Xo <- X[ok, , drop = FALSE]
    b  <- tryCatch(qr.solve(crossprod(Xo), crossprod(Xo, yo)), error = function(e) NULL)
    if (is.null(b)) next
    # t월 잔차 = 실제 t월 초과수익 - 적합값 (베타는 윈도우 OLS, 전부 과거/현재월 실현)
    out[t] <- ex[t] - sum(c(1, mk[t], sm[t], hm[t]) * b)
  }
  out
}
.MR[, eresid := .resid_one(Excess, MKT, SMB, HML), by = Ticker]

# ---- 4. residual momentum = mean(e, t-12..t-2) / sd(e, t-12..t-2) ----------
#   11개월 윈도우 (직전월 t-1 skip): 형성월 t 기준 e[t-12], ..., e[t-2].
#   data.table::shift lag(과거) 사용 — forward 없음. 표준화(정보비율) 형태.
.lagcols <- paste0("e_l", 2:12)
.MR[, (.lagcols) := shift(eresid, 2:12, type = "lag"), by = Ticker]
.MR[, rm_mean := rowMeans(.SD, na.rm = FALSE), .SDcols = .lagcols]
.MR[, rm_sd := apply(.SD, 1L, function(v) if (all(is.finite(v))) stats::sd(v) else NA_real_),
    .SDcols = .lagcols]
.MR[, Score := fifelse(is.finite(rm_sd) & rm_sd > 0, rm_mean / rm_sd, NA_real_)]

# ---- 5. 유동성 통과 결합 + decile N 산출 -----------------------------------
#   시그널일 = canonical RAWDATA 월말(.CAL[ym]). 유동성/시총은 그 월말 시점(PIT).
.MR <- merge(.MR, .CAL[, .(ym, SigDate = MEnd)], by = "ym")             # ym→canonical 월말
.LP2 <- .LP[, .(SigDate = MEnd, Ticker, LiqPass, Size)]
.MR <- merge(.MR, .LP2, by = c("Ticker", "SigDate"), all.x = TRUE)
SIG <- .MR[is.finite(Score) & LiqPass == TRUE, .(Date = SigDate, Ticker, Score)]

# decile = 각 형성월 유효 후보의 상위 10% (top decile, equal-weight). N 컬럼으로 엔진에 전달.
.NDT <- SIG[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
FACTORS <- merge(SIG, .NDT, by = "Date")
setorder(FACTORS, Date, -Score)

cat(sprintf("[fe_residmom · 논문스펙] FACTORS rows=%d | dates=%d | tickers=%d | decile N range=%d~%d | med=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            min(.NDT$N), max(.NDT$N), as.integer(median(.NDT$N))))

# 정리
rm(.RD, .MR, .FF, .LP, .LP2, .CAL, .allmo, .grid, .rng, .NDT, SIG); gc(verbose = FALSE)
