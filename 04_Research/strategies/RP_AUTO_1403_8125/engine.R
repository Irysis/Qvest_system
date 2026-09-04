# =============================================================================
# engine.R — RP_AUTO_1403_8125
# Jaehyung Choi, Sungsoo Choi, Wonseok Kang, "Maximum drawdown, recovery,
#   and momentum" (arXiv:1403.8125, q-fin.PM)   https://arxiv.org/abs/1403.8125
#
# ★fidelity = FAITHFUL (충실구현). 정본 = FIDELITY.json
#   이 논문은 판정순서 1(충실구현)이 그대로 성립한다. 신호(MDD/회복/누적)·종목선택
#   (10-decile)·방향(모멘텀 롱숏)·비중(EW)·형성/보유(6개월·6개월)·리밸(월간
#   오버래핑)이 전부 명시돼 있고, 무엇보다 **논문 자신이 KOSPI 200 을 시험 시장으로
#   쓴다**(원문: "KOSPI 200 ... 200 stocks in South Korea stock markets"). 유일한
#   변경은 지시된 유니버스 확장(KOSPI200 → K200∪KQ150) + 고정 유동성 하한뿐이다.
#
# ===== 원문 대조 (arxiv.org/html/1403.8125v1 — 전문 경로) =====
#   (A) 최대낙폭(MDD) — 로그수익 기반, 양의 크기:
#         MDD = -min_{τ∈(0,T)} ( min_{t∈(0,τ)} R(t,τ) ),  R = 로그수익
#       "The maximum drawdown is the worst successive loss among declines from
#        peaks to troughs during a given period." → 로그가격 경로의 peak→trough
#        최악 낙폭의 절댓값(양수).
#   (B) 회복(Recovery) R = R(t*, T): t* = 최대낙폭이 끝난 저점 시점, T = 형성창 말일.
#       저점→말일 **로그수익(부호 있음)**. 반등이면 R>0, 계속 하락이면 R<0.
#   (C) 누적수익(C): 형성창 전체 로그수익 = ln(P(T)/P(0)).
#   (D) 3-국면 분해 (원문): C = R_I + R_II + R_III = PP - MDD + R
#         R_I  (PP)  = 시작 → (낙폭 직전) peak 로그수익      [낙폭 전 상승]
#         R_II       = peak → trough(t*) 로그수익 = -MDD     [낙폭 국면, 음수]
#         R_III (R)  = trough(t*) → T 로그수익                [회복 국면]
#   (E) Table 1 — 7 규칙 = (R_I, R_II, R_III) 에 대한 가중치:
#         C   Cumulative return       (1,1,1)
#         M   MDD                     (0,1,0)
#         R   Recovery                (0,0,1)
#         RM  Recovery - MDD          (0,1,1)
#         CM  Cumulative - MDD        (1,2,1)   ← 본 엔진이 복제하는 규칙
#         CR  Cumulative + Recovery   (1,1,2)
#         CMR Cumulative - MDD + R    (1,2,2)
#       score = w_I·R_I + w_II·R_II + w_III·R_III.  R_II 가 이미 부호를 가지므로
#       (음수), "MDD 는 낮을수록 좋다(내림차순)" 규약이 부호로 자동 처리된다 —
#       score 오름차순 정렬 후 최상위 롱이면 그만이다(수동 부호 반전 불요, C13).
#       ▸ CM=(1,2,1) = R_I+2R_II+R_III = C + R_II = **C - MDD**. (첫 조회의
#         "C-2×MDD"는 국면 가중치 2 를 계수로 오독한 것 — Table 1 이 정본이다.)
#       ▸ CM 이 준거 규칙인 이유 = 논문의 헤드라인 결과다(내가 성과를 보고 고른 값이
#         아니다): "The best strategy is the momentum portfolio by the composite
#         rule of cumulative return and maximum drawdown" — KOSPI 200 월평균
#         1.433%(σ 7.036%) · S&P 500 도 CM 최우수. 트리아지의 'MDD 기반' 후보와도 일치.
#   (F) 방향 (원문): "assets ... are sorted in ascending order" · "group 1 is for
#       losers ... the last group is for the best performers" · "The winner group
#       is at long (short) position and the loser group is at short (long)
#       position." → **모멘텀(월간): 최상위 데실 롱 · 최하위 데실 숏.** (반대편
#       contrarian 은 주간 — 우리 축이 월간이라 모멘텀 분기를 복제한다.)
#   (G) 데실 수 (원문): "In the cases of the S&P 500 and KOSPI 200 universes,
#       numbers of groups are 10" → 10분위. 롱=10군(승자)·숏=1군(패자).
#   (H) 오버래핑 (원문): "The basic methodology ... is the momentum-style ...
#       portfolios given in Jegadeesh and Titman." · "After 6 months ... of the
#       holding period, each basket is liquidated. The portfolio is constructed at
#       the beginning of every month, i.e. it is the overlapping portfolio."
#       → J-T(1993) 오버래핑: 매월 형성, 6개월 보유, 임의 시점에 최근 6개 코호트를
#         동시 보유하고 월수익 = 6 바스켓 등가중 평균(1/K, K=6). 이 1/K 평균이
#         논문이 인용한 J-T 방법론 자체다(지어낸 값이 아니라 인용된 절차).
#   (I) 스킵 기간 없음 · 거래비용 명시 없음(gross 수익 보고 → commission_paper=null).
#   (J) 형성창 내부 표본주기(일별/주별)는 명시 없음 — 월간 모멘텀이므로 일별 로그가격
#       경로를 쓴다(표준 J-T 관행이자 MDD/회복이 의미를 갖는 최소 해상도).
#
# ===== 산출 형태 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏이므로 **반드시** 이 형태여야 한다.
#   FACTORS 로 내면 러너가 숏 다리를 버리고 롱온리 top-N 으로 재구성해 논문 전략이
#   아니게 된다. FIDELITY.json::portfolio_spec = {"construction":"engine_direct"}
#   (내가 만든 비중이 곧 논문 비중이다). Weight 는 부호 포함(롱 +, 숏 −),
#   코호트별 롱합 +1 / 숏합 −1 을 6 코호트에 걸쳐 1/K 평균 → 종목별로 상계(netting).
#
# ===== 논문 대비 변경 (FIDELITY.json::changed 와 동일) =====
#   유니버스만: KOSPI 200 → **K200 ∪ KQ150**(PIT 시변 멤버십) + adv20(t-1) ≥ 2e8.
#   그 결과 데실당 종목수가 ~20(KOSPI200 단독) → ~35(합집합)로 늘지만, 이는 '10분위
#   롱숏'이라는 논문 규칙의 산물이지 별도 변경이 아니다. 신호·데실 수·방향·EW·
#   6개월 형성/보유·오버래핑·월간 리밸은 전부 논문 그대로다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#   ▸ 구조 경계: 코호트(형성일 f)의 모든 창은 (me_dates[k-6], f] 로 잘리고 종점 = f
#     (월말 종가, f 시점 기지). 러너가 익 거래일에 집행하므로 신호창과 보유월의
#     교집합이 없다(동월 참조 원천 부재). 미래 방향 인덱싱·음수 shift 0건.
#   C1  : 전 표본 통계 0건. 누적/MDD/회복은 전부 6개월 창 **내부** 경로 통계.
#         횡단면 데실은 그 날짜 단면의 순위일 뿐 시계열 전표본 통계가 아니다.
#   C2  : same-day 순환참조 없음. f 종가까지만 쓰고 집행은 익 거래일(러너).
#   C3  : 같은 기간 집계→적용 없음. 형성창 종점(f) < 보유월 시작.
#   C4  : 재무 패널 미사용(가격/거래대금만).
#   C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#   C6  : 유니버스 = 각 f 의 K200/KQ150 멤버십(PIT 시변). 미래 명부 주입 없음.
#         창 커버리지 요건은 과거 데이터 요건이라 생존편의를 만들지 않는다.
#   C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#   C9  : DD/VT 오버레이 미사용(여기 낙폭은 신호 산출용 과거창 통계이지 실현낙폭
#         스케일러가 아니다 — C9 의 same-day DD 소비와 무관).
#   C10 : 유동성 = f **직전 20 거래일** 평균 거래대금(frollmean 후 shift(1) → 당일 배제).
#   C11 : 외부 매크로 미사용.
#   C13 : 부호 조작 없음. 방향은 논문이 정한 곳에서만 정해진다 — (1) score 오름차순
#         (2) 최상위 데실 롱/최하위 숏(원문 명시). NEGATE/FLIP 0건.
#   C15 : Factor DB parquet 직접 load 0건. 신호는 RAWDATA 가격/거래대금에서만 산출.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_1403_8125] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 상수 — 논문에서 온 것 / 지시 축에서 온 것 / 데이터 무결성 하한
# =============================================================================
# ▸ 논문에서 온 것 (Table 1 · 방법론) — 이 엔진의 논문 유래 파라미터 전부
.W       <- c(1, 2, 1)     # CM 규칙 = (R_I, R_II, R_III) 가중치 (Table 1) = C - MDD
.FORM_M  <- 6L             # 형성창 = 6개월 (월말 격자 6스텝)
.HOLD    <- 6L             # 보유 = 6개월 (J-T 오버래핑: 동시 보유 코호트 수 K)
.NDEC    <- 10L            # 10-decile (원문 "numbers of groups are 10")
# ▸ 지시 축(도훈 고정)에서 온 것
.LIQ     <- 2e8            # adv20(t-1) 하한 (KRW)
.LIQ_WIN <- 20L            # 유동성 창 (거래일)
.START   <- as.Date("2005-01-01")
# ▸ 데이터 무결성 하한 — 전략 파라미터가 아니다(성과를 보고 고른 값이 아니다)
.DCAP    <- log(3)         # 일별(연속 거래일) 로그수익 절단 = 데이터 아티팩트 가드.
                           #   KRX 가격제한폭은 ±15%(2015-06 이전)/±30%(이후)라 한
                           #   관측(연속 거래일)의 |로그수익| > log(3)(≈+200%/-67%)은
                           #   물리적으로 불가능한 값 = 수정주가 보정 실패의 지문이다.
                           #   MDD 는 단일 오손 프린트가 순위를 지배할 수 있어(가짜
                           #   낙폭/가짜 회복) 절단으로 방어한다(윈저 아닌 무결성 가드).
.COV     <- 0.80           # 창 커버리지 하한 = 창 거래일의 80%. 거래정지 며칠로 6개월
                           #   이력이 통째로 버려지는 것을 막는 자리(전략 파라미터 아님).
.NMIN    <- 30L            # 데실이 의미를 갖는 최소 횡단면 (n_dec >= 3 보장)

# ---- 6개월 창 로그가격 경로 → 누적/MDD/3-국면 (창 내부 통계만, C1) ----
#   cl = 형성창 내 그 종목의 거래일 종가(Date 오름차순). path[1]=0, path[n]=C.
#   R_II = path[trough] - path[peak] = -MDD 이므로 CM(1,2,1) score = C - MDD 로 귀결.
.mdd_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L) return(list(C = NA_real_, MDD = NA_real_,
                          RI = NA_real_, RII = NA_real_, RIII = NA_real_))
  lp <- log(cl)
  d  <- diff(lp)
  d[d >  .DCAP] <-  .DCAP                 # 아티팩트 가드 (대칭 ±log(3))
  d[d < -.DCAP] <- -.DCAP
  path <- c(0, cumsum(d))                 # 상대 로그가격 (종점 = f 시점 누적수익 C)
  pk   <- cummax(path)
  dd   <- path - pk                       # <= 0
  ts   <- which.min(dd)                   # trough(t*) — 첫 argmin
  mdd  <- -dd[ts]                         # >= 0
  tp   <- which.max(path[seq_len(ts)])    # trough 이전(포함) peak
  list(C    = path[n],
       MDD  = mdd,
       RI   = path[tp],                   # path[1] = 0
       RII  = path[ts] - path[tp],        # = -MDD
       RIII = path[n]  - path[ts])
}

# =============================================================================
# 1. 패널 준비 (RAWDATA 비파괴) + 유동성 adv20(t-1)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd <- unique(.rd, by = c("Ticker", "Date"))
setorder(.rd, Ticker, Date)

# 거래대금(결측 거래량 = 그날 거래 없음 = 0 회전). adv20 후 shift(1) → t-1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]

# 월말 거래일 격자 (전 종목 통합 마지막 거래일)
.rd[, ym := year(Date) * 12L + month(Date)]
.me_dates <- sort(.rd[, .(f = max(Date)), by = ym]$f)
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date)

cat(sprintf("[RP_1403_8125] 패널 %s행 · %s~%s · 월말 %d개\n",
            format(nrow(.rd), big.mark = ","),
            as.character(min(.all_dates)), as.character(max(.all_dates)),
            length(.me_dates)))

# =============================================================================
# 2. 코호트 — 각 형성일 f 에서 CM-score 데실 롱숏 (EW, 코호트별 롱합+1/숏합-1)
# =============================================================================
.cohorts <- vector("list", length(.me_dates))
.diag    <- vector("list", length(.me_dates))
for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) next                              # me_dates[k-6] 필요
  f  <- .me_dates[k]
  w0 <- .me_dates[k - .FORM_M]
  wdates <- .all_dates[.all_dates > w0 & .all_dates <= f]   # 6개월 일별 격자 (종점 = f)
  n_win  <- length(wdates)
  if (n_win < 40L) next

  # 자격: f 의 K200/KQ150 멤버십 + adv20(t-1) 하한 (C6·C10)
  rf   <- .rd[.(f), .(Ticker, K200, KQ150, ADV20_L1), nomatch = 0L]
  elig <- rf[(.tru(K200) | .tru(KQ150)) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (length(elig) < .NMIN) next

  wd <- .rd[.(wdates), .(Date, Ticker, Close), nomatch = 0L]
  wd <- wd[Ticker %chin% elig]
  setorder(wd, Ticker, Date)                          # 그룹 내 Date 오름차순 보장
  cnt  <- wd[, .N, by = Ticker]
  keep <- cnt[N >= ceiling(.COV * n_win), Ticker]     # 커버리지 하한
  if (length(keep) < .NMIN) next
  wd <- wd[Ticker %chin% keep]

  st <- wd[, .mdd_stats(Close), by = Ticker]          # 창 내부 경로 통계
  st[, score := .W[1] * RI + .W[2] * RII + .W[3] * RIII]   # CM = C - MDD
  st <- st[is.finite(score)]
  N  <- nrow(st)
  if (N < .NMIN) next
  n_dec <- N %/% .NDEC
  if (n_dec < 1L) next

  setorder(st, score)                                 # 오름차순: 패자 앞, 승자 뒤
  short_tk <- st$Ticker[seq_len(n_dec)]               # 최하위 데실 = 숏 (원문)
  long_tk  <- st$Ticker[(N - n_dec + 1L):N]           # 최상위 데실 = 롱 (원문)

  .cohorts[[k]] <- rbindlist(list(
    data.table(Ticker = long_tk,  w =  1 / n_dec),    # 롱 EW (합 +1)
    data.table(Ticker = short_tk, w = -1 / n_dec)))   # 숏 EW (합 -1)
  .diag[[k]] <- data.table(f = f, N = N, n_dec = n_dec,
                           mdd_med = median(st$MDD), C_med = median(st$C))
}

# =============================================================================
# 3. 오버래핑 블렌드 — 최근 K=6 코호트 1/K 평균 (J-T), 종목별 상계 → 부호로 Leg
# =============================================================================
.out <- vector("list", length(.me_dates))
for (k in seq_along(.me_dates)) {
  f <- .me_dates[k]
  if (f < .START) next
  idx <- (k - .HOLD + 1L):k
  idx <- idx[idx >= 1L]
  chs <- Filter(Negate(is.null), .cohorts[idx])
  nc  <- length(chs)
  if (nc < 1L) next
  agg <- rbindlist(chs)[, .(w = sum(w) / nc), by = Ticker]   # 1/K 평균 (K = nc)
  agg <- agg[is.finite(w) & abs(w) > 1e-12]
  if (!nrow(agg)) next
  agg[, Leg := fifelse(w > 0, "long", "short")]
  .out[[k]] <- data.table(Date = f, Ticker = agg$Ticker, Weight = agg$w, Leg = agg$Leg)
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_1403_8125] PORTFOLIO 0행 — 유니버스/창/커버리지 확인")
setorder(PORTFOLIO, Date, -Weight)

# =============================================================================
# 4. 보고 (성과 수치 선언 아님 — 구성 요약. 등급은 계약이 낸다)
# =============================================================================
.dg <- rbindlist(Filter(Negate(is.null), .diag), use.names = TRUE)
.byleg <- PORTFOLIO[, .(n = uniqueN(Ticker)), by = Leg]
.pm <- PORTFOLIO[, .(nL = sum(Leg == "long"), nS = sum(Leg == "short"),
                     gL = sum(Weight[Weight > 0]), gS = sum(Weight[Weight < 0])),
                 by = Date]
cat(sprintf(paste0(
  "[RP_1403_8125] faithful: CM 규칙(1,2,1)=C-MDD · 10-decile 롱숏 EW · ",
  "6mo 형성/보유 J-T 오버래핑(K=%d) · 월간\n",
  "  코호트 %d개(형성 %s~%s) · 데실당 종목 중앙 %d · 창내 MDD 중앙 %.1f%% · C 중앙 %.1f%%\n",
  "  PORTFOLIO %s행 · %d개월 %s~%s · 월평균 롱 %.0f/숏 %.0f종 · 그로스 롱 %.2f/숏 %.2f\n",
  "  ★engine_direct(부호 포함 비중이 곧 논문 비중) · commission_paper=null(논문 gross) · %.1f분\n"),
  .HOLD,
  nrow(.dg), as.character(min(.dg$f)), as.character(max(.dg$f)),
  as.integer(median(.dg$n_dec)), 100 * median(.dg$mdd_med), 100 * median(.dg$C_med),
  format(nrow(PORTFOLIO), big.mark = ","), uniqueN(PORTFOLIO$Date),
  as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  mean(.pm$nL), mean(.pm$nS), mean(.pm$gL), mean(.pm$gS),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
