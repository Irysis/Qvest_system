# run_04_tail_primary.R — 손실함수 정정: 보험은 평균이 아니라 꼬리로 잰다
#
# ── 왜 다시 재는가 (사전등록 재선언) ─────────────────────────────────────────
# run_01 의 1급은 **평균 수익 차이**였다. 그건 이 팔의 목적함수가 아니다.
# BOCPD 팔은 m4 게이트 안의 **보험**이다 — Case C/D 가 하는 일은 8~20% 현금을 얹어
# 나쁜 달의 손실을 줄이는 것이지 평균 수익을 올리는 게 아니다. 보험을 평균차로 검정하면
# "보험료 때문에 평균이 안 올랐다"는 이유로 작동하는 보험도 기각된다.
# 실제로 run_01 표에서 가장 강한 숫자는 LEGACY 의 **lift 2.18** 이었는데, 1급을 평균차로
# 잡는 바람에 부차 지표로 밀려났다.
#
# ★이것은 사후 갈아타기가 아니다 — 갈아타기라면 "평균차가 실패했으니 유의한 걸 찾자"가
#   된다. 여기서는 **통계량을 고르는 근거가 데이터가 아니라 팔의 목적함수**다. 평균차
#   실패는 그대로 보고하고(run_01/02 판정 유지), 목적함수에 맞는 검정을 새로 사전등록한다.
#
# 【사전등록 — 이 파일 실행 전 확정】
#   대상   : LEGACY = 가드 정정판 (mass >= 0.60, warm-up 은 관측개월수로 분리)
#   1급    : P(ret < -5% | 발화) / P(ret < -5%)  = **lift**, 단측(lift > 1)
#   검정   : 블록 순열(길이 보존 순환이동) — 발화가 연속월로 뭉치므로 월 순열은 낙관적
#   2급    : 왼쪽 꼬리 평균(CVaR@20%) 차이 · 발화월 하위 5% 손실
#   판정   : 1급 p_block < 0.05 → 채택 검토 / 그 외 → 미결 유지(도훈 판단)
#   ★문턱 0.60 은 **기존 코드값**이다. 스윕하지 않는다 — 스윕하면 selection 이 들어가고
#     이 표본(4에피소드)에서 DSR 을 감당할 수 없다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_04_tail_primary.R

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
x <- sub$LEGACY; x[is.na(x)] <- 0L
EV <- -0.05

cat("=== 사전등록 1급: 꼬리 사건 lift (보험 목적함수) ===\n")
cat(sprintf("  표본 %d개월 · 발화 %d개월 (%d에피소드)\n",
            length(y), sum(x), sum(rle(x == 1L)$values)))

ev <- y < EV
base_rate <- mean(ev)
fire_rate <- mean(ev[x == 1L])
lift_obs <- fire_rate / base_rate
cat(sprintf("  P(ret<-5%%) 전체 %.1f%% · 발화시 %.1f%%  →  lift = %.3f\n",
            base_rate * 100, fire_rate * 100, lift_obs))

# 블록 순열 — 통계량 = lift
block_perm <- function(x, stat_fn, B = 20000L, seed = 20260830) {
  n <- length(x); set.seed(seed)
  st <- sample.int(n, B, replace = TRUE)
  vapply(st, function(s) {
    xs <- x[c(s:n, seq_len(s - 1L))]
    if (sum(xs) == 0L || sum(xs) == n) return(NA_real_)
    stat_fn(xs)
  }, numeric(1))
}
lift_fn <- function(xx) mean(ev[xx == 1L]) / base_rate
null_lift <- block_perm(x, lift_fn)
p_lift <- mean(null_lift >= lift_obs, na.rm = TRUE)
cat(sprintf("  블록 순열 p(단측, lift>1) = %.4f   [1급 판정 문턱 0.05]\n", p_lift))

# 2급: 왼쪽 꼬리 평균 (CVaR@20%)
cvar <- function(v, q = 0.20) { k <- quantile(v, q, na.rm = TRUE); mean(v[v <= k], na.rm = TRUE) }
cv_fire <- cvar(y[x == 1L]); cv_rest <- cvar(y[x == 0L])
cvar_fn <- function(xx) cvar(y[xx == 1L]) - cvar(y[xx == 0L])
obs_cv <- cv_fire - cv_rest
null_cv <- block_perm(x, cvar_fn)
p_cv <- mean(null_cv <= obs_cv, na.rm = TRUE)
cat(sprintf("\n=== 2급: 왼쪽 꼬리 평균 (CVaR@20%%) ===\n"))
cat(sprintf("  발화시 %.2f%% · 그 외 %.2f%% → 차이 %+.2f%%p · p_block = %.4f\n",
            cv_fire * 100, cv_rest * 100, obs_cv * 100, p_cv))

# 2급-b: 발화월이 최악 구간에 얼마나 실리나
worst <- order(y)[1:round(length(y) * 0.10)]
hit <- sum(x[worst] == 1L)
exp_hit <- length(worst) * mean(x)
cat(sprintf("\n=== 2급-b: 최악 10%% 구간(%d개월) 포함 ===\n", length(worst)))
cat(sprintf("  발화 포함 %d개월 (기대 %.1f) → 배율 %.2f\n", hit, exp_hit, hit / exp_hit))

# 참고: 실제 개입 효과 — Case D(8% 현금)를 적용하면 어떻게 되나
prot <- 0.08
y_adj <- ifelse(x == 1L, y * (1 - prot), y)
cat(sprintf("\n=== 참고: Case D(8%% 현금) 적용 시 (거래비용 미반영) ===\n"))
cat(sprintf("  평균 %.3f%% → %.3f%% (%+.3f%%p) · 표준편차 %.3f%% → %.3f%%\n",
            mean(y) * 100, mean(y_adj) * 100, (mean(y_adj) - mean(y)) * 100,
            sd(y) * 100, sd(y_adj) * 100))
cat(sprintf("  최악 10%% 평균 %.2f%% → %.2f%% (%+.2f%%p)\n",
            mean(y[worst]) * 100, mean(y_adj[worst]) * 100,
            (mean(y_adj[worst]) - mean(y[worst])) * 100))

verdict <- if (!is.na(p_lift) && p_lift < 0.05) "1급 통과 — 채택 검토(도훈 판단)" else
  "1급 미달 — 미결 유지"
cat(sprintf("\n===== 판정: %s =====\n", verdict))

fwrite(data.table(stat = c("lift", "cvar20_diff", "worst10_ratio"),
                  obs = c(lift_obs, obs_cv, hit / exp_hit),
                  p_block = c(p_lift, p_cv, NA_real_),
                  n_fire = sum(x), n_episode = sum(rle(x == 1L)$values),
                  verdict = verdict),
       file.path(OUT, "tail_primary.csv"))
cat(sprintf("[out] %s/tail_primary.csv\n", OUT))
