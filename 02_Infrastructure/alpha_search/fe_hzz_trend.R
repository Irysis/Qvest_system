# Trend Factor — Han, Zhou & Zhu (2016, JFE 122:352-375) 논문 원본 스펙 (KR long-only 적응)
# =============================================================================
# 원문 확보: HZZ(2016) JFE 전문 PDF(ssrn 2182667) jina/WebFetch 로컬추출(pymupdf) — 식 (1)~(5) 정확 인용.
#
# 논문 정확 방법론 (price-only trend; volume trend은 China 확장판이라 원본 미포함):
#   식(1) MA price (월말 거래일 d 기준, lag L일):
#     A_{j,t,L} = mean( P_{j,d-L+1}, ..., P_{j,d-1}, P_{j,d} ) / L
#   식(2) 정규화 (현재가로 나눠 정상화 + 고가주 영향 완화):
#     Ã_{j,t,L} = A_{j,t,L} / P_{j,d}
#   식(3) 1단계 월간 횡단면 OLS (return_t on signals@t-1):
#     r_{j,t} = β0_t + Σ_i β_{i,t} · Ã_{j,t-1,L_i} + ε_{j,t}     (월별 β_{i,t} 시계열)
#   식(4) 2단계 기대수익 예측 (절편 제외 — 횡단면 랭킹에 무관):
#     E[r_{j,t+1}] = Σ_i E[β_{i,t+1}] · Ã_{j,t,L_i}
#   식(5) 계수 예측 = 직전 12개월 β 평균 (rolling 12m mean — 논문 baseline ER12):
#     E[β_{i,t+1}] = (1/12) Σ_{m=1}^{12} β_{i,t+1-m}
#   포트: E[r] 기준 5분위(quintile) 정렬, equal-weight, 월간 리밸런싱. 최상위 분위 매수.
#
#   ★ lag set L (원본 baseline, 11개): 3, 5, 10, 20, 50, 100, 200, 400, 600, 800, 1000 (일).
#     (논문: "MAs of lag lengths 3-,5-,10-,20-,50-,100-,200-days. In addition, 400-,600-,800-,1000-days.")
#   ★ burn-in: 첫 1000일 + 12개월 skip (논문 명시 — 1000d MA 형성 + 12m β평균 형성).
#
#   ★ 롱숏 불허 (도훈 mandate 2026-06-11): 논문은 L/S(Q5−Q1)이나 검증 단계 포함 전면 long-only.
#     → top quintile(Q5, E[r] 최상위 20%) long-only equal-weight로 사상. Q1 short leg 사상(드롭).
#     L/S 스프레드 수치는 판정 근거 사용 금지. (본 엔진은 long leg만 산출 — Q5만 FACTORS.)
#
# KR 적응 (논문 미명시·시스템표준 보충 — 명시):
#   - 유니버스: K200∪KQ150 (시변 PIT 멤버십). 논문 NYSE/AMEX/Nasdaq → KR 실투 유니버스 고정(mandate).
#   - 가격필터 $5 → KR 부적용(유동성 2e8 KRW로 대체, 시스템표준). 사이즈필터(최소decile 제외) → KR
#     K200∪KQ150 자체가 대형·중형 한정이라 사이즈 floor 내재(논문 의도 정합) — 추가 제외 미적용.
#   - WLS(1단계 분산역수 가중)는 논문 robustness(Table12)일 뿐 baseline은 OLS → OLS 채택.
#
# PIT (C1~C15):
#   - 식(3): r_t를 Ã_{t-1}(직전월말 신호)에 회귀 — 신호는 t-1 정보만(C2 회피, 논문 명시 "only info in month t or prior").
#   - 식(5): E[β_{t+1}]은 직전 12개월 β 평균 — t시점 β까지만(forward 없음, expanding/rolling). C1 회피.
#   - 식(4): E[r_{t+1}]에 쓰는 Ã_{j,t,L}은 t월말 종가 기준 — t시점 정보. 시그널일=t월말, 적용=t+1월.
#   - MA price는 d(월말)까지 일간 종가만 (shift/rolling, 미래가 없음). 자체 부호반전(NEGATE/FLIP) 없음.
#   - 자체합성 없음 — 월간수익은 종목 일간 Ret 월내 복리집계(자산수익 aggregation), 포트 NAV는 백엔드(Return.portfolio).
# =============================================================================
suppressMessages({ library(data.table) })
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 0. 파라미터 (논문 baseline) -------------------------------------------
.HZZ_LAGS  <- c(3L, 5L, 10L, 20L, 50L, 100L, 200L, 400L, 600L, 800L, 1000L)  # 식 lag set L
.HZZ_BETAW <- 12L     # 식(5) 계수평균 윈도우 (직전 12개월)
.HZZ_NQ    <- 5L      # 분위 수 (quintile)
.LIQ_THRESH <- 2e8    # KR 유동성 floor (시스템표준 — $5 가격필터 대체)
.LIQ_WIN    <- 20L

# ---- 1. 월말 거래일 캘린더 (canonical 유니버스 월말) ------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.CAL <- RAWDATA[, .(MEnd = max(Date)), by = .ym]      # 월별 유니버스 월말 거래일 d
setorder(.CAL, MEnd); .CAL[, ord := seq_len(.N)]      # 월 순서 인덱스(달력 정합)

# ---- 2. 종목별 일간 종가 grid + 유동성/멤버십/시총 (월말 PIT) ---------------
#   MA는 일간 종가의 후행평균. 거래정지/결측은 그 종목 시계열에서 자연스레 빠짐(연속 거래일 기준 L일).
#   ★ 논문 식(1) "P_{d-L+1..d}"는 거래일 기준 L개. KR 일간 grid도 거래일 기준 — 정합.
RAWDATA[, .tv := Close * Vol]
RAWDATA[, .adv := shift(frollmean(.tv, .LIQ_WIN, align = "right"), 1L), by = Ticker]  # t-1 PIT 유동성

# 월말 시점 멤버십·유동성·시총 (시그널 형성 PIT 기준)
.MMETA <- RAWDATA[Date %in% .CAL$MEnd,
                  .(MEnd = Date, Ticker, Close_me = Close, Size,
                    K200, KQ150, adv = .adv)]
.MMETA <- merge(.MMETA, .CAL[, .(MEnd, ym = .ym, ord)], by = "MEnd")
.MMETA[, in_univ := (K200 %in% c(TRUE, 1)) | (KQ150 %in% c(TRUE, 1))]
.MMETA[, liq_ok  := is.finite(adv) & adv >= .LIQ_THRESH]

# ---- 3. 정규화 MA 신호 Ã_{j,t,L} (월말 d 기준, 식 1·2) ----------------------
#   각 종목 일간 종가 시계열에서, 각 월말 d에 대해 후행 L거래일 평균 / 종가.
#   frollmean(align="right")로 일간 후행평균 → 월말일만 추출. (PIT: d까지 종가만.)
.PX <- RAWDATA[is.finite(Close) & Close > 0, .(Date, Ticker, Close)]
setorder(.PX, Ticker, Date)
for (L in .HZZ_LAGS) {
  cn <- paste0("ma", L)
  .PX[, (cn) := frollmean(Close, L, align = "right"), by = Ticker]   # A_{t,L} = MA price (일간)
}
# 월말일만 보존 + 정규화 Ã = MA/Close
.SIG <- .PX[Date %in% .CAL$MEnd]
for (L in .HZZ_LAGS) {
  ma <- paste0("ma", L); a <- paste0("A", L)
  .SIG[, (a) := get(ma) / Close]    # 식(2) 정규화 (현재 종가로 나눔)
}
.acols <- paste0("A", .HZZ_LAGS)
.SIG <- merge(.SIG[, c("Date", "Ticker", .acols), with = FALSE],
              .CAL[, .(Date = MEnd, ym = .ym, ord)], by = "Date")
setnames(.SIG, "Date", "MEnd")    # .SIG: 형성월 t 월말 신호. ord = 형성월 ordinal.

# ---- 4. 종목 월간 실현수익 r_{j,t} (일간 Ret 월내 복리집계 — 자산수익) ------
#   수익월 ym → ord (캘린더 ordinal) 부착.
.MR <- RAWDATA[is.finite(Ret), .(MRet = prod(1 + Ret) - 1), by = .(Ticker, ym = .ym)]
.MR <- merge(.MR, .CAL[, .(ym = .ym, ret_ord = ord)], by = "ym")

# ---- 5. 1단계 월간 횡단면 OLS (식 3): r_t ~ Ã_{t-1}  → β_{i,t} -------------
#   각 월 t: 종목별 (실현수익 r_{j,t}) 를 (직전월말 t-1 정규화신호 Ã_{j,t-1,L}) 에 OLS.
#   ★ 신호 lag: 신호 ord = t-1, 수익 ord = t. → 신호의 ord_next = ord+1 = 수익월 ord.
#   β_{i,t} 시계열 산출. 절편 포함(식 3 β0_t). 회귀표본 = 그 달 유효종목(유동성·멤버십 통과).
#   유동성·멤버십은 신호 형성 월말(t-1, = 신호 ord) 기준 PIT — .SIG에 직접 결합.
.SIGM <- merge(.SIG, .MMETA[, .(Ticker, ord, in_univ, liq_ok)], by = c("Ticker", "ord"))
.SIGM <- .SIGM[in_univ == TRUE & liq_ok == TRUE]
.SIGM[, ret_ord := ord + 1L]                       # 신호@ord → 수익@ord+1
.REG <- merge(.SIGM[, c("Ticker", "ret_ord", .acols), with = FALSE],
              .MR[, .(Ticker, ret_ord, MRet)], by = c("Ticker", "ret_ord"))
.REG <- .REG[stats::complete.cases(.REG[, .acols, with = FALSE]) & is.finite(MRet)]

.reg_months <- sort(unique(.REG$ret_ord))
.fml <- stats::as.formula(paste("MRet ~", paste(.acols, collapse = " + ")))
.beta_list <- vector("list", length(.reg_months))
for (k in seq_along(.reg_months)) {
  m <- .reg_months[k]
  sub <- .REG[ret_ord == m]
  if (nrow(sub) < (length(.acols) + 10L)) next   # 회귀 안정성: 변수수+10 이상
  fit <- tryCatch(stats::lm(.fml, data = sub), error = function(e) NULL)
  if (is.null(fit)) next
  cf <- coef(fit)               # (Intercept) + A3..A1000
  bt <- data.table(ret_ord = m)            # 이 β는 수익월 m에 대응(신호 m-1)
  for (a in .acols) bt[[a]] <- if (a %in% names(cf) && is.finite(cf[[a]])) cf[[a]] else NA_real_
  .beta_list[[k]] <- bt
}
.BETA <- rbindlist(Filter(Negate(is.null), .beta_list), use.names = TRUE)
setorder(.BETA, ret_ord)

# ---- 6. 식(5) E[β_{t+1}] = 직전 12개월 β 평균 ------------------------------
#   β_{i,t} (ret_ord = t) 의 직전 12개 평균으로 E[β_{i,t+1}] 예측 → 형성월 t에 적용.
#   ★ E[β]는 "ret_ord 1..t"의 마지막 12개 평균 → 형성월 t(= 신호월) 기대계수. PIT: t까지 β만.
#   rolling mean(k=12, align=right)로 각 ret_ord t에서 [t-11..t] β평균. 이 E[β]를 "형성월 t"라벨.
.EBETA <- copy(.BETA)
for (a in .acols) .EBETA[, (a) := frollmean(get(a), .HZZ_BETAW, align = "right")]
#   E[β@형성월 t] 는 ret_ord=t (신호월 t-1의 수익) 까지의 β 평균. 형성월 t에서 t+1 예측에 사용.
#   형성월(신호 ord) = ret_ord (수익월 라벨) — E[r_{t+1}]은 형성월 t 신호 Ã_{t}에 E[β]를 곱(식4).
#   따라서 E[β@form_ord = ret_ord] (수익월 t = 형성월 t, 동일 ord에서 신호 Ã_{t} 사용).
setnames(.EBETA, "ret_ord", "form_ord")
.EBETA <- .EBETA[stats::complete.cases(.EBETA[, .acols, with = FALSE])]

# ---- 7. 식(4) E[r_{j,t+1}] = Σ E[β_{i,t+1}]·Ã_{j,t,L} (형성월 t 신호) -------
#   형성월 t (ord = form_ord) 의 종목별 정규화신호 Ã_{j,t,L} (= .SIG[ord==form_ord]).
#   E[r] = Σ_L E[β_L] · Ã_{j,t,L}. 절편 제외(랭킹 무관). 시그널일 = 형성월 t 월말 → t+1 적용.
.SIGF <- .SIG[, c("Ticker", "ord", .acols), with = FALSE]
setnames(.SIGF, "ord", "form_ord")
# 유동성·멤버십 통과 종목만 (형성월 t 월말 PIT)
.SIGF <- merge(.SIGF, .MMETA[, .(Ticker, form_ord = ord, in_univ, liq_ok, SigDate = MEnd)],
               by = c("Ticker", "form_ord"))
.SIGF <- .SIGF[in_univ == TRUE & liq_ok == TRUE]
.SIGF <- .SIGF[stats::complete.cases(.SIGF[, .acols, with = FALSE])]

# E[β] join (형성월 동일 ord) → 종목별  Er = Σ Ã·E[β]
.ER <- merge(.SIGF, .EBETA, by = "form_ord", suffixes = c("", ".b"))
.bcols <- paste0(.acols, ".b")
.ER[, Er := rowSums(as.matrix(.SD[, .acols, with = FALSE]) *
                    as.matrix(.SD[, .bcols, with = FALSE])), .SDcols = c(.acols, .bcols)]
SIGOUT <- .ER[is.finite(Er), .(Date = SigDate, Ticker, Score = Er)]

# ---- 8. top quintile(Q5) long-only — N 컬럼으로 엔진에 전달 -----------------
#   각 형성월 유효 후보의 상위 20%(quintile) = N. equal-weight(weight_method="equal"), 월간 리밸.
#   ★ L/S(Q5−Q1) 사상 → Q5 long-only only (도훈 mandate). Score 높을수록 매수(부호 반전 없음).
.NDT <- SIGOUT[, .(N = as.integer(pmax(1L, round(.N / .HZZ_NQ)))), by = Date]
FACTORS <- merge(SIGOUT, .NDT, by = "Date")
setorder(FACTORS, Date, -Score)

cat(sprintf("[fe_hzz_trend · 논문스펙] FACTORS rows=%d | 신호월=%d | 종목=%d | β추정월=%d | quintile N=%d~%d med=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            nrow(.BETA), min(.NDT$N), max(.NDT$N), as.integer(median(.NDT$N))))

# 정리
RAWDATA[, c(".ym", ".tv", ".adv") := NULL]
rm(.PX, .SIG, .SIGM, .SIGF, .MR, .REG, .BETA, .EBETA, .ER, .MMETA, .CAL, .NDT, SIGOUT,
   .beta_list, .acols, .bcols); gc(verbose = FALSE)
