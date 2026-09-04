# =============================================================================
# engine.R — RP_AUTO_2511_12490  (재구현 · 앞 판 engine.rejected1.R 은 misdeclared)
# "Discovery of a 13-Sharpe OOS Factor: Drift Regimes Unlock Hidden
#  Cross-Sectional Predictability"  (arXiv:2511.12490)
#   전문: arxiv.org/html/2511.12490v1  — §2.1 신호(식1~4) · §2.2 포트폴리오(식5·
#   kill-switch·walk-forward) · §4 kill-switch · Table 5 특성 · Table 6 민감도
#
# ★fidelity = ADAPTED. **선언 정본 = FIDELITY.json** (이 주석은 사본이다)
#
# ===== 앞 판이 기각된 지점과 이번 판의 처리 (감사 지적 → 처분) ==================
#  ①[portfolio] 식(5) 노출 스칼라 s* 미적용·미선언  → **구현**(§3-B). 5년 학습창에서
#    s* = min(12%/TrainVol, 15%/|TrainMaxDD|) 를 산출해 1년 test 구간 동결 적용.
#  ②[undeclared] kill-switch(30% 낙폭 · 63일 롤링 −10%) 부재 → **구현**(§3-C).
#    평가구간(=test 1년) 안에서 리셋 불가. 하네스에 flat 상태가 없어 ε 그로스로 인코딩.
#  ③[undeclared] 3창 walk-forward 프로토콜 미선언 → s*/kill 의 **재추정 케이던스로
#    구현**(5년 학습 → 1년 동결 test, 전 표본을 인접 창으로 타일링) + 선언.
#  ④[signal] 룩백 창이 '그 종목의 잔존 행'으로 세어짐 → **시장 거래일 격자로 재배치**
#    (§1). shift(10)·frollsum(63)·frollmean(20) 이 전부 시장 거래일 단위가 된다.
#  ⑤[signal] value 입력 1/Close 가 **수정주가(전기간 재작성)** → t 이후 분할·무상증자가
#    섞인 미래참조(PIT 위반, 상방편의). 저장소에 **명목주가 패널이 없다**(build_cache.R:56
#    OHLCVS 6시트 전부 수정계열 · registry_migrate_ast_v11.py:74 restatement_prone).
#    → 논문 추정기(1/명목주가)를 **PIT 청정 수준변수 1/시가총액**으로 대체(§2). 선언.
#  ⑥[portfolio] 실현 종목수·집중도가 Table 5(376종·2~3%)와 갈리는데 미선언 → FIDELITY
#    에 실현형을 선언 + 이 파일이 게이트 발화율·종목수·최대비중을 출력(§4).
#  ⑦[cost] 월간 리밸에 논문 0.6bp/unit 을 그대로 적용 → 비용 부담이 논문의 ~1/12.6.
#    요율은 논문값 유지(commission_paper=6e-05), **격차를 FIDELITY 에 선언**.
#  ⑧[portfolio] 사이드 내 |z| 비례 배분의 근거를 Table 5 가 판별해 준 것처럼 과장 →
#    유지하되 "논문 미명시 · Table 5 는 EW 만 배제할 뿐 유일하게 결정하지 못한다"로 정정.
#
# ===== 원문 대조 (그대로 옮긴 것) ==============================================
#   식(1) BASE   = 0.7 x value + 0.3 x reversal
#   value        = "inverse price ... cross-sectional ranks through percentile
#                   scores between 0 and 1"        → 백분위 [0,1]  (입력만 ⑤로 대체)
#   reversal     = "trailing 10-day returns and negating them ... standardizing
#                   cross-sectionally to z-scores" → z(-R10), by Date
#   식(2) UpFrac = (1/63) SUM_{k=1..63} I[r_{t-k} > 0]   ★당일 t 제외(논문의 비대칭)
#   식(3) REGIME = I[UpFrac > 0.60]  (종목별 게이트 — 시장 전체 아님, 엄격부등호)
#   식(4) EDGE   = BASE x REGIME
#   §2.2 산출   = 활성(EDGE!=0) 부분집합 z 표준화 → z 부호로 롱/숏 버킷 →
#                  사이드별 정규화(롱 50% · 숏 50%, 그로스 100%, net~0)
#   식(5) s*     = min(12%/TrainingVol, 15%/|TrainingMaxDD|), "all portfolio weights
#                  multiplied by this factor determined once during training and
#                  applied without modification during testing"
#   §2.2/§4     = kill-switch: 절대낙폭 30% · 롤링 63일 −10%, 평가구간 내 리셋 불가
#   §2.2        = walk-forward 5년 학습 / 1년 test (논문은 3창만 보고)
#   Table 6     = Base Case 63 / 0.60 / 0.70  (구현 파라미터와 일치)
#   §2.2 비용   = 0.6 bp per unit traded  → FIDELITY::commission_paper = 6e-05
#
# ===== 산출 형태 ===============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏이므로 반드시 이 형태.
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"}.
#   사이드 그로스 = 0.5 x s* (kill 구간은 0.5 x eps). 총 그로스 = s*.
#   ▸ 하네스가 그로스를 보존한다(replication_harness.R:57 gross=sum|w| · :105
#     Rg = GL*Lr − GS*Sr) → s* 가 엔진→측정으로 실제 전달된다. 확인 후 구현.
#
# ===== 왜 월간인가 (adapted 사유 1 — 은폐하지 않는다) ===========================
#   논문은 일간이다(§2.2 "Each day ..." · Table 5 일간회전 42% · 중위보유 8일).
#   측정 계약의 실행일 함수가 월간 격자로 고정: backtest_harness.R:316-323
#   get_execution_date() = **익월 첫 거래일**. 일간 시그널을 내면 같은 달 건은
#   replication_harness.R:86-89 에서 exec==next_exec → hold_pool 0 → `next` 로 조용히
#   버려지고 월 마지막 1건만 살아남는다(라벨만 일간, 측정은 월간). 그래서 월말 격자를
#   **명시적으로** 내보내 리밸 축의 변경을 선언한다. 반전 창을 월간에 맞춰 늘리지
#   않았다 — 논문이 주지 않는 수치를 내가 정하면 그건 이식이 아니다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ====
#   ▸ 구조 경계: 시그널일 d = 월 마지막 거래일, 집행 E = 익월 첫 거래일. 모든 신호창의
#     종점이 d 이므로 종점 = t-1(t = 보유 첫날). 신호창 ∩ 보유구간 = 공집합.
#   ▸ s* 는 보유연도 Y 의 **1월 1일 이전**에서 끝나는 5년 학습창에서만 산출된다.
#     kill 상태는 보유구간 시작 **전날까지**의 실현 경로에서만 갱신된다(§3-C 루프는
#     시간순 단일 방향 — 미래 인덱싱 0건).
#   C1  : 전 표본 통계 0건. 통계는 (a) 종목별 과거 롤링창 (b) 그 날짜 하나의 횡단면
#         (by=Date) (c) **과거로 닫힌 5년 학습창** 뿐. scale()·전표본 mean/sd/quantile 0건.
#   C2  : same-day 순환참조 없음. C3 : 같은 기간 집계→적용 없음.
#   C4  : 재무제표 패널 미사용(논문 신호가 accounting-free). C11 : 매크로 미사용.
#   C5  : 노출 스칼라 s*·kill-switch 는 **논문 §2.2 의 사양**이며 신호 컷오프가
#         홀딩월 시작 전으로 닫혀 있다(assert 구간 §3-C 주석). 국면 게이트는 종목별
#         alpha 게이트라 사이징을 건드리지 않는다.
#   C6  : 유니버스 = 각 d 의 K200/KQ150 멤버십(PIT 시변). 논문의 current-constituent
#         (자인된 생존편의)를 옮기지 않았다. ★§1 의 ever-member 축소는 **출력 동일**
#         (날짜별 멤버십 필터가 뒤에 그대로 걸리므로 선택집합이 바뀌지 않는다).
#   C9  : DD/VT same-day 사용 없음 — kill 판정은 전일까지의 NAV.
#   C10 : 유동성 = d **직전** 20 시장거래일 평균 거래대금(frollmean 후 shift(1)).
#   C13 : 미신고 방향전환 0건. 부호가 정해지는 곳은 논문 문장 2개뿐 —
#         "negating them" · "long and short buckets based on z-scores".
#   C14/C15 : Factor DB 미접근(RAWDATA 가격·수익·거래량·시총만).
#   ▸ 비선언 idiom 자체 점검: shift()는 전부 양수 lag · shift(-N)/lead() 0건 ·
#     수동 미래 인덱싱 0건 · 전표본 cov()/mean()/sd() 0건 · 미래수익 정렬 0건 ·
#     cumprod/cummax 는 시간순 인과 누적.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Ret", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_2511_12490] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 상수 — 출처가 셋뿐이다: (a) 논문 명시값 (b) 지시된 고정 축 (c) 하네스 인코딩
#   임의로 고른 전략 파라미터는 없다.
# =============================================================================
# ▸ (a) 논문 명시값
.W_VALUE <- 0.7        # 식(1) value 가중            (Table 6 Base Case 0.70)
.W_REV   <- 0.3        # 식(1) reversal 가중
.REV_WIN <- 10L        # §2.1 "trailing 10-day returns"
.DRIFT_W <- 63L        # 식(2) 창 63 거래일           (Table 6 Base Case 63)
.UP_THR  <- 0.60       # 식(3) 문턱 "> 0.60"          (Table 6 Base Case 0.60)
.SIDE_G  <- 0.5        # §2.2 "long ... 50% and short ... 50%"
.VOL_CAP <- 0.12       # 식(5) 12% annual volatility cap
.DD_CAP  <- 0.15       # 식(5) 15% maximum drawdown constraint
.KS_DD   <- 0.30       # §2.2/§4 kill-switch 절대낙폭 30%
.KS_R63  <- -0.10      # §2.2/§4 kill-switch 롤링 63일 −10%
.KS_WIN  <- 63L        # §2.2/§4 롤링 창 63일
.TRAIN_Y <- 5L         # §2.2 "five-year training periods"
# ▸ (b) 지시된 고정 축
.LIQ     <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN <- 20L        # 유동성 창 (거래일)
# ▸ (c) 계약·하네스 유래
.ANN     <- 252L       # 연환산 계수 — 측정 계약 정본과 동일(run_paper_replication.R:157
                       #   Return.annualized(scale = 252)). 식(5)의 "annual" 환산에 필요.
.KILL_EPS <- 1e-6      # kill 구간 그로스. 하네스에 flat 상태가 없다 —
                       #   시그널일 행을 비우면 W[Date==d] 가 비어 직전 책을 **계속 보유**
                       #   한다(replication_harness.R:83-89). "shutting down entirely" 를
                       #   전달하려면 그로스를 0 으로 보낼 수밖에 없고, Weight!=0 필터
                       #   (:45)가 정확한 0 을 지운다. 그래서 수치 노이즈 이하의 ε 로
                       #   인코딩한다. 전략 파라미터가 아니라 **하네스 인코딩 상수**다.

# =============================================================================
# 1. 패널 — RAWDATA 비파괴 + **시장 거래일 격자**로 재배치 (감사 지적 ④)
#    앞 판은 종목별 잔존 행 위에서 shift(10)/frollsum(63)을 돌려, 거래정지 20일을
#    겪은 종목의 "trailing 10-day return" 이 실제로는 30 거래일을 가로질렀다.
#    여기서는 각 종목을 상장구간의 **모든 시장 거래일**로 채워 창을 거래일로 고정한다.
# =============================================================================
.cols <- c("Date", "Ticker", "Close", "Ret", "Vol", "Size", "K200", "KQ150")
.rd0 <- RAWDATA[, ..cols]
if (!inherits(.rd0$Date, "Date")) .rd0[, Date := as.Date(Date)]
.rd0 <- unique(.rd0, by = c("Ticker", "Date"))
.rd0 <- .rd0[is.finite(Close) & Close > 0]

.cal  <- sort(unique(.rd0$Date))          # 시장 거래일 (전 종목 합집합 — 하네스 all_dates 동일)
.caln <- as.numeric(.cal)

# ever-member 축소 (메모리 — 출력 동일. 아래 자격 필터가 날짜별 멤버십을 강제하므로
#   한 번도 멤버가 아닌 종목은 어떤 날짜에도 선택될 수 없다)
.evermem <- unique(.rd0[.tru(K200) | .tru(KQ150), Ticker])
.rd0 <- .rd0[Ticker %in% .evermem]
setorder(.rd0, Ticker, Date)

.span <- .rd0[, .(i1 = findInterval(as.numeric(min(Date)), .caln),
                  i2 = findInterval(as.numeric(max(Date)), .caln)), by = Ticker]
.grid <- .span[, .(Date = .cal[i1:i2]), by = Ticker]
.rd   <- .rd0[.grid, on = .(Ticker, Date)]      # 미거래일 = NA 행 (창 길이 보존용)
setorder(.rd, Ticker, Date)

# 유동성 (C10): 미거래일 = 그날 회전 0 → adv20 은 20 **시장거래일** 평균 → shift(1)
.rd[, TV := fifelse(is.finite(Close) & is.finite(as.numeric(Vol)),
                    Close * as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, TV := NULL]

# ── value 입력 (감사 지적 ⑤ — 대체. FIDELITY.changed 가 정본) ────────────────
#   논문: value = 백분위(1 / 명목주가). 저장소에 명목주가 패널이 없다(수정주가 전용).
#   1/수정주가는 t 이후 분할·무상증자로 재작성된 값이라 PIT 위반(상방편의)이므로 금지.
#   대체 추정기 = 1/시가총액 — 분할·무상증자에 **불변**(주가 x 주식수)이라 재작성이
#   없고, accounting-free 이며 논문과 같은 '횡단면 수준변수의 낮은 쪽 선호' 방향이다.
.rd[, INVV := fifelse(is.finite(Size) & as.numeric(Size) > 0, 1 / as.numeric(Size), NA_real_)]

# reversal 원자료 — 종점 d 의 10 **시장거래일** 수익 (미거래로 끊기면 NA → 그날 제외)
.rd[, R10 := Close / shift(Close, .REV_WIN) - 1, by = Ticker]

# 국면 원자료 — 식(2): SUM_{k=1..63} I[r_{t-k} > 0] / 63
#   frollsum 은 (t-62..t) 를 덮으므로 shift(.,1) 로 한 칸 밀어 (t-63..t-1) = k=1..63.
#   미거래일/결측 Ret = 상승일 아님(0). 분모는 식(2)대로 고정 63.
.rd[, UPD := fifelse(is.finite(Ret) & Ret > 0, 1L, 0L)]
.rd[, UP63 := shift(frollsum(UPD, .DRIFT_W, align = "right"), 1L) / .DRIFT_W, by = Ticker]
.rd[, UPD := NULL]

# 월말 **시장거래일** 격자 — 각 d 는 그 달 내부 날짜로만 결정된다(미래 참조 없음)
.me <- data.table(Date = .cal)[, .(d = max(Date)),
                               by = .(ym = year(Date) * 12L + month(Date))][order(d)]$d

cat(sprintf("[RP_2511_12490] 격자 패널 %s행 · %s~%s · 시장거래일 %d · 월말 %d\n",
            format(nrow(.rd), big.mark = ","),
            as.character(min(.cal)), as.character(max(.cal)), length(.cal), length(.me)))

# =============================================================================
# 2. 시그널일 횡단면 — 식(1)~(4)
#    ★모든 통계는 by = Date (그 날짜 단면) — 시계열 전표본 통계 0건 (C1)
# =============================================================================
.sig <- .rd[Date %in% .me & is.finite(Close)]

# 자격: d 의 K200/KQ150 멤버십 + 지시 축 adv20(t-1) 하한 (C6·C10)
.sig <- .sig[(.tru(K200) | .tru(KQ150)) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ]

# "valid ... EDGE scores" = 성분 3종이 모두 성립하는 종목만 그 날짜 횡단면에 든다
.sig <- .sig[is.finite(INVV) & is.finite(R10) & is.finite(UP63)]
.n_elig_raw <- nrow(.sig)
.sig[, NX := .N, by = Date]
.sig <- .sig[NX >= 2L]                              # 백분위·표준편차의 정의역
if (!nrow(.sig)) stop("[RP_2511_12490] 시그널 횡단면 0행 — 유니버스/유동성 확인")

# 식(1) 성분 — value = 수준변수 백분위 [0,1] · reversal = (-R10) 횡단면 z
.sig[, PCT := (frank(INVV, ties.method = "average") - 1) / (NX - 1), by = Date]
.sig[, RVR := -R10]                                 # 논문 "negating them" — 신호 정의
.sig[, REVZ := (RVR - mean(RVR)) / sd(RVR), by = Date]
.sig <- .sig[is.finite(REVZ)]                       # sd = 0 인 단면은 z 미정의

# 식(1)(3)(4)
.sig[, BASE   := .W_VALUE * PCT + .W_REV * REVZ]
.sig[, REGIME := fifelse(UP63 > .UP_THR, 1L, 0L)]
.sig[, EDGE   := BASE * REGIME]

# =============================================================================
# 3-A. 무스케일 책 (그로스 1.0) — §2.2 첫 문단 그대로
#      활성(EDGE!=0) 부분집합 z 표준화 → z 부호로 롱/숏 → 사이드별 정규화 50/50
#      ▸ 사이드 **내부** 배분 함수는 논문 미명시다. "normalize within each side"를
#        z 에 적용하는 직독 = |z| 비례를 택한다. Table 5(최대 2~3% · 상위데실 35%)는
#        EW 를 배제할 뿐 |z| 비례를 유일하게 결정하지 못한다 — 감사 지적 ⑧ 수용,
#        근거 강도를 '미명시 규약'으로 정정한다(FIDELITY.changed).
#      ▸ zero-mean 이므로 SUM z+ = SUM |z-| → 사이드별 정규화가 net 0 을 정확히 낸다.
# =============================================================================
.act <- .sig[REGIME == 1L & is.finite(EDGE)]
if (!nrow(.act)) stop("[RP_2511_12490] 국면 활성 종목 0건 — 식(2)(3) 확인")
.act[, NA_ACT := .N, by = Date]
.act <- .act[NA_ACT >= 2L]                          # 표준편차의 정의역
.act[, Z := (EDGE - mean(EDGE)) / sd(EDGE), by = Date]
.act <- .act[is.finite(Z) & Z != 0]                 # z=0 은 어느 버킷도 아니다
.act[, GP := sum(Z[Z > 0]), by = Date]              # SUM z+   (롱 사이드 분모)
.act[, GN := sum(-Z[Z < 0]), by = Date]             # SUM |z-| (숏 사이드 분모)
.act <- .act[(Z > 0 & GP > 0) | (Z < 0 & GN > 0)]
.act[, W0 := fifelse(Z > 0, .SIDE_G * Z / GP, .SIDE_G * Z / GN)]
if (!nrow(.act)) stop("[RP_2511_12490] 무스케일 책 0행")

# =============================================================================
# 3-B/C. 식(5) 노출 스칼라 s* + kill-switch  (감사 지적 ①②③)
#   ★이 블록은 **비중 결정 단계**다 — 논문이 "all portfolio weights multiplied by
#     this factor" 라고 명시한 그 단계. 성과 측정이 아니다(측정은 호출자 계약).
#     s*/kill 을 내려면 전략 자신의 경로가 필요하므로 무스케일 경로를 재구성한다.
#   ▸ 학습 경로 = 무스케일(그로스 1.0) 책의 일간 수익 — 논문의 training run 과 동일.
#   ▸ 실현 경로 = s*·kill 이 적용된 책의 일간 수익 — kill 판정 대상.
#   ▸ 시간 방향 단일. 어떤 시점의 결정도 그 시점 이후 값을 읽지 않는다.
# =============================================================================
.sd_all <- sort(unique(.act$Date))
# 집행일 = 익월 첫 거래일 (backtest_harness.R:316-323 규약을 그대로 재현)
.yy  <- year(.sd_all); .mm <- month(.sd_all)
.nxt <- as.Date(sprintf("%04d-%02d-01",
                        fifelse(.mm == 12L, .yy + 1L, .yy),
                        fifelse(.mm == 12L, 1L, .mm + 1L)))
.ei  <- findInterval(as.numeric(.nxt) - 1, .caln) + 1L
.okE <- .ei >= 1L & .ei <= length(.cal)
.sd  <- .sd_all[.okE]
.exec <- .cal[.ei[.okE]]
.M <- length(.sd)
if (!.M) stop("[RP_2511_12490] 집행일 산출 0건")

# 보유구간: [exec_i, exec_{i+1}) — 하네스 hold_pool 과 동일 (replication_harness.R:86-89)
.dayidx <- findInterval(.caln, as.numeric(.exec))    # 0 = 첫 집행 전

# 무스케일 일간 포트수익 (목표비중 고정 — 월내 drift 는 하네스가 따로 처리한다.
#   여기 경로는 s*/kill 산출용 학습통계이지 성과 산출이 아니다.)
.map  <- data.table(Date = .cal, sidx = .dayidx)[sidx >= 1L]
.wtab <- .act[Date %in% .sd, .(sidx = match(Date, .sd), Ticker, w = W0)]
.pos  <- .wtab[.map, on = "sidx", allow.cartesian = TRUE, nomatch = 0L]
.pos  <- merge(.pos, .rd0[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"), all.x = TRUE)
.pos[!is.finite(Ret), Ret := 0]                      # 미거래일 = 그날 기여 0 (하네스 동일)
.rpdt <- data.table(Date = .cal, Rp = 0)
.rpdt[.pos[, .(Rp = sum(w * Ret)), by = Date], Rp := i.Rp, on = "Date"]
.rpvec <- .rpdt$Rp
rm(.pos, .wtab, .map); gc(verbose = FALSE)

# 식(5) — 학습창 하나에서 s* 산출
.est_sstar <- function(rv) {
  rv <- rv[is.finite(rv)]
  if (length(rv) < 2L) return(NA_real_)
  v <- sd(rv) * sqrt(.ANN)                                  # TrainingVol (연환산)
  if (!is.finite(v) || v <= 0) return(NA_real_)
  nv <- cumprod(1 + rv)
  dd <- min(nv / cummax(nv) - 1)                            # TrainingMaxDD
  s_dd <- if (is.finite(dd) && dd < 0) .DD_CAP / abs(dd) else Inf
  min(.VOL_CAP / v, s_dd)
}

.scale  <- rep(NA_real_, .M)
.killed <- rep(FALSE, .M)
.trn    <- rep(NA_integer_, .M)
.nav <- 1; .peak <- 1; .buf <- numeric(0)
.cur_y <- NA_integer_; .s_now <- NA_real_; .kill <- FALSE; .n_tr <- NA_integer_

for (i in seq_len(.M)) {
  ey <- year(.exec[i])
  if (is.na(.cur_y) || ey != .cur_y) {
    # ── 새 평가구간(test 1년) 시작: kill 리셋 + s* 재추정 ──
    #    학습창 = [Jan1(ey) - 5년, Jan1(ey))  → 보유연도 시작 **전날**까지만 (PIT)
    .cur_y <- ey; .kill <- FALSE
    y0 <- as.numeric(as.Date(sprintf("%04d-01-01", ey)))
    t0 <- as.numeric(as.Date(sprintf("%04d-01-01", ey - .TRAIN_Y)))
    sel <- .caln >= t0 & .caln < y0 & .dayidx >= 1L
    .n_tr <- sum(sel)
    .s_now <- .est_sstar(.rpvec[sel])
  }
  .trn[i] <- .n_tr
  if (!is.finite(.s_now)) next          # 학습창 부재 → 논문과 동일하게 미발행
  .scale[i]  <- if (.kill) .KILL_EPS else .s_now
  .killed[i] <- .kill
  # 보유구간 일간 전진 — kill 상태는 이 구간 **안에서** 갱신되고 다음 달부터 발효
  # (월간 케이던스의 한계 — 논문은 일간 감시. FIDELITY 에 선언)
  for (k in which(.dayidx == i)) {
    x <- .scale[i] * .rpvec[k]
    .nav <- max(.nav * (1 + x), 1e-12)               # 수치 하한(파산 시 로그 붕괴 방지)
    if (.nav > .peak) .peak <- .nav
    .buf <- c(.buf, x); if (length(.buf) > .KS_WIN) .buf <- .buf[-1L]
    if (!.kill && ((.nav / .peak - 1) < -.KS_DD ||
                   (length(.buf) == .KS_WIN && (prod(1 + .buf) - 1) < .KS_R63)))
      .kill <- TRUE
  }
}

# =============================================================================
# 3-D. 최종 비중 = s* x (무스케일 책)   — 식(5) "all portfolio weights multiplied"
# =============================================================================
.sc  <- data.table(Date = .sd, SCALE = .scale, KILLED = .killed, TRN = .trn)
.out <- .act[.sc, on = "Date", nomatch = 0L][is.finite(SCALE)]
.out[, Weight := SCALE * W0]
.out[, Leg    := fifelse(Weight > 0, "long", "short")]

PORTFOLIO <- .out[is.finite(Weight) & Weight != 0, .(Date, Ticker, Weight, Leg)]
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_2511_12490] PORTFOLIO 0행 — 유니버스/국면/학습창 확인")
setorder(PORTFOLIO, Date, -Weight)

# =============================================================================
# 4. 구성 진단 (성과·등급 수치 아님 — 논문 Table 5 대조와 s*/kill 발화 기록)
#    ★감사 지적 ⑥: 이 출력이 FIDELITY 로 넘어가야 한다.
# =============================================================================
.dg <- .sig[, .(n_elig = .N, n_act = sum(REGIME)), by = Date]
.pm <- .out[SCALE > .KILL_EPS, .(nL = sum(Weight > 0), nS = sum(Weight < 0),
                                 gross = sum(abs(Weight)),
                                 wmax_g = max(abs(Weight)) / sum(abs(Weight))), by = Date]
.ss <- .sc[is.finite(SCALE)]
cat(sprintf(paste0(
  "[RP_2511_12490] adapted: EDGE = (0.7*pct(1/Size) + 0.3*z(-R10)) x I[UpFrac63(t-1..t-63) > 0.60]\n",
  "  → 활성 부분집합 z · 부호 절단 롱숏 · 사이드별 |z| 비례 50%%/50%% · x s*(식5) · kill-switch\n",
  "  자격 단면 %s행 · 국면 활성 비율 평균 %.1f%% (논문 Table 5 'Active Stock-Days 35%%')\n",
  "  발행 %d개월 %s~%s · 월평균 롱 %.0f/숏 %.0f종 (논문 187/189) · 최대비중 평균 %.2f%% of gross (논문 2-3%%)\n",
  "  s* 범위 %.3f~%.3f (중위 %.3f) · 학습창 일수 %d~%d · kill 발효 %d/%d개월\n",
  "  ★engine_direct · commission_paper=6e-05(0.6bp/unit) · 기간 절단은 러너 · %.1f분\n"),
  format(.n_elig_raw, big.mark = ","),
  100 * mean(.dg$n_act / .dg$n_elig),
  nrow(.pm), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  mean(.pm$nL), mean(.pm$nS), 100 * mean(.pm$wmax_g),
  min(.ss$SCALE), max(.ss$SCALE), median(.ss$SCALE),
  min(.ss$TRN, na.rm = TRUE), max(.ss$TRN, na.rm = TRUE),
  sum(.ss$KILLED), nrow(.ss),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
