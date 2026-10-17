# ==============================================================================
# RP_AUTO_CLEAN_2411_13555 — engine.R
#
# 논문: Junjie Guo, "Deep Learning in Long-Short Stock Portfolio Allocation:
#       An Empirical Study", arXiv:2411.13555  — ★판 = v1 (감사 대조판)
#
# 논문 원형 (v1):
#   §4.2  피처 4개 = Return (eq 12) · RSI 14일 (eq 13) · Volume · 5일 변동성 (eq 14) ★번호 = v1
#   §3.1  타깃      = 다음날 수익률 회귀  r̂_{t+1} = f_θ(X_t)                      (eq 1)
#   §4.3  모델      = MLP (eq 15) / CNN (eq 16) / LSTM (eq 17) / Transformer (eq 18)
#   §3.2  구성      = r̂>0 롱 · r̂<0 숏                                            (eq 2)
#   §5    비중      = min_w ½wᵀΣw − λwᵀR̂  s.t. Σ|w_i|=1, w_i≥0 if R̂_i>0, w_i≤0 if R̂_i<0
#                     λ = 0.5 · Σ = 학습 표본에서 추정                             (eq 19)
#   §5    리밸·비용 = 매일 · "transaction costs are negligible"
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 숏 다리는 음수 비중 · Σ|w| = 1
#       (논문 비중 그대로 → portfolio_spec construction = engine_direct)
#
# 변경·보충은 전부 FIDELITY.json 에 신고한다 (주석이 아니라 그 파일이 통로).
# ==============================================================================

suppressPackageStartupMessages(library(data.table))

# ── 상수 (전부 FIDELITY.json::constants 에 신고) ──────────────────────────────
# paper
RSI_WINDOW      <- 14L        # eq (13) RSI over 14 days, R_{t-i} i=1..14
RSI_SCALE       <- 100        # eq (13) 100 - 100/(1 + AG/AL)
VOL_WINDOW      <- 5L         # eq (14) volatility over past 5 days
VAR_DDOF        <- 1L         # eq (14) 1/(5-1) = 표본 분산 자유도
LAMBDA_RISK     <- 0.5        # eq (19) risk aversion coefficient
GROSS_EXPOSURE  <- 1.0        # eq (19) Σ|w_i| = 1
# supplement
RSI_NEUTRAL     <- 50         # 14일 전부 무변동(AG=AL=0) → 0/0 중립 치환
VAR_MIN_OBS     <- 60L        # 확장 분산 최소 관측 수
VAR_FLOOR       <- 2.5e-05    # 일간 분산 하한 = (0.005)^2 — eq (19) 1/σ² 분모 가드
TARGET_CLIP     <- 0.5        # 학습 라벨 |y| 상한
FEAT_CLIP_SD    <- 5.0        # 표준화 뒤 피처 ±sd 절단
HIDDEN1         <- 16L        # MLP 은닉 1층 폭 (eq 15 는 층수·폭 미명시)
HIDDEN2         <- 8L         # MLP 은닉 2층 폭
HE_GAIN         <- 2.0        # 초기화 분산 = HE_GAIN / fan_in (ReLU)
EPOCHS          <- 25L        # 학습 epoch
BATCH_SIZE      <- 4096L      # 미니배치 크기
LEARNING_RATE   <- 1e-3       # Adam lr
ADAM_B1         <- 0.9        # Adam β1
ADAM_B2         <- 0.999      # Adam β2
ADAM_EPS        <- 1e-8       # Adam ε
TRAIN_MAX_ROWS  <- 200000L    # 재학습 1회 학습 표본 상한
TRAIN_MIN_ROWS  <- 20000L     # 모델 성립 최소 학습 행
WARMUP_YEARS    <- 2L         # 최초 모델 전 최소 이력(년)
DAYS_PER_YEAR   <- 365L       # WARMUP_YEARS 일수 환산
SEED            <- 13555L     # 재현 seed (arXiv id 접미)
WEIGHT_MIN      <- 1e-08      # 0 비중 행 미발행 문턱

# ── 입력 계약 ────────────────────────────────────────────────────────────────
if (!exists(".RP_START_DATE", inherits = TRUE))
  stop("[2411.13555] .RP_START_DATE 미제공 — 측정 축 시작일은 호출자가 넣는다(리터럴 금지).")
.SIG_FROM <- as.Date(get(".RP_START_DATE", inherits = TRUE))

if (!is.data.table(RAWDATA)) stop("[2411.13555] RAWDATA data.table 아님")
.req <- c("Date", "Ticker", "Ret", "Vol", "K200", "KQ150")
if (!all(.req %in% names(RAWDATA)))
  stop(sprintf("[2411.13555] RAWDATA 컬럼 부족: %s", paste(setdiff(.req, names(RAWDATA)), collapse = ", ")))

# ── 1. 패널 — 측정 축 유니버스(계약이 K200/KQ150 에 주입한 위생 멤버십) ──────
P <- RAWDATA[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                 Ret = as.numeric(Ret), Vol = as.numeric(Vol),
                 Mem = as.integer((!is.na(K200) & K200 == 1L) | (!is.na(KQ150) & KQ150 == 1L)))]
P <- P[is.finite(Ret)]
# 계산량 축소 — 한 번도 멤버가 아닌 티커 제거. 소비부(학습 Mem_l==1 · 예측 Mem==1)가 전부
# 시점별 멤버십으로 걸러, 제거된 티커는 어떤 시점 t 산출에도 기여하지 않는다(표본 선택 아님).
.ever <- unique(P[Mem == 1L, Ticker])
P <- P[Ticker %chin% .ever]
setorder(P, Ticker, Date)

# ── 2. 피처 (§4.2) — 종점은 전부 t 이하 ──────────────────────────────────────
#   Return R_t (t) · RSI_t = f(R_{t-1..t-14}) · σ_t = f(R_{t-1..t-5}) · Volume_t (t)
P[, gain := pmax(Ret, 0)]
P[, loss := pmax(-Ret, 0)]
P[, c("ag", "al", "m1", "m2") := .(shift(frollmean(gain, RSI_WINDOW), 1L),
                                   shift(frollmean(loss, RSI_WINDOW), 1L),
                                   shift(frollmean(Ret, VOL_WINDOW), 1L),
                                   shift(frollmean(Ret * Ret, VOL_WINDOW), 1L)), by = Ticker]
P[, c("gain", "loss") := NULL]
P[, RSI := RSI_SCALE - RSI_SCALE / (1 + ag / al)]            # AL=0 → RSI=100 · AG=0 → RSI=0
P[is.finite(ag) & is.finite(al) & ag == 0 & al == 0, RSI := RSI_NEUTRAL]
P[, c("ag", "al") := NULL]
P[, Sigma5 := sqrt(pmax(VOL_WINDOW * (m2 - m1 * m1) / (VOL_WINDOW - VAR_DDOF), 0))]
P[, c("m1", "m2") := NULL]
P[, LVol := log1p(pmax(Vol, 0))]
P[, Vol := NULL]

# ── 3. eq (19) Σ — 확장 표본 분산(종점 t · 최소 관측 · 하한) ─────────────────
P[, n_obs := seq_len(.N), by = Ticker]
P[, c1 := cumsum(Ret), by = Ticker]
P[, c2 := cumsum(Ret * Ret), by = Ticker]
P[, VarX := (c2 - c1 * c1 / n_obs) / pmax(n_obs - VAR_DDOF, 1L)]
P[, c("c1", "c2") := NULL]
P[n_obs < VAR_MIN_OBS | !is.finite(VarX) | VarX <= 0, VarX := NA_real_]
P[is.finite(VarX), VarX := pmax(VarX, VAR_FLOOR)]
P[, n_obs := NULL]

# ── 4. 학습 라벨 — 목표일 d 의 Ret 에 직전 거래일 피처를 짝짓는다 ────────────
#   (전방 shift 미사용. x = X_{d-1}, y = R_d ⇔ 논문 eq (1) r̂_{t+1} = f(X_t))
P[, c("x1l", "x2l", "x3l", "x4l", "Mem_l") := .(shift(Ret, 1L), shift(RSI, 1L),
                                                 shift(LVol, 1L), shift(Sigma5, 1L),
                                                 shift(Mem, 1L)), by = Ticker]

TR <- P[Mem_l == 1L & is.finite(x1l) & is.finite(x2l) & is.finite(x3l) & is.finite(x4l),
        .(Date, y = pmax(pmin(Ret, TARGET_CLIP), -TARGET_CLIP), x1l, x2l, x3l, x4l)]
setorder(TR, Date)
.tr_date_int <- as.integer(TR$Date)

PR <- P[Mem == 1L & Date >= .SIG_FROM & is.finite(RSI) & is.finite(LVol) &
          is.finite(Sigma5) & is.finite(VarX),
        .(Date, Ticker, x1 = Ret, x2 = RSI, x3 = LVol, x4 = Sigma5, VarX)]
PR[, Year := year(Date)]
.first_data_date <- min(P$Date)
.model_years <- sort(unique(PR$Year))
rm(P); invisible(gc(verbose = FALSE))

# ── 5. MLP (eq 15) — 4 → HIDDEN1 → HIDDEN2 → 1 · ReLU · MSE · Adam ──────────
.addb <- function(M, b) M + rep(b, each = nrow(M))

# 표준화 + ±FEAT_CLIP_SD 절단 — 학습·예측이 같은 (mu, sdv) 로 같은 변환을 받는다
.zclip <- function(X, mu, sdv)
  pmax(pmin(.addb(X, -mu) %*% diag(1 / sdv, nrow = length(sdv)), FEAT_CLIP_SD), -FEAT_CLIP_SD)

.mlp_init <- function(n_in) list(
  W1 = matrix(rnorm(n_in * HIDDEN1, 0, sqrt(HE_GAIN / n_in)), n_in, HIDDEN1),
  b1 = numeric(HIDDEN1),
  W2 = matrix(rnorm(HIDDEN1 * HIDDEN2, 0, sqrt(HE_GAIN / HIDDEN1)), HIDDEN1, HIDDEN2),
  b2 = numeric(HIDDEN2),
  W3 = matrix(rnorm(HIDDEN2, 0, sqrt(HE_GAIN / HIDDEN2)), HIDDEN2, 1L),
  b3 = 0)

.mlp_fwd <- function(pm, X) {
  A1 <- pmax(.addb(X %*% pm$W1, pm$b1), 0)
  A2 <- pmax(.addb(A1 %*% pm$W2, pm$b2), 0)
  list(A1 = A1, A2 = A2, out = as.numeric(A2 %*% pm$W3) + pm$b3)
}

.adam_new <- function(pm) lapply(pm, function(p) list(m = p * 0, v = p * 0))

.adam_step <- function(p, g, s, step) {
  s$m <- ADAM_B1 * s$m + (1 - ADAM_B1) * g
  s$v <- ADAM_B2 * s$v + (1 - ADAM_B2) * g * g
  mh <- s$m / (1 - ADAM_B1^step)
  vh <- s$v / (1 - ADAM_B2^step)
  list(p = p - LEARNING_RATE * mh / (sqrt(vh) + ADAM_EPS), s = s)
}

.mlp_train <- function(X, y) {
  n <- nrow(X); pm <- .mlp_init(ncol(X)); st <- .adam_new(pm); step <- 0L
  for (ep in seq_len(EPOCHS)) {
    ord <- sample.int(n)
    for (lo in seq(1L, n, by = BATCH_SIZE)) {
      hi <- min(lo + BATCH_SIZE - 1L, n)
      ii <- ord[lo:hi]; nb <- length(ii)
      Xb <- X[ii, , drop = FALSE]; yb <- y[ii]
      f <- .mlp_fwd(pm, Xb)
      d3 <- matrix((2 / nb) * (f$out - yb), ncol = 1L)       # ∂MSE/∂out
      g <- list(W3 = crossprod(f$A2, d3), b3 = sum(d3))
      d2 <- (d3 %*% t(pm$W3)) * (f$A2 > 0)
      g$W2 <- crossprod(f$A1, d2); g$b2 <- colSums(d2)
      d1 <- (d2 %*% t(pm$W2)) * (f$A1 > 0)
      g$W1 <- crossprod(Xb, d1);   g$b1 <- colSums(d1)
      step <- step + 1L
      for (nm in c("W1", "b1", "W2", "b2", "W3", "b3")) {
        r <- .adam_step(pm[[nm]], g[[nm]], st[[nm]], step)
        pm[[nm]] <- r$p; st[[nm]] <- r$s
      }
    }
  }
  pm
}

# ── 6. 연 단위 확장창 재학습 → 예측 → eq (19) 비중 ───────────────────────────
.xcols_tr <- c("x1l", "x2l", "x3l", "x4l")
.xcols_pr <- c("x1", "x2", "x3", "x4")
.out <- vector("list", length(.model_years))

for (.k in seq_along(.model_years)) {
  Y <- .model_years[.k]
  cut <- as.Date(sprintf("%d-01-01", Y))                      # 학습 라벨 목표일 < cut (엄격)
  if (as.integer(cut - .first_data_date) < WARMUP_YEARS * DAYS_PER_YEAR) next
  hi <- findInterval(as.integer(cut) - 1L, .tr_date_int)
  if (hi < TRAIN_MIN_ROWS) next

  set.seed(SEED + Y)
  rows <- if (hi > TRAIN_MAX_ROWS) sample.int(hi, TRAIN_MAX_ROWS) else seq_len(hi)
  Xtr <- as.matrix(TR[rows, .xcols_tr, with = FALSE]); ytr <- TR$y[rows]

  mu <- colMeans(Xtr)
  sdv <- apply(Xtr, 2L, stats::sd)
  sdv[!is.finite(sdv) | sdv <= 0] <- 1                        # 상수 피처 보호
  Xtr <- .zclip(Xtr, mu, sdv)

  pm <- .mlp_train(Xtr, ytr)
  rm(Xtr, ytr)

  PY <- PR[Year == Y]
  if (!nrow(PY)) next
  Xpr <- .zclip(as.matrix(PY[, .xcols_pr, with = FALSE]), mu, sdv)
  PY[, pred := .mlp_fwd(pm, Xpr)$out]
  rm(Xpr)

  # eq (19) 정확해 — w_i = s_i u_i (s_i = sign(R̂_i)) 치환 후 u ≥ 0, Σu = 1 단체 QP.
  #   Σ 를 대각(VarX)으로 근사하면 KKT 가 water-filling 폐형이 된다:
  #   u_i = max(0, λ|R̂_i| − ν)/σ_i²,  ν 는 Σu = 1 을 만족하는 유일한 근.
  S <- PY[is.finite(pred) & pred != 0 & is.finite(VarX), .(Date, Ticker, pred, VarX)]
  if (!nrow(S)) next
  S[, b := LAMBDA_RISK * abs(pred)]
  setorder(S, Date, -b)
  S[, kk := seq_len(.N), by = Date]
  S[, Sk := cumsum(b / VarX), by = Date]
  S[, Tk := cumsum(1 / VarX), by = Date]
  S[, nu_k := (Sk - GROSS_EXPOSURE) / Tk]
  S <- S[S[b > nu_k, .(kk_star = max(kk)), by = Date], on = "Date"]
  S <- S[S[kk == kk_star, .(Date, nu = nu_k)], on = "Date"]
  S[, u := pmax(b - nu, 0) / VarX]
  S <- S[u > WEIGHT_MIN]
  if (!nrow(S)) next
  S[, usum := sum(u), by = Date]
  S <- S[usum > 0]
  S[, Weight := sign(pred) * GROSS_EXPOSURE * u / usum]       # 부동소수 오차만 되돌리는 항등 정규화
  .out[[.k]] <- S[, .(Date, Ticker, Weight, Leg = ifelse(pred > 0, "long", "short"))]
  rm(S, PY, pm); invisible(gc(verbose = FALSE))
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[2411.13555] PORTFOLIO 0행 — 학습 가능 구간 없음")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[2411.13555] PORTFOLIO %d행 · 신호일 %d · %s ~ %s · 하루 보유 중앙 %.0f종(롱 %.0f%%)\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            median(PORTFOLIO[, .N, by = Date]$N),
            100 * mean(PORTFOLIO$Weight > 0)))
