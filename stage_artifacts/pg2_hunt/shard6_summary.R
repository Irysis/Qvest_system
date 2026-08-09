suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- fread("stage_artifacts/pg2_hunt/shard6_results.csv")

## 요구조건 지도 (w=0.20, 메인 세션 해석해) — 선형 보간
map_rho <- c(-0.1, 0.0, 0.2, 0.4, 0.6, 0.8)
map_ir  <- c(0.237, 0.380, 0.659, 0.925, 1.181, 1.428)
req_ir <- function(rho) approx(map_rho, map_ir, xout = pmin(pmax(rho, -0.1), 0.8), rule = 2)$y

R[, best_arm := ifelse(is.finite(best_dIR_park) & (!is.finite(best_dIR_uncond) | best_dIR_park > best_dIR_uncond), "parked", "uncond")]
R[, best_dIR := pmax(best_dIR_uncond, best_dIR_park, na.rm = TRUE)]
R[, best_w := ifelse(best_arm == "parked", best_w_park, best_w_uncond)]
R[, cor_best := ifelse(best_arm == "parked", cor_park, cor_uncond)]
R[, ir_best  := ifelse(best_arm == "parked", ir_park, ir_uncond)]
R[, req := req_ir(cor_best)]
R[, shortfall := req - ir_best]

setorder(R, -best_dIR)
cat("=== TOP 8 by best_dIR ===\n")
print(R[1:8, .(factor, best_arm, best_w, cor_best, ir_best, req = round(req,3),
               shortfall = round(shortfall,3), best_dIR = round(best_dIR,4))])

cat("\n=== distribution ===\n")
f <- function(x) sprintf("n=%d med %.4f q25 %.4f q75 %.4f min %.4f max %.4f", sum(is.finite(x)),
   median(x,na.rm=TRUE), quantile(x,.25,na.rm=TRUE), quantile(x,.75,na.rm=TRUE), min(x,na.rm=TRUE), max(x,na.rm=TRUE))
cat("uncond cor      :", f(R$cor_uncond), "\n")
cat("uncond sleeveIR :", f(R$ir_uncond), "\n")
cat("uncond dIR@.20  :", f(R$dIR_uncond), "\n")
cat("uncond bestdIR  :", f(R$best_dIR_uncond), "\n")
cat("park cor        :", f(R$cor_park), "\n")
cat("park sleeveIR   :", f(R$ir_park), "\n")
cat("park dIR@.20    :", f(R$dIR_park), "\n")
cat("park bestdIR    :", f(R$best_dIR_park), "\n")
cat("cor<0.2 uncond  :", sum(R$cor_uncond<0.2,na.rm=TRUE), " park:", sum(R$cor_park<0.2,na.rm=TRUE), "\n")
cat("IR>0.5 uncond   :", sum(R$ir_uncond>0.5,na.rm=TRUE), " park:", sum(R$ir_park>0.5,na.rm=TRUE), "\n")
cat("shortfall med   :", median(R$shortfall,na.rm=TRUE), "\n")
cat("best_w table    :\n"); print(table(R$best_w, R$best_arm))
## paired: parking lever (동일 팩터 내, 창이 다르므로 상관만 비교 가능? — cor 는 창 의존)
cat("\npaired cor uncond->park t:", sprintf("%.3f", t.test(R$cor_park, R$cor_uncond, paired=TRUE)$statistic),
    " n_down=", sum(R$cor_park < R$cor_uncond, na.rm=TRUE), "/", sum(is.finite(R$cor_park)), "\n")

## CSV 출력
OUT <- R[, .(factor, n = n_uncond, cor_uncond = round(cor_uncond,4), ir_uncond = round(ir_uncond,4),
   dIR_uncond = round(best_dIR_uncond,4), cor_park = round(cor_park,4), ir_park = round(ir_park,4),
   dIR_park = round(best_dIR_park,4), best_arm, best_dIR = round(best_dIR,4), best_w)]
setorder(OUT, factor)
fwrite(OUT, "stage_artifacts/pg2_hunt/shard6_final.csv")
cat("\n=== FINAL CSV ===\n")
writeLines(readLines("stage_artifacts/pg2_hunt/shard6_final.csv"))
