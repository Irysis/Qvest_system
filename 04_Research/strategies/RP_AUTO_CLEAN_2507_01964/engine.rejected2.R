#==============================================================================
# RP_AUTO_CLEAN_2507_01964 · engine.R   (재구현 r2)
# Ojo, A. K. & Okafor, I. J. (2024)
#   "Forecasting Nigerian Equity Stock Returns Using Long Short-Term Memory Technique"
#   J. Adv. Math. Com. Sci. 39(7):45-54 · DOI 10.9734/jamcs/2024/v39i71911 · arXiv:2507.01964
#
# [논문 원형] 종목별 단변량 LSTM 회귀. NSE 일간 종가를 0-1 정규화하고, 55 타임스텝 창
#   (input shape (55,1))으로 다음 거래일 종가를 1스텝 예측한다. 유닛 40 · 드롭아웃 0.2 ·
#   배치 35 · 에폭 50 · 80/20 분할. 산출은 Accuracy/MAE/MSE/RMSE 지 포트폴리오가 아니다 —
#   종목선택 규칙 · 비중 · 리밸 · 비용이 논문에 없다.
# [이식 adapted] 기전(가격 경로만 보는 게이트 순환망의 1스텝 앞 종가 예측)을 횡단면으로 옮긴다.
#   같은 구조 · 같은 하이퍼파라미터로 패널에 풀링 학습하고, 각 신호일의 트레일링 55 종가 창으로
#   다음 거래일 종가를 예측해 **예측 수익률 (c_hat - c_t)/c_t** 를 Score 로 낸다.
#   선택(top-25) · 비중(EW)은 러너가 한다 — portfolio_spec = FIDELITY.json.
# [r2 수정] 논문 §3 이 명시한 구현 도구(Keras/TensorFlow) 기본값과 어긋났던 두 칸을 되돌렸다:
#   ① 순환 커널 초기화 — Keras Orthogonal 은 recurrent_kernel 전체 (units, 4·units) 한 장에
#      1회 적용된다(비정방 → (160,40) QR → 열 부호 보정 → 전치 = 행 40개가 길이 160 정규직교,
#      행 노름 1 · 게이트 블록 간 직교성 없음). 앞 판은 40×40 직교블록 4개를 붙여 행 노름이 2였다.
#   ② Adam 갱신식 — Keras/TF 효율형(α = lr·sqrt(1−β2^t)/(1−β1^t) · ε 는 sqrt(v) 에 가산).
#   두 변경 모두 FIDELITY.changed ⑨ 에 적었다.
# [신고] 남긴 것 · 바꾼 것 · 창 종점 · 상수 전부 = FIDELITY.json
#   (fidelity · kept · changed · paper_steps · windows · constants · harness_disclosure).
#   주석은 통로가 아니다 — 이 파일의 모든 보충값은 FIDELITY.json 에 같은 값으로 올라가 있다.
# [PIT] ① 창 종점 = 신호일 종가(체결은 다음 거래일 종가 = close_t1) ② 정규화는 그 창 안의
#   min/max 로만(논문의 전표본 MinMaxScaler 는 C1 위반이라 교체) ③ 학습 표본 · 학습 라벨은
#   전부 그 모델 컷오프 **이전** ④ 전표본 통계 0 · 성과를 본 선택 0(고정 일정 재학습 ·
#   조기종료 없음 · 최적 에폭 선택 없음) ⑤ 유니버스는 계약이 주입한 플래그로만 거른다.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(matrixStats)
})

# ── 논문 명시 상수 (Methodology §3 · Table 2 주변 서술) ───────────────────────
LOOKBACK       <- 55L      # "a total input shape of (55,1)" — 타임스텝 55 · 피처 1(종가)
LSTM_UNITS     <- 40L      # "LSTM ... with a unit value of 40"
DROPOUT_RATE   <- 0.2      # "and a Dropout value of 0.2"
BATCH_SIZE     <- 35L      # "trained using an LSTM with a batch size of 35"
N_EPOCHS       <- 50L      # "with an epoch value of 50"

# ── 보충 상수 (논문 미명시 · 전부 FIDELITY.json::constants 에 사유와 함께 신고) ──
ADAM_LR        <- 0.001    # Keras Adam 기본값(논문은 "Optimizer, learning rate"를 입력으로만 언급)
ADAM_B1        <- 0.9
ADAM_B2        <- 0.999
ADAM_EPS       <- 1e-7
FORGET_BIAS    <- 1.0      # Keras unit_forget_bias=TRUE 기본값
ORTHO_GAIN     <- 1.0      # Keras Orthogonal(gain=1.0) 기본값 — 순환 커널 초기화
TRAIN_N        <- 2100L    # 재학습 1회당 추출 시퀀스 수(= 60 배치 × 35) — 순수 R BPTT 예산
WARMUP_MONTHS  <- 36L      # 첫 모델 학습창 길이(이전 신호 없음)
RETRAIN_MONTHS <- 60L      # 확장창 재학습 간격(논문은 1회 학습 후 ~4.4년 구간을 예측)
SEED           <- 2507L    # 재현용(논문 미명시) — 모델 m 의 추출 = SEED+m · 초기화 = SEED+1000+m
CHUNK_SEQ      <- 10000L   # 추론 1회 처리 행 수(메모리만 · 값에 영향 없음)

#==============================================================================
# 1. LSTM — 순수 R 구현 (Keras LSTM(40) → Dropout(0.2) → Dense(1) 와 같은 구조)
#    게이트 순서 = Keras 커널 순서 i, f, c, o. recurrent_activation = sigmoid(TF2 기본값).
#==============================================================================

.sigm <- function(z) 1 / (1 + exp(-z))

.glorot <- function(nr, nc) {                       # glorot_uniform (Keras kernel 기본값)
  lim <- sqrt(6 / (nr + nc))
  matrix(runif(nr * nc, -lim, lim), nr, nc)
}

# orthogonal (Keras recurrent_kernel 기본값) — shape 를 그대로 받아 **한 장**으로 초기화한다.
#   Keras Orthogonal: flat = (max(nr,nc), min(nr,nc)) 정규난수 → QR → R 대각 부호로 Q 열 보정 →
#   nr < nc 면 전치. 따라서 (40,160) 은 '행 40개가 길이 160 의 정규직교'(행 노름 1)다.
.orthog <- function(nr, nc) {
  n1  <- max(nr, nc); n2 <- min(nr, nc)
  qrd <- qr(matrix(rnorm(n1 * n2), n1, n2))
  q   <- qr.Q(qrd) * rep(sign(diag(qr.R(qrd))), each = n1)
  if (nr < nc) q <- t(q)
  q
}

.init_params <- function(seed) {
  set.seed(seed)
  H <- LSTM_UNITS
  b <- rep(0, 4L * H)
  b[(H + 1L):(2L * H)] <- FORGET_BIAS               # forget 게이트 bias = 1
  list(Wx = .glorot(1L, 4L * H),
       Wh = ORTHO_GAIN * .orthog(H, 4L * H),        # 게이트 4개를 한 장으로(Keras 기본값)
       b  = b,
       Wd = .glorot(H, 1L),
       bd = 0)
}

# 순전파 — 상태는 창 시작에서 0 으로 초기화(논문 input shape (55,1) = 창마다 독립 · stateful 아님)
.fwd <- function(Xs, P) {
  B <- nrow(Xs); H <- LSTM_UNITS
  i1 <- 1L:H; i2 <- H + i1; i3 <- 2L * H + i1; i4 <- 3L * H + i1
  bb <- rep(P$b, each = B)
  Hs <- matrix(0, B, H); Cs <- matrix(0, B, H)
  for (t in seq_len(LOOKBACK)) {
    Z  <- Hs %*% P$Wh + Xs[, t, drop = FALSE] %*% P$Wx + bb
    gi <- .sigm(Z[, i1, drop = FALSE]); gf <- .sigm(Z[, i2, drop = FALSE])
    gg <- tanh(Z[, i3, drop = FALSE]);  go <- .sigm(Z[, i4, drop = FALSE])
    Cs <- gf * Cs + gi * gg
    Hs <- go * tanh(Cs)
  }
  as.vector(Hs %*% P$Wd) + P$bd
}

# 역전파(BPTT) 1 스텝 + Adam. 손실 = MSE(논문 평가지표 MSE/MAE/RMSE 와 같은 계열).
.train_step <- function(Xb, yb, P, st) {
  B <- nrow(Xb); H <- LSTM_UNITS; G <- 4L * H
  i1 <- 1L:H; i2 <- H + i1; i3 <- 2L * H + i1; i4 <- 3L * H + i1
  Ai <- array(0, c(B, H, LOOKBACK)); Af <- Ai; Ag <- Ai; Ao <- Ai; Atc <- Ai
  AH <- array(0, c(B, H, LOOKBACK + 1L)); AC <- AH
  bb <- rep(P$b, each = B)
  Hs <- matrix(0, B, H); Cs <- matrix(0, B, H)
  for (t in seq_len(LOOKBACK)) {
    Z  <- Hs %*% P$Wh + Xb[, t, drop = FALSE] %*% P$Wx + bb
    gi <- .sigm(Z[, i1, drop = FALSE]); gf <- .sigm(Z[, i2, drop = FALSE])
    gg <- tanh(Z[, i3, drop = FALSE]);  go <- .sigm(Z[, i4, drop = FALSE])
    Cs <- gf * Cs + gi * gg
    tc <- tanh(Cs)
    Hs <- go * tc
    Ai[, , t] <- gi; Af[, , t] <- gf; Ag[, , t] <- gg; Ao[, , t] <- go; Atc[, , t] <- tc
    AH[, , t + 1L] <- Hs; AC[, , t + 1L] <- Cs
  }
  # Dropout(0.2) — 마지막 은닉 벡터에 역드롭아웃(학습 시만 · 추론은 .fwd 로 마스크 없음)
  kp  <- 1 - DROPOUT_RATE
  msk <- matrix(as.numeric(runif(B * H) < kp) / kp, B, H)
  Hd  <- Hs * msk
  yh  <- as.vector(Hd %*% P$Wd) + P$bd
  err <- yh - yb
  loss <- mean(err * err)
  dy  <- matrix((2 / B) * err, ncol = 1L)
  gWd <- crossprod(Hd, dy); gbd <- sum(dy)
  dH  <- (dy %*% t(P$Wd)) * msk
  dC  <- matrix(0, B, H)
  gWx <- matrix(0, 1L, G); gWh <- matrix(0, H, G); gb <- numeric(G)
  dZ  <- matrix(0, B, G)
  for (t in LOOKBACK:1L) {
    gi <- Ai[, , t]; gf <- Af[, , t]; gg <- Ag[, , t]; go <- Ao[, , t]; tc <- Atc[, , t]
    dC <- dC + dH * go * (1 - tc * tc)
    dZ[, i1] <- dC * gg * gi * (1 - gi)
    dZ[, i2] <- dC * AC[, , t] * gf * (1 - gf)      # AC[,,t] = c_{t-1}
    dZ[, i3] <- dC * gi * (1 - gg * gg)
    dZ[, i4] <- dH * tc * go * (1 - go)
    gWx <- gWx + crossprod(Xb[, t, drop = FALSE], dZ)
    gWh <- gWh + crossprod(AH[, , t], dZ)           # AH[,,t] = h_{t-1}
    gb  <- gb + colSums(dZ)
    dH  <- tcrossprod(dZ, P$Wh)
    dC  <- dC * gf
  }
  gr <- list(Wx = gWx, Wh = gWh, b = gb, Wd = gWd, bd = gbd)
  # 수치 가드(논문에 없음 · 신고) — 손실·기울기가 비유한이면 그 배치는 갱신하지 않는다
  if (!is.finite(loss) || !all(vapply(gr, function(g) all(is.finite(g)), logical(1))))
    return(list(P = P, st = st, loss = NA_real_, skipped = TRUE))
  st$t <- st$t + 1L
  # Adam — Keras/TF 효율형 갱신: α = lr·sqrt(1−β2^t)/(1−β1^t) · ε 는 sqrt(v) 에 가산
  alpha <- ADAM_LR * sqrt(1 - ADAM_B2^st$t) / (1 - ADAM_B1^st$t)
  Pn <- P
  for (nm in names(gr)) {
    g <- gr[[nm]]
    st$m[[nm]] <- ADAM_B1 * st$m[[nm]] + (1 - ADAM_B1) * g
    st$v[[nm]] <- ADAM_B2 * st$v[[nm]] + (1 - ADAM_B2) * g * g
    Pn[[nm]] <- P[[nm]] - alpha * st$m[[nm]] / (sqrt(st$v[[nm]]) + ADAM_EPS)
  }
  # 수치 가드(논문에 없음 · 신고) — 갱신 결과가 비유한이면 직전 파라미터를 유지한다
  if (!all(vapply(Pn, function(x) all(is.finite(x)), logical(1))))
    return(list(P = P, st = st, loss = NA_real_, skipped = TRUE))
  list(P = Pn, st = st, loss = loss, skipped = FALSE)
}

.fit_model <- function(Xtr, ytr, seed) {
  P  <- .init_params(seed)
  z0 <- lapply(P, function(x) x * 0)
  st <- list(t = 0L, m = z0, v = z0)
  nb <- nrow(Xtr) %/% BATCH_SIZE                    # 나머지 배치는 버린다(TRAIN_N 은 35 의 배수)
  n_skip <- 0L; last_loss <- NA_real_
  for (ep in seq_len(N_EPOCHS)) {
    ord <- sample.int(nrow(Xtr))                    # Keras fit(shuffle=TRUE) 기본값
    for (k in seq_len(nb)) {
      ii <- ord[((k - 1L) * BATCH_SIZE + 1L):(k * BATCH_SIZE)]
      r  <- .train_step(Xtr[ii, , drop = FALSE], ytr[ii], P, st)
      P  <- r$P; st <- r$st
      if (isTRUE(r$skipped)) n_skip <- n_skip + 1L else last_loss <- r$loss
    }
  }
  list(P = P, n_skip = n_skip, loss = last_loss, n_batch = nb * N_EPOCHS)
}

#==============================================================================
# 2. 패널 준비 — 가격 창은 종목 자기 종가열에서, 멤버십은 계약이 주입한 플래그에서
#==============================================================================

if (!all(c("Date", "Ticker", "Close", "K200", "KQ150") %in% names(RAWDATA)))
  stop("[2507.01964] RAWDATA 에 Date/Ticker/Close/K200/KQ150 가 필요하다")

.SIG_FROM <- if (exists(".RP_START_DATE", inherits = TRUE)) as.Date(.RP_START_DATE) else min(RAWDATA$Date)

# 논문 "cleaned up by eliminating noise, missing data, and inconsistencies" 에 해당하는 정제:
#   비유한 · 0 이하 종가 행 제거 + (Ticker, Date) 중복 제거. 제거된 날은 그 종목 창에서 빠진다.
PXR <- RAWDATA[is.finite(Close) & Close > 0,
               list(Date, Ticker, Close,
                    mem = (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1))]
PXR <- unique(PXR, by = c("Ticker", "Date"))
setorder(PXR, Ticker, Date)
PXR[, pos := seq_len(.N), by = Ticker]              # 종목 안 누적 순번(그 행까지만 센다)

cl     <- PXR$Close
pos_v  <- PXR$pos
n_row  <- nrow(PXR)
# 다음 행이 같은 종목의 바로 다음 거래일인가 — 학습 라벨(다음 종가)이 존재하는지의 구조 판정.
#   라벨은 학습에만 쓰고, 그 라벨 행 날짜도 모델 컷오프 이전으로 제한한다(아래 §3).
nxt_ok <- c(pos_v[-1L] == pos_v[-n_row] + 1L, FALSE)

# 신호일 = ISO 주(월~일)의 마지막 거래일. 논문 신호는 일간이고 하네스는 ISO 주 1회로 접으므로
#   (고지 H10) 주의 마지막 거래일만 내도 결과가 같다 — 계산량 때문에 그렇게 한다(신고).
all_d  <- sort(unique(RAWDATA$Date))
wk_key <- (as.integer(all_d) + 3L) %/% 7L           # 1970-01-01 = 목 → +3 으로 월요일 시작 버킷
sig_d  <- all_d[!duplicated(wk_key, fromLast = TRUE) & all_d >= .SIG_FROM]
is_sig <- PXR$Date %in% sig_d

# 재학습 일정 — 확장창. 첫 컷오프 = 시작 + WARMUP_MONTHS, 이후 RETRAIN_MONTHS 마다.
#   모델 m 은 컷오프 **이전** 데이터로만 학습하고 [컷오프, 다음 컷오프) 신호에 쓰인다(PIT).
.anchor <- as.Date(format(.SIG_FROM, "%Y-%m-01"))
.n_mo   <- 12L * (as.integer(format(max(all_d), "%Y")) - as.integer(format(.anchor, "%Y")) + 2L)
cut_cal <- seq(.anchor, by = "month", length.out = .n_mo)
cut_idx <- seq(WARMUP_MONTHS + 1L, by = RETRAIN_MONTHS,
               length.out = 1L + max(0L, .n_mo - WARMUP_MONTHS - 1L) %/% RETRAIN_MONTHS)
cut_cal <- cut_cal[cut_idx[cut_idx <= .n_mo]]
cut_cal <- cut_cal[cut_cal > .SIG_FROM & cut_cal <= max(all_d)]
if (!length(cut_cal))
  stop("[2507.01964] 학습 워밍업(36개월)을 채울 표본이 없다 — 신호 0")

# 창 추출: 행 idx 의 창 = 그 종목의 최근 LOOKBACK 개 '가용' 종가(마지막 열 = idx 당일 종가)
.win_mat <- function(idx) {
  X <- matrix(NA_real_, length(idx), LOOKBACK)
  for (j in seq_len(LOOKBACK)) X[, j] <- cl[idx - (LOOKBACK - j)]
  X
}
# 0-1 정규화 — 논문 MinMaxScaler(feature_range (0,1))를 **그 창 안의 min/max** 로 적합(PIT · C1).
.norm_rows <- function(X) {
  mn  <- matrixStats::rowMins(X)
  rng <- matrixStats::rowMaxs(X) - mn
  list(Xs = (X - mn) / rng, mn = mn, rng = rng)
}

#==============================================================================
# 3. 모델별: 학습(컷오프 이전) → 그 구간 신호일 점수
#==============================================================================

out  <- vector("list", 0L)
P_cur <- NULL
M    <- length(cut_cal)
cat(sprintf("[2507.01964] 신호일 %d개(ISO 주 1회) · 모델 %d개 · 패널 %d행\n",
            length(sig_d), M, n_row))

for (m in seq_len(M)) {
  cut_m <- cut_cal[m]
  hi_m  <- if (m < M) cut_cal[m + 1L] else max(all_d) + 1L

  # ── 학습 표본: 멤버 · 창 확보 · 라벨 존재 · 라벨 날짜까지 전부 컷오프 이전 ──
  tr_ok <- PXR$mem & pos_v >= LOOKBACK & nxt_ok & PXR$Date < cut_m
  tr_i  <- which(tr_ok)
  if (length(tr_i)) tr_i <- tr_i[PXR$Date[tr_i + 1L] < cut_m]
  if (length(tr_i) >= BATCH_SIZE) {
    set.seed(SEED + m)
    if (length(tr_i) > TRAIN_N) tr_i <- sort(sample(tr_i, TRAIN_N))
    nrm <- .norm_rows(.win_mat(tr_i))
    y   <- (cl[tr_i + 1L] - nrm$mn) / nrm$rng       # 라벨 = 다음 거래일 종가(같은 창 척도)
    keep <- is.finite(nrm$rng) & nrm$rng > 0 & is.finite(y)
    nk <- sum(keep)
    if (nk >= BATCH_SIZE) {
      fit <- .fit_model(nrm$Xs[keep, , drop = FALSE], y[keep], SEED + 1000L + m)
      P_cur <- fit$P
      cat(sprintf("[2507.01964] 모델 %d/%d 학습 — 컷오프 %s · 시퀀스 %d · 배치 %d · 건너뜀 %d · 마지막 MSE %.3g\n",
                  m, M, as.character(cut_m), nk, fit$n_batch, fit$n_skip, fit$loss))
    }
    rm(nrm); gc(verbose = FALSE)
  }
  if (is.null(P_cur)) {
    cat(sprintf("[2507.01964] 모델 %d/%d 학습 표본 부족 — 이 구간 신호 없음(%s~)\n",
                m, M, as.character(cut_m)))
    next
  }

  # ── 추론: 그 구간 신호일 × 그날 멤버 ──
  rw <- which(is_sig & PXR$mem & pos_v >= LOOKBACK & PXR$Date >= cut_m & PXR$Date < hi_m)
  if (!length(rw)) next
  for (st0 in seq(1L, length(rw), by = CHUNK_SEQ)) {
    ch  <- rw[st0:min(st0 + CHUNK_SEQ - 1L, length(rw))]
    X   <- .win_mat(ch)
    nrm <- .norm_rows(X)
    ok  <- is.finite(nrm$rng) & nrm$rng > 0        # 창 전체가 같은 값(rng = 0)인 행은 제외
    if (!any(ok)) next
    ch  <- ch[ok]
    yh  <- .fwd(nrm$Xs[ok, , drop = FALSE], P_cur)
    p_hat <- nrm$mn[ok] + yh * nrm$rng[ok]          # 역정규화 = 예측 종가
    c_now <- X[ok, LOOKBACK]
    scr <- p_hat / c_now - 1                        # 점수 = 예측 1스텝 수익률
    fin <- is.finite(scr)
    if (any(fin))
      out[[length(out) + 1L]] <- data.table(Date = PXR$Date[ch][fin],
                                            Ticker = PXR$Ticker[ch][fin],
                                            Score = scr[fin])
    rm(X, nrm)
  }
  cat(sprintf("[2507.01964] 모델 %d/%d 추론 — %s ~ · 신호행 %d\n",
              m, M, as.character(cut_m), length(rw)))
}

FACTORS <- rbindlist(out, use.names = TRUE)
if (!nrow(FACTORS)) stop("[2507.01964] FACTORS 0행 — 창·멤버십 조건을 만족한 신호가 없다")
setorder(FACTORS, Date, Ticker)
cat(sprintf("[2507.01964] FACTORS %d행 · %d 신호일 · %d종목 · %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))
