# run_01_measure.R — BOCPD 팔 방향 수리: 후보 측정 (착수 라운드)
#
# ── 배경 ─────────────────────────────────────────────────────────────────────
# m4 오버레이의 BOCPD 팔은 STR_1715 **자기 월수익률**에 Adams-MacKay(2007) 변화점
# 탐지를 걸어 "이 전략의 수익 구조가 방금 깨졌는가"를 잡으려던 장치다. 개념은 살아 있다 —
# 매크로가 '깨끗하다'고 한 달 중 실제로 -5% 넘게 빠진 달이 23번 있었고 그 구멍을 메우려는
# 설계였다(factor_engine.R:525-535).
#
# 그런데 두 겹으로 죽어 있었다:
#   ① 가드 `expected_runlen >= 12` 가 warm-up 주석을 달고 있었으나 실제로는 run-length
#      사후 기대값이라 short_run_mass 와 구조적 음상관(rho=-0.5898) — 경보가 켜지는 순간
#      가드가 껐다. 271개월 0회 발화. (2026-08-30 수리: warm-up 분리 + MODE=off)
#   ② ★가드를 정정해도 못 쓴다. 발화 4건 평균 ret +5.76%(전체 +3.34%), 전수(n=247)
#      mass 의 rank-IC = **+0.046** 으로 전제("mass 高 = 위험")와 부호가 반대다.
#
# ── 진단 ─────────────────────────────────────────────────────────────────────
# ②의 기전은 명확하다. **변화점 탐지기는 '바뀌었다'만 말하고 '어느 쪽으로'는 말하지
# 않는다.** COVID 회복 같은 상방 전환도 똑같이 발화한다. 소비면을 잘못 잡은 것이다 —
# 메모리 카드 project-regime-predictors-predict-variance-not-direction-20260813 과 동형:
# "국면 예측기는 방향이 아니라 분산을 예측한다. 소비면을 잘못 잡으면 전부 null".
#
# 그런데 이 모델은 방향을 **이미 추정하고 있다**. Normal-Gamma 켤레라 run-length 별
# 충분통계(mu, kappa, alpha, beta)를 들고 있고, run-length 사후로 가중하면 "현재 국면의
# 평균 mu 와 척도 sigma" 가 그대로 나온다. 지금까지 그걸 안 꺼내 쓰고 change 플래그만 썼다.
#
# ── 이 라운드가 하는 것 ──────────────────────────────────────────────────────
# 1. 재귀를 **재현 검사 검증**하며 확장한다 — 기존 3출력(change_prob/short_run_mass/
#    expected_runlen)을 비트 단위로 재현해야 확장 출력을 믿을 수 있다(양성 대조).
# 2. 방향/분산 인지 후보를 측정한다. **사전등록 1급 = C1** (최소 수리: 기존 트리거에
#    방향 조건 하나만 추가). 나머지는 진단이며, 1급이 실패하면 그게 판정이다
#    (feedback-preregistered-primary-fails-that-is-the-verdict).
# 3. 원 설계 표적으로도 잰다 — "매크로 clean 인데 ret < -5%" 달을 잡는가(recall/lift).
#
# ── PIT ──────────────────────────────────────────────────────────────────────
# 사후는 t 시점까지의 ret 만 쓴다(재귀 자체가 online). 소비는 하류가 shift(1) 하므로
# 여기서도 동일하게 lag 를 걸어 forward ret 과 맞춘다. full-sample 통계 사용 금지(C1).
# 문턱 tau 는 **expanding 분위수**로만 잡는다 — 전 구간 분위수는 미래참조다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_01_measure.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(arrow) })

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
SRC <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R"
PANEL <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"

# ── 원 상수 (소스에서 재도출 — 손으로 옮기면 갈린다) ─────────────────────────
txt <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
.grab_num <- function(pat) {
  m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
  if (!length(m)) stop(sprintf("상수 추출 실패: %s (앵커 소실)", pat))
  eval(parse(text = sub("^[A-Za-z_]+ *<- *", "", sub(" *#.*$", "", m))))
}
HAZARD    <- .grab_num("BOCPD_HAZARD <- [^\n]+")
PRIOR_VAR <- .grab_num("BOCPD_PRIOR_VAR <- [^\n]+")
cat(sprintf("[const] hazard=%.6f prior_var=%.6f (소스 재도출)\n", HAZARD, PRIOR_VAR))

# ── 확장 재귀 — 원본과 동일 연산 + 사후 평균/척도 추출 ───────────────────────
#   ★추출 지점: 충분통계를 x_t 로 갱신한 **뒤**. new_mu[r+1] 이 run-length r 에 대응하고
#     R[r+1, t+1] 이 P(r) 이므로 이 둘을 짝지어야 정합이다(갱신 전 mu_vec 과 짝지으면
#     한 관측 어긋난다 — 이 종류의 off-by-one 이 이 저장소의 단골 오염원이다).
bocpd_ext <- function(ret_vec, hazard = HAZARD, prior_mean = 0,
                      prior_var = PRIOR_VAR, prior_alpha = 1.0,
                      prior_beta = prior_var * prior_alpha) {
  T_n <- length(ret_vec)
  R <- matrix(0, nrow = T_n + 1L, ncol = T_n + 1L); R[1L, 1L] <- 1.0
  cp <- srm <- erl <- pmu <- psd <- numeric(T_n)
  alpha_vec <- rep(prior_alpha, T_n + 1L); beta_vec <- rep(prior_beta, T_n + 1L)
  mu_vec <- rep(prior_mean, T_n + 1L); kappa_vec <- rep(1.0, T_n + 1L)
  SHORT <- 6L
  for (t in seq_len(T_n)) {
    x <- ret_vec[t]
    pred <- numeric(t)
    for (r in seq_len(t)) {
      a <- alpha_vec[r]; b <- beta_vec[r]; m <- mu_vec[r]; k <- kappa_vec[r]
      sc <- sqrt(b * (k + 1) / (a * k))
      pred[r] <- dt((x - m) / sc, df = 2 * a) / sc
    }
    growth <- R[1:t, t] * pred * (1 - hazard)
    cpp <- sum(R[1:t, t] * pred * hazard)
    R[1L, t + 1L] <- cpp; R[2:(t + 1L), t + 1L] <- growth
    Z <- sum(R[, t + 1L]); if (Z > 0) R[, t + 1L] <- R[, t + 1L] / Z else R[1L, t + 1L] <- 1.0
    cp[t] <- R[1L, t + 1L]
    srm[t] <- sum(R[1L:min(SHORT + 1L, t + 1L), t + 1L])
    erl[t] <- sum((0L:t) * R[1L:(t + 1L), t + 1L])
    na <- nb <- nm <- nk <- numeric(t + 1L)
    na[1] <- prior_alpha; nb[1] <- prior_beta; nm[1] <- prior_mean; nk[1] <- 1.0
    for (r in seq_len(t)) {
      na[r + 1L] <- alpha_vec[r] + 0.5
      nk[r + 1L] <- kappa_vec[r] + 1
      nm[r + 1L] <- (kappa_vec[r] * mu_vec[r] + x) / nk[r + 1L]
      nb[r + 1L] <- beta_vec[r] + (kappa_vec[r] * (x - mu_vec[r])^2) / (2 * nk[r + 1L])
    }
    w <- R[1L:(t + 1L), t + 1L]
    pmu[t] <- sum(w * nm[1:(t + 1L)])                       # 현재 국면의 평균 추정
    psd[t] <- sum(w * sqrt(nb[1:(t + 1L)] * (nk[1:(t + 1L)] + 1) /
                             (na[1:(t + 1L)] * nk[1:(t + 1L)])))   # 예측 척도
    alpha_vec[1:(t + 1L)] <- na; beta_vec[1:(t + 1L)] <- nb
    mu_vec[1:(t + 1L)] <- nm; kappa_vec[1:(t + 1L)] <- nk
  }
  list(change_prob = cp, short_run_mass = srm, expected_runlen = erl,
       post_mean = pmu, post_sd = psd)
}

# ── 입력 ─────────────────────────────────────────────────────────────────────
p <- as.data.table(read_parquet(PANEL))
p[, Date := as.Date(Date)]
p <- unique(p, by = "Date")[order(Date)]
valid <- !is.na(p$ret_net)
r <- p$ret_net[valid]
cat(sprintf("[panel] %d개월 (%s ~ %s) · ret_net 유효 %d\n",
            nrow(p), p$Date[1], p$Date[nrow(p)], sum(valid)))

ext <- bocpd_ext(r)

# ── ★재현 검사 (양성 대조) — 확장본이 원본 3출력을 재현하는가 ──────────────────
base_srm <- p$bocpd_short_run_mass_lag[valid]
base_erl <- p$bocpd_expected_runlen_lag[valid]
# 패널은 lag(1) 적용본이므로 확장본도 같은 규약으로 밀어 비교
lag1 <- function(v) c(NA_real_, v[-length(v)])
e_srm <- abs(lag1(ext$short_run_mass) - base_srm)
e_erl <- abs(lag1(ext$expected_runlen) - base_erl)
n_v <- length(base_srm)
# ★꼬리 2행 제외 이유 (2026-08-30 실측): **원본 함수를 그대로 재실행해도** 1~269행은
#   비트 단위로 재현되는데 270·271행(2026-07·08)만 ~1.8e-3 갈린다. 즉 구현 차이가 아니라
#   저장된 ret_net 의 꼬리가 bocpd 가 소비한 벡터와 다르다(런 내에서 최근월 수익이
#   Stage 3 이후 갱신된다). 그래서 본문은 **엄격 일치**로 걸고, 꼬리는 별도 관용으로
#   걸되 크기 상한을 둔다 — 진짜 알고리즘 변경이면 꼬리에서도 이 상한을 넘는다.
head_n <- max(1L, n_v - 2L)
d_head <- max(c(e_srm[1:head_n], e_erl[1:head_n]), na.rm = TRUE)
d_tail <- max(c(e_srm[(head_n + 1L):n_v], e_erl[(head_n + 1L):n_v]), na.rm = TRUE)
cat(sprintf("[parity] 본문 1~%d max|delta| = %.3e · 꼬리 2행 max|delta| = %.3e\n",
            head_n, d_head, d_tail))
if (d_head > 1e-9)
  stop("[parity] 본문이 원본을 재현하지 못함 — 확장 출력을 신뢰할 수 없다. 중단")
if (d_tail > 1e-1)
  stop("[parity] 꼬리 편차가 상한(1e-1)을 넘음 — ret_net 갱신으로 설명되지 않는다. 중단")
cat("[parity] OK — 확장 출력(post_mean/post_sd) 사용 가능\n")

# ── 소비 규약: 하류와 동일하게 lag(1) ────────────────────────────────────────
d <- data.table(Date = p$Date[valid], ret_net = r,
                mass = lag1(ext$short_run_mass), erl = lag1(ext$expected_runlen),
                pmu = lag1(ext$post_mean), psd = lag1(ext$post_sd),
                cash = p$Cash_Pct_lag[valid])
d[, fwd := ret_net]           # 결정행 t 의 소비 대상 = 그 달 수익 (패널 규약)
d[, clean := is.na(cash) | cash == 0]

# expanding 분위수 (full-sample 금지 — C1)
.exp_q <- function(v, q, min_n = 36L) {
  out <- rep(NA_real_, length(v))
  for (i in seq_along(v)) if (i > min_n) out[i] <- quantile(v[1:(i - 1L)], q, na.rm = TRUE)
  out
}
d[, q80_mass := .exp_q(mass, 0.80)]
d[, q20_pmu  := .exp_q(pmu, 0.20)]
d[, q80_psd  := .exp_q(psd, 0.80)]

# ── 후보 (사전등록 1급 = C1) ─────────────────────────────────────────────────
d[, C1 := as.integer(!is.na(q80_mass) & mass >= q80_mass & !is.na(pmu) & pmu < 0)]
d[, C2 := as.integer(!is.na(q80_mass) & mass >= q80_mass & !is.na(q20_pmu) & pmu <= q20_pmu)]
d[, C3 := as.integer(!is.na(q20_pmu) & pmu <= q20_pmu)]
d[, C4 := as.integer(!is.na(q80_psd) & psd >= q80_psd)]
d[, LEGACY := as.integer(!is.na(mass) & mass >= 0.60)]

cands <- c("C1", "C2", "C3", "C4", "LEGACY")

# ── 측정 ─────────────────────────────────────────────────────────────────────
sub <- d[clean == TRUE & !is.na(fwd)]
cat(sprintf("\n[scope] 매크로 clean 구간 %d개월 (전체 %d)\n", nrow(sub), nrow(d)))
miss <- sub[fwd < -0.05]
cat(sprintf("[target] 원 설계 표적 = clean 인데 ret < -5%% 인 달: %d개월\n", nrow(miss)))

res <- rbindlist(lapply(cands, function(cc) {
  x <- sub[[cc]]; y <- sub$fwd
  keep <- !is.na(x) & !is.na(y)
  x <- x[keep]; y <- y[keep]
  if (sum(x) == 0L) return(data.table(cand = cc, n_fire = 0L, mean_fire = NA_real_,
                                      mean_rest = mean(y), lift = NA_real_,
                                      recall = NA_real_, p_perm = NA_real_))
  mf <- mean(y[x == 1L]); mr <- mean(y[x == 0L])
  ev <- y < -0.05
  rec <- if (sum(ev) > 0) sum(x == 1L & ev) / sum(ev) else NA_real_
  base_rate <- mean(ev); fire_rate <- if (sum(x) > 0) mean(ev[x == 1L]) else NA_real_
  lift <- if (!is.na(base_rate) && base_rate > 0) fire_rate / base_rate else NA_real_
  # 순열검정 (단측: 발화달이 더 나쁜가)
  set.seed(20260830); B <- 5000L
  obs <- mf - mr
  perm <- replicate(B, { s <- sample(x); mean(y[s == 1L]) - mean(y[s == 0L]) })
  data.table(cand = cc, n_fire = sum(x), mean_fire = mf, mean_rest = mr,
             lift = lift, recall = rec, p_perm = mean(perm <= obs))
}))

cat("\n=== 후보 측정 (매크로 clean 구간, 단측 = 발화달이 더 나쁜가) ===\n")
print(res[, .(cand, n_fire,
              mean_fire = round(mean_fire * 100, 2), mean_rest = round(mean_rest * 100, 2),
              lift = round(lift, 3), recall = round(recall, 3), p_perm = round(p_perm, 4))])

# rank-IC (연속 신호 — 부호 확인)
ic <- data.table(
  signal = c("mass", "post_mean", "post_sd"),
  rank_ic = c(cor(sub$mass, sub$fwd, method = "spearman", use = "complete.obs"),
              cor(sub$pmu,  sub$fwd, method = "spearman", use = "complete.obs"),
              cor(sub$psd,  sub$fwd, method = "spearman", use = "complete.obs")))
cat("\n=== 연속 신호 rank-IC (fwd ret 대비) ===\n"); print(ic[, .(signal, rank_ic = round(rank_ic, 4))])

fwrite(d, file.path(OUT, "panel_measured.csv"))
fwrite(res, file.path(OUT, "candidates.csv"))
fwrite(ic, file.path(OUT, "rank_ic.csv"))
cat(sprintf("\n[out] %s/{panel_measured,candidates,rank_ic}.csv\n", OUT))
