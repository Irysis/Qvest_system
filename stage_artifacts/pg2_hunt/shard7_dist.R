suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- fread("stage_artifacts/pg2_hunt/shard7_results.csv")
p <- function(x) paste(sprintf("%.4f", quantile(x, c(.25,.5,.75))), collapse=" / ")
cat("n=", nrow(R), "\n")
cat("dIR_uncond q25/med/q75:", p(R$dIR_uncond), " min", sprintf("%.4f",min(R$dIR_uncond)), " max", sprintf("%.4f",max(R$dIR_uncond)), " pos", sum(R$dIR_uncond>0), "\n")
cat("dIR_park   q25/med/q75:", p(R$dIR_park), " min", sprintf("%.4f",min(R$dIR_park)), " max", sprintf("%.4f",max(R$dIR_park)), " pos", sum(R$dIR_park>0), "\n")
cat("cor_uncond q25/med/q75:", p(R$cor_uncond), " min", sprintf("%.4f",min(R$cor_uncond)), " max", sprintf("%.4f",max(R$cor_uncond)), " lt0.2", sum(R$cor_uncond<0.2), "\n")
cat("cor_park   q25/med/q75:", p(R$cor_park), " min", sprintf("%.4f",min(R$cor_park)), " max", sprintf("%.4f",max(R$cor_park)), " lt0.2", sum(R$cor_park<0.2), "\n")
cat("ir_uncond  q25/med/q75:", p(R$ir_uncond), " min", sprintf("%.4f",min(R$ir_uncond)), " max", sprintf("%.4f",max(R$ir_uncond)), " gt0.5", sum(R$ir_uncond>0.5), "\n")
cat("ir_park    q25/med/q75:", p(R$ir_park), " min", sprintf("%.4f",min(R$ir_park)), " max", sprintf("%.4f",max(R$ir_park)), " gt0.5", sum(R$ir_park>0.5), "\n")
tt <- t.test(R$cor_park, R$cor_uncond, paired = TRUE)
cat("cor(park)-cor(uncond) mean", sprintf("%.4f", mean(R$cor_park - R$cor_uncond)),
    " paired t", sprintf("%.3f", tt$statistic), " p", format.pval(tt$p.value),
    " lower_in", sum(R$cor_park < R$cor_uncond), "/", nrow(R), "\n")
tt2 <- t.test(R$dIR_park, R$dIR_uncond, paired = TRUE)
cat("dIR(park)-dIR(uncond) [★창 다름 — 비교 아님, 참고] mean", sprintf("%.4f", mean(R$dIR_park - R$dIR_uncond)),
    " t", sprintf("%.3f", tt2$statistic), " higher_in", sum(R$dIR_park > R$dIR_uncond), "/", nrow(R), "\n")
