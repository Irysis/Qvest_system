# =============================================================================
# run_era_nowcast.R — WT-D20260803_006 (FQ-133)
#   era 공통성분의 사전 추정 가능성 — 자격 게이트의 구속 관문
#   사전등록: stage_artifacts/WT_D20260803_006/preregistration.json (측정 전 고정)
#
#   입력: WT-D20260803_005 canonical_pool.rds (322 factor canonical net-active, 287월)
#   핵심: t 시점까지의 정보만으로 다음 h개월 era(팩터 집단 부호 방향)를 맞히는가
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_006/run_era_nowcast.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006] ", fmt, "\n"), ...))
set.seed(20260803L)

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
H_PRIMARY <- 24L
H_ROB     <- c(12L, 36L, 60L)
BURN_IN   <- 60L
MIN_SEG   <- 12L
NBOOT     <- 2000L

# ── 1. 풀 로드 + 중복제거 (WT-005 사전등록 규칙 동일) ───────────────────────
CP  <- readRDS(file.path(SRC, "canonical_pool.rds"))
LAB <- as.data.table(readRDS(file.path(SRC, "registry_labels.rds")))
RES <- CP$res
DATES <- sort(unique(as.Date(unlist(lapply(RES, function(x) as.character(x$date))))))
A0 <- matrix(NA_real_, nrow = length(DATES), ncol = length(RES),
             dimnames = list(as.character(DATES), names(RES)))
BM <- rep(NA_real_, length(DATES)); names(BM) <- as.character(DATES)
for (f in names(RES)) {
  r <- RES[[f]]; A0[as.character(r$date), f] <- r$active
  BM[as.character(r$date)] <- r$benchmark_ret
}
CM <- suppressWarnings(cor(A0, use = "pairwise.complete.obs")); CM[!is.finite(CM)] <- 0
ord <- sort(colnames(A0)); keep <- character(0)
for (f in ord) {
  if (!length(keep)) { keep <- f; next }
  if (max(abs(CM[f, keep]), na.rm = TRUE) < 0.99) keep <- c(keep, f)
}
A <- A0[, keep, drop = FALSE]; POOL <- keep; NM <- nrow(A)
say("풀 %d → 중복제거 %d factor | %d월 (%s ~ %s)", ncol(A0), ncol(A), NM,
    DATES[1], DATES[NM])
say("완전관측 factor %d | 월별 유효 factor min %d", sum(colSums(is.na(A)) == 0L),
    min(rowSums(is.finite(A))))

# ── 2. era 통계 (동일 functional, segment 만 다름) ──────────────────────────
# era_stat(S, M): 구간 S 에서 '평균 net-active > 0 인 factor 비율'
era_stat <- function(idx, M = A, min_cov = 0.8) {
  if (!length(idx)) return(NA_real_)
  sub <- M[idx, , drop = FALSE]
  nf  <- colSums(is.finite(sub))
  ok  <- nf >= max(1L, floor(min_cov * length(idx)))
  if (!any(ok)) return(NA_real_)
  mu <- colMeans(sub[, ok, drop = FALSE], na.rm = TRUE)
  mean(mu > 0, na.rm = TRUE)
}
# 월간 breadth (CUSUM 입력 — 원시, 롤링 없음: FQ-055 V2 프레임)
Bm <- apply(A, 1L, function(x) mean(x[is.finite(x)] > 0))
# 대체 정의: 횡단면 평균 active
Gm <- apply(A, 1L, function(x) mean(x[is.finite(x)]))
say("월간 breadth B_t: 평균 %.4f / sd %.4f / 범위 [%.3f, %.3f]",
    mean(Bm), sd(Bm), min(Bm), max(Bm))

# forward target
fwd_E <- function(h, M = A) vapply(seq_len(NM), function(t) {
  if (t + h > NM) return(NA_real_)
  era_stat((t + 1L):(t + h), M)
}, numeric(1))

# ── 3. 추정자 (전부 동일 functional, segment 시작점만 다름) ─────────────────
# 실시간 CUSUM 단절 위치 (확장창)
cusum_tau <- function(x) { cs <- cumsum(x - mean(x)); which.max(abs(cs)) }

est_rt_cusum <- function(t, M = A, xB = Bm, tmax = t) {
  # 정보집합 1..tmax (tmax>t 이면 누출 주입)
  tau <- cusum_tau(xB[1:tmax])
  s0  <- tau + 1L
  if (tmax - s0 + 1L < MIN_SEG) s0 <- max(1L, tmax - MIN_SEG + 1L)
  list(seg = s0:tmax, tau = tau, val = era_stat(s0:tmax, M))
}
est_trail  <- function(t, L, M = A) era_stat(max(1L, t - L + 1L):t, M)
est_expand <- function(t, M = A) era_stat(1:t, M)

pred_from <- function(v) ifelse(is.na(v), NA_integer_, ifelse(v > 0.5, 1L, -1L))

# ── 4. 평가 루프 ────────────────────────────────────────────────────────────
evaluate <- function(h, M = A, xB = Bm, tag = "primary") {
  E  <- fwd_E(h, M)
  y  <- pred_from(E)
  tt <- which(seq_len(NM) > BURN_IN & is.finite(y))
  n  <- length(tt)
  P  <- data.table(t = tt, Date = DATES[tt], E = E[tt], y = y[tt])
  # primary + baselines + trailing diagnostics
  P[, rt_cusum := vapply(t, function(x) est_rt_cusum(x, M, xB)$val, numeric(1))]
  P[, tau_hat  := vapply(t, function(x) est_rt_cusum(x, M, xB)$tau,  numeric(1))]
  P[, br_rt    := vapply(t, function(x) est_expand(x, M), numeric(1))]
  for (L in c(12L, 24L, 36L, 60L))
    P[, paste0("trail", L) := vapply(t, function(x) est_trail(x, L, M), numeric(1))]
  # 누출 주입
  P[, peek6 := vapply(t, function(x) est_rt_cusum(x, M, xB, tmax = min(NM, x + 6L))$val, numeric(1))]
  tau_full <- cusum_tau(xB)
  P[, fullcusum := vapply(t, function(x) {
      idx <- if (x <= tau_full) 1:tau_full else (tau_full + 1L):NM
      era_stat(idx, M) }, numeric(1))]
  P[, oracle := E]
  for (cc in c("rt_cusum","br_rt","trail12","trail24","trail36","trail60",
               "peek6","fullcusum","oracle"))
    set(P, j = paste0("p_", cc), value = pred_from(P[[cc]]))
  list(P = P, h = h, n = n, tag = tag)
}

# ── 5. 정확도 + block bootstrap ─────────────────────────────────────────────
acc_of <- function(p, y) mean(p == y, na.rm = TRUE)
sb_boot <- function(d, block_mean, B = NBOOT) {
  n <- length(d); out <- numeric(B); p <- 1 / block_mean
  for (b in seq_len(B)) {
    idx <- integer(n); i <- sample.int(n, 1L)
    for (k in seq_len(n)) {
      idx[k] <- i
      if (runif(1) < p) i <- sample.int(n, 1L) else { i <- i + 1L; if (i > n) i <- 1L }
    }
    out[b] <- mean(d[idx])
  }
  out
}

summarize <- function(EV) {
  P <- EV$P; h <- EV$h; y <- P$y
  BR_maj <- max(mean(y == 1L), mean(y == -1L))
  cols <- c("rt_cusum","br_rt","trail12","trail24","trail36","trail60",
            "peek6","fullcusum","oracle")
  acc <- vapply(cols, function(cc) acc_of(P[[paste0("p_", cc)]], y), numeric(1))
  # 전이-조건부: y_t != y_{t-h} (지평을 가로질러 era 가 바뀌는 월)
  ylag <- rep(NA_integer_, nrow(P))
  m <- match(P$t - h, P$t); ok <- !is.na(m); ylag[ok] <- y[m[ok]]
  trans <- which(!is.na(ylag) & ylag != y)
  acc_tr <- vapply(cols, function(cc)
    if (length(trans)) acc_of(P[[paste0("p_", cc)]][trans], y[trans]) else NA_real_, numeric(1))
  # 비중첩 평가
  ni <- seq(1L, nrow(P), by = h)
  acc_ni <- vapply(cols, function(cc) acc_of(P[[paste0("p_", cc)]][ni], y[ni]), numeric(1))
  # bootstrap: rt_cusum vs br_rt / vs 최빈상수
  d1 <- (P$p_rt_cusum == y) - (P$p_br_rt == y)
  maj <- if (mean(y == 1L) >= 0.5) 1L else -1L
  d2 <- (P$p_rt_cusum == y) - (maj == y)
  bl <- h + 12L
  b1 <- sb_boot(as.numeric(d1), bl); b2 <- sb_boot(as.numeric(d2), bl)
  # era 에피소드
  rl <- rle(y); n_ep <- length(rl$lengths)
  list(h = h, n_eval = nrow(P), n_noverlap = length(ni), BR_maj = BR_maj,
       maj_class = maj, acc = acc, acc_trans = acc_tr, acc_noverlap = acc_ni,
       n_trans = length(trans), n_episodes = n_ep, episode_len = rl$lengths,
       episode_sign = rl$values,
       d1_mean = mean(d1), d1_p = mean(b1 <= 0), d1_ci = quantile(b1, c(.025, .975)),
       d2_mean = mean(d2), d2_p = mean(b2 <= 0), d2_ci = quantile(b2, c(.025, .975)),
       block = bl, eff_n = nrow(P) / bl, P = P)
}

say("=== primary h=%d 평가 시작 ===", H_PRIMARY)
EVp <- evaluate(H_PRIMARY); Sp <- summarize(EVp)
say("평가 관측 %d (비중첩 %d) | era 에피소드 %d | 전이 월 %d",
    Sp$n_eval, Sp$n_noverlap, Sp$n_episodes, Sp$n_trans)
say("에피소드 길이/부호: %s", paste(sprintf("%+d:%dm", Sp$episode_sign, Sp$episode_len), collapse=" "))
say("base rate  BR_maj(사후 최빈 상수) %.4f | BR_rt(실시간 확장) %.4f",
    Sp$BR_maj, Sp$acc[["br_rt"]])
print(data.table(estimator = names(Sp$acc), acc = round(Sp$acc, 4),
                 acc_transition = round(Sp$acc_trans, 4),
                 acc_nonoverlap = round(Sp$acc_noverlap, 4)))
say("★PRIMARY RT_CUSUM 적중률 %.4f | vs BR_rt Δ %+.4f (block bootstrap p=%.4f, CI[%.3f,%.3f])",
    Sp$acc[["rt_cusum"]], Sp$d1_mean, Sp$d1_p, Sp$d1_ci[1], Sp$d1_ci[2])
say("★PRIMARY vs BR_maj Δ %+.4f (p=%.4f, CI[%.3f,%.3f]) | block=%d, 유효표본 %.1f",
    Sp$d2_mean, Sp$d2_p, Sp$d2_ci[1], Sp$d2_ci[2], Sp$block, Sp$eff_n)

# ── 6. 위반 주입 판정 ───────────────────────────────────────────────────────
say("=== 위반 주입 ===")
inj <- data.table(
  arm = c("BASE(RT_CUSUM)", "INJ_ORACLE", "INJ_PEEK6", "INJ_FULLSAMPLE_CUSUM"),
  acc = c(Sp$acc[["rt_cusum"]], Sp$acc[["oracle"]], Sp$acc[["peek6"]], Sp$acc[["fullcusum"]]),
  acc_transition = c(Sp$acc_trans[["rt_cusum"]], Sp$acc_trans[["oracle"]],
                     Sp$acc_trans[["peek6"]], Sp$acc_trans[["fullcusum"]]))
inj[, delta_vs_base := acc - acc[1]]
print(inj)
ORACLE_OK <- abs(Sp$acc[["oracle"]] - 1) < 1e-9
say("INJ_ORACLE 양성대조: %s (적중률 %.6f — 1.000 아니면 배관 파손)",
    ifelse(ORACLE_OK, "PASS", "FAIL"), Sp$acc[["oracle"]])
say("INJ_FULLSAMPLE_CUSUM Δ %+.4f (전이월 Δ %+.4f) — '사후 era 분할은 쉽다' 실증",
    inj$delta_vs_base[4], Sp$acc_trans[["fullcusum"]] - Sp$acc_trans[["rt_cusum"]])
say("INJ_PEEK6 Δ %+.4f (전이월 Δ %+.4f)",
    inj$delta_vs_base[3], Sp$acc_trans[["peek6"]] - Sp$acc_trans[["rt_cusum"]])

# ── 7. 탐지 지연 ────────────────────────────────────────────────────────────
P <- Sp$P
chg <- which(c(FALSE, diff(P$y) != 0))
lagd <- data.table()
for (i in chg) {
  tgt <- P$y[i]
  fut <- which(seq_len(nrow(P)) >= i & P$p_rt_cusum == tgt)
  lg  <- if (length(fut)) fut[1] - i else NA_integer_
  futF <- which(seq_len(nrow(P)) >= i & P$p_fullcusum == tgt)
  lgF <- if (length(futF)) futF[1] - i else NA_integer_
  lagd <- rbind(lagd, data.table(change_date = P$Date[i], to_sign = tgt,
                                 lag_rt_cusum_m = lg, lag_fullcusum_m = lgF))
}
say("=== era 전환 시점 탐지 지연 (전환 %d회) ===", nrow(lagd))
if (nrow(lagd)) print(lagd)
say("지연 중앙값 RT_CUSUM %s개월 (지평 h=%d 초과 = 실무상 사전 추정 불가)",
    ifelse(nrow(lagd), as.character(median(lagd$lag_rt_cusum_m, na.rm=TRUE)), "NA"), H_PRIMARY)

# ── 8. h robustness ─────────────────────────────────────────────────────────
say("=== h robustness (12/36/60) ===")
ROB <- list()
for (h in H_ROB) {
  ev <- evaluate(h); s <- summarize(ev); ROB[[as.character(h)]] <- s
  say("h=%2d | n %3d | 에피소드 %d | BR_rt %.4f BR_maj %.4f | RT_CUSUM %.4f (전이 %.4f) | Δvs BR_rt %+.4f p=%.4f | ORACLE %.4f",
      h, s$n_eval, s$n_episodes, s$acc[["br_rt"]], s$BR_maj, s$acc[["rt_cusum"]],
      s$acc_trans[["rt_cusum"]], s$d1_mean, s$d1_p, s$acc[["oracle"]])
}

# ── 9. 진단 추정자: 횡단면 구조 / 스프레드 / 음성대조 국면 라벨 ─────────────
say("=== 진단 추정자 (확장창 로지스틱, 학습 target 은 t-h 까지 실현분만) ===")
feat_build <- function() {
  n <- NM
  f_sd <- rep(NA_real_, n); f_sp <- rep(NA_real_, n); f_cor <- rep(NA_real_, n)
  for (t in seq_len(n)) {
    i12 <- max(1L, t - 11L):t
    mu <- colMeans(A[i12, , drop = FALSE], na.rm = TRUE)
    mu <- mu[is.finite(mu)]
    if (length(mu) > 10) { f_sd[t] <- sd(mu); f_sp[t] <- diff(quantile(mu, c(.1, .9))) }
    if (t >= 24L) {
      i24 <- (t - 23L):t
      sub <- A[i24, , drop = FALSE]
      sub <- sub[, colSums(is.finite(sub)) == length(i24), drop = FALSE]
      if (ncol(sub) > 20) {
        cc <- suppressWarnings(cor(sub)); f_cor[t] <- mean(cc[upper.tri(cc)], na.rm = TRUE)
      }
    }
  }
  bm12 <- vapply(seq_len(n), function(t) { i <- max(1L,t-11L):t; prod(1 + BM[i]) - 1 }, numeric(1))
  bv12 <- vapply(seq_len(n), function(t) { i <- max(1L,t-11L):t; sd(BM[i]) }, numeric(1))
  data.table(t = seq_len(n), xsec_sd = f_sd, xsec_cor = f_cor, spread = f_sp,
             bm_ret12 = bm12, bm_vol12 = bv12)
}
FT <- feat_build()
logit_rt <- function(P, FT, vars, h) {
  D <- merge(P[, .(t, y)], FT, by = "t")
  pr <- rep(NA_integer_, nrow(D))
  for (i in seq_len(nrow(D))) {
    tt <- D$t[i]
    tr <- D[t <= tt - h]
    tr <- tr[complete.cases(tr[, c("y", vars), with = FALSE])]
    if (nrow(tr) < 40 || length(unique(tr$y)) < 2) next
    fml <- as.formula(paste("I(y==1L) ~", paste(vars, collapse = " + ")))
    fit <- tryCatch(suppressWarnings(glm(fml, data = tr, family = binomial())),
                    error = function(e) NULL)
    if (is.null(fit)) next
    nd <- D[i, c(vars), with = FALSE]
    if (any(!is.finite(unlist(nd)))) next
    pp <- tryCatch(predict(fit, newdata = nd, type = "response"), error = function(e) NA_real_)
    if (is.finite(pp)) pr[i] <- if (pp > 0.5) 1L else -1L
  }
  list(acc = mean(pr == D$y, na.rm = TRUE), n = sum(!is.na(pr)), pred = pr, D = D)
}
L3 <- logit_rt(P, FT, c("xsec_sd", "xsec_cor"), H_PRIMARY)
L4 <- logit_rt(P, FT, c("spread", "bm_ret12", "bm_vol12"), H_PRIMARY)
say("③ XSEC_STRUCT (xsec_sd + xsec_cor): 적중률 %.4f (n=%d)", L3$acc, L3$n)
say("④ SPREAD_COMPRESS (spread + bm_ret12 + bm_vol12): 적중률 %.4f (n=%d)", L4$acc, L4$n)

# 음성대조: 기존 국면 라벨 (추정자 아님)
RG <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
RG[, Date := as.Date(Date)]
RGm <- RG[, .(YM = format(Date, "%Y-%m"), Category)]
Pm <- copy(P)[, YM := format(Date, "%Y-%m")]
Pm <- merge(Pm, RGm, by = "YM", all.x = TRUE)
setorder(Pm, t)
pr_nc <- rep(NA_integer_, nrow(Pm))
for (i in seq_len(nrow(Pm))) {
  tt <- Pm$t[i]; cat_i <- Pm$Category[i]
  if (is.na(cat_i)) next
  tr <- Pm[t <= tt - H_PRIMARY & Category == cat_i]
  if (nrow(tr) < 12) next
  pr_nc[i] <- if (mean(tr$y == 1L) > 0.5) 1L else -1L
}
acc_nc <- mean(pr_nc == Pm$y, na.rm = TRUE)
say("★음성대조 REGIME_LABEL_NC (기존 국면 라벨 확장창 매핑): 적중률 %.4f (n=%d) — 설계 제약상 추정자 아님",
    acc_nc, sum(!is.na(pr_nc)))
say("   라벨 분포 x era: ")
print(Pm[!is.na(Category), .(n = .N, era_pos_ratio = mean(y == 1L)), by = Category][order(-n)])

# ── 10. Sensitivity ─────────────────────────────────────────────────────────
say("=== sensitivity ===")
full_f <- colnames(A)[colSums(is.na(A)) == 0L]
Af <- A[, full_f, drop = FALSE]
Bf <- apply(Af, 1L, function(x) mean(x[is.finite(x)] > 0))
Sf <- summarize(evaluate(H_PRIMARY, M = Af, xB = Bf, tag = "fullobs"))
say("S1 완전관측 %d factor 한정: RT_CUSUM %.4f | BR_rt %.4f | 전이 %.4f | Δ %+.4f p=%.4f",
    ncol(Af), Sf$acc[["rt_cusum"]], Sf$acc[["br_rt"]], Sf$acc_trans[["rt_cusum"]],
    Sf$d1_mean, Sf$d1_p)

set.seed(11L); hlf <- sample(POOL, floor(length(POOL)/2))
A1 <- A[, hlf, drop = FALSE]; A2 <- A[, setdiff(POOL, hlf), drop = FALSE]
B1 <- apply(A1, 1L, function(x) mean(x[is.finite(x)] > 0))
B2 <- apply(A2, 1L, function(x) mean(x[is.finite(x)] > 0))
E1 <- fwd_E(H_PRIMARY, A1); E2 <- fwd_E(H_PRIMARY, A2)
agree <- mean(pred_from(E1) == pred_from(E2), na.rm = TRUE)
say("S2 pool 무작위 반분: 월간 breadth 상관 %.4f | forward era 지수 상관 %.4f | 부호 일치 %.4f",
    cor(B1, B2), cor(E1, E2, use = "complete.obs"), agree)

# 대체 era 정의 g_t (횡단면 평균) — CUSUM 입력만 교체
Sg <- summarize(evaluate(H_PRIMARY, M = A, xB = Gm, tag = "g_index"))
say("S3 era 지수 대체(g_t 횡단면 평균)로 CUSUM: RT_CUSUM %.4f | 전이 %.4f | Δ %+.4f p=%.4f",
    Sg$acc[["rt_cusum"]], Sg$acc_trans[["rt_cusum"]], Sg$d1_mean, Sg$d1_p)

# family 별 era 일치도
LABp <- LAB[Factor_Name %in% POOL]
fam_tab <- data.table()
for (fm in unique(LABp$family)) {
  ff <- LABp[family == fm, Factor_Name]
  if (length(ff) < 8) next
  Ef <- fwd_E(H_PRIMARY, A[, ff, drop = FALSE])
  fam_tab <- rbind(fam_tab, data.table(family = fm, n_factor = length(ff),
    cor_with_pool = cor(Ef, fwd_E(H_PRIMARY), use = "complete.obs"),
    sign_agree = mean(pred_from(Ef) == pred_from(fwd_E(H_PRIMARY)), na.rm = TRUE)))
}
say("S4 family 별 era 지수 vs 풀 전체 (era 가 공통성분인지)")
print(fam_tab[order(-n_factor)])

# ── 11. MDE (검정력) ────────────────────────────────────────────────────────
mde <- function(n_eff) 1.645 * sqrt(0.25 / n_eff)   # 이항 근사 단측 5%
say("=== 검정력 ===")
say("유효 독립 블록 %.1f (block=%d) → 단측 5%% 검출 최소 우위 MDE ~ %.3f (적중률 절대폭)",
    Sp$eff_n, Sp$block, mde(Sp$eff_n))
say("비중첩 시행 %d회 → MDE ~ %.3f | era 에피소드 %d개 (플리커 포함)",
    Sp$n_noverlap, mde(Sp$n_noverlap), Sp$n_episodes)
need_n <- ceiling(0.25 * (1.645 / max(1e-6, abs(Sp$d1_mean)))^2)
say("관측 Δ %+.4f 를 p<0.05 로 확정하려면 유효 독립 블록 %d개 필요 → 현재 %.1f개, 추가 %.1f년 (block %d개월)",
    Sp$d1_mean, need_n, Sp$eff_n, max(0, (need_n - Sp$eff_n)) * Sp$block / 12, Sp$block)

# ── 11b. 지속 에피소드 / 전이 부분집합의 정직한 검정 ────────────────────────
say("=== 지속(sustained) era 에피소드 + 전이 부분집합 검정 ===")
rl <- rle(P$y)
sus <- which(rl$lengths >= 6L)
say("전체 에피소드 %d개 중 지속(>=6m) %d개 | 지속 길이: %s",
    length(rl$lengths), length(sus), paste(rl$lengths[sus], collapse = ","))
ends <- cumsum(rl$lengths); starts <- ends - rl$lengths + 1L
SUS <- data.table(from = P$Date[starts[sus]], to = P$Date[ends[sus]],
                  sign = rl$values[sus], len_m = rl$lengths[sus])
print(SUS)
# 지속 에피소드 간 전환 시점의 탐지 지연
lag_sus <- data.table()
if (nrow(SUS) >= 2) for (i in 2:nrow(SUS)) {
  i0 <- starts[sus[i]]; tgt <- rl$values[sus[i]]
  fut <- which(seq_len(nrow(P)) >= i0 & P$p_rt_cusum == tgt)
  futF <- which(seq_len(nrow(P)) >= i0 & P$p_fullcusum == tgt)
  lag_sus <- rbind(lag_sus, data.table(change_date = P$Date[i0], to_sign = tgt,
    lag_rt_cusum_m = if (length(fut)) fut[1] - i0 else NA_integer_,
    lag_fullcusum_m = if (length(futF)) futF[1] - i0 else NA_integer_))
}
say("지속 에피소드 전환 %d회 탐지 지연:", nrow(lag_sus)); if (nrow(lag_sus)) print(lag_sus)

# 전이 부분집합 (y_t != y_{t-h}) — 이항 + block bootstrap
ylag2 <- rep(NA_integer_, nrow(P)); m2 <- match(P$t - H_PRIMARY, P$t); ok2 <- !is.na(m2)
ylag2[ok2] <- P$y[m2[ok2]]
tr_idx <- which(!is.na(ylag2) & ylag2 != P$y)
hit_tr <- as.numeric(P$p_rt_cusum[tr_idx] == P$y[tr_idx])
bt <- sb_boot(hit_tr, H_PRIMARY + 12L)
say("전이 부분집합 n=%d | RT_CUSUM 적중 %d/%d = %.4f | 이항(중첩 무시, 낙관) p(X<=k|0.5)=%.5f | block bootstrap P(acc>=0.5)=%.4f",
    length(tr_idx), sum(hit_tr), length(hit_tr), mean(hit_tr),
    pbinom(sum(hit_tr), length(hit_tr), 0.5), mean(bt >= 0.5))
say("★trail24 의 전이 적중률 0.000 은 **정의상 항등** (전이 부분집합 = y_t != y_{t-24}, trail24 예측 = y_{t-24}) — 증거 아님, 해석 제외")
tr_eff <- length(tr_idx) / (H_PRIMARY + 12L)
say("전이 부분집합 유효 독립 블록 %.1f — 이 축도 형식적 검정력은 낮다(정직 라벨)", tr_eff)

# ── 11c. 명확 era 부분집합 (|E-0.5| > 0.1) ──────────────────────────────────
clr <- which(abs(P$E - 0.5) > 0.1)
say("명확 era 부분집합 |E-0.5|>0.1: n=%d | RT_CUSUM %.4f | BR_rt %.4f | fullcusum %.4f | oracle %.4f",
    length(clr), mean(P$p_rt_cusum[clr] == P$y[clr]), mean(P$p_br_rt[clr] == P$y[clr]),
    mean(P$p_fullcusum[clr] == P$y[clr]), mean(P$p_oracle[clr] == P$y[clr]))
clr_tr <- intersect(clr, tr_idx)
say("  그 중 전이 월 n=%d | RT_CUSUM %.4f", length(clr_tr),
    if (length(clr_tr)) mean(P$p_rt_cusum[clr_tr] == P$y[clr_tr]) else NA_real_)

# ── 11d. 추정자 ⑤ 유니버스 집중도 (기계적 후보 — 메가캡 레짐 가설) ──────────
say("=== 추정자 ⑤ 유니버스 집중도 (top-10 시총 비중 / HHI) ===")
RAWc <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Size","K200","KQ150")))
RAWc[, Date := as.Date(Date)]
RAWc <- RAWc[Date %in% DATES & (K200 == TRUE | KQ150 == TRUE) & is.finite(Size) & Size > 0]
CONC <- RAWc[, {
  s <- sort(Size, decreasing = TRUE); w <- s / sum(s)
  .(top10 = sum(head(w, 10)), hhi = sum(w^2), n_univ = length(w))
}, by = Date][order(Date)]
CONC <- merge(data.table(Date = DATES, t = seq_along(DATES)), CONC, by = "Date", all.x = TRUE)
CONC[, top10_d12 := top10 - shift(top10, 12L)]
CONC[, hhi_d12   := hhi   - shift(hhi, 12L)]
say("집중도 top10 범위 [%.3f, %.3f] | 최근값 %.3f", min(CONC$top10, na.rm=TRUE),
    max(CONC$top10, na.rm=TRUE), CONC$top10[nrow(CONC)])
FT5 <- CONC[, .(t, top10, hhi, top10_d12, hhi_d12)]
L5 <- logit_rt(P, FT5, c("top10", "top10_d12"), H_PRIMARY)
say("⑤ CONCENTRATION (top10 + Δ12m): 적중률 %.4f (n=%d)", L5$acc, L5$n)
# 전이 부분집합에서의 ⑤
D5 <- L5$D; pr5 <- L5$pred
i5 <- match(P$t[tr_idx], D5$t); i5 <- i5[!is.na(i5)]
say("  전이 부분집합 ⑤ 적중률 %.4f (n=%d)", mean(pr5[i5] == D5$y[i5], na.rm = TRUE),
    sum(!is.na(pr5[i5])))
# 동시대 상관 (진단): 집중도 vs 실현 era
say("  진단 — top10 vs forward era 지수 상관 %.4f | top10 vs 월간 breadth 상관 %.4f",
    cor(CONC$top10, fwd_E(H_PRIMARY), use = "complete.obs"),
    cor(CONC$top10, Bm, use = "complete.obs"))

# ── 12. 판정 ────────────────────────────────────────────────────────────────
PASS_acc  <- (Sp$acc[["rt_cusum"]] > Sp$acc[["br_rt"]]) && (Sp$acc[["rt_cusum"]] > Sp$BR_maj)
PASS_p    <- Sp$d1_p < 0.05
PASS_tr   <- is.finite(Sp$acc_trans[["rt_cusum"]]) && Sp$acc_trans[["rt_cusum"]] > 0.5
n_sus <- length(sus)
verdict <- if (!ORACLE_OK) "INVALID_PLUMBING" else
           if (PASS_acc && PASS_p && PASS_tr) "PASS" else
           if (PASS_acc && !PASS_p && n_sus <= 3) "UNDERPOWERED" else "FAIL"
say("=== 판정: %s ===", verdict)
say("  적중률>base %s | bootstrap p<0.05 %s (p=%.4f) | 전이-조건부>0.5 %s (%.4f) | 지속 에피소드 %d",
    PASS_acc, PASS_p, Sp$d1_p, PASS_tr, Sp$acc_trans[["rt_cusum"]], n_sus)

saveRDS(list(Sp = Sp, ROB = ROB, inj = inj, lagd = lagd, L3 = L3, L4 = L4, L5 = L5,
             acc_nc = acc_nc, Pm = Pm, Sf = Sf, Sg = Sg, fam_tab = fam_tab,
             agree_half = agree, cor_half_B = cor(B1, B2),
             cor_half_E = cor(E1, E2, use = "complete.obs"),
             Bm = Bm, Gm = Gm, DATES = DATES, POOL = POOL, FT = FT, CONC = CONC,
             SUS = SUS, lag_sus = lag_sus, n_sus = n_sus,
             tr_idx = tr_idx, hit_tr = hit_tr, tr_boot_p = mean(bt >= 0.5),
             tr_binom_p = pbinom(sum(hit_tr), length(hit_tr), 0.5), tr_eff = tr_eff,
             clr_n = length(clr), clr_acc = mean(P$p_rt_cusum[clr] == P$y[clr]),
             verdict = verdict, oracle_ok = ORACLE_OK,
             mde_eff = mde(Sp$eff_n), mde_ni = mde(Sp$n_noverlap), need_n = need_n),
        file.path(OUT, "era_results.rds"))
say("saved era_results.rds")
say("DONE")
