setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp3_card_calibration.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led)
cards <- cc_load_negative_cards()
cat("음성 DIST 카드:", length(cards), "\n")
d <- cc_run(att, cards)
cat("\n=== 판정 분포 ===\n"); print(table(d$verdict))
cat("\n=== status 별 ===\n"); print(table(d$status, d$verdict))
m <- d[d$verdict %in% c("held", "not_held"), ]
cat(sprintf("\n=== 잴 수 있었던 카드 %d장 ===\n", nrow(m)))
if (nrow(m)) {
  cat(sprintf("  유지(held: 같은 경로 후속 칸이 열위) %d · 불유지 %d  → 보정도 %.0f%%\n",
              sum(m$verdict == "held"), sum(m$verdict == "not_held"), 100 * mean(m$verdict == "held")))
  cat(sprintf("  같은경로−다른경로 PORT_t 중앙차: 중앙 %+.3f · 평균 %+.3f\n", median(m$diff), mean(m$diff)))
  set.seed(20260918)
  bs <- replicate(4000, mean(sample(m$verdict == "held", nrow(m), TRUE)))
  ci <- quantile(bs, c(.025, .975))
  cat(sprintf("  보정도 95%%CI [%.0f%%, %.0f%%]  (우연 50%% 를 %s)\n", 100*ci[1], 100*ci[2],
              if (ci[1] > 0.5) "넘는다" else if (ci[2] < 0.5) "밑돈다" else "구분 못 한다"))
  cat(sprintf("  후속 같은경로 칸 F비율 중앙 %.2f · 다른경로 %.2f\n", median(m$same_f), median(m$other_f)))
  cat("\n  카드별:\n")
  o <- m[order(m$diff), c("dist_id","status","family","n_evidence","n_path","n_same","n_other","same_med","other_med","diff","verdict")]
  o$same_med <- round(o$same_med,3); o$other_med <- round(o$other_med,3); o$diff <- round(o$diff,3)
  print(o, row.names = FALSE)
}
cat("\n=== 잴 수 없었던 사유 ===\n")
u <- d[!(d$verdict %in% c("held","not_held")), ]
print(table(u$verdict, u$status))
saveRDS(d, "out/wp3_cards.rds")
