# =============================================================================
# RP_AUTO_CLEAN_1505_00328 — engine.R  (1계층 충실구현)
#
# 논문: Huai-Long Shi, Zhi-Qiang Jiang, Wei-Xing Zhou,
#       "Profitability of contrarian strategies in the Chinese stock market"
#       arXiv:1505.00328  (https://arxiv.org/abs/1505.00328)
#
# 논문 산출 형태 — Jegadeesh-Titman 절차의 역방향(contrarian):
#   "For a given 'current' month t=0, all the stocks are sorted according to
#    their returns in the past J months from t=-J to t=0."
#   → 10분위 분할(decile grouping — 논문이 quintile·tertile 대비 우월하다고 보고)
#   → 최하위 10분위 = 패자(LOS), 최상위 10분위 = 승자(WIN)
#   → CON(J,K) = LOS 매수 + WIN 매도, K개월 보유, equal-weighted
#   비용·시장조정 없음(논문 미명시). skip 월 없음(주 결과 기준).
#
# 이 엔진이 구현한 칸: CON(J=1, K=1) · decile · EW · skip 없음.
#   (81칸 격자 {1,6,12,18,24,30,36,42,48}^2 중 한 칸 — 선택 사유는 FIDELITY.json
#    changed 에 적혀 있다. K=1 이라 overlapping/non-overlapping 해석이 동일해
#    논문이 명시하지 않은 중첩 규약을 지어낼 필요가 없는 유일한 칸이다.)
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중 그대로.
#   롱 다리 Σw = +1 · 숏 다리 Σw = -1  → 하네스 Rg = GL·Lr - GS·Sr = R_LOS - R_WIN
#   (= 논문 CON 수익 정의). 러너 portfolio_spec = {"construction":"engine_direct"}.
#   ★종목수 상한을 걸지 않는다 — 10분위는 유니버스 크기가 정하고(≈35종/다리),
#     충실구현 축은 "논문 그대로"다. 축 초과는 러너·감사가 기록한다.
#
# PIT 구조 보장 (detect_lookahead 통과를 근거로 삼지 않는다 — 구조로 보장):
#   · 신호 = 그 달 일별 수익의 월내 복리곱. 창이 **월 안에서만** 닫힌다(by Ticker,Mon).
#   · 시그널일 = 그 달 **마지막 거래일**(거래소 달력 = 사전 공표 사실). 월간 수익은
#     그 종가에 전량 확정 → 보유는 러너 get_execution_date 로 익월 첫 거래일부터.
#   · 유동성 = 거래대금 20일 이동평균을 shift(1) 한 값(종점 t-1 · C10).
#   · 횡단면 통계는 전부 by=SigDate(그 날 안에서만). 전 표본 mean/sd/cov/quantile 0건.
#   · 미래 인덱싱(shift 음수·[-1] 역참조·forward merge) 0건. 팩터 DB 미사용
#     (신호가 가격 수익이라 C13/C15 소비 경로가 없다).
# =============================================================================

suppressWarnings(suppressMessages(library(data.table)))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.NEED <- c("Date", "Ticker", "Ret", "Close", "Vol", "K200", "KQ150")
if (!all(.NEED %in% names(RAWDATA)))
  stop(sprintf("[1505.00328] RAWDATA 열 부재: %s",
               paste(setdiff(.NEED, names(RAWDATA)), collapse = ", ")))

# 고정 축 (변수 아님) — 유동성 하한. 논문에는 없고 우리 축이 부과한다(FIDELITY changed).
.LIQ_FLOOR <- 2e8     # 20일 평균 거래대금 KRW, 종점 t-1
.LIQ_WIN   <- 20L     # 거래대금 이동평균 창(거래일)
.N_GROUP   <- 10L     # 논문 decile grouping

RD <- RAWDATA[, .(Date, Ticker, Ret, Close, Vol, K200, KQ150)]
if (!inherits(RD$Date, "Date")) RD[, Date := as.Date(Date)]
setorder(RD, Ticker, Date)

# 월 키 = 연*12 + (월-1). 정수라 "직전 달 = Mon - 1L" 이 달력 경계에서도 성립한다.
RD[, Mon := data.table::year(Date) * 12L + (data.table::month(Date) - 1L)]

# ── 유동성: 거래대금 20일 이동평균, 종점 t-1 (C10) ──────────────────────────
#   frollmean 은 align="right" 로 후행창, 그 뒤 shift(1) 로 당일을 창에서 뺀다.
RD[, TradeVal := Close * Vol]
RD[, TradeVal_ma := frollmean(TradeVal, .LIQ_WIN, align = "right", na.rm = TRUE), by = Ticker]
RD[, ADV20_lag := shift(TradeVal_ma, 1L, type = "lag"), by = Ticker]

# ── 시그널일 = 그 달 거래소 마지막 거래일 (by=Mon — 달 안에서만 닫히는 창) ──
MEND <- RD[, .(SigDate = max(Date)), by = Mon]

# ── 신호: 그 달 수익 (J=1 → "t=-1 에서 t=0 까지의 수익") ────────────────────
#   월내 일별 수익 복리곱. 결측일은 제외(해당 종목이 그 날 거래 자료가 없는 경우).
MRET <- RD[is.finite(Ret), .(MRet = prod(1 + Ret) - 1), by = .(Ticker, Mon)]

# ── IPO 월 수익 배제 (논문: "the first-month return data of individual stocks
#    are excluded from our analysis") — 직전 달 관측이 있어야 그 달 수익을 신호로 쓴다.
#    prev_ret 은 **존재 플래그로만** 쓰고 신호에 섞지 않는다.
PREV <- MRET[, .(Ticker, Mon = Mon + 1L, prev_ret = MRet)]
MRET <- merge(MRET, PREV, by = c("Ticker", "Mon"), all.x = TRUE)
MRET[, PrevOK := is.finite(prev_ret)]

# ── 시그널일 상태 결합: 유니버스 멤버십 · 유동성을 **그 시그널일 행**에서 읽는다 ──
#   inner merge 이므로 그 달 마지막 거래일에 거래 자료가 없는 종목(중도 상장폐지·
#   장기 정지)은 후보에서 빠진다 = 결정 시점에 투자 불가능한 종목을 담지 않는다.
MRET <- merge(MRET, MEND, by = "Mon")
STATE <- RD[, .(Date, Ticker, K200, KQ150, ADV20_lag)]
CAND <- merge(MRET, STATE, by.x = c("SigDate", "Ticker"), by.y = c("Date", "Ticker"))

# 유일한 유니버스 변경 = K200 ∪ KQ150 (PIT 시변 멤버십 — 그 시그널일 플래그)
CAND <- CAND[(K200 == TRUE | KQ150 == TRUE) &
             is.finite(ADV20_lag) & ADV20_lag >= .LIQ_FLOOR &
             is.finite(MRet) & PrevOK == TRUE]

# ── 10분위 분할 (논문 decile grouping) ──────────────────────────────────────
CAND[, N_elig := .N, by = SigDate]
CAND <- CAND[N_elig >= .N_GROUP]           # 10개 군이 존재할 구조적 최소 조건
CAND[, r := as.integer(frank(MRet, ties.method = "first")), by = SigDate]
#   정수 산술로만 분위를 매긴다 — ceiling(r/N*10) 은 r/N*10 이 정수일 때
#   부동소수 오차로 한 칸 밀릴 수 있다(예: 35/350*10). 아래는 그 위험이 없다.
CAND[, dec := (((r - 1L) * .N_GROUP) %/% N_elig) + 1L]

LOS <- CAND[dec == 1L]                     # 최하위 10분위 = 패자 → 롱
WIN <- CAND[dec == .N_GROUP]               # 최상위 10분위 = 승자 → 숏

# ── equal-weighted · 롱 Σw=+1 / 숏 Σw=-1 (논문 CON = R_LOS - R_WIN) ─────────
LOS[, Weight :=  1 / .N, by = SigDate]
WIN[, Weight := -1 / .N, by = SigDate]

PORTFOLIO <- rbind(
  LOS[, .(Date = SigDate, Ticker, Weight, Leg = "LONG")],
  WIN[, .(Date = SigDate, Ticker, Weight, Leg = "SHORT")]
)
setorder(PORTFOLIO, Date, Leg, Ticker)
PORTFOLIO <- PORTFOLIO[]

if (nrow(PORTFOLIO) == 0L)
  stop("[1505.00328] PORTFOLIO 0행 — 적격 종목(유니버스∩유동성∩직전달 관측)이 어느 달도 10종에 못 미쳤다")

# 구조 단정 — N_elig >= 10 이면 r=1 은 dec 1, r=N 은 dec 10 이라 두 다리는 항상 존재한다.
#   (증명: dec(r) = ((r-1)*10) %/% N + 1 → dec(1)=1 · dec(N)=((N-1)*10)%/%N+1=10)
#   한쪽 다리만 남는 달이 생기면 CON 정의가 깨진 것이므로 조용히 넘기지 않는다.
.chk <- PORTFOLIO[, .(has_L = any(Weight > 0), has_S = any(Weight < 0)), by = Date]
if (!all(.chk$has_L & .chk$has_S))
  stop(sprintf("[1505.00328] 한쪽 다리만 있는 시그널일 %d건 — CON 정의 위반",
               sum(!(.chk$has_L & .chk$has_S))))

cat(sprintf("[1505.00328] CON(J=1,K=1) decile EW — %d개월 · %s ~ %s · 다리당 평균 %.1f종\n",
            uniqueN(PORTFOLIO$Date), format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date)),
            nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date) / 2))
