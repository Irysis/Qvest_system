# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2007_081   (3판 · 2026-09-06 · 재료 4편 중 [A] 를 쓴다)
#
#   [A] Choi · Choi · Kang, "Maximum drawdown, recovery, and momentum"
#       (arXiv:1403.8125)   https://arxiv.org/abs/1403.8125   전문 = arxiv.org/html/1403.8125v1
#       → **두 시간척도를 모두 쓴다**: 월간 6/6 모멘텀(Table 3, CM 최우수) + 주간 6/6 반전(Table 2, R 최우수)
#   [H] Borri · Chetverikov · Liu · Tsyvinski, "One Factor to Bind the Cross-Section of Returns"
#       (arXiv:2404.08129) — **이 판에 코드가 없다.** 모형·추정(§2 3단계)·예측수익·5분위 정렬 어느 것도
#       구현하지 않는다 (FIDELITY.changed ③ (A) — 2판 잔차 설계의 사전등록 반증 실패 + KR 실측 사유)
#   [B] Polimenis, "Uncovering a factor-based expected return conditioning structure with
#       Regression Trees jointly for many stocks" (arXiv:2007.08115) — 미사용 (FIDELITY.changed ③ (B))
#   [C] Pinchuk, "Labor Income Risk and the Cross-Section of Expected Returns" (arXiv:2301.09173) — 미사용 (③ (C))
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
# ★2판(engine.rejected1.R · Score = CM([H] 잔차 경로))은 측정됐다: Grade C · PORT_t 0.788 · SR 0.567 ·
#   MDD 0.650 · Calmar 0.204 · IC −0.006 · FMB t −0.54 (stage_artifacts/replication/20260906_231128_5756).
#   자기 반증 조건(PORT_t > 0.925 ∧ Calmar > 0.240)이 둘 다 깨졌고, 엔진 자신의 F1 이 '원수익 CM 과
#   top-25 겹침 0.80'(25종 중 5종만 교체)을 인쇄했다 — [H] 잔차 정화는 [A] 의 선택을 거의 바꾸지 않고
#   알파만 낮췄다. 그 설계는 폐기한다. 이 판은 그 수리가 아니라 **새 설계**다.
#
# =============================================================================
# 한 문장 요약
# =============================================================================
#   [A] 는 같은 시장(KOSPI 200)에서 두 가지를 보고한다: 6개월 척도에서는 **모멘텀**이고 최우수 규칙은
#   CM = C − MDD(누적수익에서 최대낙폭을 한 번 더 뺀 값, 승자 롱), 6주 척도에서는 **반전**이고 최우수
#   규칙은 R = 저점→말일 회복(회복이 작은 패자 롱 — "the asset already spent the fuel for the
#   reversion"). 이 판은 그 둘을 한 종목 점수로 합친다:
#
#       Score_i = CM_i(6개월 경로) − R_i(6주 경로)
#
#   = "6개월 경로가 매끄럽게 상승했고(중기 모멘텀), 최근 6주의 저점에서 아직 반등을 소진하지 않은
#      (단기 반전 여지) 종목". 두 항 모두 로그수익 단위이고 가중은 논문 Table 1 의 정수 가중(CM=(1,2,1) ·
#   R=(0,0,1)) 그대로, 주간 항의 부호는 논문이 선언한 contrarian 방향이다. 자유 파라미터 0.
#
# =============================================================================
# §1. [A] 원문 대조  (본 세션 2026-09-06 · arxiv.org/html/1403.8125v1 직접 판독 2회 · 따옴표 안 = 축자)
# =============================================================================
#  (A1) 정의  "P(t) is the log-price at time t" · "R(t,τ) is the log-return between t and τ" ·
#             MDD = max_{τ∈(0,T)}( max_{t∈(0,τ)}( P(t) − P(τ) ) ) · "t* is the moment for the end of the
#             maximum drawdown formation" · R = R(t*, T) ·
#             "C = R_I + R_II + R_III = PP − MDD + R"  (R_I = 시작→peak · R_II = peak→trough = −MDD ·
#             R_III = trough→말일 = R)
#  (A2) Table 1  C(1,1,1) · M(0,1,0) · **R(0,0,1)** · RM(0,1,1) · **CM(1,2,1)** · CR(1,1,2) · CMR(1,2,2)
#  (A3) §3.1  "The KOSPI 200 is a stock benchmark index that is the value-weighted and sector-diversified
#             index with 200 stocks in South Korea stock markets. Historical price information and
#             component-roster are downloaded from Korea Exchange. The period from January 2003 to
#             December 2012 is considered."
#  (A4) §3.2  "Based on given selection rules during 6 months (weeks) of estimation period, assets in market
#             universes are sorted in ascending order. In this study, most criteria will be used in
#             increasing order except for the maximum drawdown." · "The group 1 is for losers that exhibit
#             the worst ranking scores and the last group is for the best performers in the selection
#             rules." · "The winner group is at long (short) position and the loser group is at short
#             (long) position." · "In the cases of the S&P 500 and KOSPI 200 universes, numbers of groups
#             are 10." · "The portfolio is constructed at the beginning of every month, i.e. it is the
#             overlapping portfolio." · "After 6 months (weeks) of the holding period, each basket is
#             liquidated."
#  (A5) Table 3 (monthly 6/6 momentum, KOSPI 200) W−L 월평균/σ: C 1.3305/6.8258 · M 1.0234/6.5769 ·
#             R 0.3740/4.0823 · RM 1.2803/6.2406 · **CM 1.4330/7.0357(최우수)** · CR 1.1028/6.5956 ·
#             CMR 1.3106/6.7290 · CM 승자 1.7005/8.0623 · 패자 0.2676/9.1117
#  (A6) Table 2 (weekly 6/6 **contrarian**, KOSPI 200) L−W 주평균/σ: C 0.0731/2.8417 · M −0.0010/3.1694 ·
#             **R 0.1455/1.7567(최우수)** · RM 0.0295/2.7489 · CM 0.0335/3.0442 · CR 0.0857/2.6649 ·
#             CMR 0.0779/2.8645 · R 승자 0.1688/4.0728 · **패자 0.3143/3.3376** (패자 > 승자 = 반전)
#  (A7) §4.1.1·결론  "In weekly scale, the contrarian portfolios constructed by the recovery measures
#             exhibit the outperformance over the traditional contrarian strategy." · "The R, CR, and CMR
#             criteria are the best stock selection rules for the weekly contrarian strategy in any
#             markets." · "In monthly scale, the maximum drawdown associated strategies outperform the
#             traditional momentum strategy." · 해석: 회복이 작을수록 반전 여력이 남아 있다
#             ("the asset already spent the fuel for the reversion").
#  (A8) 원문이 침묵하는 것: 형성창 내부 표본주기(§3.1 은 자료원·기간만 · 위험 측정만 "calculated from the
#             daily time series of the overlapping portfolio") · N 이 10 의 배수가 아닐 때의 분할 ·
#             동값 처리 · 거래비용(자기 분석에 미적용) · 유동성 필터.
#  (A9) 저장소 실측(고정 축 top-25 롱온리 EW · 월간 · 15bps · K200∪KQ150 · 2005~):
#       · [A] 충실구현(10-decile 롱숏 · J-T 6/6 · 일별 로그가격 경로) = PORT_t −0.639 · Grade F → recent_regime
#         구제 (stage_artifacts/replication/20260904_163647_18444)
#       · 같은 entry 의 B1_1 = 그 CM 신호(가중 0.5) + 등록부 팩터 C01_SUE(0.5) · PORT_t 0.925 · SR 0.631 ·
#         CAGR 0.138 · MDD 0.577 · Calmar 0.240 · C  ← 순수 CM top-25 는 이 축에서 미측정. 가장 가까운 비교군.
#       · 같은 entry 의 B1_4 = CM 신호(0.5) + 등록부 팩터 M11_ST_Reversal(0.5) · **PORT_t 1.502** · SR 0.688 ·
#         CAGR 0.166 · MDD 0.669 · Calmar 0.247 · C  ← "CM 에 단순 1개월 반전을 얹으면 오른다" 의 실측.
#
# =============================================================================
# §2. 결합 연산자 — 무엇을 어떻게 붙였나 (평균이 아니다 · 두 엔진 신호의 rank-Z 0건)
# =============================================================================
#   형성일 f = 매월 마지막 거래일(전 종목 통합 격자). 집행 = 익 거래일(러너).
#   월간 창 W_m = (me[k−6], f]  — 6개월 형성 (A4), 그 종목의 일별 종가 로그가격 경로
#   주간 창 W_w = (f − 42일, f]   — 6주 형성 (A4), 같은 방식의 일별 경로  (6주 = 6×7 캘린더일)
#   경로 path = log(P) − log(P_0), P_0 = 창 첫 관측 종가 · dd = path − cummax(path) · t* = argmin dd ·
#   peak = argmax path[1..t*] · R_I = path(peak) · R_II = path(t*) − path(peak) = −MDD · R_III = path(T) − path(t*)
#   ▸ 월간 항  CM_m = 1·R_I + 2·R_II + 1·R_III  (Table 1 CM · 오름차순 정렬의 승자 = 큰 값 롱)
#   ▸ 주간 항  R_w  = 0·R_I + 0·R_II + 1·R_III  (Table 1 R  · 오름차순 정렬의 패자 = 작은 값 롱, contrarian)
#   ▸ Score = CM_m − R_w     (주간 항의 음부호 = 논문의 contrarian 방향 · 창 간 상대 척도 1 · 둘 다 로그수익)
#   ★R_w ≥ 0 이 구조로 성립한다(t* 가 dd 의 최솟값이므로 path(T) ≥ path(t*)) — 그래서 주간 항은 '이미 반등한
#     만큼의 벌점'이고, 저점에 있는 종목(R_w = 0)은 벌점 0 이며 그 사이의 순위는 CM 이 정한다.
#   ★퇴화 경계: 주간 항이 순위를 못 바꾸면(엔진 F1: CM 단독 top-25 와 겹침 ≥ 0.80) 이 판은 [A] 월간의
#     재라벨이다 — 결과와 무관하게 설계 실패로 기록한다. 그 반대(겹침 < 0.80)면 두 시간척도가 실제로
#     다른 종목을 고른 것이고, 그 차이의 값어치는 계약이 잰다(FIDELITY ②).
#
# =============================================================================
# §3. PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#   ▸ 구조 경계: 모든 창이 (·, f] 로 닫히고 종점 = f 의 종가. 러너가 익 거래일에 집행 → 신호창 ∩ 보유월 = ∅.
#     f 를 넘는 날짜·음수 shift·lead·전표본 통계는 코드에 없다(shift 는 +1 한 번 — adv20 의 t−1).
#   C1 전표본 통계 0건(모든 통계는 창 내부 경로 통계 · 순위는 그 날짜 단면) · C2 f 종가까지 · C3 형성창 종점
#   f < 보유월 · C4 재무 미사용 · C5 오버레이 없음 · C6 유니버스 = f 의 K200/KQ150 멤버십(PIT 시변) ·
#   C7 shift 는 +1 뿐 · C9 DD/VT 미사용 · C10 유동성 = f 직전 20 거래일 평균 거래대금(frollmean 후 shift(1)) ·
#   C11 외부 매크로 미사용 · C13 NEGATE/FLIP 0건(방향 = 논문이 정한 두 곳: 월간 승자 롱 · 주간 패자 롱) ·
#   C15 팩터 DB 미접근 · rawdata Market 열 미사용.
#
# =============================================================================
# §4. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = CM_m − R_w (로그수익 단위 · 클수록 롱).
#   러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · n_long 25 · n_max 25).
#   commission_paper = null(논문 gross). 기간 절단(2005-01-01~)은 러너가 적용한다 — 엔진은 기간을 선택하지 않는다.
#   ★판정·창·문턱에 쓰이는 수치는 전부 아래 §0 상수 블록에 있다. 그 밖의 구조 리터럴(shift 1 = t−1 · 경로 정의역
#     n ≥ 2 · 결측 거래량 = 0 · 월 인덱스 12 · nomatch 0 · 표시용 ×100)까지 FIDELITY._notes.constants 표가 전수
#     열거한다 — 표 밖의 수치 리터럴은 이 파일에 없다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_CM_R] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()

# =============================================================================
# 0. 상수 — 출처가 셋뿐이다: (a) [A] 명시값  (b) 지시된 고정 축  (c) 진단 전용(신호에 안 들어간다)
#    ★판정·창·문턱 수치는 이 블록이 전부다. 구조 리터럴(shift 1 · n≥2 · 결측 거래량 0 · 월 인덱스 12 ·
#      nomatch 0 · 표시 ×100)은 코드 자리에 있고 FIDELITY._notes.constants 표가 함께 전수 열거한다.
# =============================================================================
# ▸ (a) [A] 명시값
.W_CM    <- c(1, 2, 1)     # Table 1 CM = (R_I, R_II, R_III) 가중 = C − MDD   (월간 최우수, Table 3)
.W_R     <- c(0, 0, 1)     # Table 1 R  = (0, 0, 1) = 회복 R                    (주간 최우수, Table 2)
.FORM_M  <- 6L             # §3.2 "6 months ... of estimation period" — 월말 격자 6스텝
.FORM_W  <- 6L             # §3.2 "6 ... (weeks) of estimation period" — 6주
.WEEK_D  <- 7L             # 1주 = 7 캘린더일 → 주간 창 = 6×7 = 42 캘린더일 (창 내부 표본주기는 일별 — 원문 침묵, 규약)
# ▸ (b) 지시된 고정 축 (두 논문에 없다 — FIDELITY.changed 에 선언)
.LIQ     <- 2e8            # adv20(t−1) 하한 (KRW)
.LIQ_WIN <- 20L            # 유동성 창 (거래일) · 뒤의 shift(1) 이 종점을 f−1 로 만든다
# ▸ (c) 진단 전용 — Score 계산에 쓰이지 않는다
.NTOP     <- 25L           # 고정 축 종목수 — top-25 겹침 진단의 n
.DIAG_MIN <- 5L            # 순위상관을 계산하는 최소 횡단면(그 아래는 NA 로 인쇄)
.OVL_MAX  <- 0.80          # F1/F2 재라벨 판정 문턱(겹침 중앙 ≥ 0.80 = 한 항이 무작동)
.RANGE0   <- as.Date("2005-01-01")   # F4 월 결번 진단의 분모 범위(측정구간 시작 = 러너 start_date)

# =============================================================================
# 1. 보조 함수
# =============================================================================
.as_flag <- function(x) {                     # 멤버십 플래그: 논리/0-1/문자 혼재 방어
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}
.med <- function(x) { x <- as.numeric(x); x <- x[is.finite(x)]; if (length(x)) stats::median(x) else NA_real_ }

# ---- 형성창 로그가격 경로 → C / MDD / 3-국면 (창 내부 통계만, C1) ----------------
#   RP_AUTO_1403_8125/engine.R 의 .mdd_stats 와 동일(그 판은 감사 faithful). cl = 창 안 그 종목의 거래일 종가
#   (Date 오름차순). ★경로는 미처리다: path = log(P) − log(P_0). 증분 절단·winsorize·clip 없음(원문 식 그대로).
#   ★cummax 는 t≤τ 포함형 — 단조 상승 경로에서 MDD = 0 (비음수 규약). n < 2 는 경로 정의 불가 = 정의역 밖.
.path_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L)
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
       RIII = path[n]  - path[ts],              # R (>= 0: t* 가 dd 최솟값이므로 path(T) >= path(t*))
       nobs = n)
}

# =============================================================================
# 2. 일간 패널 → 멤버십 · 유동성(t−1) · 월말 격자   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd[, MEM := .as_flag(K200) | .as_flag(KQ150)]
.rd[, c("K200", "KQ150") := NULL]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[COMBO_CM_R] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
# 거래대금(거래량 결측 = 그날 회전 0). adv20 후 shift(1) → 종점 t−1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, c("TV", "Vol") := NULL]

# 월말 거래일 격자 (전 종목 통합 마지막 거래일) — 각 f 는 그 달 내부 날짜로만 결정된다.
#   RAWDATA 의 마지막(진행 중) 달도 격자에 있다: 그 형성은 익월 집행이 없어 백테스트에 안 들어간다.
.rd[, ym := year(Date) * 12L + month(Date)]
.me_dates  <- sort(.rd[, .(f = max(Date)), by = ym]$f)
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date)
cat(sprintf("[COMBO_CM_R] 패널 %s행 · %s~%s · 월말 %d개 · 상수: CM(%s) R(%s) 창 %d개월/%d주(=%d일) · adv20(t-1) >= %.0e\n",
            format(nrow(.rd), big.mark = ","), as.character(min(.all_dates)), as.character(max(.all_dates)),
            length(.me_dates), paste(.W_CM, collapse = ","), paste(.W_R, collapse = ","),
            .FORM_M, .FORM_W, .FORM_W * .WEEK_D, .LIQ))

# =============================================================================
# 3. 형성월 루프 — 월간 CM(6개월 경로) · 주간 R(6주 경로) → Score = CM − R
# =============================================================================
.OUT <- vector("list", length(.me_dates)); .LOG <- vector("list", length(.me_dates))
.skip_warm <- 0L; .skip_def <- 0L
for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) { .skip_warm <- .skip_warm + 1L; next }          # me_dates[k-6] 필요 (워밍업)
  f    <- .me_dates[k]
  w0   <- .me_dates[k - .FORM_M]
  wd_m <- .all_dates[.all_dates > w0 & .all_dates <= f]              # 6개월 일별 격자 (종점 = f)
  wd_w <- .all_dates[.all_dates > (f - .FORM_W * .WEEK_D) & .all_dates <= f]   # 6주 일별 격자 (종점 = f)
  if (!length(wd_m) || !length(wd_w)) { .skip_def <- .skip_def + 1L; next }

  # ---- 자격: f 의 K200/KQ150 멤버십 + 지시 축 adv20(t−1) 하한 (C6 · C10) — f 에 종가가 있는 종목만 ----
  rf   <- .rd[.(f), .(Ticker, MEM, ADV20_L1), nomatch = 0L]
  elig <- rf[MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (!length(elig)) { .skip_def <- .skip_def + 1L; next }

  pm <- .rd[.(wd_m), .(Date, Ticker, Close), nomatch = 0L][Ticker %chin% elig]
  pw <- .rd[.(wd_w), .(Date, Ticker, Close), nomatch = 0L][Ticker %chin% elig]
  if (!nrow(pm) || !nrow(pw)) { .skip_def <- .skip_def + 1L; next }
  setorder(pm, Ticker, Date)                                         # 그룹 내 Date 오름차순 보장
  setorder(pw, Ticker, Date)

  # ---- 두 창의 3-국면 분해 (커버리지로 거르지 않는다 — 원문에 그 요건이 없다. 진단으로만 남긴다) ----
  sm <- pm[, .path_stats(Close), by = Ticker]
  sm[, cm := .W_CM[1] * RI + .W_CM[2] * RII + .W_CM[3] * RIII]      # CM = C − MDD (월간, 승자 롱)
  sw <- pw[, .path_stats(Close), by = Ticker]
  sw[, rw := .W_R[1] * RI + .W_R[2] * RII + .W_R[3] * RIII]         # R  = 회복    (주간, 패자 롱)

  # ---- 결합: 두 항이 모두 정의된 종목만 (정의역 — 스크린 아님) · Score = CM − R ----
  st <- merge(sm[is.finite(cm), .(Ticker, cm, MDD_m = MDD, C_m = C, n_m = nobs)],
              sw[is.finite(rw), .(Ticker, rw, n_w = nobs)], by = "Ticker")
  if (!nrow(st)) { .skip_def <- .skip_def + 1L; next }
  st[, Score := cm - rw]                                             # 음부호 = 논문의 주간 contrarian 방향 (A4·A6)
  setorder(st, -Score, Ticker)                                       # 결정론적 동값 처리 (Score 내림, Ticker 오름)
  .OUT[[k]] <- data.table(Date = f, Ticker = st$Ticker, Score = st$Score)

  # ---- 진단 (전부 이 형성일 단면·창 내부 통계 — 미래참조 0) ----
  N  <- nrow(st); nt <- min(.NTOP, N)
  top_s  <- st$Ticker[seq_len(nt)]
  o_cm   <- order(-st$cm, st$Ticker)                                 # 월간 CM 단독의 순위
  o_rw   <- order(st$rw, st$Ticker)                                  # 주간 R 단독(오름차순 = 패자 우선)의 순위
  .LOG[[k]] <- data.table(
    f = f, N = N, N_elig = length(elig), N_m = sum(is.finite(sm$cm)), N_w = sum(is.finite(sw$rw)),
    share_r0  = mean(st$rw == 0),                                    # f 에 6주 저점인 종목 비율 (벌점 0)
    rho_cm_rw = if (N >= .DIAG_MIN) suppressWarnings(stats::cor(st$cm, st$rw, method = "spearman")) else NA_real_,
    ovl_cm    = length(intersect(top_s, st$Ticker[o_cm][seq_len(nt)])) / nt,
    ovl_rw    = length(intersect(top_s, st$Ticker[o_rw][seq_len(nt)])) / nt,
    rw_top = .med(st$rw[seq_len(nt)]),    rw_all = .med(st$rw),
    cm_top = .med(st$cm[seq_len(nt)]),    cm_all = .med(st$cm),
    mdd_top = .med(st$MDD_m[seq_len(nt)]), mdd_all = .med(st$MDD_m),
    cov_m = .med(st$n_m) / length(wd_m),   cov_w = .med(st$n_w) / length(wd_w))
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop(sprintf("[COMBO_CM_R] FACTORS 0행 — 워밍업 skip %d · 정의역 skip %d", .skip_warm, .skip_def))
setorder(FACTORS, Date, -Score)

# =============================================================================
# 4. 보고 — 구성 요약 + 엔진이 스스로 인쇄하는 반증 4종 (성과 수치 선언 아님 · 등급은 계약이 낸다)
# =============================================================================
LG <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
# F4 — ★세기 전에 범위를 선언한다: 분모 = 측정구간(.RANGE0~)의 월말 중 워밍업 이후의 것.
.cand_f <- .me_dates[.me_dates >= .RANGE0 & seq_along(.me_dates) > .FORM_M]
.got_f  <- LG$f[LG$f >= .RANGE0]
.miss   <- !(.cand_f %in% .got_f)
.rl     <- rle(.miss)
.gapmax <- if (any(.miss)) max(.rl$lengths[.rl$values]) else 0L
.f1 <- .med(LG$ovl_cm); .f2 <- .med(LG$ovl_rw); .f3 <- .med(LG$rho_cm_rw)

cat(sprintf(paste0(
  "[COMBO_CM_R] combination: Score = CM(6개월 경로) − R(6주 경로)  — [A] 월간 모멘텀(Table 3) × 주간 반전(Table 2)\n",
  "  [A] Table 1 CM(%s) 승자 롱 · Table 1 R(%s) 패자 롱(contrarian, 음부호) · 일별 로그가격 경로 · 미처리(절단/윈저 0)\n",
  "  형성 %d개월(%s~%s · 워밍업 skip %d · 정의역 skip %d) · FACTORS %s행 · 횡단면 중앙 %d종(적격 중앙 %d)\n",
  "  [진단·비스크린] 창 관측 커버리지 중앙 월간 %.2f / 주간 %.2f · 6주 저점 종목 비율 중앙 %.2f · 창내 MDD 중앙 %.1f%%(top-25 %.1f%%)\n",
  "  top-25 의 R_w 중앙 %.3f (전체 %.3f) · CM 중앙 %.3f (전체 %.3f)\n"),
  paste(.W_CM, collapse = ","), paste(.W_R, collapse = ","),
  nrow(LG), as.character(min(LG$f)), as.character(max(LG$f)), .skip_warm, .skip_def,
  format(nrow(FACTORS), big.mark = ","), as.integer(.med(LG$N)), as.integer(.med(LG$N_elig)),
  .med(LG$cov_m), .med(LG$cov_w), .med(LG$share_r0), 100 * .med(LG$mdd_all), 100 * .med(LG$mdd_top),
  .med(LG$rw_top), .med(LG$rw_all), .med(LG$cm_top), .med(LG$cm_all)))

cat(sprintf(paste0(
  "[COMBO_CM_R] 반증 (전부 형성일 단면 통계 · 미래참조 0):\n",
  "  F1 [A]월간 재라벨 아님 : top-25 겹침(vs CM 단독) 중앙 %.3f      → %s (기준 < %.2f — 주간 항이 순위를 바꿨는가)\n",
  "  F2 [A]주간 재라벨 아님 : top-25 겹침(vs R 단독)  중앙 %.3f      → %s (기준 < %.2f — 월간 항이 순위를 바꿨는가)\n",
  "  F3 두 항의 독립성      : rho(CM, R_w) 단면 중앙 %+.3f  (보고만 — |rho| 가 크면 두 시간척도가 같은 정보)\n",
  "  F4 월 결번 0           : [범위 = %s~ ∧ 워밍업 이후] 후보 %d · 산출 %d · 최대 연속 결번 %d → %s\n",
  "  ★러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · n_max %d) · commission_paper = null · %.1f분\n"),
  .f1, if (is.finite(.f1) && .f1 < .OVL_MAX) "PASS" else "FAIL", .OVL_MAX,
  .f2, if (is.finite(.f2) && .f2 < .OVL_MAX) "PASS" else "FAIL", .OVL_MAX,
  .f3,
  as.character(.RANGE0), length(.cand_f), length(.got_f), .gapmax,
  if (length(.cand_f) && length(.got_f) == length(.cand_f) && .gapmax == 0L) "PASS" else "FAIL",
  .NTOP, as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
