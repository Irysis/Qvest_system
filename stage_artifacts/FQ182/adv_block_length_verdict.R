## 렌즈 block_length — 판정 요약표 생성
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
BL <- fread(file.path(OUT, "adv_block_length.csv"))
CS <- fread(file.path(OUT, "adv_circular_shift.csv"))
MC <- fread(file.path(OUT, "adv_block_mechanism.csv"))
RB <- fread(file.path(OUT, "adv_robust_skew.csv"))

V <- rbindlist(list(
  BL[stat %in% c("skew","sd","tail_asym") & thr <= -20,
     .(block = "A_blk_sweep", thr, stat, blk = as.character(blk), value = round(ratio,3),
       metric = "ratio=|diff|/(2se)", note = sprintf("se=%.4f", se))],
  CS[stat %in% c("skew","sd","tail_asym","p_up3","p_dn3","mean") & thr <= -20,
     .(block = "B_circular_shift", thr, stat, blk = "-", value = round(p_two_centered,4),
       metric = "p_two_centered", note = sprintf("null_se=%.4f z=%+.2f", null_se, z_vs_null))],
  MC[, .(block = "C_outlier_mechanism", thr, stat = variant, blk = as.character(blk),
         value = round(ratio,3), metric = "ratio=|diff|/(2se)", note = sprintf("diff=%+.4f se=%.4f", diff, se))],
  RB[, .(block = "D_robust_skew", thr, stat, blk = "-", value = round(p_two,4),
         metric = "p_two_centered", note = sprintf("diff=%+.4f null_se=%.4f", diff, null_se))]
), use.names = TRUE)
fwrite(V, file.path(OUT, "adv_block_length_verdict.csv"))
cat(sprintf("verdict rows = %d\n", nrow(V)))
cat("\n== A: blk 스윕에서 skew ratio<1.0 셀 ==\n")
print(BL[stat=="skew" & blk>=250 & thr<=-20 & ratio<1.0])
cat("\n== C: 극단 1~2일 제거/윈저화 후 ratio<1.0 셀 수 (blk 전체) ==\n")
print(MC[ratio < 1.0, .N, by=.(thr, variant)][order(thr, variant)])
cat("\n== B: 순환이동 귀무 p (skew/tail_asym) ==\n")
print(CS[stat %in% c("skew","tail_asym") & thr<=-20, .(thr, stat, p=round(p_two_centered,4),
        boot60_se = NA_real_, null_se=round(null_se,4))])
cat("\n== se 배율: 순환이동 null_se / blk60 boot se (skew) ==\n")
for (t in c(-20,-30)) {
  b <- BL[stat=="skew" & thr==t & blk==60, se]; s <- CS[stat=="skew" & thr==t, null_se]
  cat(sprintf("  thr %d%%: boot60 %.4f · shift-null %.4f · 배율 %.2fx\n", t, b, s, s/b))
}
