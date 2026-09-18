# run_pilot.R — WP2 실행: 검증 배터리 → 정책 비교 → β 스윕 → 보고
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/score.R")
source("R/policies/pi0_current.R")
source("R/policies/candidates.R")
source("R/policies/controls.R")

ws_all <- readRDS("out/worlds.rds")
ws <- Filter(function(w) identical(w$regime, "post_0904"), ws_all)   # 사전등록 1차 층
cat(sprintf("세계: post_0904 %d 트리 (전체 %d)\n", length(ws), length(ws_all)))

bu <- ar_beta_unit(ws)
cat(sprintf("β 단위 u = %.4f  (트리 %d개 |최고-기저| 중앙값 / 25)\n", bu$u, bu$n))

pols <- list(pi0 = rf_policy_fn,
             calmar_first = pol_calmar_first,
             first_two = pol_first_two,
             reallocate = pol_reallocate,
             stop_plateau = pol_stop_plateau,
             random = pol_random,
             oracle = make_oracle_stop,
             peek = pol_peek_violation)

d <- ar_eval_all(ws, pols, W = 5L)
saveRDS(list(d = d, u = bu$u), "out/pilot_eval.rds")

cat("\n=== 정책별 요약 (post_0904", length(ws), "트리) ===\n")
agg <- do.call(rbind, lapply(split(d, d$policy), function(s) data.frame(
  policy = s$policy[1],
  N = round(mean(s$N), 1), k = round(mean(s$k), 1), minutes = round(mean(s$minutes)),
  best = round(mean(s$best, na.rm = TRUE), 3),
  best_found = sprintf("%.0f%%", 100 * mean(s$best_found)),
  first_rank = round(mean(s$first_best_rank, na.rm = TRUE), 1),
  regret = round(mean(s$regret, na.rm = TRUE), 3),
  unreach = sum(s$unreachable), stringsAsFactors = FALSE)))
agg <- agg[order(-agg$best), ]
print(agg, row.names = FALSE)

cat("\n=== 무작위 귀무 (정책별 V 백분위, 기본 β) ===\n")
set.seed(20260918)
b1 <- 2 * bu$u; b2 <- b1
null_V <- replicate(200, {
  dd <- ar_eval_all(ws, list(random = pol_random), W = 5L, seed = sample.int(1e6, 1))
  mean(ar_V(dd, b1, b2), na.rm = TRUE)
})
for (p in names(pols)) {
  s <- d[d$policy == p, ]
  v <- mean(ar_V(s, b1, b2), na.rm = TRUE)
  cat(sprintf("  %-13s V=%+.3f  귀무 백분위 %.0f%%\n", p, v, 100 * mean(null_V < v)))
}

cat("\n=== π₀ 대비 β 스윕 (mean_gain / win_frac) ===\n")
sw <- ar_sweep_V(d, bu$u)
for (p in unique(sw$policy)) {
  s <- sw[sw$policy == p & sw$beta2_mult == 1, ]
  cat(sprintf("  %-13s ", p))
  for (i in seq_len(nrow(s)))
    cat(sprintf("β1=%gu:%+.3f(%.0f%%) ", s$beta1_mult[i], s$mean_gain[i], 100 * s$win_frac[i]))
  cat("\n")
}
saveRDS(sw, "out/pilot_sweep.rds")

cat("\n=== 위반 주입 결과 ===\n")
pk <- d[d$policy == "peek", ]
cat(sprintf("  peek 정책의 평균 최고 %.3f vs π₀ %.3f — 엿보기로 이득을 봤는가: %s\n",
            mean(pk$best, na.rm = TRUE), mean(d$best[d$policy == "pi0"], na.rm = TRUE),
            if (mean(pk$best, na.rm = TRUE) > mean(d$best[d$policy == "pi0"], na.rm = TRUE) + 1e-9)
              "★뚫렸다" else "아니다(차단 확인)"))
