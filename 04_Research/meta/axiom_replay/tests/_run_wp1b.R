setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
ev <- wp1_events(ent, att)

cat("=== (1) 게이트 입력이 성과를 예측하는가 (n=12) ===\n")
pred <- list(bp = ev$bp_recorded, margin_cur = ev$margin_cur, depth = ev$depth,
             parent_cells = ent$n_cells[match(ev$parent_id, ent$base_id)])
set.seed(20260918)
for (nm in names(pred)) {
  x <- pred[[nm]]; y <- ev$payoff; ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 4) { cat(sprintf("  %-13s n=%d 부족\n", nm, sum(ok))); next }
  rho <- suppressWarnings(cor(x[ok], y[ok], method = "spearman"))
  bs <- replicate(4000, { i <- sample(which(ok), sum(ok), TRUE)
    if (length(unique(x[i])) < 2 || length(unique(y[i])) < 2) NA_real_
    else suppressWarnings(cor(x[i], y[i], method = "spearman")) })
  ci <- quantile(bs, c(.025, .975), na.rm = TRUE)
  cat(sprintf("  %-13s n=%2d  rho=%+.3f  95%%CI [%+.3f, %+.3f] %s\n", nm, sum(ok), rho, ci[1], ci[2],
              if (ci[1] > 0 || ci[2] < 0) "<- 0 제외" else ""))
}
cat("\n  깊이별 payoff 평균:\n")
for (d in sort(unique(ev$depth)))
  cat(sprintf("    d=%d  n=%d  mean=%+.3f  개선 %d/%d\n", d, sum(ev$depth==d),
              mean(ev$payoff[ev$depth==d]), sum(ev$payoff[ev$depth==d] > 0), sum(ev$depth==d)))

cat("\n=== (2) 승격 전면 차단 반사실 ===\n")
promo_ids <- ent$base_id[ent$kind == "promo"]
keep <- att[!(att$base_id %in% promo_ids), ]
pb_all <- max(att$port_t[att$measured], na.rm = TRUE)
pb_nop <- max(keep$port_t[keep$measured], na.rm = TRUE)
src <- att[att$measured & att$port_t == pb_all, c("base_id","cell_code","port_t","grade","calmar")]
cat(sprintf("  프로그램 최고 %.3f  (%s / %s)\n", pb_all, sub("^RP_2026","",src$base_id[1]), src$cell_code[1]))
cat(sprintf("  승격 없었다면  %.3f   → 승격이 산 것 = %+.3f PORT_t, 값 = %d칸 (%.1f%%) · %d분\n",
            pb_nop, pb_all - pb_nop, sum(ent$n_cells[ent$kind=="promo"]),
            100*sum(ent$n_cells[ent$kind=="promo"])/nrow(att),
            round(sum(ent$minutes[ent$kind=="promo"]))))
cat(sprintf("  B등급 칸: 전체 %d · 승격산 %d (%.0f%%)\n",
            sum(att$grade %in% "B", na.rm=TRUE),
            sum(att$grade %in% "B" & att$base_id %in% promo_ids, na.rm=TRUE),
            100*sum(att$grade %in% "B" & att$base_id %in% promo_ids, na.rm=TRUE)/max(1,sum(att$grade %in% "B", na.rm=TRUE))))
cat("\n=== (3) 같은 부모에서 두 번 승격한 사례 ===\n")
dup <- table(ev$parent_id); dup <- dup[dup > 1]
if (length(dup)) for (p in names(dup)) {
  ch <- ev[ev$parent_id == p, ]
  cat(sprintf("  %s -> %d children: %s (칸 %d)\n", sub("^RP_2026","",p), nrow(ch),
              paste(sub("^.*_promo", "promo", ch$child_id), collapse=", "), sum(ch$subtree_cells)))
} else cat("  없음\n")
