# =============================================================================
# engine.R — RP_AUTO_1403_8125
# Jaehyung Choi, Sungsoo Choi, Wonseok Kang, "Maximum drawdown, recovery,
#   and momentum" (arXiv:1403.8125, q-fin.PM)   https://arxiv.org/abs/1403.8125
# 원문 전문 경로: arxiv.org/html/1403.8125v1  (§3.1 data · §3.2 methodology · Table 1)
#
# ★fidelity = FAITHFUL. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#
# ===== 원문 대조 (§3.2 · Table 1 · 식(1)(2)) =====
#   (A) MDD — 식(1) MDD = max_τ ( max_{t<τ} ( P(t) - P(τ) ) )   [로그가격]
#             식(2) MDD = -min_τ ( min_{t<τ} R(t,τ) )           [로그수익, 양의 크기]
#       → 로그가격 경로의 peak→trough 최악 낙폭의 절댓값. **경로에 어떤 처리도 없다.**
#   (B) 회복 R = R(t*, T), t* = "the moment for the end of the maximum drawdown
#       formation"(= 최대낙폭 저점), T = 형성창 말일. 저점→말일 로그수익(부호 있음).
#   (C) 3-국면 분해 (원문): C = R_I + R_II + R_III = PP - MDD + R
#         R_I  (PP)  = 시작 → peak 로그수익        [낙폭 전 상승]
#         R_II       = peak → trough 로그수익 = -MDD   [낙폭 국면, ≤0]
#         R_III (R)  = trough → T 로그수익          [회복 국면, 부호 있음]
#   (D) Table 1 — 7 규칙 = (R_I, R_II, R_III) 가중치:
#         C(1,1,1) · M(0,1,0) · R(0,0,1) · RM(0,1,1) · CM(1,2,1) ·
#         CR(1,1,2) · CMR(1,2,2).   score = w_I·R_I + w_II·R_II + w_III·R_III.
#       ▸ 본 엔진 = **CM = (1,2,1) = C + R_II = C - MDD** (Table 1 표기 "Cumulative
#         return-MDD" 와 산술 일치). CM 을 고른 근거는 논문의 헤드라인 결과다(내가
#         성과를 보고 고른 값이 아니다): "The best strategy is the momentum portfolio
#         by the composite rule of cumulative return and maximum drawdown" —
#         KOSPI 200 월평균 1.433%(σ 7.036%). 트리아지 후보('MDD 기반')와도 일치.
#   (E) 정렬·방향 (원문 §3.2): "assets in market universes are sorted in ascending
#       order ... most criteria will be used in increasing order **except for the
#       maximum drawdown**" · "The group 1 is for losers ... the last group is for
#       the best performers" · "The winner group is at long (short) position and the
#       loser group is at short (long) position."
#       → 오름차순 · 최상위 데실 롱 · 최하위 데실 숏(월간 = 모멘텀 분기).
#       ▸ "except for the maximum drawdown" 는 **부호로 자동 처리**된다: R_II 가 이미
#         -MDD(음수)라 큰 MDD = 낮은 score = group 1(패자). 수동 부호반전 0건(C13).
#   (F) 그룹 수 (원문): "In the cases of the S&P 500 and KOSPI 200 universes,
#       numbers of groups are 10" → 10-decile.  비중: "Each group is constructed as
#       an equal-weighted portfolio" → EW.
#   (G) 형성/보유/리밸 (원문): "during 6 months (weeks) of estimation period" ·
#       "After 6 months (weeks) of the holding period, each basket is liquidated.
#        The portfolio is constructed at the beginning of every month, i.e. it is
#        the overlapping portfolio." + J-T(1993) 인용
#       → J = 6개월 · K = 6개월 · **스킵 기간 없음** · 월간 오버래핑 · 1/K = 1/6.
#         (J,K) 다중 조합 표는 원문에 없다 — 단일 6/6.
#   (H) 거래비용: 원문 전체에 비용 공제 없음(잠재적 설명 목록의 참조 1건뿐) →
#       gross. FIDELITY::commission_paper = null.
#
# ===== 원문이 침묵하는 곳 (지어내지 않고 FIDELITY.changed 에 선언) =====
#   ▸ 형성창 내부 표본주기(일별/주별/월별) 미명시 → 일별 로그가격 경로.
#   ▸ N 이 10 의 배수가 아닐 때의 분할 → ceiling(rank·10/N) 등분할(잔여 미배정 없음).
#   ▸ score 동값 정렬 → (score, Ticker) 결정론적 정렬(재현성 확보용, 전략 선택 아님).
#
# ===== ★앞 판(engine.rejected1.R)에서 제거한 것 — 전부 원문에 없던 장치다 =====
#   원문 데이터·방법 절에 winsorize/truncate/clip · 최소 거래일 · 커버리지 요건 ·
#   최소 종목수 언급이 **전무**함을 전문 대조로 확인했다. 따라서:
#   ✗ ±log(3) 일별 로그수익 절단(.DCAP)  → 삭제. MDD·C·R 은 **미처리 로그가격 경로**
#       위에서 식(1)(2) 그대로 산출한다. (수정주가 아티팩트 방어는 신호 층이 아니라
#       데이터 층 소관 — 02_Infrastructure/data/rawdata_sanitize.R 가 |Ret|>1.0
#       물리불가 프린트를 상류에서 처리한다. 신호식에 가드를 겹치지 않는다.)
#   ✗ 창 커버리지 하한 80%(.COV)          → 삭제. 편입 스크린 추가 없음.
#   ✗ 최소 횡단면 30종(.NMIN) · 최소 창길이 40거래일 → 삭제.
#   ✗ 엔진 내 기간 절단(.START)           → 삭제. 기간 축은 러너가 적용한다
#       (run_paper_replication.R:252 `PORTFOLIO[Date >= start_date]`). 엔진은 기간을
#       선택하지 않고 가용 전 구간을 낸다.
#   ✗ 가용 코호트 수 nc 로 나누는 정규화   → 삭제. **고정 1/K(K=6)** — 코호트가
#       비면 그 슬리브는 미노출로 남고 생존 코호트를 만액 재스케일하지 않는다(J-T).
#   남은 하한 2개는 스크린이 아니라 **정의의 정의역**이다(FIDELITY 에 명시):
#     · n ≥ 2 — 로그가격 경로가 성립하는 최소 관측(MDD 정의 불가 구간 배제)
#     · N ≥ 10 — "numbers of groups are 10" 이 성립하는 최소 횡단면
#   창 관측수는 **거르지 않고 진단으로 보고**한다(측정하되 스크린하지 않는다).
#
# ===== 논문 대비 변경 3건 (지시된 고정 축 — 전문은 FIDELITY.changed 가 정본) =====
#   ① 유니버스: KOSPI 200 → **K200 ∪ KQ150**(PIT 시변 멤버십).
#   ② 유동성: **adv20(t-1) ≥ 2e8 KRW** 신설 — 논문에는 유동성 필터가 없다.
#   ③ 기간: 논문 KOSPI 200 표본은 "The period from January 2003 to December 2012",
#      본 판은 2005-01-01~가용말일. **이 절단은 엔진이 아니라 러너가 적용한다.**
#   ★①②는 이 파일에서 발화하고(자격 게이트), ③은 발화하지 않는다. 셋 다 FIDELITY.json
#     에 선언돼 있다 — 주석은 사본이고 그 파일이 통로다.
#
# ===== 산출 형태 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏이라 반드시 이 형태.
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"} — 여기 Weight 가 곧
#   논문 비중이다(FACTORS 로 내면 러너가 숏 다리를 버리고 롱온리 top-N 으로 재구성).
#   코호트별 롱합 +1 / 숏합 -1 → 최근 6 코호트 고정 1/6 합산 → 종목별 상계(netting).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#   ▸ 구조 경계: 코호트(형성일 f)의 모든 창은 (me_dates[k-6], f] 로 닫히고 종점 = f
#     (월말 종가, f 시점 기지). 러너가 익 거래일에 집행 → 신호창 ∩ 보유월 = ∅.
#   C1  : 전 표본 통계 0건. C/MDD/회복은 전부 6개월 창 **내부** 경로 통계이고,
#         데실은 그 날짜 단면의 순위일 뿐 시계열 전표본 통계가 아니다.
#   C2  : same-day 순환참조 없음(f 종가까지만 사용, 집행은 익 거래일).
#   C3  : 같은 기간 집계→적용 없음(형성창 종점 f < 보유월 시작).
#   C4  : 재무 패널 미사용(가격·거래대금만).
#   C5  : 오버레이 없음.
#   C6  : 유니버스 = 각 f 의 K200/KQ150 멤버십(PIT 시변). 미래 명부 주입 없음.
#   C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 +1(과거 방향) 1회뿐.
#   C9  : DD/VT 오버레이 미사용(여기 낙폭은 과거창 신호 통계이지 실현낙폭 스케일러가
#         아니다 — C9 의 same-day DD 소비와 무관).
#   C10 : 유동성 = f **직전** 20 거래일 평균 거래대금(frollmean 후 shift(1) → 당일 배제).
#   C11 : 외부 매크로 미사용.
#   C13 : NEGATE/FLIP 0건. 방향은 논문이 정한 두 곳에서만 정해진다(오름차순 · 최상위
#         데실 롱/최하위 숏).
#   C15 : Factor DB parquet 직접 load 0건(RAWDATA 가격·거래대금에서만 산출).
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
# 상수 — 출처가 둘뿐이다: (a) 논문 명시값  (b) 지시된 고정 축
#   임의로 고른 수치는 없다. 정의의 정의역(n>=2 · N>=10)은 상수가 아니라 아래 코드에서
#   식이 성립하는 최소 조건으로 직접 나타난다.
# =============================================================================
# ▸ (a) 논문 명시값 — 이 엔진의 논문 유래 파라미터 전부
.W       <- c(1, 2, 1)     # Table 1 · CM 규칙 = (R_I,R_II,R_III) 가중 = C - MDD
.FORM_M  <- 6L             # §3.2 "6 months of estimation period" (월말 격자 6스텝)
.HOLD    <- 6L             # §3.2 "After 6 months of the holding period" = J-T 의 K
.NDEC    <- 10L            # §3.2 "numbers of groups are 10"
# ▸ (b) 지시된 고정 축 (FIDELITY.changed 에 선언)
.LIQ     <- 2e8            # adv20(t-1) 하한 (KRW)
.LIQ_WIN <- 20L            # 유동성 창 (거래일)

# ---- 형성창 로그가격 경로 → C / MDD / 3-국면 (창 내부 통계만, C1) --------------
#   cl = 형성창 내 그 종목의 거래일 종가(Date 오름차순).
#   ★경로는 **미처리**다: path = log(P) - log(P_0). 증분 절단·winsorize·clip 없음
#     (원문 식(1)(2) 가 정의된 그 경로). path[1] = 0, path[n] = C.
#   ★cummax 는 t<=τ 포함형 — 단조 상승 경로에서 MDD = 0 이 되어 "worst successive
#     loss" 의 비음수 규약과 일치한다(엄격 t<τ 는 신고점에서 양수를 내 규약 위반).
.mdd_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L)                                   # 경로 정의 불가 = 정의역 밖
    return(list(C = NA_real_, MDD = NA_real_, RI = NA_real_,
                RII = NA_real_, RIII = NA_real_, nobs = n))
  path <- log(cl) - log(cl[1L])                 # 상대 로그가격 경로 (미처리)
  dd   <- path - cummax(path)                   # <= 0
  ts   <- which.min(dd)                         # trough t* (동값이면 최초)
  tp   <- which.max(path[seq_len(ts)])          # trough 이전(포함) peak
  list(C    = path[n],                          # = R_I + R_II + R_III
       MDD  = -dd[ts],                          # 식(2), >= 0
       RI   = path[tp],                         # PP (path[1] = 0)
       RII  = path[ts] - path[tp],              # = -MDD
       RIII = path[n]  - path[ts],              # R (부호 있음)
       nobs = n)
}

# =============================================================================
# 1. 패널 준비 (RAWDATA 비파괴) + 유동성 adv20(t-1)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd <- unique(.rd, by = c("Ticker", "Date"))
setorder(.rd, Ticker, Date)

# 거래대금(결측 거래량 = 그날 회전 0). adv20 후 shift(1) → t-1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]

# 월말 거래일 격자 (전 종목 통합 마지막 거래일) — 각 f 는 그 달 내부 날짜로만 결정된다
.rd[, ym := year(Date) * 12L + month(Date)]
.me_dates  <- sort(.rd[, .(f = max(Date)), by = ym]$f)
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date)

cat(sprintf("[RP_1403_8125] 패널 %s행 · %s~%s · 월말 %d개\n",
            format(nrow(.rd), big.mark = ","),
            as.character(min(.all_dates)), as.character(max(.all_dates)),
            length(.me_dates)))

# =============================================================================
# 2. 코호트 — 각 형성일 f 에서 CM-score 10분위 롱숏 (EW · 롱합 +1 / 숏합 -1)
# =============================================================================
.cohorts <- vector("list", length(.me_dates))
.diag    <- vector("list", length(.me_dates))
for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) next                                    # me_dates[k-6] 필요
  f      <- .me_dates[k]
  w0     <- .me_dates[k - .FORM_M]
  wdates <- .all_dates[.all_dates > w0 & .all_dates <= f]   # 6개월 일별 격자 (종점 = f)
  if (!length(wdates)) next

  # 자격: f 의 K200/KQ150 멤버십 + 지시 축 adv20(t-1) 하한 (C6·C10)
  rf   <- .rd[.(f), .(Ticker, K200, KQ150, ADV20_L1), nomatch = 0L]
  elig <- rf[(.tru(K200) | .tru(KQ150)) &
               is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (!length(elig)) next

  wd <- .rd[.(wdates), .(Date, Ticker, Close), nomatch = 0L]
  wd <- wd[Ticker %chin% elig]
  if (!nrow(wd)) next
  setorder(wd, Ticker, Date)                                # 그룹 내 Date 오름차순 보장

  # ★커버리지로 거르지 않는다 — 원문에 그 요건이 없다. 대신 진단으로 남긴다.
  st <- wd[, .mdd_stats(Close), by = Ticker]
  st[, score := .W[1] * RI + .W[2] * RII + .W[3] * RIII]    # CM = C - MDD
  st <- st[is.finite(score)]                                # 정의역 밖(n<2) 배제
  N  <- nrow(st)
  if (N < .NDEC) next                                       # 10 그룹이 성립하는 최소 횡단면

  setorder(st, score, Ticker)                               # 오름차순 + 결정론적 동값 처리
  grp <- as.integer(ceiling(seq_len(N) * .NDEC / N))        # 1 = 패자 … 10 = 승자
  long_tk  <- st$Ticker[grp == .NDEC]                       # 최상위 데실 = 롱 (원문)
  short_tk <- st$Ticker[grp == 1L]                          # 최하위 데실 = 숏 (원문)

  .cohorts[[k]] <- rbindlist(list(
    data.table(Ticker = long_tk,  w =  1 / length(long_tk)),   # EW · 합 +1
    data.table(Ticker = short_tk, w = -1 / length(short_tk)))) # EW · 합 -1
  # ★진단만: 창 관측 커버리지(문턱 없음 — 거르지 않으므로 임계값도 두지 않는다)
  .diag[[k]] <- data.table(f = f, N = N, nL = length(long_tk), nS = length(short_tk),
                           n_win = length(wdates),
                           cov_min = min(st$nobs) / length(wdates),
                           cov_med = median(st$nobs) / length(wdates),
                           mdd_med = median(st$MDD), C_med = median(st$C))
}

# =============================================================================
# 3. 오버래핑 — 최근 K=6 코호트 **고정 1/K** 합산 (J-T), 종목별 상계 → 부호로 Leg
#    ★nc 로 나누지 않는다: 코호트가 비면 그 슬리브는 미노출로 남는다(재스케일 없음).
#    ★k >= .FORM_M + .HOLD = 12 부터 산출 — K개 슬리브가 모두 형성 가능한 시점.
#      (전략의 워밍업이지 기간 선택이 아니다. 기간 축은 러너가 적용한다.)
# =============================================================================
.out    <- vector("list", length(.me_dates))
.n_part <- 0L                                    # 코호트 결측으로 슬리브가 빈 달 수
for (k in seq_along(.me_dates)) {
  if (k < .FORM_M + .HOLD) next
  idx <- (k - .HOLD + 1L):k
  chs <- Filter(Negate(is.null), .cohorts[idx])
  if (!length(chs)) next
  if (length(chs) < .HOLD) .n_part <- .n_part + 1L
  agg <- rbindlist(chs)[, .(w = sum(w) / .HOLD), by = Ticker]   # 고정 1/K
  agg <- agg[is.finite(w) & abs(w) > 1e-12]
  if (!nrow(agg)) next
  agg[, Leg := fifelse(w > 0, "long", "short")]
  .out[[k]] <- data.table(Date = .me_dates[k], Ticker = agg$Ticker,
                          Weight = agg$w, Leg = agg$Leg)
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_1403_8125] PORTFOLIO 0행 — 유니버스/형성창 확인")
setorder(PORTFOLIO, Date, -Weight)

# =============================================================================
# 4. 보고 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
.dg <- rbindlist(Filter(Negate(is.null), .diag), use.names = TRUE)
.pm <- PORTFOLIO[, .(nL = sum(Leg == "long"), nS = sum(Leg == "short"),
                     gL = sum(Weight[Weight > 0]), gS = sum(Weight[Weight < 0])),
                 by = Date]
cat(sprintf(paste0(
  "[RP_1403_8125] faithful: CM(1,2,1)=C-MDD · 10-decile 롱숏 EW · 6mo 형성/보유 ",
  "J-T 오버래핑(고정 1/K, K=%d) · 월간 · 미처리 로그가격 경로(절단/윈저 0)\n",
  "  코호트 %d개(형성 %s~%s) · 횡단면 중앙 %d종(롱 %d/숏 %d) · 창내 MDD 중앙 %.1f%% · C 중앙 %.1f%%\n",
  "  [진단·비스크린] 창 관측 커버리지 최소 %.2f / 중앙 %.2f · 슬리브 결손 달 %d개\n",
  "  PORTFOLIO %s행 · %d개월 %s~%s · 월평균 롱 %.0f/숏 %.0f종 · 그로스 롱 %.2f/숏 %.2f\n",
  "  ★engine_direct · commission_paper=null(논문 gross) · 기간축은 러너 적용 · %.1f분\n"),
  .HOLD,
  nrow(.dg), as.character(min(.dg$f)), as.character(max(.dg$f)),
  as.integer(median(.dg$N)), as.integer(median(.dg$nL)), as.integer(median(.dg$nS)),
  100 * median(.dg$mdd_med), 100 * median(.dg$C_med),
  min(.dg$cov_min), median(.dg$cov_med), .n_part,
  format(nrow(PORTFOLIO), big.mark = ","), uniqueN(PORTFOLIO$Date),
  as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  mean(.pm$nL), mean(.pm$nS), mean(.pm$gL), mean(.pm$gS),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
