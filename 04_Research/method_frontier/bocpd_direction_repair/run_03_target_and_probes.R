# run_03_target_and_probes.R — 표적 자체를 의심 + 탐색 후보 (사후, 라벨 명시)
#
# ── 왜 ───────────────────────────────────────────────────────────────────────
# run_01/02 에서 사전등록 1급(C1)이 실패했고 나머지도 블록 순열에서 전멸했다. 여기서
# 개별 후보를 더 만들기 전에 **표적을 먼저 의심**한다 — 정교화 전에 범주 상한부터
# (메모리: feedback-ceiling-first-before-refinement-probes).
#
# 이 팔의 설계 표적은 "매크로가 clean 이라 한 달 중 ret < -5%" 였다. 그런데 이 전략은
# 월 변동성이 크다. 변동성 대비 -5% 가 **꼬리 사건이 아니라 일상 사건**이면, 그걸 잡으라는
# 요구 자체가 월 단위 마켓타이밍이고 어떤 신호로도 안 된다. 그러면 팔의 문제가 아니라
# 표적의 문제다. 먼저 그걸 잰다.
#
# ★이 스크립트의 후보(C5/C6)는 **사후 탐색**이다. 1급은 이미 C1 에서 소진됐다
#   (feedback-preregistered-primary-fails-that-is-the-verdict). 여기서 무엇이 유의해도
#   그것은 확정이 아니라 **다음 라운드의 사전등록 대상**이다. 라벨을 붙여 보고한다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_03_target_and_probes.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(data.table))

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
d <- fread(file.path(OUT, "panel_measured.csv"))
d[, Date := as.Date(Date)]
sub <- d[clean == TRUE & !is.na(fwd)][order(Date)]
y <- sub$fwd

# ── ① 표적 진단: -5% 는 꼬리인가 일상인가 ───────────────────────────────────
mu <- mean(y); sdv <- sd(y)
obs_rate <- mean(y < -0.05)
norm_rate <- pnorm(-0.05, mean = mu, sd = sdv)
z_of_target <- (-0.05 - mu) / sdv
cat("=== 표적 진단 (매크로 clean 구간) ===\n")
cat(sprintf("  n=%d · 월평균 %.2f%% · 월변동성 %.2f%%\n", length(y), mu * 100, sdv * 100))
cat(sprintf("  -5%% 의 z 점수 = %.2f  →  정규 가정 발생률 %.1f%% · 실측 %.1f%%\n",
            z_of_target, norm_rate * 100, obs_rate * 100))
cat(sprintf("  판정: %s\n", if (abs(z_of_target) < 1.0)
  "★-5% 는 꼬리가 아니라 **일상 사건**(|z|<1). 이걸 잡으라는 건 월 단위 마켓타이밍 요구다."
  else "-5% 는 꼬리 영역."))

# 진짜 꼬리 기준(-1.5σ)이면 몇 개월인가 — 표적 재정의 여지
tail_cut <- mu - 1.5 * sdv
cat(sprintf("  참고: -1.5σ 컷 = %.2f%% → 해당 %d개월 (기저율 %.1f%%)\n",
            tail_cut * 100, sum(y < tail_cut), mean(y < tail_cut) * 100))

# ── ② 탐색 후보 (사후 — 확정 아님) ──────────────────────────────────────────
#   C5: 변화점 ∩ **하향 이동** — 수준이 아니라 Δ(사후평균). "국면이 아래로 바뀌었다".
#   C6: 사후평균의 하향 이동 단독(변화점 조건 없음) — C5 의 대조군(변화점이 기여하는가).
.exp_q <- function(v, q, min_n = 36L) {
  out <- rep(NA_real_, length(v))
  for (i in seq_along(v)) if (i > min_n) out[i] <- quantile(v[1:(i - 1L)], q, na.rm = TRUE)
  out
}
sub[, dmu := pmu - shift(pmu, 3L)]                  # 3개월 전 대비 국면평균 이동
sub[, q20_dmu := .exp_q(dmu, 0.20)]
sub[, C5 := as.integer(!is.na(q80_mass) & mass >= q80_mass &
                         !is.na(q20_dmu) & dmu <= q20_dmu)]
sub[, C6 := as.integer(!is.na(q20_dmu) & dmu <= q20_dmu)]

block_perm_p <- function(x, y, B = 5000L, seed = 20260830) {
  x[is.na(x)] <- 0L
  if (sum(x) == 0L) return(NA_real_)
  obs <- mean(y[x == 1L]) - mean(y[x == 0L])
  set.seed(seed); n <- length(x)
  st <- sample.int(n, B, replace = TRUE)
  p <- vapply(st, function(s) {
    xs <- x[c(s:n, seq_len(s - 1L))]
    if (sum(xs) == 0L || sum(xs) == n) return(NA_real_)
    mean(y[xs == 1L]) - mean(y[xs == 0L])
  }, numeric(1))
  mean(p <= obs, na.rm = TRUE)
}

probe <- rbindlist(lapply(c("C5", "C6"), function(cc) {
  x <- sub[[cc]]; x[is.na(x)] <- 0L
  if (sum(x) == 0L) return(data.table(cand = cc, n_fire = 0L, n_episode = 0L,
                                      mean_fire = NA_real_, mean_rest = mean(y),
                                      lift = NA_real_, p_block = NA_real_))
  r <- rle(x == 1L)
  ev <- y < -0.05
  data.table(cand = cc, n_fire = sum(x), n_episode = sum(r$values),
             mean_fire = mean(y[x == 1L]), mean_rest = mean(y[x == 0L]),
             lift = mean(ev[x == 1L]) / mean(ev),
             p_block = block_perm_p(x, y))
}))
cat("\n=== 탐색 후보 (★사후 — 확정 아님, 다음 라운드 사전등록 대상) ===\n")
print(probe[, .(cand, n_fire, n_episode,
                mean_fire = round(mean_fire * 100, 2), mean_rest = round(mean_rest * 100, 2),
                lift = round(lift, 3), p_block = round(p_block, 4))])

fwrite(probe, file.path(OUT, "probes.csv"))
cat(sprintf("\n[out] %s/probes.csv\n", OUT))
