# ============================================================================
#  RP_AUTO_CLEAN_2412_12516 — engine.R        (재구현 r2 — r1 기각 사유 수리)
#  논문: "Enhanced Momentum with Momentum Transformers"
#        Mason M., Jagirdar W. A., Huang D., Murugan R. (2024) arXiv:2412.12516
#
#  fidelity = adapted.  ★구현/변경 신고의 유일한 통로는 FIDELITY.json 이다.
#  산출: PORTFOLIO(Date, Ticker, Weight, Leg)  — portfolio_spec = engine_direct
#        (논문 산출 = 자산별 롱숏 포지션 z in [-1,1] · 1/N 배분 — FACTORS 형이 아니다)
#  입력: 호출자가 환경에 넣는 RAWDATA · BM_DT · .RP_START_DATE
#
#  ★r1 기각 수리 — 앞 판은 어텐션 '값'으로 실현 수익을 썼다. 논문 §2.1 의 멀티헤드
#    어텐션은 입력 시퀀스의 표현을 받고("fed to a multi-head attention block that
#    allows the model to capture multiple relationships among the input sequence"),
#    실현 수익은 오직 손실에만 들어간다("used to calculate the Sharpe ratio as the
#    loss function"). 상위 프레임워크 [6](arXiv:2112.08534)도 값을 v(x_k) = W_v x_k,
#    즉 특징의 학습된 선형투영으로 정의한다. 이 판의 값 = 키 시점 특징의 투영이며
#    (학습 투영이 없으므로 항등 투영) 실현 수익은 샤프 손실에만 쓴다.
#    → 시점 t 포지션은 특징 이력 {x(t-j)}_{j=0..52} 만의 함수다.
#
#  PIT 구조 보장 (정적 검출기 통과를 근거로 삼지 않는다 — 구조로 보장한다):
#   · 모든 롤링·EWMA 창의 종점 = 신호일 t 종가(= 논문 §3 "the current day's close").
#     체결은 t+1 종가(하네스 H4)이므로 결정 시점 이후 정보가 비중에 들어가지 않는다.
#   · 미래 인덱싱이 이 파일에 한 줄도 없다: shift 는 전부 양수 lag, type="lead" 없음,
#     음수 색인 없음.
#   · 질의 = 신호일 t 의 특징, 키·값 = t-k 주(k >= 1)의 특징 — 둘 다 t 이하 시점.
#   · 학습 라벨은 "그 행 날짜에 이미 실현된 지난 한 주 수익"이다(상태를 1스텝 lag).
#   · 연간 재적합은 그 해 1월 1일 이전에 실현된 라벨만 쓴다(확장창 · 논문 §5.1).
#   · 전 표본 통계 없음: 유일한 통계는 확장창 적합의 평균·공분산이다.
# ============================================================================

suppressMessages(library(data.table))

# ----------------------------------------------------------------------------
# 1. 상수 — 전부 FIDELITY.json::constants 에 신고된다
# ----------------------------------------------------------------------------
WEEKS_PER_YEAR  <- 52L                            # 252 거래일 / 주 5일 ~= ISO 52주
ATTN_STEPS      <- WEEKS_PER_YEAR                 # 어텐션 키 개수 (논문 window 252)
ATTN_HEADS      <- 4L                             # 논문 §3 "utilizes 4 attention heads"
ATTN_KEY_DIV    <- 2L                             # 유효 키 하한 = 창 / 이 값(커버리지 요건)
RET_HORIZONS    <- c(1L, 21L, 63L, 126L, 252L)    # 정규화 수익 지평(거래일)
MACD_SHORT      <- c(8L, 16L, 32L)                # MACD 단기 시간척도
MACD_LONG       <- c(24L, 48L, 96L)               # MACD 장기 시간척도
MACD_PRICE_SD   <- 63L                            # MACD 분모 — 가격 표준편차 창
MACD_SIG_SD     <- 252L                           # MACD 정규화 — q 표준편차 창
VOL_SPAN        <- 60L                            # 일간 수익 EW 변동성 span
EWM_SPAN_C      <- 2                              # span -> alpha 관례: alpha = C/(span+1)
HL_DECAY        <- 0.5                            # 반감기 정의의 감쇠비
FEAT_CLIP       <- 10                             # 특징 절대값 상한(수치 가드)
RET_FLOOR       <- -1                             # 유효 수익 하한(-100% 초과만 유효)
TRAIN_YEARS_MIN <- 3L                             # 논문 §5.1 초기 학습 3년
VALID_FRAC      <- 0.20                           # 논문 §3.1 검증 20%
SHRINK_SET      <- c(0, 0.25, 0.50, 0.75, 1.00)   # 공분산 수축 후보(검증으로 선택)
RIDGE_REL       <- 1e-8                           # 상대 지터(역행렬 수치 가드)
FIT_DOF_MARGIN  <- 1L                             # 학습 관측 >= 채널 수 + 이 값
TICK_CHUNK      <- 400L                           # 종목 묶음 크기(메모리 — 결과 무관)
GC_EVERY        <- 13L                            # 어텐션 루프 gc·진행출력 간격(결과 무관)
STATE_LAG       <- 1L                             # 상태 -> 라벨 짝의 스텝 lag (논문 §3.1 "backward shift of one")
DAYS_PER_WEEK   <- 7L                             # ISO 주 길이
ISO_DOW_OFFSET  <- 3L                             # 1970-01-01 = 목요일 → 월요일 보정
MIN_FIT_DATES   <- WEEKS_PER_YEAR * TRAIN_YEARS_MIN  # 적합 최소 신호일 수

NFEAT     <- length(RET_HORIZONS) + length(MACD_SHORT)      # 8
FEAT_COLS <- paste0("x", seq_len(NFEAT))
# 헤드 = 특징 부분공간 4분할(학습 투영이 없으므로 종류별 군집으로 나눈다):
#   h1 = 단기 정규화수익(1d,21d) · h2 = 중기(63d,126d) · h3 = 장기(252d) · h4 = MACD 3개
HEAD_GROUPS <- list(c(1L, 2L), c(3L, 4L), 5L, c(6L, 7L, 8L))
ATTN_COLS <- paste0("a", seq_len(NFEAT))                    # 헤드별 값 차원을 연결 = 8
CH_COLS   <- c("one", FEAT_COLS, ATTN_COLS)                 # 17 채널
MIN_ATTN_KEYS <- ATTN_STEPS %/% ATTN_KEY_DIV                # 26

.SIG_FROM <- as.Date(if (exists(".RP_START_DATE", inherits = TRUE)) .RP_START_DATE
                     else min(RAWDATA$Date))

# ----------------------------------------------------------------------------
# 2. 보조 함수
# ----------------------------------------------------------------------------
# EWMA — y[i] = (1-lam)x[i] + lam*y[i-1], y[0] = x[1] (종점 = i)
.ewm_core <- function(x, lam) {
  if (!length(x)) return(numeric(0))
  as.numeric(stats::filter(x * (1 - lam), filter = lam, method = "recursive", init = x[1L]))
}
.ewm_hl  <- function(x, hl)   .ewm_core(x, HL_DECAY^(1 / hl))     # 반감기 모수
.ewm_vol <- function(r, span) {                                   # EW 변동성(span 모수)
  lam <- 1 - EWM_SPAN_C / (span + 1)
  m1 <- .ewm_core(r, lam); m2 <- .ewm_core(r * r, lam)
  sqrt(pmax(m2 - m1 * m1, 0))
}
# 후행 표준편차 — 종점 = 현재 행, 앞 n-1 행은 NA (대수 전개형 + Bessel 보정)
.rollsd <- function(x, n) {
  m1 <- frollmean(x, n); m2 <- frollmean(x * x, n)
  sqrt(pmax((m2 - m1 * m1) * (n / (n - 1)), 0))
}

# ----------------------------------------------------------------------------
# 3. 거래일 격자 · 신호일(ISO 주 마지막 거래일)
#    정수 일번호로 ISO 주 월요일을 구한다(로케일 · 플랫폼 무관).
#    1970-01-01 = 목요일 → (as.integer(d) + 3) %% 7 == 0 이 월요일.
# ----------------------------------------------------------------------------
all_d <- sort(unique(RAWDATA$Date))
dnum  <- as.integer(all_d)
wkey  <- dnum - ((dnum + ISO_DOW_OFFSET) %% DAYS_PER_WEEK)
sig_dates <- all_d[sort(as.integer(tapply(seq_along(all_d), wkey, max)))]
cat(sprintf("[2412.12516] 거래일 %d · 신호일(ISO 주) %d · 신호 시작 %s\n",
            length(all_d), length(sig_dates), format(.SIG_FROM)))

# ----------------------------------------------------------------------------
# 4. 유니버스 — 측정 축이 정한다. 엔진은 주입된 멤버십 플래그로만 거른다.
#    (특징은 해당 종목의 전 가격 이력으로 계산하고, 포지션만 멤버 행에 낸다)
#    한 번도 멤버가 아닌 종목은 산출에 나타날 수 없으므로 계산에서 뺀다(산출 동일).
# ----------------------------------------------------------------------------
if (!all(c("K200", "KQ150") %in% names(RAWDATA)))
  stop("[2412.12516] RAWDATA 에 K200/KQ150 멤버십 플래그가 없다 — 측정 축 미주입")
tk_all <- unique(RAWDATA[(!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1), Ticker])
cat(sprintf("[2412.12516] 멤버 이력 보유 종목 %d\n", length(tk_all)))

# ----------------------------------------------------------------------------
# 5. 특징 — 전부 종가 파생 (논문 §3 "inputs are all derived directly from price
#    data, specifically the price at close")
#      x1..x5 = 변동성 정규화 수익 r(t-k,t) / (sigma_t * sqrt(k)), k = 1,21,63,126,252
#      x6..x8 = MACD(S,L), (S,L) = (8,24),(16,48),(32,96)
#    가격계열 = 수익 기반 지수 p = exp(cumsum(log1p(r))) = Close / Close_first.
#    MACD 는 p 에 대해 1차 동차(분자·분모 모두)라 상수배에 불변 → Close 와 동일값.
#    창은 일간 격자에서 계산하고(논문 일간 지평) 신호일 행만 남긴다.
# ----------------------------------------------------------------------------
chunks <- split(tk_all, ceiling(seq_along(tk_all) / TICK_CHUNK))
pieces <- vector("list", length(chunks))

for (ci in seq_along(chunks)) {
  dk <- RAWDATA[Ticker %in% chunks[[ci]], .(Date, Ticker, Ret, K200, KQ150)]
  dk[, mem := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  dk[, c("K200", "KQ150") := NULL]
  setorder(dk, Ticker, Date)

  # 비유한 · <= -100% 수익은 0 으로 둔다(가격지수 연속성 가드 — 하네스 수익 결합과 동일)
  dk[, r0 := fifelse(is.finite(Ret) & Ret > RET_FLOOR, Ret, 0)]
  dk[, cl := cumsum(log1p(r0)), by = Ticker]
  dk[, p  := exp(cl)]
  dk[, sg := .ewm_vol(r0, VOL_SPAN), by = Ticker]

  for (ii in seq_along(RET_HORIZONS)) {
    hh  <- RET_HORIZONS[ii]
    nmx <- paste0("x", ii)
    dk[, (nmx) := (exp(cl - shift(cl, hh)) - 1) / (sg * sqrt(hh)), by = Ticker]
  }

  dk[, psd_ := .rollsd(p, MACD_PRICE_SD), by = Ticker]
  for (jj in seq_along(MACD_SHORT)) {
    hs  <- log(HL_DECAY) / log(1 - 1 / MACD_SHORT[jj])
    hl  <- log(HL_DECAY) / log(1 - 1 / MACD_LONG[jj])
    nmx <- paste0("x", length(RET_HORIZONS) + jj)
    dk[, ms_ := .ewm_hl(p, hs), by = Ticker]
    dk[, ml_ := .ewm_hl(p, hl), by = Ticker]
    dk[, q_  := (ms_ - ml_) / psd_]
    dk[, qsd_ := .rollsd(q_, MACD_SIG_SD), by = Ticker]
    dk[, (nmx) := q_ / qsd_]
    dk[, c("ms_", "ml_", "q_", "qsd_") := NULL]
  }

  for (cc in FEAT_COLS) {
    v <- dk[[cc]]
    v[!is.finite(v)] <- NA_real_
    set(dk, j = cc, value = pmax(pmin(v, FEAT_CLIP), -FEAT_CLIP))
  }

  pieces[[ci]] <- dk[Date %in% sig_dates,
                     c("Date", "Ticker", "cl", "mem", FEAT_COLS), with = FALSE]
  rm(dk); gc(verbose = FALSE)
  cat(sprintf("[2412.12516] 특징 묶음 %d/%d\n", ci, length(chunks)))
}

S <- rbindlist(pieces); rm(pieces); gc(verbose = FALSE)
if (!nrow(S)) stop("[2412.12516] 신호일 특징 패널이 비었다")
setorder(S, Ticker, Date)
S[, si := match(Date, sig_dates)]
S[, one := 1]
nS <- nrow(S)

# 종목 안에서 n 행 뒤로 민다(종목 경계 넘지 않음 · 양수 lag 만)
S[, gpos := seq_len(.N), by = Ticker]
.gp <- S$gpos
.shv <- function(v, k) {
  v <- as.numeric(v)
  if (k <= 0L) return(v)
  n <- length(v)
  out <- rep(NA_real_, n)
  if (k < n) out[(k + 1L):n] <- v[1L:(n - k)]
  out[.gp <= k] <- NA_real_
  out
}

# ----------------------------------------------------------------------------
# 6. 어텐션 — 비모수 scaled dot-product, 헤드 4개 = 특징 부분공간 4분할.
#    질의 = 신호일 t 의 특징 x(t), 키 = x(t-k), 값 = x(t-k) 의 투영(= 항등).
#      a_f(t) = sum_k softmax_k( <x_h(t), x_h(t-k)> / sqrt(d_h) ) * x_f(t-k),  f in h
#    논문 §2.1 의 어텐션 블록은 입력 시퀀스의 표현을 받고([6] 의 v(x_k) = W_v x_k),
#    실현 수익은 손실에만 쓰인다 — 그래서 값도 특징이다(실현 수익 아님).
#    키 유효 = '정확히 k주 전' 행 + 그 행의 특징 8개 전부 유한.
#    FEAT_CLIP 이 로짓을 묶는다: 최대 d_h = 3 → |logit| <= 3*10*10/sqrt(3) ~= 173,
#    exp(173) ~= 3e75 이고 52개 합도 double 범위 안이라 오버플로가 구조적으로 없다.
# ----------------------------------------------------------------------------
cat("[2412.12516] 어텐션 누적...\n")
FV <- lapply(FEAT_COLS, function(cc) S[[cc]])
fin_num <- as.numeric(Reduce(`&`, lapply(FV, is.finite)))
si_num  <- as.numeric(S$si)
acc_num <- replicate(NFEAT, numeric(nS), simplify = FALSE)       # 값 누적(특징 차원별)
acc_den <- replicate(ATTN_HEADS, numeric(nS), simplify = FALSE)  # softmax 분모(헤드별)
acc_cnt <- replicate(ATTN_HEADS, integer(nS), simplify = FALSE)  # 유효 키 수(헤드별)

for (k in seq_len(ATTN_STEPS)) {
  kk <- .shv(si_num, k)
  fk <- .shv(fin_num, k)
  key_ok <- !is.na(kk) & (si_num - kk == k) & !is.na(fk) & fk > 0
  key_ok[is.na(key_ok)] <- FALSE
  rm(kk, fk)
  if (any(key_ok)) for (h in seq_len(ATTN_HEADS)) {
    idx <- HEAD_GROUPS[[h]]
    SX  <- lapply(idx, function(f) .shv(FV[[f]], k))
    dp  <- numeric(nS)
    for (jj in seq_along(idx)) dp <- dp + FV[[idx[jj]]] * SX[[jj]]
    aw <- exp(dp / sqrt(length(idx)))
    ok <- key_ok & is.finite(aw)
    aw[!ok] <- 0
    for (jj in seq_along(idx)) {
      sv <- SX[[jj]]; sv[!ok] <- 0
      acc_num[[idx[jj]]] <- acc_num[[idx[jj]]] + aw * sv
    }
    acc_den[[h]] <- acc_den[[h]] + aw
    acc_cnt[[h]] <- acc_cnt[[h]] + as.integer(ok)
    rm(SX, dp, aw, ok, sv)
  }
  if (k %% GC_EVERY == 0L) { gc(verbose = FALSE); cat(sprintf("[2412.12516]   키 %d/%d\n", k, ATTN_STEPS)) }
}
for (h in seq_len(ATTN_HEADS)) {
  bad <- !is.finite(acc_den[[h]]) | acc_den[[h]] <= 0 | acc_cnt[[h]] < MIN_ATTN_KEYS
  for (f in HEAD_GROUPS[[h]]) {
    av <- acc_num[[f]] / acc_den[[h]]
    av[bad | !is.finite(av)] <- NA_real_
    set(S, j = ATTN_COLS[f], value = av)
  }
}
rm(FV, acc_num, acc_den, acc_cnt, fin_num, si_num); gc(verbose = FALSE)

# ----------------------------------------------------------------------------
# 7. 학습 라벨 — 그 행 날짜에 이미 실현된 지난 한 주 수익 (lag-only)
#    직전 신호일이 바로 앞 ISO 주가 아니면(거래 공백) 라벨 없음.
#    실현 수익은 여기(샤프 손실)에만 쓰인다 — 특징·어텐션에는 들어가지 않는다.
# ----------------------------------------------------------------------------
p_si <- .shv(S$si, STATE_LAG)
p_cl <- .shv(S$cl, STATE_LAG)
ok1  <- !is.na(p_si) & (S$si - p_si == STATE_LAG)
ok1[is.na(ok1)] <- FALSE
R_wk <- exp(S$cl - p_cl) - 1
R_wk[!ok1 | !is.finite(R_wk)] <- NA_real_
S[, cl := NULL]; rm(p_si, p_cl); gc(verbose = FALSE)

# ----------------------------------------------------------------------------
# 8. 학습표 — 채널별 "특징 가중 포트폴리오" 수익
#    f_j(t) = (1/N_{t-1}) sum_i  c_j(i, t-1) * r_i(t-1 -> t)
#    선형 포지션의 포트폴리오 수익이 채널 수익의 1차 결합이므로(샤프 최대화의 닫힌
#    해가 성립) 날짜별로 한 번만 집계한다. 상태는 1스텝 lag — 라벨이 그 행 날짜에
#    이미 실현되게 만든다(lead·음수 색인 없음).
# ----------------------------------------------------------------------------
fin_ch <- Reduce(`&`, lapply(c(FEAT_COLS, ATTN_COLS), function(cc) is.finite(S[[cc]])))
p_mem  <- .shv(as.numeric(S$mem), STATE_LAG)
p_fin  <- .shv(as.numeric(fin_ch), STATE_LAG)
elig   <- ok1 & is.finite(R_wk) & !is.na(p_mem) & p_mem > 0 & !is.na(p_fin) & p_fin > 0
elig[is.na(elig)] <- FALSE
rm(p_mem, p_fin); gc(verbose = FALSE)
cat(sprintf("[2412.12516] 적합 가능 행 %d / %d\n", sum(elig), nS))
if (!any(elig)) stop("[2412.12516] 적합 가능한 (상태, 실현수익) 짝이 없다")

r_el <- R_wk[elig]
u_si <- sort(unique(S$si[elig]))
agg  <- data.table(gi = match(S$si[elig], u_si))     # 1..G (정수 군번호 = 행 색인)
nn_fit <- tabulate(agg$gi, nbins = length(u_si))
Fm   <- matrix(NA_real_, nrow = length(u_si), ncol = length(CH_COLS))
for (j in seq_along(CH_COLS)) {
  set(agg, j = "v", value = .shv(S[[CH_COLS[j]]], STATE_LAG)[elig] * r_el)
  s1 <- agg[, .(s = sum(v)), by = gi]
  Fm[s1$gi, j] <- s1$s / nn_fit[s1$gi]
}
fit_dates <- sig_dates[u_si]
rm(r_el, agg, u_si, elig, fin_ch, R_wk, ok1); gc(verbose = FALSE)
if (!all(is.finite(Fm))) stop("[2412.12516] 학습표에 비유한값이 있다")

# ----------------------------------------------------------------------------
# 9. 확장창 연간 재적합 (논문 §5.1) — 학습 80% / 검증 20% (논문 §3.1)
#    손실 = 음의 샤프(논문 §2.1 "trained to minimize the negative Sharpe ratio").
#    tanh 를 적합 단계에서만 항등으로 선형화하면(tanh(u) ~= u) 포트폴리오 수익이
#    b 에 선형이 되어 샤프 최대해가 닫힌 형태 Sigma^-1 mu 로 나온다. 추론 단계에는
#    논문대로 tanh 를 씌운다(§10). 수축 강도는 검증 샤프로 고른다.
# ----------------------------------------------------------------------------
u_fd   <- sort(unique(c(fit_dates, S$Date)))
u_fy   <- as.integer(format(u_fd, "%Y"))
fit_yr <- u_fy[match(fit_dates, u_fd)]
S[, yr := u_fy[match(Date, u_fd)]]
y_lo <- min(fit_yr)
y_hi <- max(S$yr)
b_years <- integer(0); b_list <- list()
y_seq <- if (y_hi >= y_lo + TRAIN_YEARS_MIN) seq.int(y_lo + TRAIN_YEARS_MIN, y_hi) else integer(0)

for (yy in y_seq) {
  sel <- fit_yr < yy
  if (sum(sel) < MIN_FIT_DATES) next
  Xw  <- Fm[sel, , drop = FALSE]
  ntr <- floor(nrow(Xw) * (1 - VALID_FRAC))
  if (ntr < ncol(Xw) + FIT_DOF_MARGIN || ntr >= nrow(Xw)) next
  Xtr <- Xw[seq_len(ntr), , drop = FALSE]
  Xva <- Xw[seq.int(ntr + 1L, nrow(Xw)), , drop = FALSE]
  mu  <- colMeans(Xtr)
  Sg  <- stats::cov(Xtr)
  if (!all(is.finite(Sg)) || !all(is.finite(mu))) next
  jit  <- RIDGE_REL * mean(diag(Sg))
  cand <- vector("list", length(SHRINK_SET))
  val_obj <- rep(-Inf, length(SHRINK_SET))
  for (li in seq_along(SHRINK_SET)) {
    lam <- SHRINK_SET[li]
    Sl  <- (1 - lam) * Sg + lam * diag(diag(Sg)) + diag(jit, ncol(Sg))
    bb  <- tryCatch(as.numeric(solve(Sl, mu)), error = function(e) NULL)
    if (is.null(bb) || !all(is.finite(bb))) next
    nb <- sqrt(sum(bb * bb))
    if (!is.finite(nb) || nb <= 0) next
    bb <- bb / nb
    rv <- as.numeric(Xva %*% bb)
    sv <- stats::sd(rv)
    if (!is.finite(sv) || sv <= 0) next
    cand[[li]] <- bb
    val_obj[li] <- mean(rv) / sv
  }
  pick <- which.max(val_obj)
  if (!length(pick) || !is.finite(val_obj[pick]) || is.null(cand[[pick]])) next
  b_years <- c(b_years, yy)
  b_list[[length(b_list) + 1L]] <- cand[[pick]]
}
if (!length(b_years)) stop("[2412.12516] 확장창 적합이 한 해도 성립하지 않았다")
Bm <- do.call(rbind, b_list)
cat(sprintf("[2412.12516] 재적합 %d개 연도 (%d~%d) · 채널 %d\n",
            length(b_years), min(b_years), max(b_years), ncol(Bm)))

# ----------------------------------------------------------------------------
# 10. 포지션 — z = tanh(b' c) in [-1,1] (논문 §2.1 최종 dense + tanh),
#     비중 = z / N  (논문 자산 균등 배분 · 롱숏 · 잔여는 현금)
# ----------------------------------------------------------------------------
bi <- match(S$yr, b_years)
s_lin <- numeric(nS)
for (j in seq_along(CH_COLS)) s_lin <- s_lin + S[[CH_COLS[j]]] * Bm[bi, j]
set(S, j = "z", value = tanh(s_lin))
rm(s_lin, bi); gc(verbose = FALSE)

OUT <- S[is.finite(z) & mem == TRUE & Date >= .SIG_FROM]
if (!nrow(OUT)) stop("[2412.12516] 신호 시작일 이후 포지션이 비었다")
OUT[, nn := .N, by = Date]
OUT[, Weight := z / nn]
OUT <- OUT[is.finite(Weight) & Weight != 0]

PORTFOLIO <- OUT[, .(Date, Ticker, Weight,
                     Leg = fifelse(Weight > 0, "long", "short"))]
setorder(PORTFOLIO, Date, Ticker)
cat(sprintf("[2412.12516] PORTFOLIO %d행 · %d 신호일 · %s~%s · 하루 중앙 %d종 · 중앙 총노출 %.3f\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date)),
            as.integer(stats::median(PORTFOLIO[, .N, by = Date]$N)),
            stats::median(PORTFOLIO[, sum(abs(Weight)), by = Date]$V1)))
