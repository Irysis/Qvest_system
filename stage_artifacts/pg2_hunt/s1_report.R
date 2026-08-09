suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- readRDS("stage_artifacts/pg2_hunt/s1_results.rds")
R[, best_arm := ifelse(is.finite(dir_p) & dir_p > dir_u, "parked", "uncond")]
R[, best_dIR := pmax(dir_u, dir_p, na.rm=TRUE)]
R[, best_w  := ifelse(best_arm=="parked", w_p, w_u)]
CSV <- R[, .(factor, n_u, cor_uncond=round(cor_u,4), ir_uncond=round(ir_u,4), dIR_uncond=round(dir_u,4),
             n_p, cor_park=round(cor_p,4), ir_park=round(ir_p,4), dIR_park=round(dir_p,4),
             best_arm, best_dIR=round(best_dIR,4), best_w, port_t=round(port_t,3))]
setorder(CSV, -best_dIR)
fwrite(CSV, "stage_artifacts/pg2_hunt/s1_final.csv")
cat(paste(capture.output(write.csv(CSV, row.names=FALSE, quote=FALSE)), collapse="\n"), "\n")
cat("\n### window check\n"); print(unique(R$win_u)); print(unique(R$win_p))
cat("\n### sweep monotone check (best_w table)\n"); print(table(R$w_u)); print(table(R$w_p))
cat("\n### shortfall top5\n")
R[, `:=`(short_u=req_u-ir_u, short_p=req_p-ir_p)]
R[, sb := pmin(short_u, short_p, na.rm=TRUE)]
print(R[order(sb)][1:5, .(factor, cor_u, ir_u, req_u, short_u, cor_p, ir_p, req_p, short_p)])
cat("\n### quantiles\n")
for (v in c("cor_u","ir_u","dir_u","cor_p","ir_p","dir_p","port_t")) {
  x <- R[[v]]; cat(sprintf("%-7s med %.4f q25 %.4f q75 %.4f min %.4f max %.4f\n", v,
    median(x,na.rm=T), quantile(x,.25,na.rm=T), quantile(x,.75,na.rm=T), min(x,na.rm=T), max(x,na.rm=T)))
}
cat("\ncor_u<0.2:", sum(R$cor_u<0.2), " cor_p<0.2:", sum(R$cor_p<0.2),
    " ir_u>0.5:", sum(R$ir_u>0.5), " ir_p>0.5:", sum(R$ir_p>0.5), "\n")
cat("cols:", paste(names(R), collapse=","), "\n")
cat("paired ir_p vs ir_u t:", t.test(R$ir_p, R$ir_u, paired=TRUE)$statistic, "\n")
cat("paired dir_p vs dir_u t:", t.test(R$dir_p, R$dir_u, paired=TRUE)$statistic, "\n")
