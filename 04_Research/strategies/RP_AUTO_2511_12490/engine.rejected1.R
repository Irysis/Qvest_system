# =============================================================================
# engine.R — RP_AUTO_2511_12490
# "Discovery of a 13-Sharpe OOS Factor: Drift Regimes Unlock Hidden
#  Cross-Sectional Predictability"  (arXiv:2511.12490)
#   https://arxiv.org/abs/2511.12490   전문 경로: arxiv.org/html/2511.12490v1
#   (§2.1 signal construction · 식(1)~(4) · §portfolio formation · Table 5)
#
# ★fidelity = ADAPTED. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#   adapted 사유 1건 = **리밸 주기 daily → monthly**. 측정 계약이 일간 리밸을 표현하지
#   못한다(아래 "왜 monthly 인가" 참조). 신호·국면·레그분할·비중은 논문 그대로다.
#
# ===== 원문 대조 (식(1)~(4) · 산출 문단 · Table 5) =====
#   (A) 식(1) BASE_{i,t} = 0.7 x value_{i,t} + 0.3 x reversal_{i,t}
#   (B) value — "The value component employs a price-based measure requiring no
#       accounting information, computing **inverse price** for each stock then
#       converting to cross-sectional ranks through **percentile scores between
#       0 and 1**."                        → value = pct_rank(1/P), [0,1]
#   (C) reversal — "computing **trailing 10-day returns** and **negating** them to
#       create contrarian signals ... then **standardizing cross-sectionally to
#       z-scores**"                        → reversal = z( -R10 )
#       ▸ 부호반전은 논문의 신호 정의 자체다(C13 의 미신고 방향전환과 무관 — 팩터 DB
#         정렬을 건드리지 않고, 반전 지점이 논문 문장 하나로 특정된다).
#   (D) 식(2) UpFraction_{i,t} = (1/63) SUM_{k=1..63} I[ r_{i,t-k} > 0 ]
#       ★합의 정의역이 k=1..63 이다 — **당일 t 의 수익은 창에 들어가지 않는다**(논문 자신
#         이 한 칸 밀어놨다). 그대로 지킨다.
#   (E) 식(3) REGIME_{i,t} = I[ UpFraction_{i,t} > 0.60 ]   (종목별 · 시장 전체 아님)
#   (F) 식(4) EDGE_{i,t} = BASE_{i,t} x REGIME_{i,t}
#       → 국면 밖 종목은 스코어 0 = 편입 대상 자체에서 빠진다("we only trade stocks
#         exhibiting specific conditions where our signal proves most effective").
#   (G) 산출 문단(원문 그대로): "Each day we identify all stocks with valid, non-zero
#       EDGE scores, compute standardized z-scores ensuring zero mean and unit
#       variance, then construct market-neutral long-short portfolios by separating
#       stocks into long and short buckets based on z-scores. We normalize within
#       each side to control gross exposure, with **long positions summing to 50%
#       and short positions to 50%**, ensuring constant gross exposure of 100% and
#       approximately zero net exposure for market neutrality."
#       → ① z 는 **EDGE != 0 부분집합**에서 표준화(zero mean/unit variance)
#         ② 롱/숏 분할 = z 부호(zero-mean 이므로 평균 절단 = 부호 절단)
#         ③ 사이드별 정규화 = |z| 비례로 각 사이드 합 0.5 (그로스 1.0)
#       ▸ ②의 근거: Table 5 "Average Positions: 187 long, 189 short" — **거의 같지만
#         정확히 같지 않은** 두 수는 분위 절단(정확히 같아진다)이 아니라 zero-mean
#         분포의 부호 절단의 지문이다. 데실·퀸타일 절단은 이 개수를 낼 수 없다.
#       ▸ ③의 근거: 같은 Table 5 의 "Largest Position 2-3% of gross" +
#         "Top Decile Weight 35% of gross". 187+189 종을 사이드별 EW 로 담으면 최대
#         비중은 0.5/187 = 0.27%, 상위 데실 비중은 10% 가 된다 — 보고값과 어긋난다.
#         |z| 비례 사이징이어야 두 수가 함께 성립한다(→ EW 배제).
#   (H) 비용 — "Transaction costs of **0.6 basis points per unit traded** reflect
#       combined explicit and implicit costs for liquid large-cap stocks."
#       → FIDELITY::commission_paper = 6e-05 (러너의 SUM|dw| x commission 단위와 동일 =
#         "per unit traded". 왕복 환산 1.2bps.)
#
# ===== 왜 monthly 인가 (adapted 의 유일한 사유 — 은폐하지 않는다) =================
#   논문은 일간 리밸이다("Each day we identify all stocks ..." · Table 5 일간 회전율
#   42% · 중위 보유 8일). 그런데 측정 계약의 실행일 함수가 월간 격자로 고정돼 있다:
#     backtest_harness.R:316 get_execution_date() = **다음 달 첫 거래일**.
#   그래서 일간 시그널 날짜를 내보내면 replication_harness.R:84-89 에서 같은 달의
#   시그널은 exec_date == next_exec 가 되어 hold_pool 이 비고 `next` 로 **조용히
#   버려진다** — 그 달의 마지막 시그널 1건만 살아 다음 달 한 달을 통째로 보유한다.
#   즉 일간을 내면 결과는 "월말 시그널 + 월간 보유"인데 기록만 일간으로 남는다.
#   지어낸 성과보다 나쁜 것이 **전달되지 않은 설정**이므로, 월말 격자를 **명시적으로**
#   내보내 리밸 축의 변경을 선언한다. (인프라 수정·직접 백테스트는 금지 축이다.)
#   ▸ 남는 것: 신호 3종(1/P 백분위 · -R10 z · 63일 상승일비율 국면 게이트)의 정의와
#     파라미터(0.7/0.3 · 10 · 63 · 0.60), 부호 절단 롱숏, |z| 비례 50/50 정규화.
#   ▸ 바뀌는 것: 그 포트폴리오를 매일이 아니라 매월 갈아탄다. 10일 반전 성분은 월간
#     보유에서 약해지는 것이 물리적으로 맞다 — 그 약화는 결과이지 은폐가 아니다.
#     ★반전 창을 월간에 맞춰 늘리지 **않았다**: 논문이 주지 않는 수치를 내가 정하면
#       그건 이식이 아니다(창 확장은 강화 레인의 next_probe 로 남긴다).
#
# ===== 논문 대비 변경 4건 (전문은 FIDELITY.changed 가 정본) ======================
#   (1) ★리밸: daily → monthly (위 사유. 월말 거래일 시그널 → 익월 첫 거래일 집행)
#   (2) 유니버스: S&P 500 **current** constituents → **K200 ∪ KQ150**(PIT 시변).
#       ▸ 논문은 생존편의를 자인한다("all current constituents ... deliberately
#         selecting current constituents"). 지시 축이 그 편의를 함께 제거한다.
#   (3) 유동성: adv20(t-1) >= 2e8 KRW 신설 — 논문에는 유동성 필터가 없다.
#   (4) 기간: 논문 2004-01~2024-12 → 2005-01-01~가용말일. **엔진은 기간을 자르지
#       않는다** — 절단은 러너(run_paper_replication.R:252)가 적용한다.
#   ★(2)(3)은 이 파일에서 발화하고 (1)은 시그널 격자로, (4)는 발화하지 않는다.
#
# ===== 원문이 침묵하는 곳 (지어내지 않고 규약으로 선언) =========================
#   ▸ 백분위 규약 미명시 → (frank-1)/(N-1) 로 [0,1] 정확히 채움. ★이 선택은 사실상
#     결과에 영향이 없다: 최종 z 표준화가 BASE 의 아핀변환을 흡수한다(rank/N 과의 차이
#     = 아핀). 그래서 "0 과 1 사이"라는 문장만 지키면 충분하다.
#   ▸ 동값 순위 → ties.method="average"(표준 백분위).
#   ▸ 성분 결측 종목 → 그 날짜 횡단면에서 **제외**(complete-case). 논문의 "valid ...
#     EDGE scores" 를 이렇게 읽는다. 결측을 0 으로 채워 순위·평균을 흔들지 않는다.
#   ▸ r > 0 판정에서 Ret 결측 = 상승일 아님(0). 분모는 식(2)대로 **고정 63**.
#   ▸ 섹터 중립화 없음 — Table 5 의 "Sector Deviation" 은 사후 보고 특성이지 제약이
#     아니다(구성 절에 중립화 언급 전무). 윈저·클리핑·최소가격 요건도 전무 → 넣지 않는다.
#   ▸ 워밍업 미명시 → NA 전파로 자연 결정(UP63 64행 · R10 11행 · adv20 21행).
#   ★수치 하한 2개(횡단면 N>=2 · 활성 N>=2)는 스크린이 아니라 정의의 정의역이다
#     (표준편차·백분위가 성립하는 최소 관측).
#
# ===== 산출 형태 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏이라 반드시 이 형태.
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"} — 여기 Weight 가 곧
#   논문 비중이다(FACTORS 로 내면 러너가 숏 다리를 버리고 롱온리 top-N 으로 재구성).
#   롱합 +0.5 / 숏합 -0.5 = 논문의 "50% / 50%, gross 100%".
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ====
#   ▸ 구조 경계: 시그널일 d = 월 마지막 거래일, 집행 E = 익월 첫 거래일 = d 의 **다음
#     거래일**. 모든 창의 종점이 d 이므로 종점 = t-1 (t = 보유 첫날). 신호창 ∩ 보유
#     구간 = 공집합.
#   C1  : 전 표본 통계 0건. 모든 통계는 (a) 종목별 과거 롤링창(frollmean/frollsum) 또는
#         (b) **그 날짜 하나의 횡단면**(by = Date) 이다. 시계열 전표본 mean/sd/quantile
#         0건 · scale() 미사용.
#   C2  : same-day 순환참조 없음(d 종가까지만, 집행은 다음 거래일).
#   C3  : 같은 기간 집계→적용 없음(d < 보유월 시작).
#   C4  : 재무제표 패널 미사용(가격·거래량만 — 논문의 value 가 accounting-free 다).
#   C5  : 오버레이 없음(국면은 alpha 게이트이지 노출 스칼라가 아니다 — 총노출은 항상
#         그로스 1.0 고정이라 국면이 사이징을 건드리지 않는다).
#   C6  : 유니버스 = 각 d 의 K200/KQ150 멤버십(PIT 시변). 미래 명부 주입 없음.
#         ★논문의 current-constituent 표본을 그대로 옮기지 않았다(그게 생존편의다).
#   C9  : DD/VT 미사용.
#   C10 : 유동성 = d **직전** 20 거래일 평균 거래대금(frollmean 후 shift(1) → 당일 배제).
#   C11 : 외부 매크로 미사용.
#   C13 : 미신고 방향전환 0건. 부호가 정해지는 곳은 논문 문장 2개뿐 —
#         "negating them"(반전 성분) · "long and short buckets based on z-scores".
#   C14 : IC 패널 미접근.
#   C15 : Factor DB parquet 직접 load 0건(RAWDATA 가격·수익·거래량에서만 산출).
#   ▸ 비선언 idiom 자체 점검: shift() 는 전부 양수 lag(과거 방향) · lead()/shift(-N) 0건 ·
#     수동 미래 인덱싱 0건 · 전 표본 cov()/mean()/sd() 0건 · 미래수익 정렬 0건.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Ret", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_2511_12490] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 상수 — 출처가 둘뿐이다: (a) 논문 명시값  (b) 지시된 고정 축
#   임의로 고른 수치는 없다. 정의역 하한(N>=2)은 상수가 아니라 아래에서 식이 성립하는
#   최소 조건으로 직접 나타난다.
# =============================================================================
# ▸ (a) 논문 명시값 — 이 엔진의 논문 유래 파라미터 전부
.W_VALUE <- 0.7        # 식(1) value 가중
.W_REV   <- 0.3        # 식(1) reversal 가중
.REV_WIN <- 10L        # §2.1 "trailing 10-day returns"
.DRIFT_W <- 63L        # 식(2) 창 = 63 거래일
.UP_THR  <- 0.60       # 식(3) 문턱 "> 0.60"
.SIDE_G  <- 0.5        # 산출 문단 "long positions summing to 50% and short ... 50%"
# ▸ (b) 지시된 고정 축 (FIDELITY.changed 에 선언)
.LIQ     <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN <- 20L        # 유동성 창 (거래일)

# =============================================================================
# 1. 패널 준비 (RAWDATA 비파괴) — 종목별 과거 롤링창만 (C1)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Ret, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd <- unique(.rd, by = c("Ticker", "Date"))
setorder(.rd, Ticker, Date)

# 유동성: 거래대금(결측 거래량 = 그날 회전 0) → adv20 후 shift(1) → t-1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, TV := NULL]

# value 원자료 — 역가격 (논문: accounting-free "inverse price"). d 종가에서 산출
.rd[, INVP := 1 / Close]

# reversal 원자료 — 종점 d 의 10 거래일 수익 (그 종목의 거래일 격자 기준)
.rd[, R10 := Close / shift(Close, .REV_WIN) - 1, by = Ticker]

# 국면 원자료 — 식(2): SUM_{k=1..63} I[r_{t-k} > 0] / 63
#   frollsum 은 (t-62..t) 를 덮으므로 shift(.,1) 로 한 칸 밀어 (t-63..t-1) = k=1..63.
#   결측 Ret 은 상승일 아님(0). 분모는 식(2)대로 고정 63.
.rd[, UPD := fifelse(is.finite(Ret) & Ret > 0, 1L, 0L)]
.rd[, UP63 := shift(frollsum(UPD, .DRIFT_W, align = "right"), 1L) / .DRIFT_W, by = Ticker]
.rd[, UPD := NULL]

# 월말 거래일 격자 — 각 d 는 그 달 내부 날짜로만 결정된다(미래 참조 없음)
.rd[, ym := year(Date) * 12L + month(Date)]
.me <- sort(.rd[, .(d = max(Date)), by = ym]$d)

cat(sprintf("[RP_2511_12490] 패널 %s행 · %s~%s · 월말 격자 %d개\n",
            format(nrow(.rd), big.mark = ","),
            as.character(min(.rd$Date)), as.character(max(.rd$Date)), length(.me)))

# =============================================================================
# 2. 시그널일 횡단면 — 식(1)~(4)
#    ★모든 통계는 by = Date (그 날짜 단면) — 시계열 전표본 통계 0건 (C1)
# =============================================================================
.sig <- .rd[Date %in% .me]

# 자격: d 의 K200/KQ150 멤버십 + 지시 축 adv20(t-1) 하한 (C6·C10)
.sig <- .sig[(.tru(K200) | .tru(KQ150)) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ]

# "valid ... EDGE scores" = 성분 3종이 모두 성립하는 종목만 그 날짜 횡단면에 든다
.sig <- .sig[is.finite(INVP) & is.finite(R10) & is.finite(UP63)]
.n_elig_raw <- nrow(.sig)
.sig[, NX := .N, by = Date]
.sig <- .sig[NX >= 2L]                              # 백분위·표준편차의 정의역
if (!nrow(.sig)) stop("[RP_2511_12490] 시그널 횡단면 0행 — 유니버스/유동성 확인")

# 식(1) 성분 — value = 역가격 백분위 [0,1] · reversal = (-R10) 횡단면 z
.sig[, PCT := (frank(INVP, ties.method = "average") - 1) / (NX - 1), by = Date]
.sig[, REV_RAW := -R10]                             # 논문 "negating them" — 신호 정의
.sig[, REVZ := (REV_RAW - mean(REV_RAW)) / sd(REV_RAW), by = Date]
.sig <- .sig[is.finite(REVZ)]                       # sd = 0 인 단면은 z 미정의

# 식(1)(3)(4)
.sig[, BASE   := .W_VALUE * PCT + .W_REV * REVZ]
.sig[, REGIME := fifelse(UP63 > .UP_THR, 1L, 0L)]
.sig[, EDGE   := BASE * REGIME]

# =============================================================================
# 3. 산출 — 활성(EDGE != 0) 부분집합 z 표준화 → 부호 절단 롱숏 → 사이드별 |z| 비례
#    "compute standardized z-scores ensuring zero mean and unit variance, then
#     ... separating stocks into long and short buckets based on z-scores.
#     We normalize within each side ... long 50% / short 50%"
#    ▸ zero-mean 이므로 SUM z+ = SUM |z-| — 사이드별 정규화가 자동으로 net 0 을 낸다
#      (논문의 "approximately zero net exposure" 가 여기서는 정확히 0).
# =============================================================================
.act <- .sig[REGIME == 1L & is.finite(EDGE)]
if (!nrow(.act)) stop("[RP_2511_12490] 국면 활성 종목 0건 — 식(2)(3) 확인")
.act[, NA_ACT := .N, by = Date]
.act <- .act[NA_ACT >= 2L]                          # 표준편차의 정의역
.act[, Z := (EDGE - mean(EDGE)) / sd(EDGE), by = Date]
.act <- .act[is.finite(Z) & Z != 0]                 # z=0 은 어느 버킷도 아니다

.act[, GP := sum(Z[Z > 0]), by = Date]              # SUM z+   (롱 사이드 정규화 분모)
.act[, GN := sum(-Z[Z < 0]), by = Date]             # SUM |z-| (숏 사이드 정규화 분모)
.act <- .act[(Z > 0 & GP > 0) | (Z < 0 & GN > 0)]
.act[, Weight := fifelse(Z > 0, .SIDE_G * Z / GP, .SIDE_G * Z / GN)]
.act[, Leg    := fifelse(Weight > 0, "long", "short")]

PORTFOLIO <- .act[is.finite(Weight) & abs(Weight) > 1e-12,
                  .(Date, Ticker, Weight, Leg)]
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_2511_12490] PORTFOLIO 0행 — 유니버스/국면/성분 확인")
setorder(PORTFOLIO, Date, -Weight)

# =============================================================================
# 4. 보고 (구성 요약 + 논문 Table 5 대조 진단 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
.dg <- .sig[, .(n_elig = .N, n_act = sum(REGIME)), by = Date]
.pm <- PORTFOLIO[, .(nL = sum(Leg == "long"), nS = sum(Leg == "short"),
                     gL = sum(Weight[Weight > 0]), gS = sum(abs(Weight[Weight < 0])),
                     wmax = max(abs(Weight))), by = Date]
cat(sprintf(paste0(
  "[RP_2511_12490] adapted(리밸 daily->monthly): EDGE = (0.7*pct(1/P) + 0.3*z(-R10)) x I[UpFrac63(t-1..t-63) > 0.60]\n",
  "  → 활성 부분집합 z 표준화 · 부호 절단 롱숏 · 사이드별 |z| 비례 50%%/50%%(그로스 1.0) · 월말 시그널\n",
  "  자격 단면 %s행 · 국면 활성 비율 평균 %.1f%% (논문 Table 5 'Active Stock-Days 35%% of universe')\n",
  "  PORTFOLIO %s행 · %d개월 %s~%s · 월평균 롱 %.0f/숏 %.0f종 (논문 187/189)\n",
  "  그로스 롱 %.3f/숏 %.3f (논문 0.5/0.5) · 최대 비중 평균 %.2f%% (논문 'Largest Position 2-3%% of gross')\n",
  "  ★engine_direct · commission_paper=6e-05(0.6bps/unit traded) · 기간축은 러너 적용 · %.1f분\n"),
  format(.n_elig_raw, big.mark = ","),
  100 * mean(.dg$n_act / .dg$n_elig),
  format(nrow(PORTFOLIO), big.mark = ","), uniqueN(PORTFOLIO$Date),
  as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  mean(.pm$nL), mean(.pm$nS), mean(.pm$gL), mean(.pm$gS), 100 * mean(.pm$wmax),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
