suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
D <- fread("stage_artifacts/pg2_hunt/s2_results.csv")
cat("rows", nrow(D), "\n")
cat("status uncond:", paste(unique(D$u_status)), " parked:", paste(unique(D$p_status)), "\n")
cat("uncond window:", unique(D$u_win_start), "-", unique(D$u_win_end), " n:", paste(unique(D$u_n)), "\n")
cat("parked window:", unique(D$p_win_start), "-", unique(D$p_win_end), " n:", paste(unique(D$p_n)), "\n")
q <- function(x) sprintf("med %.4f [q1 %.4f, q3 %.4f] min %.4f max %.4f", median(x), quantile(x,.25), quantile(x,.75), min(x), max(x))
cat("\n-- UNCOND --\n")
cat("cor      :", q(D$u_cor), "\n")
cat("sleeveIR :", q(D$u_sleeve_ir), "\n")
cat("dIR w20  :", q(D$u_dir_w20), "\n")
cat("dIR best :", q(D$u_best_d), "\n")
cat("pos best :", sum(D$u_best_d > 0), "/", nrow(D), "  >=0.05:", sum(D$u_best_d >= 0.05), "\n")
cat("best_w table:\n"); print(table(D$u_best_w))
cat("cor<0.2:", sum(D$u_cor < 0.2), " IR>0.5:", sum(D$u_sleeve_ir > 0.5), "\n")
cat("\n-- PARKED --\n")
cat("cor      :", q(D$p_cor), "\n")
cat("sleeveIR :", q(D$p_sleeve_ir), "\n")
cat("dIR w20  :", q(D$p_dir_w20), "\n")
cat("dIR best :", q(D$p_best_d), "\n")
cat("pos best :", sum(D$p_best_d > 0), "/", nrow(D), "  >=0.05:", sum(D$p_best_d >= 0.05), "\n")
cat("best_w table:\n"); print(table(D$p_best_w))
cat("cor<0.2:", sum(D$p_cor < 0.2), " IR>0.5:", sum(D$p_sleeve_ir > 0.5), "\n")
cat("\n-- parked vs uncond (윈도 다름 — 진단용) --\n")
cat("cor paired t:", sprintf("%.3f", t.test(D$p_cor, D$u_cor, paired=TRUE)$statistic),
    " p", format.pval(t.test(D$p_cor, D$u_cor, paired=TRUE)$p.value), " lower in", sum(D$p_cor < D$u_cor), "/", nrow(D), "\n")
cat("dIRbest paired t:", sprintf("%.3f", t.test(D$p_best_d, D$u_best_d, paired=TRUE)$statistic),
    " better in", sum(D$p_best_d > D$u_best_d), "/", nrow(D), "\n")
## 요구조건 지도 (해석해) — w 에서 ΔIR>=0.05 에 필요한 슬리브 IR
need_ir <- function(rho, w, ir_i) {
  ## book active = (1-w)a_i + w a_s ; IR_book = ((1-w)mu_i + w mu_s)/sd
  ## sd^2 = (1-w)^2 s_i^2 + w^2 s_s^2 + 2w(1-w)rho s_i s_s ; 단위 s_i=1, s_s=1 정규화
  ## IR_s = mu_s (s_s=1 기준) => 수치해
  f <- function(irs) {
    sd <- sqrt((1-w)^2 + w^2 + 2*w*(1-w)*rho)
    ((1-w)*ir_i + w*irs)/sd - ir_i - 0.05
  }
  uniroot(f, c(-50, 200))$root
}
D[, u_need := mapply(function(rho, w) need_ir(rho, w, 1.4160), u_cor, u_best_w)]
D[, p_need := mapply(function(rho, w) need_ir(rho, w, 1.4160), p_cor, p_best_w)]
D[, u_short := u_need - u_sleeve_ir][, p_short := p_need - p_sleeve_ir]
cat("\nneed_ir sanity (rho=0.4,w=0.2):", sprintf("%.3f", need_ir(0.4, 0.20, 1.4160)), "(기대 0.925)\n")
cat("uncond shortfall: ", q(D$u_short), "\n")
cat("parked shortfall: ", q(D$p_short), "\n")
setorder(D, -u_best_d)
cat("\n== top5 closest UNCOND ==\n")
print(D[1:5, .(factor, u_cor=round(u_cor,3), u_sleeve_ir=round(u_sleeve_ir,3), u_need=round(u_need,3), u_short=round(u_short,3), u_best_d=round(u_best_d,4), u_best_w)])
setorder(D, -p_best_d)
cat("\n== top5 closest PARKED ==\n")
print(D[1:5, .(factor, p_cor=round(p_cor,3), p_sleeve_ir=round(p_sleeve_ir,3), p_need=round(p_need,3), p_short=round(p_short,3), p_best_d=round(p_best_d,4), p_best_w)])
setorder(D, factor)
E <- D[, .(factor, n = u_n, cor_uncond = round(u_cor,4), ir_uncond = round(u_sleeve_ir,4), dIR_uncond = round(u_best_d,4),
           n_park = p_n, cor_park = round(p_cor,4), ir_park = round(p_sleeve_ir,4), dIR_park = round(p_best_d,4),
           best_arm = ifelse(u_best_d >= p_best_d, "uncond", "parked"),
           best_dIR = round(pmax(u_best_d, p_best_d),4),
           best_w = ifelse(u_best_d >= p_best_d, u_best_w, p_best_w))]
fwrite(E, "stage_artifacts/pg2_hunt/s2_results_report.csv")
cat("\n== REPORT CSV ==\n")
cat(paste(readLines("stage_artifacts/pg2_hunt/s2_results_report.csv"), collapse="\n"), "\n")
