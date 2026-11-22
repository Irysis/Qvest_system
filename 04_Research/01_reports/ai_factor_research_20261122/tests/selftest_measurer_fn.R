## selftest_measurer_fn.R — 측정기를 답을 아는 입력으로 확인한다(승인 계획 '검증 · 측정기'). 결과는 results/selftest_measurer.json.
##   T1 점수 = 다음 달 수익 → IC 1          T2 무작위 점수 → IC 0 근처
##   T3 벤치마크 수익을 포트폴리오 자리에 → 초과수익 0 · β 1 · 추적오차 0
##   T4 Return.portfolio 로 만든 일별 수익 = 직접 계산(달 초 동일가중 · 달 안 보유) — 비중 적용 시점 대조 + 소요 시간
aif_selftest_measurer <- function(M, Rx, cfg, root) {
  res <- list()
  ok <- function(name, pass, detail) { res[[name]] <<- list(pass = isTRUE(pass), detail = detail); aif_log("%s %s — %s", if (isTRUE(pass)) "통과" else "★실패", name, detail) }
  mn <- cfg$measure$min_names; nq <- cfg$measure$n_quantiles

  i1 <- aif_ic(M$FWD[["1"]], M, 1L, mn)$ic
  ok("T1_perfect_foresight_ic", all(abs(i1[is.finite(i1)] - 1) < 1e-12) && sum(is.finite(i1)) > 200L,
     sprintf("IC 최솟값 %.6f · 달 수 %d", min(i1, na.rm = TRUE), sum(is.finite(i1))))

  set.seed(20261122L)
  S2 <- matrix(rnorm(length(M$MEM)), nrow(M$MEM)); S2[!M$MEM] <- NA_real_
  i2 <- aif_ic(S2, M, 1L, mn)$ic; i2 <- i2[is.finite(i2)]
  t2 <- mean(i2) / (sd(i2) / sqrt(length(i2)))
  ok("T2_random_score_ic", abs(mean(i2)) < 0.01 && abs(t2) < 3, sprintf("평균 IC %.5f · t %.2f · 달 수 %d", mean(i2), t2, length(i2)))

  e <- nrow(Rx); d <- M$dates[seq_len(e)]
  z <- aif_stats(M$bm[seq_len(e)], d, M$bm[seq_len(e)], M$rf[seq_len(e)], cfg)
  ok("T3_benchmark_as_portfolio", abs(z$excess_CAGR) < 1e-12 && abs(z$beta - 1) < 1e-9 && abs(z$TE) < 1e-12 && abs(z$alpha_ann) < 1e-9,
     sprintf("초과수익 %.2e · β %.6f · 추적오차 %.2e", z$excess_CAGR, z$beta, z$TE))

  top <- aif_quantiles(S2, M, nq, mn) == nq
  t0 <- Sys.time(); a <- aif_port_daily(top, M, Rx); tp <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  t0 <- Sys.time(); b <- aif_port_daily_direct(top, M); td <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  both <- is.finite(a) & is.finite(b)
  ok("T4_return_portfolio_equals_direct", sum(both) > 5000L && identical(is.finite(a), is.finite(b)) && max(abs(a[both] - b[both])) < 1e-10,
     sprintf("최대 차 %.2e · 일수 %d · Return.portfolio %.1f초 · 직접 계산 %.1f초", max(abs(a[both] - b[both])), sum(both), tp, td))

  out <- list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), market = M$source, universe = M$ep,
              n_signals = length(M$sig_dates), last_hold_end = as.character(M$last_hold_end),
              members_by_year = as.list(tapply(rowSums(M$MEM), format(M$sig_dates, "%Y"), function(v) round(mean(v)))),
              return_portfolio_seconds = tp, tests = res, all_pass = all(vapply(res, function(r) r$pass, TRUE)))
  aif_write_json(out, aif_results("selftest_measurer.json", root = root, cfg = cfg))
  aif_log("자가 시험 %s", if (out$all_pass) "전부 통과" else "★실패 있음")
  out
}
