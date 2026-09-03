# =============================================================================
# engine.R — RP_AUTO_2608_23944
# "Bulk Phase Transition and Edge Behavior in Temporally Correlated
#  Random Matrices"  (arXiv:2608.23944)
#  https://arxiv.org/abs/2608.23944
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json
#
# ===== 왜 faithful 이 불가능한가 (판정 순서 1 → 2) =====
# 이 논문은 순수 수리 논문이다. 초록이 스스로 그렇게 말한다 — "We study long-range
# correlated Wigner-type matrices built from row-independent stationary Gaussian
# sequences ... we prove the fourth-moment transition exactly and find numerically
# that the self-consistent edge varies smoothly across γ=1". 종목도 수익률도
# 포트폴리오도 비용도 없다. 산출은 정리와 수치실험이다.
#   → 복제할 '논문 그대로의 신호·종목수·비중·리밸'이 존재하지 않는다. faithful 불가.
#   → 데이터는 있다(일별 수익률). ABORT 사유도 아니다. 판정 순서 2 = 기전 이식.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전) =====
# 논문의 결과 세 줄이 그대로 이식된다. 셋 다 원문 수식이다.
#
#  ★원문 대조 완료(2026-08-31, arXiv PDF 전문). 아래 세 식·정의는 원문 표기 그대로다.
#       앙상블 정의: S_ij = (σ/√N)·η_i(j) (i ≤ j) · η_i(i) ~ N(0,1) ·
#                    η_i(j) = ρ·η_i(j−1) + √(1−ρ²)·ε_i(j), j > i
#
#  (K1) **허브 기전 = 4차 모멘트에만 나타난다.** 행(row)이 시간상관을 가지면
#       극한 벌크 스펙트럼의 2차 모멘트는 **반원율 그대로**(μ₂ = σ² — η 가 단위분산
#       정상과정이라 E[S_ij²] = σ²/N 이 ρ 에 안 걸린다. 앙상블 정의에서 직접 나오는
#       값이고, 논문이 식으로 명시하는 건 μ₄ 쪽이다)인데 4차 모멘트만 어긋난다:
#           μ₄(ρ) = 2σ⁴ + (4/3)σ⁴·ρ²/(1−ρ²),  ρ ∈ (−1,1)   … AR(1) 커널 d_t = ρ^t
#           μ₄(∞,γ) = 2 + (4/3)·(ζ(2γ) − 1),   γ > 1/2      … 멱법칙 d_t = (1+t)^{−γ}
#       두 식이 같은 형태다. 공통항을 읽으면 이탈량 = (4/3)·Σ_{t≥1} d_t² 이고,
#       실제로 AR(1): Σ ρ^{2t} = ρ²/(1−ρ²) · 멱법칙: Σ(1+t)^{−2γ} = ζ(2γ)−1 로
#       두 특수해가 모두 맞는다(그래서 2γ ≤ 1, 즉 γ_c = 1/2 에서 발산한다).
#       원문 asymptotic 도 같은 척도를 확인해 준다: ρ→1⁻ 에서 μ₄(ρ) − 2σ⁴ ~ (2/3)σ⁴·ε⁻¹
#       (ε = 1−ρ). 실제로 ρ²/(1−ρ²) → 1/(2ε) 이므로 (4/3)·1/(2ε) = (2/3)/ε 로 맞는다.
#       ★금융적 함의가 여기 있다: **분산(2차)은 시간상관을 못 본다.** 실현변동성이
#       같은 두 종목이 허브 강도는 전혀 다를 수 있고, 그 차이는 4차 모멘트
#       = 스펙트럼 꼬리에서만 드러난다. 이것이 이 논문이 주는 미측정 축이다.
#
#  (K2) **허브 강도의 정본 척도는 h = ρ²/(1−ρ²) 이다.** 위 식에서 그대로 읽는다.
#       h 는 ρ 의 **짝함수** — 부호가 아니라 크기가 스펙트럼을 변형시킨다.
#       그래서 이 축은 모멘텀/리버설(부호 축)과 같은 축이 아니다.
#       (반전: ρ² = h/(1+h) · 1/(1+h) = 1 − ρ². 본 엔진의 Score 가 이 반전이다.)
#
#  (K3) **엣지는 보편적이고 벌크가 오염된다.** 고정 ρ<1 에서 최대고유값 요동은
#       Tracy-Widom 보편성을 따르고(엣지는 믿을 수 있다), 변형되는 것은 벌크다.
#       그리고 ρ→1⁻ 에서 엣지 자체가 τ₀(ρ) = Θ((1−ρ)^{−1/2}) 로 발산한다.
#       → 이식: 횡단면 상관행렬의 **최상위 모드(엣지 = 시장 모드)를 먼저 제거**하고
#         남은 잔차(=벌크)에서 허브를 잰다. 이건 장식이 아니라 **모형 전제를 맞추는
#         필수 단계**다 — 논문의 앙상블은 row-independent 인데 한국 주식 수익률은
#         시장 모드로 강하게 교차상관돼 있어, 그대로는 논문 설정에 사상되지 않는다.
#
# ===== 무엇을 바꿨는가 (changed) — 전문은 FIDELITY.json =====
#  (1) 산출 형태: 정리·수치실험 → **횡단면 팩터 점수**. 논문에 포트폴리오가 없으므로
#      종목수·비중·리밸은 논문이 아니라 **우리 고정 축**을 쓴다(25종·EW·월간).
#  (2) 행(row) ↔ 종목: 논문의 행 = 시간상관을 갖는 정상 가우스 수열. 이식에서는
#      **종목의 (시장모드 제거 후) 일별 잔차수익 계열**이 행이다. 논문 Def.1 의
#      η(j) = ρ·η(j−1) + √(1−ρ²)·ε(j) 가 곧 AR(1) 잔차이므로 사상이 정확하다.
#  (3) 커널: **AR(1)(지수감쇠) 가지만 이식**한다. 트리아지 후보도 AR(1)이다.
#      멱법칙 가지(γ_c=1/2)는 Σd_t² 를 유한 lag 로 잘라야 하는데 그 최대 lag 을
#      논문이 주지 않는다 — 지어내지 않고 뺀다. AR(1)은 모수가 ρ 하나뿐이라
#      **자를 lag 이 없다**(Yule-Walker: ρ̂ = lag-1 자기상관). 임의 수치 0개.
#  (4) 부호: **바꾼 것이 아니다.** 원문이 μ₄ 식의 정의역을 ρ ∈ (−1,1) 로 직접 명시한다
#      (전문 대조 확인). ρ̂<0 을 그대로 쓰는 것이 논문 그대로이고, h 가 짝함수라는
#      것도 논문 식에서 읽히는 성질이다. 여기에 우리가 얹은 확장은 0개다.
#  (5) 방향: 논문은 **수익 방향을 말하지 않는다**(수익 자체가 없는 논문이다).
#      부호는 논문의 위험 진술로만 정한다 — 허브 ⇒ μ₄ 초과(스펙트럼 꼬리 비대) +
#      엣지 발산 τ₀ ~ (1−ρ)^{−1/2}. 따라서 **허브가 약한 쪽(반원율에 가까운 쪽)을
#      롱**한다. 성과를 보고 고른 부호가 아니다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계: 모든 계산이 `.RM[lo:ip, ]` 한 창 안에서만 일어난다. lo = ip − 749,
#    ip = 시그널일(그 달 마지막 거래일)의 행 인덱스. 창 밖 행을 참조하는 지점이
#    **코드에 존재하지 않는다** — 전 표본을 한 번에 훑는 연산이 0건이다.
#    (엣지 제거·표준화·자기상관·편의보정 전부 이 창 안. 창 밖 미래 인덱싱 없음.)
#  C1  : 전 표본 통계 0건. 평균·표준편차·상관행렬·PC1 전부 750일 롤링창(종점 = 시그널일).
#  C2  : same-day 순환참조 없음. 시그널일 종가까지의 수익만 쓰고, 집행은 익월 첫 거래일.
#  C3  : 같은 기간 집계→적용 없음. 창의 종점이 보유월 **시작 전**이다.
#  C4  : 재무 패널 미사용(일별 수익률·거래대금만). 시차 이슈 자체가 없다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수). 신호는 홀딩월 시작 전 데이터뿐.
#  C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#  C7  : shift(-N)·미래 인덱싱 0건. 유일한 shift 는 +1(과거 방향, 유동성).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t-1 값 ≥ 2e8.
#  C11 : 매크로·외부 시계열 미사용.
#  C13 : Factor DB 미소비 → 부호 정렬 대상 없음. 본 엔진의 방향은 측정된 IC 가 아니라
#        논문 수식(μ₄ 초과 · 엣지 발산)에서 사전(a priori)으로 나온다.
#  C15 : Factor DB parquet 직접 load 0건(애초에 Factor DB 를 안 쓴다).
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 메모리 카드). 시장구분 불필요.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = 1 − ρ̂²  ( = 1/(1+ĥ), ĥ = 허브 강도 )
#     높을수록 반원율(비변형) 쪽 = 롱 후보. 적격 전 종목에 발행하므로 러너의
#     IC·FF3/FF5/Carhart·FMB 분석이 선다.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25) · commission_paper = NULL(논문 무명시).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(26082394L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축에서 온 것 / 계산 경계
# =============================================================================
# ▸ 논문에서 온 것: 없다(수치가 아니라 **수식**이 왔다 — μ₄(ρ) 의 ρ²/(1−ρ²)).
#   그 수식의 반전 1/(1+h) = 1−ρ² 이 아래 Score 다. 자유 모수 0개.
# ▸ 우리 고정 축: 25종·EW·월간(러너 spec) · adv20(t-1) ≥ 2e8 · 2005-01-01~.
# ▸ 계산 경계(논문 미명시 — 각 1값, 훑지 않는다. 성과를 보고 고르지 않았다):
.TWIN        <- 750L          # 추정창(거래일 ≈ 3년). 근거 = 추정량의 **귀무 표준오차**
                              #   se(ρ̂) ≈ 1/√T. T=750 → 0.037 로, 일별 주식 자기상관의
                              #   전형 크기(0.02~0.10)보다 작아지는 가장 짧은 창이다.
                              #   성과가 아니라 추정량 분포에서 나온 수다.
.MINOBS_FRAC <- 0.95          # 창 내 수익 관측 완전성 하한(거래정지 등). 미만은 제외,
                              #   나머지 결측은 0(무거래 = 무수익)으로 채운다(≤ 37일).
.LIQ         <- 2e8           # adv20(t-1) 하한 (KRW) — 고정 축 명시값
.NMIN        <- 50L           # 월 최소 횡단면. 엣지(PC1) 추정과 상위 25 선택이 의미를
                              #   갖는 하한. 미만인 달은 신호를 내지 않는다.
.SIG_FROM    <- as.Date("2005-01-01")   # 고정 축 시작
.PANEL_FROM  <- as.Date("2001-01-01")   # 패널 하한(메모리 경계). 첫 시그널일(2005-01)의
                                        #   추정창 750거래일을 채우려면 ~2002-01 이면 되고
                                        #   여기 1년 여유를 둔다. 신호 산출 범위에 무영향.

# =============================================================================
# 1. 일별 패널 → 시그널일(월말) · 적격 유니버스 (C6 · C10)
# =============================================================================
.rd <- RAWDATA[Date >= .PANEL_FROM, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어. 중복이 남으면 뒤의 dcast 가 조용히 fun.aggregate=length 로
#   떨어져 '수익률' 대신 '건수' 행렬을 만든다 — 에러 없이 신호가 통째로 바뀌는 침묵 실패다.
#   ADV20 의 by-Ticker shift 도 같은 전제를 쓴다. 중복이 없으면 무연산.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2608_23944] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]  # C10 t-1
.rd[, TV := NULL]

.rd[, MI := year(Date) * 12L + month(Date)]
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIG <- .mend[SigDate >= .SIG_FROM, .(MI, SigDate)]
if (nrow(.SIG) == 0L)
  stop("[RP_AUTO_2608_23944] 시그널일 0건 — RAWDATA 날짜 범위 확인")

# 적격: 시그널일의 K200/KQ150 멤버십(PIT 시변) + adv20(t-1) 하한
.ELIG <- .rd[Date %in% .SIG$SigDate][
             (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ,
             .(SigDate = Date, Ticker)]
if (nrow(.ELIG) == 0L)
  stop("[RP_AUTO_2608_23944] 적격 종목 0건 — 멤버십/유동성 필터 확인")

# =============================================================================
# 2. 수익률 행렬 (한 번만 만든다 — 이후 전부 '창 슬라이스'로만 접근한다)
# =============================================================================
# ★PIT 구조: 아래 .RM 은 날짜 오름차순 행렬이고, 모든 소비는 `.RM[lo:ip, ]`
#   (ip = 시그널일 행) 뿐이다. ip 보다 큰 행을 읽는 코드가 존재하지 않는다.
.DATES <- sort(unique(.rd$Date))
.SIG[, IP := match(SigDate, .DATES)]
.SIG <- .SIG[is.finite(IP) & IP >= .TWIN]
if (nrow(.SIG) == 0L)
  stop(sprintf("[RP_AUTO_2608_23944] 추정창 %d일을 채우는 시그널일 없음", .TWIN))

.from_i  <- min(.SIG$IP) - .TWIN + 1L
.from_d  <- .DATES[.from_i]
.KEEP_TK <- unique(.ELIG$Ticker)

.wide <- dcast(.rd[Date >= .from_d & Ticker %chin% .KEEP_TK, .(Date, Ticker, Ret)],
               Date ~ Ticker, value.var = "Ret")
setorder(.wide, Date)
.WD <- .wide$Date
.RM <- as.matrix(.wide[, -1L, with = FALSE])
.TK <- colnames(.RM)
rm(.wide); gc(verbose = FALSE)

.SIG[, RI := match(SigDate, .WD)]
.SIG <- .SIG[is.finite(RI) & RI >= .TWIN]
cat(sprintf("[RP_AUTO_2608_23944] 패널 %d일 × %d종 | 시그널일 %d개 (%s ~ %s) | 창 %d일\n",
            length(.WD), length(.TK), nrow(.SIG),
            as.character(min(.SIG$SigDate)), as.character(max(.SIG$SigDate)), .TWIN))

# =============================================================================
# 3. 월별 루프 — 엣지 제거(K3) → 허브 강도(K1·K2) → Score
# =============================================================================
.out   <- vector("list", nrow(.SIG))
.nskip <- 0L
.t0    <- Sys.time()

for (k in seq_len(nrow(.SIG))) {
  sd_k <- .SIG$SigDate[k]
  ip   <- .SIG$RI[k]
  lo   <- ip - .TWIN + 1L                     # ★창 = [ip−749, ip]. 종점이 시그널일이다.

  tkc <- .ELIG[SigDate == sd_k, Ticker]
  ci  <- match(tkc, .TK)
  ok  <- is.finite(ci)
  ci  <- ci[ok]; tkc <- tkc[ok]
  if (length(ci) < .NMIN) { .nskip <- .nskip + 1L; next }

  Z <- .RM[lo:ip, ci, drop = FALSE]           # T×n — 이 블록 밖 데이터는 만지지 않는다

  # 관측 완전성 (거래정지·신규상장). 통과분의 잔여 결측은 0(무거래=무수익)으로 채운다.
  nob  <- colSums(is.finite(Z))
  keep <- nob >= .MINOBS_FRAC * .TWIN
  if (sum(keep) < .NMIN) { .nskip <- .nskip + 1L; next }
  Z <- Z[, keep, drop = FALSE]; tkc <- tkc[keep]; nob <- nob[keep]
  Z[!is.finite(Z)] <- 0

  # 창 내 중심화 + 단위분산화 → 이후 crossprod 가 곧 (T−1)×상관행렬.
  #   (논문 앙상블의 항등 분산 σ²/N 설정에 맞추는 정규화. 창 안 통계 = C1 준수)
  Z  <- Z - rep(colMeans(Z), each = .TWIN)
  sv <- sqrt(colSums(Z * Z) / (.TWIN - 1L))
  gv <- is.finite(sv) & sv > 1e-12
  if (sum(gv) < .NMIN) { .nskip <- .nskip + 1L; next }
  Z <- Z[, gv, drop = FALSE]; tkc <- tkc[gv]; nob <- nob[gv]
  Z <- Z / rep(sv[gv], each = .TWIN)

  # ---- (K3) 엣지 = 최대고유값 모드. Tracy-Widom 보편(= 허브 변형의 대상이 아님).
  #      이걸 먼저 뺀다: 논문 앙상블은 row-independent 인데 원 수익률은 시장 모드로
  #      묶여 있어 그대로는 사상되지 않는다. 남는 것이 논문이 말하는 '벌크'다.
  ev <- tryCatch(eigen(crossprod(Z), symmetric = TRUE), error = function(e) NULL)
  if (is.null(ev)) { .nskip <- .nskip + 1L; next }
  f  <- as.vector(Z %*% ev$vectors[, 1L])
  nf <- sqrt(sum(f * f))
  if (!is.finite(nf) || nf <= 0) { .nskip <- .nskip + 1L; next }
  f  <- f / nf
  E  <- Z - outer(f, as.vector(crossprod(f, Z)))       # 벌크 잔차
  # 사영 뒤 열평균은 정확히 0 이 아니다 — colMeans(E) = −mean(f)·(fᵀZ). Yule-Walker 는
  #   중심화된 계열을 전제하므로 창 안에서 한 번 더 중심화한다(창 밖 통계 0건 — C1 유지).
  E  <- E - rep(colMeans(E), each = .TWIN)

  # ---- (K2) AR(1) 모수 = lag-1 자기상관 (Yule-Walker). 모수가 하나라 자를 lag 이 없다.
  s0 <- colSums(E * E)
  s1 <- colSums(E[1L:(.TWIN - 1L), , drop = FALSE] * E[2L:.TWIN, , drop = FALSE])
  r1 <- ifelse(s0 > 0, s1 / s0, NA_real_)

  # 유한표본 편의: 귀무(백색잡음)에서 E[ρ̂²] ≈ Var(ρ̂) = (T−1)/(T(T+2)) (Anderson).
  #   그만큼 빼면 귀무 기대가 0 이 된다. 절단(clamp)하지 않는다 — 절단하면 귀무측
  #   68% 가 정확히 동점이 되어 상위 25 선택이 순서가 아니라 정렬 우연이 된다.
  r2 <- r1 * r1 - (nob - 1) / (nob * (nob + 2))

  # ---- (K1) 허브 강도 ĥ = ρ̂²/(1−ρ̂²) → Score = 1/(1+ĥ) = 1 − ρ̂².
  #      높을수록 μ₄ 초과가 작다 = 반원율(비변형) 쪽 = 롱 후보.
  sc <- 1 - r2
  fin <- is.finite(sc)
  if (sum(fin) < .NMIN) { .nskip <- .nskip + 1L; next }

  .out[[k]] <- data.table(Date = .SIG$SigDate[k], Ticker = tkc[fin], Score = sc[fin])

  if (k %% 24L == 0L) {
    .hh <- r2[fin] / pmax(1 - r2[fin], 1e-6)
    cat(sprintf("[RP_AUTO_2608_23944] %s | n=%d | ĥ 중앙 %.5f · 상위10%% %.5f | 누적 skip=%d\n",
                as.character(.SIG$SigDate[k]), sum(fin),
                median(.hh), as.numeric(stats::quantile(.hh, 0.9, names = FALSE)), .nskip))
    gc(verbose = FALSE)
  }
}

FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L)
  stop("[RP_AUTO_2608_23944] FACTORS 0행 — 유니버스/추정창 확인")
setorder(FACTORS, Date, -Score)

cat(sprintf(paste0("[RP_AUTO_2608_23944] adapted: 허브 강도 h = ρ²/(1−ρ²) (μ₄ 초과항) 의 ",
                   "반전 Score = 1 − ρ̂² | 엣지(PC1) 제거 후 lag-1 AR(1) | 창 %d일\n",
                   "  월 %d개 (%s ~ %s) · skip %d · FACTORS %d행 · %.1f분\n",
                   "  ★러너 호출: portfolio_spec=list(construction=\"top_n_long\", ",
                   "weighting=\"ew\", rebalance=\"monthly\", n_long=25) · commission_paper=NULL\n"),
            .TWIN, uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            .nskip, nrow(FACTORS),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
