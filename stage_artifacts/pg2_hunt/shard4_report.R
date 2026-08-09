suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- fread("stage_artifacts/pg2_hunt/shard4_results.csv")
R[, best_arm := ifelse(!is.finite(dIR_park) | dIR_uncond >= dIR_park, "uncond", "parked")]
R[, best_dIR := pmax(dIR_uncond, dIR_park, na.rm = TRUE)]
R[, best_w := ifelse(best_arm == "uncond", w_uncond, w_park)]
O <- R[, .(factor, n = n_months,
           cor_uncond = round(cor_uncond,4), ir_uncond = round(ir_uncond,4), dIR_uncond = round(dIR_uncond,4),
           cor_park = round(cor_park,4), ir_park = round(ir_park,4), dIR_park = round(dIR_park,4),
           best_arm, best_dIR = round(best_dIR,4), best_w)]
setorder(O, -best_dIR)
fwrite(O, "stage_artifacts/pg2_hunt/shard4_report.csv")
cat(paste(capture.output(write.csv(O, row.names = FALSE, quote = FALSE)), collapse = "\n"), "\n")

## 요구조건 지도 (w=0.20) 보간
rho <- c(-0.1,0,0.2,0.4,0.6,0.8); need <- c(0.237,0.380,0.659,0.925,1.181,1.428)
req <- function(x) approx(rho, need, xout = x, rule = 2)$y
cat("\n--- TOP5 CLOSEST (best arm) ---\n")
T5 <- copy(R)
T5[, cor_b := ifelse(best_arm=="uncond", cor_uncond, cor_park)]
T5[, ir_b  := ifelse(best_arm=="uncond", ir_uncond,  ir_park)]
T5[, need_ir := req(cor_b)][, short := need_ir - ir_b]
setorder(T5, -best_dIR)
print(T5[1:5, .(factor, best_arm, cor=round(cor_b,3), ir=round(ir_b,3),
                need=round(need_ir,3), shortfall=round(short,3), dIR=round(best_dIR,4))])
cat("\nshortfall median(all,best arm):", round(median(T5$short, na.rm=TRUE),3), "\n")
cat("cor<0.2 count uncond:", sum(R$cor_uncond<0.2,na.rm=TRUE), " park:", sum(R$cor_park<0.2,na.rm=TRUE), "\n")
cat("ir>0.5 count uncond:", sum(R$ir_uncond>0.5,na.rm=TRUE), " park:", sum(R$ir_park>0.5,na.rm=TRUE), "\n")
cat("paired cor uncond->park: t=", round(t.test(R$cor_uncond, R$cor_park, paired=TRUE)$statistic,3),
    " median delta=", round(median(R$cor_park-R$cor_uncond),4), " lower in ", sum(R$cor_park<R$cor_uncond), "/41\n")
cat("paired dIR uncond->park: t=", round(t.test(R$dIR_uncond, R$dIR_park, paired=TRUE)$statistic,3),
    " median delta=", round(median(R$dIR_park-R$dIR_uncond),4), " higher in ", sum(R$dIR_park>R$dIR_uncond), "/41\n")
