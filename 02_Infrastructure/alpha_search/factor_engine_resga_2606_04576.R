# =============================================================================
# factor_engine_resga_2606_04576.R
# "ReSGA: A Large Tail Risk Model for Learning Value-at-Risk and Expected
#  Shortfall" (arXiv 2606.04576) — KR(KOSPI200∪KOSDAQ150) faithful 복제
# =============================================================================
# 논문 Eq.(11)의 size × tail-risk *상호작용* 신호를 그대로 구현한다.
#   alpha_{i,t} = (logCap_{i,t} - 횡단면평균 logCap_t) * (1 - exp(ES_hat_{i,t}))
# - logCap = log(시가총액 Size). 횡단면평균은 신호월 t 의 거래대상 유니버스
#   (KOSPI200∪KOSDAQ150 멤버 ∩ 유동성통과) 단면에서만 계산(전체표본 X · PIT).
# - ES_hat_{i,t} = 직전 252 거래일 일별수익(Ret) 하위 5% 평균(음수). 우리 registry
#   R03_CVaR_95 의 pre-negate(음수) 입력과 동일 정의. 역사적 ES(historical CVaR).
#     ES 음수 → exp(ES_hat) ∈ (0,1] → (1 - exp(ES_hat)) ≥ 0, 꼬리위험 클수록 ↑.
# - 신호 = alpha 횡단면 정렬. 논문 long leg(P1) = 대형주 × 고꼬리위험("too-big-
#   to-fail" 매수측, demeaned logCap>0 ∧ 고 tail) = alpha 상위. long-only top-25 EW.
#
# 부호 방향: 논문은 US 에서 P1(고 alpha) 매수가 유효하나 中·日서 역전된다고 보고
#   → KR 재검증 위해 두 방향 분리(IMPL_SPEC "부호 empirical 양방향" 충실).
#     RESGA_DIRECTION="POS"  (기본) → Score = +alpha  (논문 US 주명세, P1 롱)
#     RESGA_DIRECTION="NEG"          → Score = -alpha  (반대; 소형×고꼬리 롱)
#   임의 부호반전(C13 NEGATE)이 아니라 논문이 명시한 시장의존 방향가설(문서화).
#
# ── PIT (lookahead_detector + C1~C15) ──
#  - ES_hat: 신호날짜(월말) 시점 직전 252 거래일만 사용(전부 과거) → C1/C2 무위반.
#  - logCap: 신호날짜 Size(관측가능). 횡단면평균은 단면(per-date) 집계만 — 전체표본
#    통계 아님(C1 비위반). scale()/전역 quantile/fwd_ret 없음.
#  - 포지션은 run_monthly_simulation 이 다음 달 보유(t+1) → 수익 대비 t-1 PIT 충족.
#  - 수동 부호반전(NEGATE/FLIP) 아님 — 시장의존 방향가설(C13 비위반).
#
# RAWDATA columns: Date, Ticker, Close, Vol, Size, Ret, K200, KQ150, LiqPass, ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Ret", "Size", "K200", "KQ150") %in% names(RAWDATA)))
setorder(RAWDATA, Ticker, Date)

# ---- 방향 선택 (POS: 논문 US 주명세 P1 롱 / NEG: 반대 방향) ----
.DIR <- toupper(Sys.getenv("RESGA_DIRECTION", "POS"))
if (!.DIR %in% c("POS", "NEG")) .DIR <- "POS"

# ---- 파라미터 ----
.ES_WIN     <- 252L     # 직전 거래일 수 (논문 ES forecaster lookback ≈ 1yr daily)
.ES_TAIL    <- 0.05     # 하위 5% (ES_95 / CVaR_95)
.ES_MIN_OBS <- 200L     # 윈도 내 최소 거래일(>=200/252) — tail 추정 신뢰
.MIN_NAMES  <- 10L      # 단면 demean 최소 종목수

# ---- 신호 시작 하한(전기간 표준 2005, ES 252d 룩백 위해 base는 2004부터) ----
#   run_alpha_search가 FACTORS를 start_date(기본 2005-01-01)로 후필터하므로
#   2005-01 시그널의 직전 252거래일(~2004-01~)만 있으면 충분 → 1990s 무의미 연산 제거.
.SIG_FROM  <- as.Date(Sys.getenv("RESGA_SIG_FROM",  "2004-06-01"))  # 시그널 산출 하한
.BASE_FROM <- .SIG_FROM - 420L                                       # ES 룩백 base 하한

# ---- ES base: 필요한 컬럼/기간만 단일 사본(메모리·세그폴트 위험 축소) ----
.base <- RAWDATA[Date >= .BASE_FROM & is.finite(Ret), .(Ticker, Date, Ret)]
setorder(.base, Ticker, Date)

# ---- 신호월(month-end) 시그널 날짜 목록 (.SIG_FROM 이상만) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[Date >= .SIG_FROM, .(Date = max(Date)), by = .ym]
me_dates <- sort(.me$Date)

# ---- 신호날짜별 거래대상 유니버스(K200∪KQ150 멤버 ∩ 유동성) + logCap ----
.has_liq <- "LiqPass" %in% names(RAWDATA)
.uni <- RAWDATA[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(Size) & Size > 0]
if (.has_liq) .uni <- .uni[LiqPass == TRUE]
.uni <- .uni[, .(Date, Ticker, Size)]
.uni[, logcap := log(Size)]

# ---- ES_hat: 신호날짜별 직전 252 거래일 일별수익 하위5% 평균(음수) ----
#   month-end 마다 직전 ~14개월 캘린더 윈도 → 종목별 최근 252 거래행만 사용.
es_list <- vector("list", length(me_dates))
for (k in seq_along(me_dates)) {
  me <- me_dates[k]
  lo <- me - 420L   # 캘린더 420일 ⊃ 252 거래일(여유). 이후 종목별 최근 252행 절단.
  win <- .base[Date > lo & Date <= me, .(Ticker, Date, Ret)]
  if (!nrow(win)) next
  win[, .ntk := .N, by = Ticker]
  win[, .idx := seq_len(.N), by = Ticker]
  win <- win[.idx > .ntk - .ES_WIN]                 # 종목별 최근 252 거래일만
  es <- win[, .(n_es = .N,
                ES = {
                  q <- as.numeric(quantile(Ret, .ES_TAIL, type = 7L, names = FALSE))
                  tail_obs <- Ret[Ret <= q]
                  if (length(tail_obs)) mean(tail_obs) else NA_real_
                }), by = Ticker]
  es <- es[n_es >= .ES_MIN_OBS & is.finite(ES)]
  if (!nrow(es)) next
  es[, Date := me]
  es_list[[k]] <- es[, .(Date, Ticker, ES)]
  if (k %% 40L == 0L) { cat(sprintf("[fe_resga] ES loop %d/%d (%s)\n", k, length(me_dates), me)); flush.console() }
}
ES_DT <- rbindlist(es_list, use.names = TRUE, fill = TRUE)
rm(.base); gc(verbose = FALSE)
stopifnot(nrow(ES_DT) > 0)

# ---- merge(유니버스 단면 logCap, ES) → alpha = demeaned logCap × (1-exp(ES)) ----
SIG <- merge(.uni, ES_DT, by = c("Date", "Ticker"), all.x = FALSE)
# 단면 demean(per signal date) — 거래대상 유니버스 내에서만, 종목수 충분할 때만
SIG[, .nd := .N, by = Date]
SIG <- SIG[.nd >= .MIN_NAMES]
SIG[, logcap_dm := logcap - mean(logcap), by = Date]
SIG[, tail_load := 1 - exp(ES)]                       # ES<0 → (0,1], 꼬리위험 ↑일수록 ↑
SIG[, alpha := logcap_dm * tail_load]

# ---- Score: 방향별 alpha 정렬 ----
if (.DIR == "POS") {
  SIG[, Score := alpha]    # 논문 US 주명세: P1(대형×고꼬리) 롱
} else {
  SIG[, Score := -alpha]   # 반대 방향(소형×고꼬리 롱)
}

FACTORS <- unique(SIG[is.finite(Score), .(Date, Ticker, Score)])

# ---- 정리 ----
RAWDATA[, .ym := NULL]

cat(sprintf("[fe_resga 2606.04576] direction=%s | FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            .DIR, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
