# =============================================================================
# engine.R — RP_AUTO_2511_12490  (3판)
# "Discovery of a 13-Sharpe OOS Factor: Drift Regimes Unlock Hidden
#  Cross-Sectional Predictability"  (arXiv:2511.12490)
#   전문: arxiv.org/html/2511.12490v1 — §2.1 신호(식1~4) · §2.2 포트폴리오(식5 ·
#   kill-switch · walk-forward) · §4/Table 10 kill-switch · Table 5 특성 · Table 6 민감도
#
# ★fidelity = ADAPTED. **선언 정본 = FIDELITY.json** (이 주석은 사본이다)
#
# ===== 2판이 죽은 자리와 이번 판의 처리 ========================================
#  ▸ 2판은 실행에는 성공했고(책 247개월 발행) 정적 PIT 스캐너에서 죽었다:
#      [C1] line 283 `v <- sd(rv) * sqrt(.ANN)`  — "full-sample vol 의심".
#    이 줄이 구현하려던 것은 식(5)의 **TrainingVol** 이다. 실제로는 학습창을 잘라
#    넘긴 벡터였지만, **코드만 봐서는 전 표본 통계와 구분되지 않았다** — 스캐너가
#    읽은 그대로다. 그래서 증상(줄)을 지우는 대신 **창을 계산 지점으로 끌어왔다**:
#    통계는 이제 `sd(.rpvec[j1:j2])` 처럼 인덱스 구간 위에서만 계산되고, j2 가
#    test 구간 시작 전날 이하임을 실행 시점 assert 가 강제한다(§5-A). 창의 PIT
#    경계가 함수 인자 뒤가 아니라 식 자체에 남는다.
#  ▸ 함께 고친 것 2건 (2판의 실제 결함 — 스캐너와 무관):
#    ① kill-switch 흡수상태. 2판은 평가구간 경계에서 스위치만 풀고 NAV·peak 을
#       이어받아, 한 번 −30% 를 맞으면 peak 이 그대로라 다음 해 첫날 즉시 재발화했다
#       (실측 62/247개월 정지). 논문의 평가구간은 서로 겹치지 않는 **독립 test 실행**
#       이므로 감시 상태도 구간 시작에서 초기화한다(§5-B, 논문 침묵 → 규약 선언).
#    ② 창 결측 처리. 2판은 성분 하나라도 NA 면 그 달 횡단면에서 종목을 통째로
#       버렸다(단 하루 미거래로 10일 수익이 NA). 미거래 = 가격 불변이므로
#       **LOCF 로 채우고 그날 수익 0** 이 논문 식의 직독이다(§2). 창 길이는 여전히
#       시장 거래일로 고정된다.
#
# ===== 원문 대조 (그대로 옮긴 것) ==============================================
#   §2.1 value    = "computing inverse price for each stock then converting to
#                    cross-sectional ranks through percentile scores between 0 and 1"
#                   → 백분위 [0,1]. ★입력만 대체(1/명목주가 → 1/시가총액, FIDELITY ⑦)
#   §2.1 reversal = "trailing 10-day returns and negating them ... standardizing
#                    cross-sectionally to z-scores"
#   식(1) BASE    = 0.7 x value + 0.3 x reversal
#   식(2) UpFrac  = (1/63) SUM_{k=1..63} I[r_{t-k} > 0]      ★당일 t 제외(논문의 비대칭)
#   식(3) REGIME  = I[UpFrac > 0.60]   (종목별 게이트 — 시장 전체 아님, 엄격부등호)
#   식(4) EDGE    = BASE x REGIME
#   §2.2 산출     = 활성(EDGE!=0) 부분집합 z 표준화 → z 부호로 롱/숏 버킷 →
#                   "normalize within each side ... long 50% and short 50%"
#   식(5) s*      = min(12%/TrainingVol, 15%/|TrainingMaxDD|),  "with all portfolio
#                   weights multiplied by this factor determined once during training
#                   and applied without modification during testing"
#   §2.2/§4/T10   = kill-switch: 절대낙폭 −30% · 롤링 63일 −10%,
#                   "switches that cannot reset within evaluation periods"
#                   (논문 표본에서는 미발화 — "never activated during any OOS period")
#   §2.2          = walk-forward "five-year training periods ... followed by
#                   one-year test periods where we apply frozen strategies"
#   Table 5       = 187 long / 189 short · Largest Position 2-3% of gross ·
#                   Top Decile 35% · Daily Turnover 42% · Median Holding 8 days ·
#                   Active Stock-Days 35% of universe
#   Table 6       = Base Case  Drift Window 63 / Up Threshold 0.60 / Value Weight 0.70
#   §2.2 비용     = "0.6 basis points per unit traded"  → commission_paper = 6e-05
#
# ===== 산출 형태 ===============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏이므로 반드시 이 형태.
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"}.
#   사이드 그로스 = 0.5 x s* (kill 구간은 0.5 x eps). 총 그로스 = s*.
#   ▸ 하네스가 그로스를 보존한다(replication_harness.R:57 gross=sum|w| · :105
#     Rg = GL*Lr − GS*Sr) → s* 가 엔진에서 측정까지 실제로 전달된다.
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
#   ▸ 식(5) 학습창 = 인덱스 구간 [j1, j2]. j2 = 보유연도 1월 1일 **직전** 거래일 —
#     assert 로 강제(§5-A). kill 상태는 보유구간 시작 **전날까지**의 실현 경로에서만
#     갱신된다(§5-B 루프는 시간순 단일 방향 — 미래 인덱싱 0건).
#   C1  : 전 표본 통계 0건. 통계는 (a) 종목별 과거 롤링창 (b) 그 날짜 하나의 횡단면
#         (by=Date) (c) **과거로 닫힌 학습창 [j1,j2]** 뿐. scale()·전표본 mean/sd 0건.
#   C2  : same-day 순환참조 없음.  C3 : 같은 기간 집계→적용 없음.
#   C4  : 재무제표 패널 미사용(논문 신호가 accounting-free).  C11 : 매크로 미사용.
#   C5  : 노출 스칼라 s*·kill-switch 는 **논문 §2.2 의 사양**이며, 둘 다 홀딩월 시작
#         전에 닫힌 정보만 쓴다. 국면 게이트는 종목별 alpha 게이트라 사이징 무관.
#   C6  : 유니버스 = 각 d 의 K200/KQ150 멤버십(PIT 시변). 논문의 current-constituent
#         (자인된 생존편의)를 옮기지 않았다. §2 의 ever-member 축소는 **출력 동일**
#         (날짜별 멤버십 필터가 뒤에 그대로 걸리므로 선택집합이 바뀌지 않는다).
#   C9  : DD/VT same-day 사용 없음 — kill 판정은 전일까지의 실현 NAV.
#   C10 : 유동성 = d **직전** 20 시장거래일 평균 거래대금(frollmean 후 shift(1)).
#   C13 : 미신고 방향전환 0건. 부호가 정해지는 곳은 논문 문장 2개뿐 —
#         "negating them" · "long and short buckets based on z-scores".
#   C14/C15 : Factor DB 미접근(RAWDATA 가격·수익·거래량·시총만).
#   ▸ 비선언 idiom 자체 점검: shift()는 전부 양수 lag · shift(-N)/lead() 0건 ·
#     수동 미래 인덱싱 0건 · 전표본 cov()/mean()/sd() 0건 · 미래수익 정렬 0건 ·
#     nafill 은 locf(과거→현재)만 · cumprod/cummax 는 시간순 인과 누적.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Ret", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_2511_12490] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru  <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0   <- Sys.time()
# 서식 헬퍼 — 길이 0/비유한 인자가 sprintf 를 통째로 붕괴시키는 사고를 막는다
.fmtn <- function(x, digits = 2L) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x) != 1L || !is.finite(x)) return("NA")
  formatC(x, format = "f", digits = digits, big.mark = ",")
}
.agg  <- function(f, x) if (length(x)) f(x) else NA_real_

# =============================================================================
# 1. 상수 — 출처가 셋뿐이다: (a) 논문 명시값 (b) 지시된 고정 축 (c) 하네스 인코딩
#    임의로 고른 전략 파라미터는 없다.
# =============================================================================
# ▸ (a) 논문 명시값
.W_VALUE <- 0.7        # 식(1) value 가중            (Table 6 Base Case 0.70)
.W_REV   <- 0.3        # 식(1) reversal 가중
.REV_WIN <- 10L        # §2.1 "trailing 10-day returns"
.DRIFT_W <- 63L        # 식(2) 창 63 거래일           (Table 6 Base Case 63)
.UP_THR  <- 0.60       # 식(3) 문턱 "> 0.60"          (Table 6 Base Case 0.60)
.SIDE_G  <- 0.5        # §2.2 "long ... 50% and short ... 50%"
.VOL_CAP <- 0.12       # 식(5) 12% volatility cap
.DD_CAP  <- 0.15       # 식(5) 15% maximum drawdown constraint
.KS_DD   <- 0.30       # §4/Table 10 kill-switch 절대낙폭 −30%
.KS_R63  <- -0.10      # §4/Table 10 kill-switch 롤링 63일 −10%
.KS_WIN  <- 63L        # §4/Table 10 롤링 창 63일
.TRAIN_Y <- 5L         # §2.2 "five-year training periods"
# ▸ (b) 지시된 고정 축
.LIQ     <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN <- 20L        # 유동성 창 (거래일)
# ▸ (c) 계약·하네스 유래
.ANN     <- 252L       # 연환산 계수 — 측정 계약 정본과 동일(run_paper_replication.R:157
                       #   Return.annualized(scale = 252)). 식(5) 좌항 환산에 필요.
.KILL_EPS <- 1e-6      # kill 구간 그로스. 하네스에 flat 상태가 없다 —
                       #   시그널일 행을 비우면 W[Date==d] 가 비어 직전 책을 **계속 보유**
                       #   한다(replication_harness.R:83-89). "shutting down entirely" 를
                       #   전달하려면 그로스를 0 으로 보낼 수밖에 없고, Weight!=0 필터
                       #   (:45)가 정확한 0 을 지운다. 그래서 수치 노이즈 이하의 eps 로
                       #   인코딩한다. 전략 파라미터가 아니라 **하네스 인코딩 상수**다.

# =============================================================================
# 2. 패널 — RAWDATA 비파괴 + 시장 거래일 격자 + 미거래일 LOCF
#    ▸ 창을 "그 종목의 잔존 행"이 아니라 **시장 거래일**로 센다(1판 기각 사유).
#    ▸ 미거래일(거래정지·결측)은 가격이 움직이지 않은 날이다 → 종가 LOCF, 그날 수익 0,
#      거래대금 0. 식(2)의 I[r>0] 은 0(상승일 아님), 분모는 논문대로 고정 63.
#      2판처럼 NA 를 전파해 종목을 통째로 버리면 창 정의가 아니라 표본이 바뀐다.
# =============================================================================
.cols <- c("Date", "Ticker", "Close", "Ret", "Vol", "Size", "K200", "KQ150")
.rd0 <- RAWDATA[, .SD, .SDcols = .cols]   # ★.. 접두어는 'cols'(무점) 를 찾는다 — 점 이름은 .SDcols 로
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
.rd   <- .rd0[.grid, on = .(Ticker, Date)]      # 상장구간 x 시장거래일 (미거래 = NA 행)
setorder(.rd, Ticker, Date)
.n_grid <- nrow(.rd)
.n_obs  <- sum(is.finite(.rd$Close))            # 실제 관측(거래) 행
.rd[, Ret := NULL]                              # 수익은 아래에서 LOCF 종가로 다시 낸다

# 미거래일 = 가격 불변 → 직전 종가 유지 (locf = 과거→현재. 미래참조 아님)
.rd[, CLS := nafill(Close, type = "locf"), by = Ticker]

# 유동성 (C10): 미거래일 거래대금 0 → 20 **시장거래일** 평균 → shift(1) 로 t-1
.rd[, TV := fifelse(is.finite(Close) & is.finite(as.numeric(Vol)),
                    Close * as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, c("TV", "Vol") := NULL]

# ── value 입력 (FIDELITY ⑦ 이 정본 — 여기 주석은 사본) ────────────────────────
#   논문: value = 백분위(1 / 명목주가). 저장소에 명목주가 패널이 없다(OHLCVS 6시트가
#   전부 수정계열 · registry_migrate_ast_v11.py:74 restatement_prone = 전기간 재작성).
#   1/수정주가는 t **이후** 분할·무상증자로 재작성된 값이라 PIT 위반(상방편의)이므로 금지.
#   대체 추정기 = 1/시가총액 — 분할·무상증자에 불변(주가 x 주식수)이라 재작성이 없고,
#   accounting-free 이며 '횡단면 수준변수의 낮은 쪽 선호'라는 논문 방향과 같다.
.rd[, CAPV := as.numeric(Size)]
.rd[, INVV := fifelse(is.finite(CAPV) & CAPV > 0, 1 / CAPV, NA_real_)]
.rd[, c("CAPV", "Size") := NULL]

# reversal 원자료 — 종점 d 의 10 **시장거래일** 수익
.rd[, R10 := CLS / shift(CLS, .REV_WIN) - 1, by = Ticker]

# 국면 원자료 — 식(2): SUM_{k=1..63} I[r_{t-k} > 0] / 63
#   frollsum 은 (t-62..t) 를 덮으므로 shift(.,1) 로 한 칸 밀어 (t-63..t-1) = k=1..63.
.rd[, RET1 := CLS / shift(CLS, 1L) - 1, by = Ticker]
.rd[, UPD  := fifelse(is.finite(RET1) & RET1 > 0, 1L, 0L)]
.rd[, UP63 := shift(frollsum(UPD, .DRIFT_W, align = "right"), 1L) / .DRIFT_W, by = Ticker]
.rd[, c("RET1", "UPD") := NULL]

# 월말 **시장거래일** 격자 — 각 d 는 그 달 내부 날짜로만 결정된다(미래 참조 없음)
.me <- data.table(Date = .cal)[, .(d = max(Date)),
                               by = .(ym = year(Date) * 12L + month(Date))][order(d)]$d

# =============================================================================
# 3. 시그널일 횡단면 — 식(1)~(4)
#    ★모든 통계는 by = Date (그 날짜 단면) — 시계열 전표본 통계 0건 (C1)
# =============================================================================
.sig <- .rd[Date %in% .me & is.finite(Close)]        # 시그널일에 실제로 호가가 선 종목만

# 자격: d 의 K200/KQ150 멤버십 + 지시 축 adv20(t-1) 하한 (C6·C10)
.sig <- .sig[(.tru(K200) | .tru(KQ150)) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ]

# "valid ... EDGE scores" = 성분 3종이 모두 성립하는 종목만 그 날짜 횡단면에 든다
#   (LOCF 이후 남는 결측은 워밍업뿐 — UP63 64행 · R10 11행 · adv20 21행)
.sig <- .sig[is.finite(INVV) & is.finite(R10) & is.finite(UP63)]
.n_elig_raw <- nrow(.sig)
.sig[, NX := .N, by = Date]
.sig <- .sig[NX >= 2L]                              # 백분위·표준편차의 정의역
if (!nrow(.sig)) stop("[RP_2511_12490] 시그널 횡단면 0행 — 유니버스/유동성 확인")

# 식(1) 성분 — value = 수준변수 백분위 [0,1] · reversal = (-R10) 횡단면 z
.sig[, PCT  := (frank(INVV, ties.method = "average") - 1) / (NX - 1), by = Date]
.sig[, RVR  := -R10]                                # 논문 "negating them" — 신호 정의
.sig[, REVZ := (RVR - mean(RVR)) / sd(RVR), by = Date]
.sig <- .sig[is.finite(REVZ)]                       # sd = 0 인 단면은 z 미정의

# 식(1)(3)(4)
.sig[, BASE   := .W_VALUE * PCT + .W_REV * REVZ]
.sig[, REGIME := fifelse(UP63 > .UP_THR, 1L, 0L)]
.sig[, EDGE   := BASE * REGIME]

# =============================================================================
# 4. 무스케일 책 (그로스 1.0) — §2.2 첫 문단 그대로
#    활성(EDGE!=0) 부분집합 z 표준화 → z 부호로 롱/숏 → 사이드별 정규화 50/50
#    ▸ 사이드 **내부** 배분 함수는 논문 미명시다. "normalize within each side"를 z 에
#      적용한 직독 = |z| 비례를 택한다. Table 5(최대 2-3% · 상위데실 35%)는 EW 를
#      배제할 뿐 |z| 비례를 유일하게 결정하지 못한다(FIDELITY ⑩ — 근거 강도 정정).
#    ▸ zero-mean 이므로 SUM z+ = SUM |z-| → 사이드별 정규화가 net 0 을 정확히 낸다.
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
if (!nrow(.act)) stop("[RP_2511_12490] 무스케일 책 0행")
.act[, W0 := fifelse(Z > 0, .SIDE_G * Z / GP, .SIDE_G * Z / GN)]

# =============================================================================
# 5. 식(5) 노출 스칼라 s* + kill-switch  (walk-forward 케이던스)
#   ★이 블록은 **비중 결정 단계**다 — 논문이 "all portfolio weights multiplied by
#     this factor" 라고 명시한 그 단계. 성과 측정이 아니다(측정은 호출자 계약).
#     s*/kill 을 내려면 전략 자신의 경로가 필요하므로 무스케일 경로를 재구성한다.
#   ▸ 학습 경로 = 무스케일(그로스 1.0) 책의 일간 수익 — 논문의 training run 과 동일.
#   ▸ 실현 경로 = s*·kill 이 적용된 책의 일간 수익 — kill 판정 대상.
#   ▸ 시간 방향 단일. 어떤 시점의 결정도 그 시점 이후 값을 읽지 않는다.
# =============================================================================
.sd_all <- sort(unique(.act$Date))
# 집행일 = 익월 첫 거래일 (backtest_harness.R:316-323 규약을 그대로 재현)
.yy   <- year(.sd_all); .mm <- month(.sd_all)
.nxt  <- as.Date(sprintf("%04d-%02d-01",
                         fifelse(.mm == 12L, .yy + 1L, .yy),
                         fifelse(.mm == 12L, 1L, .mm + 1L)))
.ei   <- findInterval(as.numeric(.nxt) - 1, .caln) + 1L
.okE  <- .ei >= 1L & .ei <= length(.cal)
.sd   <- .sd_all[.okE]
.exec <- .cal[.ei[.okE]]
.M    <- length(.sd)
if (!.M) stop("[RP_2511_12490] 집행일 산출 0건")

# 보유구간: [exec_i, exec_{i+1}) — 하네스 hold_pool 과 동일 (replication_harness.R:86-89)
.dayidx <- findInterval(.caln, as.numeric(.exec))    # 0 = 첫 집행 전
.i_pos1 <- suppressWarnings(min(which(.dayidx >= 1L)))
if (!is.finite(.i_pos1)) stop("[RP_2511_12490] 보유일 0건 — 집행일 정합 확인")

# 무스케일 일간 포트수익 (목표비중 고정 — 월내 drift 와 비용은 하네스가 따로 처리한다.
#   이 경로는 s*/kill 산출용 학습통계이지 성과 산출이 아니다. FIDELITY ⑥(a))
.map  <- data.table(Date = .cal, sidx = .dayidx)[sidx >= 1L]
.wtab <- .act[Date %in% .sd, .(sidx = match(Date, .sd), Ticker, w = W0)]
.pos  <- .wtab[.map, on = "sidx", allow.cartesian = TRUE, nomatch = 0L]
.pos  <- merge(.pos, .rd0[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"), all.x = TRUE)
.pos[!is.finite(Ret), Ret := 0]                      # 미거래일 = 그날 기여 0 (하네스 동일)
.rpdt <- data.table(Date = .cal, Rp = 0)
.rpdt[.pos[, .(Rp = sum(w * Ret)), by = Date], Rp := i.Rp, on = "Date"]
.rpvec <- .rpdt$Rp
.rpvec[!is.finite(.rpvec)] <- 0
rm(.pos, .wtab, .map); gc(verbose = FALSE)

# ── 5-A. 식(5) — 학습창 [j1, j2] 하나에서 s* 산출 ────────────────────────────
#   ★창을 인자로 넘겨받지 않고 **인덱스로 잘라 쓴다**: 통계가 어느 구간에서 나왔는지가
#     계산 지점에 남아야 한다. 2판은 잘린 벡터를 받아 sd() 를 돌려, 코드만 봐서는
#     전 표본 통계와 구분되지 않았다(정적 PIT 스캐너도 같은 이유로 위반으로 읽었다).
#   ★반환 = c(변동성 제약 s, 낙폭 제약 s). s* = min(둘) 은 호출부에서 — 어느 쪽이
#     결속했는지 세기 위해서다(논문 OOS 실현 sigma 12.0% = 캡 일치 → 논문 s* 는 vol 결속).
.est_sstar <- function(j1, j2) {
  if (!is.finite(j1) || !is.finite(j2) || (j2 - j1) < 1L) return(c(NA_real_, NA_real_))
  v_ann <- sd(.rpvec[j1:j2]) * sqrt(.ANN)            # TrainingVol (학습창 한정)
  nv    <- cumprod(1 + .rpvec[j1:j2])                # 학습창 NAV (시간순 인과 누적)
  mdd   <- min(nv / cummax(nv) - 1)                  # TrainingMaxDD
  c(if (is.finite(v_ann) && v_ann > 0) .VOL_CAP / v_ann else NA_real_,
    if (is.finite(mdd) && mdd < 0) .DD_CAP / abs(mdd) else Inf)
}

# ── 5-B. walk-forward 케이던스 + kill-switch ────────────────────────────────
#   평가구간 = test 1년. 구간 시작에서 (a) s* 재추정(직전 5년 학습창) (b) 스위치 해제
#   (c) 감시 상태(NAV·peak·63일 버퍼) 초기화.
#   ▸ (c) 는 논문 침묵 구간의 규약이다(FIDELITY ⑤). 논문의 세 test 창은 서로 겹치지
#     않는 독립 실행이라 연속 경로가 원문에 존재하지 않는다. 상태를 이어받으면 peak 이
#     남아 "평가구간 내 리셋 불가"가 **영구 정지**로 변질된다(2판 실측 62/247개월).
.scale  <- rep(NA_real_, .M)
.killed <- rep(FALSE, .M)
.trn    <- rep(NA_integer_, .M)
.bind   <- rep(NA_character_, .M)
.nav <- 1; .peak <- 1; .buf <- numeric(0)
.cur_y <- NA_integer_; .s_now <- NA_real_; .kill <- FALSE
.n_tr <- NA_integer_; .b_now <- NA_character_

for (i in seq_len(.M)) {
  ey <- year(.exec[i])
  if (is.na(.cur_y) || ey != .cur_y) {
    .cur_y <- ey
    .kill  <- FALSE
    .nav <- 1; .peak <- 1; .buf <- numeric(0)
    .y0 <- as.Date(sprintf("%04d-01-01", ey))               # test 구간 시작
    .tt <- as.Date(sprintf("%04d-01-01", ey - .TRAIN_Y))    # 5년 학습창 시작
    j2 <- findInterval(as.numeric(.y0) - 1, .caln)          # test 시작 직전 거래일
    j1 <- max(findInterval(as.numeric(.tt) - 1, .caln) + 1L, .i_pos1)
    # ★PIT 실행 assert — 학습창 종점이 test 구간 시작보다 앞이어야 한다.
    if (j2 >= j1 && !(.cal[j2] < .y0))
      stop("[RP_2511_12490] PIT 정지 — 식(5) 학습창 종점이 test 구간 시작 이후")
    .n_tr  <- if (j2 >= j1) j2 - j1 + 1L else 0L
    .zz    <- .est_sstar(j1, j2)
    .s_now <- suppressWarnings(min(.zz))
    if (!is.finite(.s_now)) .s_now <- NA_real_
    .b_now <- if (!is.finite(.s_now)) NA_character_ else
      if (.zz[1] <= .zz[2]) "vol" else "dd"
  }
  .trn[i] <- .n_tr
  if (!is.finite(.s_now)) next          # 학습창 부재 → 논문과 동일하게 미발행
  .scale[i]  <- if (.kill) .KILL_EPS else .s_now
  .killed[i] <- .kill
  .bind[i]   <- .b_now
  # 보유구간 일간 전진 — kill 상태는 이 구간 **안에서** 갱신되고 다음 리밸부터 발효
  # (월간 케이던스의 한계 — 논문은 일간 감시·일간 청산. FIDELITY ⑥(b))
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
# 6. 최종 비중 = s* x (무스케일 책)  — 식(5) "all portfolio weights multiplied"
# =============================================================================
.sc  <- data.table(Date = .sd, SCALE = .scale, KILLED = .killed,
                   TRN = .trn, BIND = .bind)
.out <- .act[.sc, on = "Date", nomatch = 0L][is.finite(SCALE)]
.out[, Weight := SCALE * W0]
.out[, Leg    := fifelse(Weight > 0, "long", "short")]

PORTFOLIO <- .out[is.finite(Weight) & Weight != 0, .(Date, Ticker, Weight, Leg)]
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_2511_12490] PORTFOLIO 0행 — 유니버스/국면/학습창 확인")
setorder(PORTFOLIO, Date, -Weight)

# =============================================================================
# 7. 구성 진단 (성과·등급 수치 아님 — 논문 Table 5 대조 + s*/kill 발화 기록)
#    ★이 출력이 FIDELITY 의 실현형 선언과 같은 수를 가리켜야 한다.
# =============================================================================
.dg <- .sig[, .(n_elig = .N, n_act = sum(REGIME)), by = Date]
.pm <- .out[SCALE > .KILL_EPS, .(nL = sum(Weight > 0), nS = sum(Weight < 0),
                                 wmax_g = max(abs(Weight)) / sum(abs(Weight))), by = Date]
.ss <- .sc[is.finite(SCALE)]
cat(sprintf(paste0(
  "[RP_2511_12490] adapted — EDGE = (0.7*pct(1/Size) + 0.3*z(-R10)) x I[UpFrac63(t-1..t-63) > 0.60]\n",
  "  책 = 활성 부분집합 z · 부호로 롱/숏 · 사이드별 |z| 비례 50/50 · x s*(식5) · kill-switch\n",
  "  격자 %s행(관측 %s · 미거래 %s%% → LOCF·수익 0) · 시장거래일 %s · 월말 %s\n",
  "  자격 단면 %s행 · 국면 활성 비율 평균 %s%% (논문 Table 5 'Active Stock-Days 35%% of universe')\n",
  "  발행 %s개월(정상노출 %s) %s~%s · 월평균 롱 %s/숏 %s종 (논문 Table 5 187/189)\n",
  "  최대비중 평균 %s%% of gross (논문 Table 5 'Largest Position 2-3%%')\n",
  "  s* %s~%s (중위 %s · 결속 vol %s/dd %s개월) · 학습창 일수 %s~%s · kill 발효 %s/%s개월\n",
  "  engine_direct · commission_paper=6e-05(0.6bp/unit) · 기간 절단은 러너 · %s분\n"),
  .fmtn(.n_grid, 0), .fmtn(.n_obs, 0), .fmtn(100 * (1 - .n_obs / .n_grid), 1),
  .fmtn(length(.cal), 0), .fmtn(length(.me), 0),
  .fmtn(.n_elig_raw, 0), .fmtn(100 * mean(.dg$n_act / .dg$n_elig), 1),
  .fmtn(uniqueN(PORTFOLIO$Date), 0), .fmtn(nrow(.pm), 0),
  as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  .fmtn(.agg(mean, .pm$nL), 1), .fmtn(.agg(mean, .pm$nS), 1),
  .fmtn(100 * .agg(mean, .pm$wmax_g), 2),
  .fmtn(.agg(min, .ss$SCALE), 3), .fmtn(.agg(max, .ss$SCALE), 3),
  .fmtn(.agg(median, .ss$SCALE), 3),
  .fmtn(sum(.ss$BIND == "vol", na.rm = TRUE), 0),
  .fmtn(sum(.ss$BIND == "dd",  na.rm = TRUE), 0),
  .fmtn(.agg(min, .ss$TRN), 0), .fmtn(.agg(max, .ss$TRN), 0),
  .fmtn(sum(.ss$KILLED), 0), .fmtn(nrow(.ss), 0),
  .fmtn(as.numeric(difftime(Sys.time(), .t0, units = "mins")), 1)))
