# =============================================================================
# RP_AUTO_CLEAN_1505_00328 — engine.R  (1계층 충실구현 · 재구현 R2)
#
# 논문: Huai-Long Shi, Zhi-Qiang Jiang, Wei-Xing Zhou,
#       "Profitability of contrarian strategies in the Chinese stock market"
#       arXiv:1505.00328  (https://arxiv.org/abs/1505.00328)
#
# 논문 절차 (Materials and Methods · 원문 직접 인용):
#   "For a given 'current' month t=0, all the stocks are sorted according to
#    their returns in the past J months from t=-J to t=0. We divide the stocks
#    into several groups. For comparison, decile grouping, quintile grouping and
#    tertile grouping are adopted. The group of stocks with the worst performance
#    in the estimation is called loser portfolio LOS(J,K) and the group with best
#    performance is called winner portfolio WIN(J,K). One then adopts the
#    contrarian strategy by buying the loser portfolio and selling the winner
#    portfolio. The contrarian portfolio CON(J,K) is held for K months."
#   "We examine the equal-weighted average returns per annum of the loser
#    portfolio, the winner portfolio, and the contrarian portfolio ..."
#   격자: "The periods range from one month to four years: J=K∈{1,6,12,18,24,30,36,42,48}"
#   비용: 논문 전체에 거래비용 서술 0건(gross). skip 1개월 = 강건성(주 결과 미적용).
#
# ★거래소 독립 정렬 — 이 판의 수리 지점 (R1 기각 사유):
#   "Because the average market capitalizations of SHSE stocks (16.73 billion CNY
#    per stock) and SZSE stocks (4.64 billion CNY per stock) are significantly
#    different, we shall investigate separately the A-share stocks in the two
#    exchanges for comparison."
#   "Since the features of A-shares listed on these two stock exchanges are not
#    similar, we investigate the momentum and contrarian effects in the SHSE and
#    the SZSE independently."
#   → 논문은 두 거래소를 **절대 한 횡단면으로 묶지 않는다**(Table 2 = Panel A: SHSE /
#     Panel B: SZSE · Table 3 = SHSE 격자 / Table 4 = SZSE 격자 · Table 6 = 두 거래소
#     차분). 따라서 분위 경계·LOS·WIN 은 **세그먼트 안에서만** 산출한다.
#     KR 대응 = 상장 보드(K200 = 대형 · KQ150 = 중소형) — 논문이 분리를 택한 사유가
#     시가총액 이질성이고 그 이질성이 K200 vs KQ150 에 그대로 해당한다.
#   → 논문 산출물은 세그먼트별 CON 2개다. 러너는 PORTFOLIO 1개를 받으므로
#     세그먼트 CON 을 **등가중 합성**한다(각 1/S gross). 그러면
#       Rg = (1/S)·Σ_seg (R_LOS,seg − R_WIN,seg) = 논문 보고 CON 수익들의 단순 평균.
#     합성 규칙은 논문에 없다 — FIDELITY.changed ② 에 선언한다.
#
# 이 엔진이 구현한 칸: CON(J=1, K=1) · decile · skip 없음 · EW.
#   (9×9 격자 중 한 칸 — 선택 사유 = FIDELITY.changed ④)
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 비중은 논문 EW 를 세그먼트 안에서 그대로.
#   롱 Σw = +1 · 숏 Σ|w| = 1 → 하네스 Rg = GL·Lr − GS·Sr = CON 수익.
#   러너 portfolio_spec = {"construction":"engine_direct"}.
#
# PIT 구조 보장 (detect_lookahead 통과를 근거로 삼지 않는다 — 구조로 보장):
#   · 신호 = 그 달 일별 수익의 월내 복리곱. 창이 **달 안에서만** 닫힌다(by Ticker,Mon).
#   · 시그널일 = 그 달 **마지막 거래일**(거래소 달력 = 사전 공표 사실). 월간 수익은
#     그 종가에 전량 확정 → 보유는 러너 get_execution_date 로 익월 첫 거래일부터.
#   · 유동성 = 거래대금 20일 이동평균을 shift(1) 한 값(종점 t-1 · C10).
#   · 횡단면 통계는 전부 by = .(SigDate, Seg) — 그 날·그 세그먼트 안에서만.
#     전 표본 mean/sd/cov/quantile/scale 0건. 전 표본 선정 규칙 0건(C1/C14).
#   · 미래 인덱싱 0건(shift 음수·[-1] 역참조·forward merge 없음). Mon+1L 은 **과거**
#     달의 관측을 현재 달 행에 붙이는 방향이다(직전 달 존재 = IPO 첫 달 배제).
#   · 팩터 DB 미사용 — 신호가 가격 수익이라 C13/C15 소비 경로가 없다.
# =============================================================================

suppressWarnings(suppressMessages(library(data.table)))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.NEED <- c("Date", "Ticker", "Ret", "Close", "Vol", "K200", "KQ150")
if (!all(.NEED %in% names(RAWDATA)))
  stop(sprintf("[1505.00328] RAWDATA 열 부재: %s",
               paste(setdiff(.NEED, names(RAWDATA)), collapse = ", ")))

# 고정 축 (변수 아님) — 유동성 하한은 논문에 없고 우리 축이 부과한다(FIDELITY changed ③)
.LIQ_FLOOR <- 2e8     # 20일 평균 거래대금 KRW, 종점 t-1
.LIQ_WIN   <- 20L     # 거래대금 이동평균 창(거래일)
.N_GROUP   <- 10L     # 논문 decile grouping

RD <- RAWDATA[, .(Date, Ticker, Ret, Close, Vol, K200, KQ150)]
if (!inherits(RD$Date, "Date")) RD[, Date := as.Date(Date)]
setorder(RD, Ticker, Date)

# 월 키 = 연*12 + (월-1). 정수라 "직전 달 = Mon - 1L" 이 달력 경계에서도 성립한다.
RD[, Mon := data.table::year(Date) * 12L + (data.table::month(Date) - 1L)]

# ── 유동성: 거래대금 20일 이동평균, 종점 t-1 (C10) ──────────────────────────
#   frollmean 은 align="right" 로 후행창, 그 뒤 shift(1) 로 당일을 창에서 뺀다(lag).
RD[, TradeVal := Close * Vol]
RD[, TradeVal_ma := frollmean(TradeVal, .LIQ_WIN, align = "right", na.rm = TRUE), by = Ticker]
RD[, ADV20_lag := shift(TradeVal_ma, 1L, type = "lag"), by = Ticker]

# ── 시그널일 = 그 달 거래소 마지막 거래일 (by=Mon — 달 안에서만 닫히는 창) ──
MEND <- RD[, .(SigDate = max(Date)), by = Mon]

# 적재 데이터가 끝나는 달은 **달이 데이터 안에서 닫혔다는 보장이 없다**(부분월 수익이
#   월간 수익으로 들어간다). 신호에서 제외한다 — 하네스가 집행일 부재로 어차피 건너뛰는
#   달이고, 이렇게 두면 모든 신호가 완결된 달력월 수익이라는 것이 구조로 보장된다.
.LAST_MON <- RD[Date == max(Date), Mon][1]
MEND <- MEND[Mon < .LAST_MON]

# ── 신호: 그 달 수익 (J=1 → "t=-1 에서 t=0 까지의 수익") ────────────────────
#   월내 일별 수익 복리곱. 비유한 Ret 행은 제외(그 날 거래 자료가 없는 종목).
#   월내 최소 거래일수 요건은 부과하지 않는다(논문 침묵 · FIDELITY changed ⑤).
MRET <- RD[is.finite(Ret), .(MRet = prod(1 + Ret) - 1), by = .(Ticker, Mon)]

# ── IPO 첫 달 수익 배제 (논문: "the first-month return data of individual stocks
#    are excluded from our analysis") — 직전 달 관측이 있어야 그 달 수익을 신호로 쓴다.
#    직전 달에서 가져오는 것은 **존재 플래그뿐**이고 수익값은 신호에 섞지 않는다.
PREV <- MRET[, .(Ticker, Mon = Mon + 1L, PrevObs = TRUE)]
MRET <- merge(MRET, PREV, by = c("Ticker", "Mon"), all.x = TRUE)
MRET[, PrevOK := !is.na(PrevObs)]

# ── 시그널일 상태 결합: 보드 멤버십·유동성을 **그 시그널일 행**에서 읽는다 ──
#   inner merge 이므로 그 달 마지막 거래일에 거래 자료가 없는 종목(중도 상장폐지·
#   장기 정지)은 후보에서 빠진다 = 결정 시점에 투자 불가능한 종목을 담지 않는다.
MRET <- merge(MRET, MEND, by = "Mon")
STATE <- RD[, .(Date, Ticker, K200, KQ150, ADV20_lag)]
CAND <- merge(MRET, STATE, by.x = c("SigDate", "Ticker"), by.y = c("Date", "Ticker"))

# ── 세그먼트 = 논문의 "두 거래소" 대응 (상장 보드 · PIT 시변 플래그) ───────────
#   K200(대형) ↔ SHSE · KQ150(중소형) ↔ SZSE. 두 플래그는 보드가 달라 상호배타적이지만
#   동시 TRUE 행이 있으면 K200 우선으로 결정론을 확보한다(FIDELITY changed ⑥).
CAND[, Seg := NA_character_]
CAND[!is.na(KQ150) & KQ150 == TRUE, Seg := "KQ150"]
CAND[!is.na(K200)  & K200  == TRUE, Seg := "K200"]

CAND <- CAND[!is.na(Seg) &
             is.finite(ADV20_lag) & ADV20_lag >= .LIQ_FLOOR &
             is.finite(MRet) & PrevOK == TRUE]

# ── 10분위 분할 — **세그먼트 안에서 독립으로** (논문 거래소 독립 정렬) ─────────
#   분위 경계·순위·군 크기가 전부 (SigDate, Seg) 안에서만 결정된다. 두 세그먼트가
#   한 번도 같은 분포를 공유하지 않는다 = 논문 Table 3/4 의 분리 격자 구조.
CAND[, N_elig := .N, by = .(SigDate, Seg)]
CAND <- CAND[N_elig >= .N_GROUP]           # 10개 군이 존재할 구조적 최소 조건
CAND[, r := as.integer(frank(MRet, ties.method = "first")), by = .(SigDate, Seg)]
#   정수 산술로만 분위를 매긴다 — ceiling(r/N*10) 은 r/N*10 이 정수일 때
#   부동소수 오차로 한 칸 밀릴 수 있다(예: 20/200*10). 아래는 그 위험이 없다.
CAND[, dec := (((r - 1L) * .N_GROUP) %/% N_elig) + 1L]

LOS <- CAND[dec == 1L]                     # 세그먼트 최하위 10분위 = 패자 → 롱
WIN <- CAND[dec == .N_GROUP]               # 세그먼트 최상위 10분위 = 승자 → 숏

# ── 비중: 세그먼트 안 equal-weighted(논문) × 세그먼트 간 등가중 합성(1/S) ──────
#   논문은 거래소별 CON 2개를 따로 보고하고 합치지 않는다(Table 6 = 차분).
#   러너는 PORTFOLIO 1개를 받으므로 그 달 분위 산출이 성립한 세그먼트 S 개를
#   등가중으로 합성한다 → Rg = (1/S)·Σ_seg CON_seg = 논문 CON 수익들의 단순 평균.
#   (종목 풀링 EW 는 쓰지 않는다 — 적격 종목이 많은 보드가 지배해 논문이 보고하는
#    어느 거래소 CON 수익도 보존되지 않는다. 사유·대안 = FIDELITY.changed ②)
NSEG <- CAND[, .(S = uniqueN(Seg)), by = SigDate]
LOS <- merge(LOS, NSEG, by = "SigDate")
WIN <- merge(WIN, NSEG, by = "SigDate")
LOS[, Weight :=  (1 / S) * (1 / .N), by = .(SigDate, Seg)]
WIN[, Weight := -(1 / S) * (1 / .N), by = .(SigDate, Seg)]

PORTFOLIO <- rbind(
  LOS[, .(Date = SigDate, Ticker, Weight, Leg = "LONG")],
  WIN[, .(Date = SigDate, Ticker, Weight, Leg = "SHORT")]
)
setorder(PORTFOLIO, Date, Leg, Ticker)
PORTFOLIO <- PORTFOLIO[]

if (nrow(PORTFOLIO) == 0L)
  stop("[1505.00328] PORTFOLIO 0행 — 적격 종목(보드∩유동성∩직전달 관측)이 어느 보드·달도 10종에 못 미쳤다")

# ── 구조 단정 — 조용히 깨지지 않게 한다 ────────────────────────────────────
#   (a) N_elig >= 10 이면 r=1 은 dec 1, r=N 은 dec 10 이라 세그먼트마다 두 다리가 항상 존재한다.
#       (증명: dec(r) = ((r-1)*10) %/% N + 1 → dec(1)=1 · dec(N)=((N-1)*10)%/%N+1=10)
#   (b) 따라서 날짜별 Σ(롱) = Σ_seg (1/S) = 1 이고 Σ|숏| = 1 이다. 어긋나면 합성이 깨진 것.
.chk <- PORTFOLIO[, .(wl = sum(Weight[Weight > 0]), ws = sum(abs(Weight[Weight < 0]))), by = Date]
if (nrow(.chk[abs(wl - 1) > 1e-8 | abs(ws - 1) > 1e-8]))
  stop(sprintf("[1505.00328] 날짜별 다리 합 불일치 %d건 — 세그먼트 합성(1/S) 위반",
               nrow(.chk[abs(wl - 1) > 1e-8 | abs(ws - 1) > 1e-8])))

.legn <- LOS[, .N, by = .(SigDate, Seg)][, .(avg = mean(N)), by = Seg]
cat(sprintf("[1505.00328] CON(J=1,K=1) decile EW · 보드 독립 정렬(K200|KQ150) — %d개월 · %s ~ %s\n",
            uniqueN(PORTFOLIO$Date), format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date))))
cat(sprintf("[1505.00328] 보드별 다리 평균 종목수: %s · 월평균 보드 %.2f개 · 월평균 보유 %.1f종\n",
            paste(sprintf("%s %.1f", .legn$Seg, .legn$avg), collapse = " · "),
            mean(NSEG$S), nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date)))
