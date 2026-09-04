# =============================================================================
# engine.R — RP_AUTO_1505_00328
# "Profitability of contrarian strategies in the Chinese stock market"
#  (arXiv:1505.00328 · 게재판 = Shi, Jiang & Zhou, PLoS ONE 10(9): e0137892, 2015)
#  https://arxiv.org/abs/1505.00328
#
# ★fidelity = FAITHFUL (충실구현). 정본 = FIDELITY.json — 이 주석은 사본이다.
#
# ===== 원문 대조 =====
#  /abs 초록 + 게재판 전문(PLOS 오픈액세스 XML · journal.pone.0137892)으로 대조했다.
#  arXiv /pdf 는 이 환경에서 바이너리로 떨어져 못 읽는다(메모리 카드 기록과 동일).
#
# ===== 왜 faithful 인가 (판정 순서 1에서 끝난다) =====
#  이 논문은 처음부터 횡단면 종목선택이다. 원문 그대로:
#    "all the stocks are sorted according to their returns in the past J months
#     from t = −J to t = 0" → "The group of stocks with the worst performance in
#     the estimation is called loser portfolio LOS(J,K) and the group with best
#     performance is called winner portfolio WIN(J,K). One then adopts the
#     contrarian strategy by buying the loser portfolio and selling the winner
#     portfolio. The contrarian portfolio CON(J,K) is held for K months. We
#     examine the equal-weighted average returns per annum."
#  신호·그룹화·비중·보유기간·롱숏이 전부 명시돼 있다. 이식할 것이 없다.
#
# ===== 논문에서 온 값 (전부. 우리가 정한 수치 0개) =====
#  (P1) 신호      = 추정기간 J개월 수익률. 순위 변수는 그것 하나다(다른 팩터 없음).
#  (P2) 그룹화    = **decile**. 논문이 decile/quintile/tertile 셋을 비교한 뒤
#                   "decile grouping outperforms quintile grouping and tertile
#                   grouping, which is more evident and robust in the long run"
#                   으로 decile 을 결론으로 삼는다. 종목수는 논문이 개수가 아니라
#                   **분위**로 정의한다 — 그래서 여기서도 개수를 못 박지 않는다.
#  (P3) 비중      = equal-weighted (원문 "equal-weighted average returns").
#  (P4) 방향      = 롱 loser · 숏 winner (CON = 패자 매수·승자 매도). 성과를 보고
#                   고른 부호가 아니라 논문 정의 그대로다.
#  (P5) 리밸/보유 = 매월 t=0 에서 정렬해 K개월 보유. 본 엔진은 격자 셀 J=K=1 —
#                   형성월 = 그 달, 보유월 = 다음 달, 매월 재구성.
#  (P6) skip      = 없음(baseline). 1개월 skip 은 논문의 **강건성 확인**이지 기준선이 아니다.
#  (P7) 표본필터  = 상장 첫 달 수익 제외 ("the first-month return data of individual
#                   stocks are excluded from our analysis" — IPO 월 가격점프 때문).
#
# ===== 왜 격자 9셀 중 J=K=1 인가 (성과가 아니라 '지어내지 않기'가 기준) =====
#  논문은 J=K∈{1,6,12,18,24,30,36,42,48} 격자를 보고하고 **기준 셀을 지정하지 않는다**.
#  하나를 골라야 하고, 고른 기준은 두 가지다.
#   ① 초록이 수익성을 긍정하는 구간에 있다 — "when the estimation and holding
#      horizons are 1 month or longer than 12 months". J=K=1 은 그 문장이 직접 지목한 셀이다.
#   ② **논문이 주지 않은 값을 지어내지 않아도 되는 유일한 셀이다.** K>1 이면 JT 방식
#      중첩 코호트를 짜야 하는데, 논문은 중첩의 기계적 세부(코호트 내 월별 EW 재조정이냐
#      드리프트냐 · 코호트 평균 방식)를 명시하지 않는다. 그걸 우리가 정하는 순간
#      충실구현이 아니라 우리 설계가 섞인다. K=1 은 그 자유도가 **존재하지 않는다**.
#  ★부수 효과이지 선택 사유가 아님: 장기 셀(K=48)은 보유 중 상폐·거래중단 종목이
#    조용히 leg 에서 빠지며 생존편의가 **패자 다리에** 쌓인다(하네스가 결측 종목을
#    빼고 재정규화한다). K=1 은 그 누적이 한 달치라 구조적으로 얕다.
#  ★다른 셀(장기 반전)은 이 엔진의 확장이 아니라 **강화 레인의 축**이다 — 여기서 섞지 않는다.
#
# ===== 무엇을 바꿨는가 (changed — 유니버스뿐) =====
#  중국 SHSE+SZSE 전 A주 → **K200∪KQ150 (PIT 시변 멤버십)** + 고정 축 유동성 하한
#  adv20(t-1) ≥ 2e8 KRW. 그 외 신호·그룹화·비중·방향·리밸·IPO 필터는 논문 그대로다.
#  기간은 1997-2012(논문) → 2005-01-01~ (고정 축).
#
# ===== PIT (C1~C15) — 구조로 보장한다 (detect_lookahead 통과를 근거로 쓰지 않는다) =====
#  ▸ 구조 경계: 시그널일 t 에서 소비하는 값은 셋뿐이고 전부 Date ≤ t 로만 만들어진다 —
#    ①형성월 수익(그 달 첫 거래일~t 종가) ②adv20 을 하루 민 t-1 값 ③t 시점 지수 멤버십.
#    미래 행을 읽는 연산이 코드에 존재하지 않는다(음수 shift·lead·수동 미래 인덱싱 0건).
#  C1 : 전 표본 통계 0건. 월 수익은 `by=.(Ticker, MI)` 안에서만 곱해지고 그 달의 신호에만
#       쓰인다. 표준화·상관·공분산·전기간 평균 없음. 등수는 **그날의 횡단면**에서만 매긴다.
#  C2 : same-day 순환참조 없음 — 형성수익 종점 = t 종가, 집행 = t+1(러너 get_execution_date).
#  C3 : 같은 기간 집계→적용 없음. 형성월(M)과 보유월(M+1)이 겹치지 않는다.
#  C4 : 재무 패널 미사용(일별 수익·거래대금·멤버십만). 공시시차 이슈 자체가 없다.
#  C5 : 오버레이 0건(S0/S1 오버레이 금지 준수).
#  C6 : 유니버스 = 각 시그널일의 K200/KQ150 멤버십. 최종 생존명부 주입 없음.
#       상장 첫 달 판정도 t 이전 정보만 쓴다 — 적격 종목은 t 에 행이 있으므로 첫 관측일이
#       항상 t 이하다(미래에 상장할 종목은 애초에 그날의 횡단면에 없다).
#  C7 : 자동탐지 안티패턴 0건. 유일한 shift 는 +1(과거 방향).
#  C9 : DD/VT 미사용.  C10 : 유동성 = adv20 을 by-Ticker 로 하루 민 t-1 값 ≥ 2e8.
#  C11: 매크로 시계열 미사용.
#  C13/C15 : Factor DB 미소비(신호가 가격 하나에서 나온다) → 정렬·직접로드 대상 없음.
#       Score 부호는 측정된 IC 가 아니라 **논문 정의**(P4)에서 사전에 나온다.
#  ★rawdata Market 열 미사용(KOSDAQ 0건 날조 — 메모리 카드). 시장구분이 필요 없다.
#
# ===== 산출 =====
#  PORTFOLIO(Date, Ticker, Weight, Leg) — **논문 비중 그대로**. 롱(loser) +1/nL ·
#    숏(winner) −1/nS → Σw_long=+1 · Σw_short=−1 이라 하네스 결합 GL·L − GS·S 가
#    논문의 C = L − W 와 정확히 같은 양이 된다(달러중립 1x/1x).
#    ★러너 호출: portfolio_spec = list(construction="engine_direct") — 이게 없으면
#      숏 다리가 버려지고 롱온리 top-N 으로 재구성된다(FIDELITY.json 이 정본 통로).
#  FACTORS(Date, Ticker, Score) — Score = −(형성월 수익). 적격 전 종목에 발행해
#    러너의 IC·FF·FMB 분석이 서게 한다. 비중은 위 PORTFOLIO 가 정본이다.
#  commission_paper = NULL — 논문은 거래비용을 명시하지 않는다(등급은 15bps 판).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언은 고정한다.
set.seed(15050328L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축 / 계산 경계 (세 층을 섞지 않는다)
# =============================================================================
# ▸ 논문에서 온 것
.J        <- 1L        # (P1)(P5) 추정기간 J개월
.K        <- 1L        # (P5) 보유기간 K개월
.NDEC     <- 10L       # (P2) decile grouping
.SKIP     <- 0L        # (P6) 형성-보유 사이 skip 없음 = baseline
# ★J=K=1·skip=0 이라 '매월 재구성·1개월 보유'가 러너의 월간 리밸 그대로다. 다른 셀은
#   중첩 코호트가 필요하고 그 세부를 논문이 주지 않는다 — 지어내지 않으려고 여기서 막는다.
stopifnot(.J == 1L, .K == 1L, .SKIP == 0L)

# ▸ 우리 고정 축(유니버스 치환에 딸린 것)
.LIQ      <- 2e8                        # adv20(t-1) 하한 (KRW)
.SIG_FROM <- as.Date("2005-01-01")      # 측정 시작

# ▸ 계산 경계(논문 미명시 — 성과를 보고 고르지 않았다)
.NMIN       <- 30L                      # 월 최소 횡단면. decile 이 성립하려면 10 이상이어야
                                        #   하고, 30 이면 양 극단 데실이 각 3종 이상이 된다.
.PANEL_FROM <- as.Date("2003-01-01")    # 패널 하한(메모리 경계). 첫 시그널일(2005-01)에
                                        #   필요한 건 adv20 20거래일 + 형성월 1개월뿐이고,
                                        #   2년 여유는 상장 첫 달 판정을 정확히 하기 위한 것.

# =============================================================================
# 1. 일별 패널 정리 — 유동성(t-1) · 월 인덱스
# =============================================================================
.rd <- RAWDATA[Date >= .PANEL_FROM, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어 — 중복이 남으면 아래 월 집계가 같은 날 수익을 두 번 곱한다.
#   에러 없이 형성수익만 바뀌는 침묵 실패라 여기서 막는다. 중복이 없으면 무연산.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_1505_00328] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]  # C10 t-1
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# =============================================================================
# 2. 시그널일 = 각 달의 마지막 거래일 (형성월 종점 · 보유월 시작 전)
# =============================================================================
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIG <- .mend[SigDate >= .SIG_FROM]
if (nrow(.SIG) == 0L)
  stop("[RP_AUTO_1505_00328] 시그널일 0건 — RAWDATA 날짜 범위 확인")

# =============================================================================
# 3. 형성월 수익 (P1, J=1) + 상장 첫 달 제외 (P7)
# =============================================================================
# 월 수익 = 그 달 일별 수익의 곱 − 1. 각 그룹이 그 달 안에서 닫힌다(C1: 전 표본 통계 아님).
.mret <- .rd[is.finite(Ret), .(RF = prod(1 + Ret) - 1), by = .(Ticker, MI)]

# 상장 첫 달 판정: 패널 첫 거래일에 이미 존재했으면 신규상장이 아니다(패널 절단일 뿐).
#   그 이후에 처음 나타난 종목만 '첫 달'을 제외한다 — 논문의 IPO 필터가 겨냥한 대상.
.PSTART <- min(.rd$Date)
.first  <- .rd[, .(FirstDate = min(Date), FirstMI = min(MI)), by = Ticker]
.first[, IsNew := FirstDate > .PSTART]
.mret   <- merge(.mret, .first[, .(Ticker, FirstMI, IsNew)], by = "Ticker", all.x = TRUE)
.n_ipo  <- .mret[IsNew == TRUE & MI == FirstMI, .N]
.mret   <- .mret[!(IsNew == TRUE & MI == FirstMI)]
.mret[, c("FirstMI", "IsNew") := NULL]

# =============================================================================
# 4. 적격 유니버스 (C6 · C10) → 형성수익 결합
# =============================================================================
.ELIG <- .rd[Date %in% .SIG$SigDate][
             (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ,
             .(SigDate = Date, MI, Ticker)]
if (nrow(.ELIG) == 0L)
  stop("[RP_AUTO_1505_00328] 적격 종목 0건 — 멤버십/유동성 필터 확인")

D <- merge(.ELIG, .mret, by = c("Ticker", "MI"))
D <- D[is.finite(RF)]
if (nrow(D) == 0L)
  stop("[RP_AUTO_1505_00328] 형성수익 결합 0행 — 월 인덱스 정합 확인")

# 횡단면이 얇은 달은 decile 이 의미를 잃는다 — 신호를 내지 않는다(대체값 주입 없음).
D[, NG := .N, by = SigDate]
.n_thin <- uniqueN(D[NG < .NMIN, SigDate])
D <- D[NG >= .NMIN]
if (nrow(D) == 0L)
  stop(sprintf("[RP_AUTO_1505_00328] 횡단면 %d종 이상인 달이 없음", .NMIN))

# =============================================================================
# 5. decile 정렬 (P2) → loser 롱 / winner 숏 (P4) · 등가중 (P3)
# =============================================================================
# 등수는 그날의 횡단면 안에서만 매긴다. 동점은 Ticker 사전순으로 갈라 결정론을 지킨다.
setorder(D, SigDate, RF, Ticker)
D[, RK := frank(RF, ties.method = "first"), by = SigDate]
D[, DEC := pmin(as.integer(ceiling(RK * .NDEC / NG)), .NDEC)]   # 1 = 최저수익(loser)

# 어느 한 다리가 2종 미만이면 그 달은 통째로 뺀다(한쪽만 남기면 롱숏이 아니게 된다).
.cnt <- D[, .(nL = sum(DEC == 1L), nS = sum(DEC == .NDEC)), by = SigDate]
.bad <- .cnt[nL < 2L | nS < 2L, SigDate]
if (length(.bad) > 0L) D <- D[!SigDate %in% .bad]
if (nrow(D) == 0L)
  stop("[RP_AUTO_1505_00328] 양 다리를 채우는 달이 없음")

D[, NL := sum(DEC == 1L),      by = SigDate]
D[, NS := sum(DEC == .NDEC),   by = SigDate]

PORTFOLIO <- rbindlist(list(
  D[DEC == 1L,     .(Date = SigDate, Ticker, Weight =  1 / NL, Leg = "long")],
  D[DEC == .NDEC,  .(Date = SigDate, Ticker, Weight = -1 / NS, Leg = "short")]
), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_AUTO_1505_00328] PORTFOLIO 0행 — decile 분할 확인")
setorder(PORTFOLIO, Date, -Weight)

# 적격 전 종목의 점수 패널 — 방향은 논문 정의(패자 매수)라 형성수익의 반대 부호다.
FACTORS <- D[, .(Date = SigDate, Ticker, Score = -RF)]
setorder(FACTORS, Date, -Score)

# =============================================================================
# 6. 진단 출력 (판정이 아니라 관측 — 등급은 계약이 낸다)
# =============================================================================
.dbg <- D[, .(n = .N, nL = NL[1], nS = NS[1],
              lo_med = median(RF[DEC == 1L]),
              hi_med = median(RF[DEC == .NDEC])), by = SigDate]
setorder(.dbg, SigDate)
for (i in seq(1L, nrow(.dbg), by = 24L)) {
  cat(sprintf("[RP_AUTO_1505_00328] %s | n=%d (L %d / S %d) | 형성수익 중앙 loser %+.1f%% · winner %+.1f%%\n",
              as.character(.dbg$SigDate[i]), .dbg$n[i], .dbg$nL[i], .dbg$nS[i],
              100 * .dbg$lo_med[i], 100 * .dbg$hi_med[i]))
}

cat(sprintf(paste0(
  "[RP_AUTO_1505_00328] faithful: CON(J=%d,K=%d) decile EW — 롱 loser / 숏 winner · skip %d\n",
  "  월 %d개 (%s ~ %s) · 다리당 평균 %.1f/%.1f종 · PORTFOLIO %d행 · FACTORS %d행\n",
  "  상장 첫 달 제외 %d건(P7) · 횡단면 %d종 미만으로 건너뛴 달 %d개\n",
  "  ★러너 호출: portfolio_spec=list(construction=\"engine_direct\") · commission_paper=NULL\n"),
  .J, .K, .SKIP,
  uniqueN(PORTFOLIO$Date),
  as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  mean(.dbg$nL), mean(.dbg$nS), nrow(PORTFOLIO), nrow(FACTORS),
  .n_ipo, .NMIN, .n_thin))
