suppressPackageStartupMessages(library(data.table))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
r <- readRDS("stage_artifacts/WT_D20260808_001/fq122_part2.rds")
cat("=== PARITY GATE A max|dev| =", format(r$gateA_max_dev, scientific = TRUE), "===\n\n")
print(r$PROD[, .(arm, n, base_port_t = round(base_port_t,3), filt_port_t = round(filt_port_t,3),
                 base_ir = round(base_ir,4), filt_ir = round(filt_ir,4),
                 delta_ir = round(delta_ir,4), d_ann = round(d_ann_pct,2),
                 t = round(paired_t,2), sign_agree,
                 to_b = round(base_to_ann), to_f = round(filt_to_ann))])
cat("\n=== 부호 요약 (q=0.20, 팩터 x base x 가중규칙) ===\n")
R <- r$RECON[q == 0.20, .(cell = weighting, factor, d_ann = round(d_ann_pct,2), t = round(paired_t,2))]
P <- r$PROD[!grepl("lag1", arm), .(cell = sub("_D03_EWMA|_Q01_EB", "", arm),
      factor = ifelse(grepl("D03", arm), "D03_EWMA", "Q01_EB"),
      d_ann = round(d_ann_pct,2), t = round(paired_t,2))]
S <- rbind(R, P)[order(factor, cell)]
S[, sign := ifelse(d_ann > 0, "+", "-")]
print(S)
cat("\n=== 플라시보 대비 초과 (real - placebo_mean) ===\n")
print(r$PLC[, .(factor, real_d_ann_pct = round(real_d_ann_pct,2),
                placebo_mean = round(placebo_mean,2),
                excess_vs_placebo = round(real_d_ann_pct - placebo_mean, 2),
                placebo_range = sprintf("[%+.2f, %+.2f]", placebo_min, placebo_max),
                outside_range)])
cat("\n=== P1 (primary) ===\n"); print(r$P1)
cat("\n=== canonical W1 arm PORT_t (dual-basis) ===\n")
p1 <- readRDS("stage_artifacts/WT_D20260808_001/fq122_part1.rds")
for (nm in names(p1$w1)) {
  x <- p1$w1[[nm]]; ew <- x$diag_ew_universe; ct <- x$diag_cap_tier
  cat(sprintf("%-16s capw_t=%+.3f EWuni_t=%+.3f EWuni_post17=%+.3f TO=%.0f%%\n",
      nm, x$portfolio_alpha_t_nw_lag3,
      if (is.null(ew$portfolio_alpha_t_nw_lag3)) NA_real_ else ew$portfolio_alpha_t_nw_lag3,
      if (is.null(ew$post2017_t_nw_lag3)) NA_real_ else ew$post2017_t_nw_lag3,
      100 * x$turnover_annual))
}
cat("\n=== cap_tier (base vs Q01_q20) ===\n")
str(p1$w1$base$diag_cap_tier, max.level = 2)
