suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- fread("stage_artifacts/pg2_hunt/shard5_results_full.csv")
R[, def20 := pmin(def20_u, def20_p, na.rm = TRUE)]
print(R[order(def20)][1:5, .(factor, port_t=round(port_t,3), cor_u=round(cor_u,4), ir_u=round(ir_u,4),
  req20_u=round(req20_u,4), def20_u=round(def20_u,4), cor_p=round(cor_p,4), ir_p=round(ir_p,4),
  req20_p=round(req20_p,4), def20_p=round(def20_p,4))])
f <- function(lbl, x) cat(sprintf("%s: min %.4f max %.4f\n", lbl, min(x,na.rm=TRUE), max(x,na.rm=TRUE)))
f("ir_u", R$ir_u); f("ir_p", R$ir_p); f("cor_u", R$cor_u); f("cor_p", R$cor_p)
f("bd_u", R$bd_u); f("bd_p", R$bd_p); f("port_t", R$port_t)
cat("ir_p>0.3:", sum(R$ir_p>0.3,na.rm=TRUE), "· port_t>=2.95:", sum(R$port_t>=2.95),
    "· port_t>0:", sum(R$port_t>0), "\n")
cat("all_u TRUE:", sum(R$all_u,na.rm=TRUE), "· all_p TRUE:", sum(R$all_p,na.rm=TRUE), "\n")
cat("bd_p>bd_u:", sum(R$bd_p>R$bd_u, na.rm=TRUE), "/", sum(is.finite(R$bd_p)), "\n")
cat("best_w 분포 uncond:", paste(names(table(R$bw_u)), table(R$bw_u), sep="x", collapse=" "), "\n")
cat("best_w 분포 parked:", paste(names(table(R$bw_p)), table(R$bw_p), sep="x", collapse=" "), "\n")
cat("port_t 중앙:", round(median(R$port_t),4), "· 사분위:", paste(round(quantile(R$port_t,c(.25,.75)),4),collapse=", "), "\n")
