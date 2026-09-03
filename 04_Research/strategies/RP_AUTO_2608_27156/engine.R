# =============================================================================
# engine.R — RP_AUTO_2608_27156
# "Traveling Waves in Equity Markets with Rank-Based Entry and Exit"
#  Graeme Baker, Caroline Smyth (arXiv:2608.27156)
#  https://arxiv.org/abs/2608.27156
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json
#
# ===== 왜 faithful 이 아닌가 (판정 순서 1 → 2) =====
# 이 논문은 팩터 논문이 아니라 확률론·SPT(Stochastic Portfolio Theory) 논문이다.
# 시장을 순위의존 진입·퇴출 강도를 갖는 기하 브라운 입자로 모형화하고, many-firm
# 극한에서 자본분포가 reaction-diffusion 방정식의 해로 수렴함을 보인 뒤, CRSP
# Monthly Stock File(1925-12~2024-12 · 26,100사 · 3,751,795 firm-months · 월 평균
# 3,155사. **주 분석창은 1975~2024**)로 보정해 장기분포가 traveling wave 임을 증명한다.
# 그 파동 위에서 논문이 하는 일은 **패시브 규칙의 자본성장 평가**다 — 원문:
#   "we evaluate the capitalization growth of common **passive portfolio rules**
#    along its wave."
# 즉 논문에는 **횡단면 종목선택 규칙이 없다**. 평가 대상인 p-diversity-weighted
# portfolio(w_i ∝ mu_i^p)는 전 종목을 담는 패시브 가중규칙이고 Fernholz(1998)의
# 기존 객체이며, 논문은 p 를 하나로 고정하지도 않는다.
# → "논문 그대로의 신호·종목수" 가 존재하지 않으므로 충실구현이 정의되지 않는다.
#   트리아지 초안(rank_based_diversity_weight_momentum · "3개월 rank percentile
#   변화율 long")은 논문에 없는 신호다 — 지어내기이므로 채택하지 않는다.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전) =====
# 논문의 성장 항등식(§6 "Growth of Diversity-Weighted Portfolios" · Prop 6.1
# reduction formula of [JR15] + **two turnover corrections**)과 그 보정 결론:
#   상대성장 = 초과성장률(rebalancing gain) − 순위턴오버 누출(leakage)
# 원문 결론 두 줄이 이 기전의 전부다:
#   "Turnover, not drift, stabilizes the calibrated market."
#   "with the calibrated coefficients, the **equally weighted portfolio gains the
#    excess growth rate of the variance curve, but turnover takes most of it back**."
#   "Turnover reclaims most of what rebalancing gains."
# 그리고 누출은 **순위 의존**이다 — 진입·퇴출 강도 lambda^b(q), lambda^d(q) 를
# 순위분위 q 의 함수로 **100 등분 순위 bin** 위에서 Poisson 회귀·스플라인으로 적합
# (보정치: 진입 5.78e-3 · 퇴출 4.98e-3 per firm-month). Remark 6.4 "Open markets
# and leakage" 가 top-set 규칙의 경계 누출을 따로 다룬다.
#
# ★이식: 논문이 **시장 총량 진단**으로 쓴 이 분해를 **종목별 횡단면 점수**로 옮긴다.
#   담아야 할 종목은 (얻는 rebalancing gain − 내는 rank leakage) 가 큰 종목이다.
#   논문이 시장 전체에 대해 "대부분 반납된다"고 말한 그 차이를, 종목별로 벌린다.
#
# ===== 무엇을 바꿨는가 (changed) =====
#   (1) 산출 형태: 시장 총량 성장회계 → 종목별 횡단면 Score  ← 이식의 본체
#   (2) 유니버스: CRSP 전 종목 → K200∪KQ150(PIT 시변 멤버십) + adv20(t-1) >= 2e8
#   (3) 선택 파라미터(25종·월간·EW): 논문이 주지 않으므로 **우리 고정 축**을 쓴다.
#       ★EW 는 논문 가족에서의 이탈이 아니다 — p-diversity-weighted 의 **p=0 극단**이고,
#         논문이 수치로 보고하는 바로 그 경우다("the equally weighted portfolio
#         gains the excess growth rate ... turnover takes most of it back").
#         p 를 임의로 고르는 것이야말로 지어내기라 하지 않는다.
#
# ===== Score 구성 — 두 항 모두 논문 항등식에서 나온다 =====
# (A) rebalancing gain — Fernholz 초과성장률의 **정확한** 종목별 분해:
#       gamma*_pi = (1/2) * sum_i w_i * tau^pi_ii ,  tau^pi_ii = Var(r_i − r_pi)
#     EW 포트(w=1/N)에서 종목 i 의 기여는 정확히 (1/2N)·Var(r_i − r_EW).
#     → A_i = Var_W( r_i,t − rbar_t ) ,  rbar = 후보 풀의 EW 바스켓 일별 수익
#       (근사가 아니라 항등식이다. 임의 가중치 없음.)
# (B) rank leakage — 논문이 적합한 **순위 크로싱 강도**의 종목별 실현값:
#     날짜별 시가총액 순위 백분위 q 를 논문의 **100 bin** 격자로 이산화하고,
#       L_i = mean_t | bin_i,t − bin_i,t-1 |   (일 평균 크로싱 bin 수)
#     lambda 는 방향이 아니라 **비율(rate)** 이므로 절대값을 쓴다 — 순위 상승·하락
#     어느 쪽도 누출이다. 이것이 트리아지 초안의 rank momentum(방향 베팅)과
#     결정적으로 다른 지점이다. bin 수 100 은 논문 명시값이지 우리가 고른 값이 아니다.
# (C) 결합: Score_i = zr(A_i) − zr(L_i)
#     zr = 월내 횡단면 **정규점수**(rank → qnorm). 단조불변이라 log 등 변환 선택이
#     판정에 개입하지 않는다. 계수는 1:1 — 논문이 두 항을 "most of it back"(같은
#     크기대, 누출이 근소 우위)이라 보고하므로 1:1 이 논문정합적 null 이고,
#     적합계수를 두면 그게 지어내기다.
#     부호(+A · −L)는 항등식이 정하는 것이지 성과를 보고 뒤집은 게 아니다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#   모든 창의 종점 = 시그널일 d(월말 종가 — d 시점에 기지). 러너가 익월 첫 거래일에
#   집행하므로 신호창과 보유구간의 교집합이 없다(동월 참조 원천 부재).
#   C1  : 전 표본 통계 0건. Var·크로싱률 전부 **rolling 252일 창 내부**이고,
#         q(순위 백분위)·zr(정규점수)는 **그 날짜/그 달 횡단면 내부** 통계다.
#         cov()/mean() 을 패널 전 구간에 거는 지점 없음.
#   C2  : same-day 순환참조 없음. rbar_t 는 t 일 횡단면 평균이고 A_i 는 창 전체의
#         분산 — 어느 항도 t 시점 자기수익을 t 시점 판단에 되먹이지 않는다.
#   C3  : 같은 기간 집계→적용 없음. 창은 [d-251, d], 보유는 익월.
#   C6  : 유니버스 = 각 날짜의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#         q 도 **그 날짜의** 지수 구성원 안에서만 매긴다 — 미래 상장·퇴출 정보 부재.
#   C7  : shift(-1)·수동 미래 인덱싱 0건. 유일한 shift 는 +1(과거 방향).
#   C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t-1 값.
#   C13 : 부호 조작(NEGATE/FLIP) 없음. 부호는 (A) 논문 항등식의 +gamma*
#         (B) −leakage 두 지점에서만 정해진다.
#   C15 : Factor DB 미접근 — 신호는 RAWDATA 가격/거래량/시총에서만 산출.
#   ★Market 열 미사용(rawdata Market 열은 KOSDAQ 0건 날조 — 시장구분 대신 Size 사용).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))

# ---- 논문 명시값 ----
# 논문 원문(§ calibration): "We partition (0,1] into J=100 equal bins, count the
# events in each bin, and model the counts as Poisson with a smooth log-intensity."
# → 100 은 논문 명시값이다(우리가 고른 값 아님). 우리는 lambda 를 재적합하지 않고
#   그 격자 위의 **실현 크로싱 수**만 센다 — 계수를 지어내지 않기 위해서다.
.NBIN <- 100L
# ---- 계산 경계 (논문 미명시. 성과를 보고 고르지 않는다 — 각 1값, sweep 없음) ----
.W    <- 252L                # 추정창 = 1역년. 논문은 수십년 시장보정이라 종목별 창을 주지 않는다
.COV  <- 0.80                # 창 내 최소 관측 비율 (거래정지 허용 하한)
.NMIN <- 40L                 # 월 최소 횡단면 — 25종 선택 + 정규점수가 의미를 갖는 하한
.LIQ  <- 2e8                 # adv20(t-1) 하한 (KRW)

# ---- 월내 횡단면 정규점수 (단조불변 — 변환 선택이 판정에 개입하지 않는다) ----
.zr <- function(x) {
  n <- length(x)
  if (n < 2L) return(rep(0, n))
  qnorm((frank(x, ties.method = "average") - 0.5) / n)
}

# ---- 패널 준비 (RAWDATA 비파괴 — 러너가 이후 시뮬레이션에 재사용) ----
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10 t-1
.rd[, TV := NULL]

# 날짜별 시가총액 순위 백분위 q — **그 날짜의 지수 구성원 안에서만** (C6 · C1: per-date)
.rd[, q := NA_real_]
.rd[(K200 | KQ150) & is.finite(Size) & Size > 0,
    q := (frank(Size, ties.method = "average") - 0.5) / .N, by = Date]
# 논문의 100 등분 순위 bin → 종목별 일간 크로싱 수 |Δbin| (방향 아닌 rate)
.rd[, bin := as.integer(pmin(.NBIN, pmax(1L, ceiling(q * .NBIN))))]
.rd[, dbin := abs(bin - shift(bin, 1L)), by = Ticker]                            # shift 는 +1 뿐
.rd[, c("q", "bin") := NULL]

.rd[, ymk := format(Date, "%Y-%m")]
.month_ends <- sort(.rd[, .(D = max(Date)), by = ymk]$D)
.rd[, ymk := NULL]
.sig_dates <- .month_ends[.month_ends >= as.Date("2005-01-01")]   # 러너 절단선과 정합
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date, Ticker)

# ---- 월별: 후보 풀 → (A) 초과성장 기여 · (B) 순위 크로싱 누출 → Score ----
.out <- vector("list", length(.sig_dates))
for (ii in seq_along(.sig_dates)) {
  d  <- .sig_dates[ii]
  di <- match(d, .all_dates)
  if (is.na(di) || di < .W) next
  win <- .all_dates[(di - .W + 1L):di]        # 종점 = d. 창 전체가 d 시점 기지 (C1·C3)

  # 후보 풀: d 의 K200/KQ150 멤버십 + adv20(t-1) 하한 + 유효 시총 (C6·C10)
  elig <- .rd[.(d), .(Ticker, K200, KQ150, Size, ADV20_L1), nomatch = 0L][
                (K200 | KQ150) & is.finite(Size) & Size > 0 &
                is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (length(elig) < .NMIN) next

  wdt <- .rd[.(win), .(Date, Ticker, Ret, dbin), nomatch = 0L][
              Ticker %chin% elig & is.finite(Ret)]
  if (nrow(wdt) == 0L) next

  # 창 관측 커버리지 — 추정량이 정의되는 종목만 풀에 남긴다
  keep <- wdt[, .N, by = Ticker][N >= .COV * length(win), Ticker]
  if (length(keep) < .NMIN) next
  wdt <- wdt[Ticker %chin% keep]

  # rbar_t = 후보 풀의 EW 바스켓 일별 수익 (= 논문 p=0 diversity-weighted portfolio)
  wdt[, rbar := mean(Ret), by = Date]

  st <- wdt[, .(A  = var(Ret - rbar),                       # (A) tau^pi_ii = Var(r_i − r_pi)
                L  = mean(dbin, na.rm = TRUE),              # (B) 일 평균 순위 bin 크로싱
                nb = sum(is.finite(dbin))), by = Ticker]
  st <- st[is.finite(A) & is.finite(L) & A > 0 &
           nb >= .COV * (length(win) - 1L)]
  if (nrow(st) < .NMIN) next

  # (C) Score = zr(rebalancing gain) − zr(rank leakage). 계수 1:1 · 부호는 항등식이 정함
  st[, Score := .zr(A) - .zr(L)]

  .out[[ii]] <- st[, .(Date = d, Ticker, Score)]

  if (ii %% 24L == 0L) {
    cat(sprintf("[RP_AUTO_2608_27156] %s | pool=%d | A med=%.2e | leak med=%.2f bins/d\n",
                as.character(d), nrow(st), median(st$A), median(st$L)))
    gc(verbose = FALSE)
  }
}

FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L)
  stop("[RP_AUTO_2608_27156] FACTORS 0행 — 유니버스/창/커버리지 확인")
setorder(FACTORS, Date, -Score)

cat(sprintf(paste0("[RP_AUTO_2608_27156] adapted: excess-growth minus rank-leakage ",
                   "(W=%d · %d bins · 1:1) | rows=%d months=%d %s~%s | avg pool/mo=%.0f\n"),
            .W, .NBIN, nrow(FACTORS), uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            nrow(FACTORS) / uniqueN(FACTORS$Date)))
