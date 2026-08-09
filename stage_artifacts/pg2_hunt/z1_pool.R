## z1_pool.R — 8 샤드 결과를 단일 표로 통합 + 전수 분포/기전 분해
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")

rd <- function(f) fread(file.path(d, f), na.strings = c("", "NA"))

out <- list()

## --- shard0: w20 = dIR_uncond/dIR_park; best per arm from sweeps
s0 <- rd("shard0_results_enriched.csv")
sw0 <- rd("shard0_sweeps.csv")
b0 <- sw0[status == "MEASURED", .(bd = max(delta_ir, na.rm = TRUE)), by = .(factor, arm)]
b0u <- b0[arm == "uncond"]; b0p <- b0[arm == "parked"]
out[[1]] <- data.table(shard = 0L, factor = s0$factor,
  n_u = s0$n, cor_u = s0$cor_uncond, ir_u = s0$ir_uncond, d20_u = s0$dIR_uncond,
  n_p = s0$n_parked, cor_p = s0$cor_park, ir_p = s0$ir_park, d20_p = s0$dIR_park,
  st_u = s0$status_uncond, st_p = s0$status_park)
out[[1]][b0u, bd_u := i.bd, on = "factor"]
out[[1]][b0p, bd_p := i.bd, on = "factor"]

## --- shard1 (s1_results): dir_* = best; sweep string 4번째 = w0.20
s1 <- rd("s1_results.csv")
pick4 <- function(x) sapply(strsplit(x, "\\|"), function(v) if (length(v) >= 4) as.numeric(v[4]) else NA_real_)
out[[2]] <- data.table(shard = 1L, factor = s1$factor,
  n_u = s1$n_u, cor_u = s1$cor_u, ir_u = s1$ir_u, d20_u = pick4(s1$sweep_u),
  n_p = s1$n_p, cor_p = s1$cor_p, ir_p = s1$ir_p, d20_p = pick4(s1$sweep_p),
  st_u = "MEASURED", st_p = "MEASURED", bd_u = s1$dir_u, bd_p = s1$dir_p)

## --- shard2
s2 <- rd("s2_results.csv")
out[[3]] <- data.table(shard = 2L, factor = s2$factor,
  n_u = s2$u_n, cor_u = s2$u_cor, ir_u = s2$u_sleeve_ir, d20_u = s2$u_dir_w20,
  n_p = s2$p_n, cor_p = s2$p_cor, ir_p = s2$p_sleeve_ir, d20_p = s2$p_dir_w20,
  st_u = s2$u_status, st_p = s2$p_status, bd_u = s2$u_best_d, bd_p = s2$p_best_d)

## --- shard3 (dIR_* = best-over-w)
s3 <- rd("shard3_results.csv")
out[[4]] <- data.table(shard = 3L, factor = s3$factor,
  n_u = s3$n_uncond, cor_u = s3$cor_uncond, ir_u = s3$ir_uncond, d20_u = NA_real_,
  n_p = s3$n_park, cor_p = s3$cor_park, ir_p = s3$ir_park, d20_p = NA_real_,
  st_u = "MEASURED", st_p = "MEASURED", bd_u = s3$dIR_uncond, bd_p = s3$dIR_park)

## --- shard4 (best-over-w)
s4 <- rd("shard4_results.csv")
out[[5]] <- data.table(shard = 4L, factor = s4$factor,
  n_u = s4$n_uncond, cor_u = s4$cor_uncond, ir_u = s4$ir_uncond, d20_u = NA_real_,
  n_p = s4$n_park, cor_p = s4$cor_park, ir_p = s4$ir_park, d20_p = NA_real_,
  st_u = "MEASURED", st_p = "MEASURED", bd_u = s4$dIR_uncond, bd_p = s4$dIR_park)

## --- shard5
s5 <- rd("shard5_results_full.csv")
out[[6]] <- data.table(shard = 5L, factor = s5$factor,
  n_u = s5$n_u, cor_u = s5$cor_u, ir_u = s5$ir_u, d20_u = s5$d20_u,
  n_p = s5$n_p, cor_p = s5$cor_p, ir_p = s5$ir_p, d20_p = s5$d20_p,
  st_u = "MEASURED", st_p = ifelse(is.na(s5$cor_p), "NO_MEASURE", "MEASURED"),
  bd_u = s5$bd_u, bd_p = s5$bd_p)

## --- shard6
s6 <- rd("shard6_results.csv")
out[[7]] <- data.table(shard = 6L, factor = s6$factor,
  n_u = s6$n_uncond, cor_u = s6$cor_uncond, ir_u = s6$ir_uncond, d20_u = s6$dIR_uncond,
  n_p = s6$n_park, cor_p = s6$cor_park, ir_p = s6$ir_park, d20_p = s6$dIR_park,
  st_u = s6$status_uncond, st_p = s6$status_park,
  bd_u = s6$best_dIR_uncond, bd_p = s6$best_dIR_park)

## --- shard7 (best-over-w)
s7 <- rd("shard7_results.csv")
out[[8]] <- data.table(shard = 7L, factor = s7$factor,
  n_u = s7$n, cor_u = s7$cor_uncond, ir_u = s7$ir_uncond, d20_u = NA_real_,
  n_p = s7$n_park, cor_p = s7$cor_park, ir_p = s7$ir_park, d20_p = NA_real_,
  st_u = s7$status_uncond, st_p = s7$status_park,
  bd_u = s7$dIR_uncond, bd_p = s7$dIR_park)

P <- rbindlist(out, use.names = TRUE, fill = TRUE)

cat("=== [입력 실측] 통합 표\n")
cat("행수:", nrow(P), " 고유 팩터:", uniqueN(P$factor), "\n")
cat("샤드별 건수:\n"); print(P[, .N, by = shard][order(shard)])
cat("중복 팩터명:", paste(P[, .N, by = factor][N > 1]$factor, collapse = ", "), "\n")
cat("status uncond:\n"); print(P[, .N, by = st_u])
cat("status park:\n"); print(P[, .N, by = st_p])
cat("결측: cor_u", sum(is.na(P$cor_u)), " ir_u", sum(is.na(P$ir_u)), " bd_u", sum(is.na(P$bd_u)),
    " | cor_p", sum(is.na(P$cor_p)), " ir_p", sum(is.na(P$ir_p)), " bd_p", sum(is.na(P$bd_p)),
    " | d20_u", sum(is.na(P$d20_u)), " d20_p", sum(is.na(P$d20_p)), "\n")
cat("n_u 범위:", paste(range(P$n_u, na.rm = TRUE), collapse = "~"),
    " n_p 범위:", paste(range(P$n_p, na.rm = TRUE), collapse = "~"), "\n\n")

## --- 요구조건 지도 해석해 (k = sd_s/sd_i = 1 정규화, IR_i = 1.4160, 문턱 0.05)
IRi <- 1.4160; THR <- 0.05
need_ir <- function(rho, w = 0.20, iri = IRi, thr = THR) {
  den <- sqrt((1 - w)^2 + w^2 + 2 * w * (1 - w) * rho)
  ((iri + thr) * den - (1 - w) * iri) / w
}
cat("=== [검산] need_ir(rho=0.4, w=0.20) =", round(need_ir(0.4), 4), " (지도값 0.925)\n")
cat("      need_ir(0.0)=", round(need_ir(0.0), 3), " need_ir(0.2)=", round(need_ir(0.2), 3),
    " need_ir(0.6)=", round(need_ir(0.6), 3), " need_ir(0.8)=", round(need_ir(0.8), 3), "\n\n")

P[, req_u := need_ir(cor_u)]; P[, req_p := need_ir(cor_p)]
P[, short_u := req_u - ir_u]; P[, short_p := req_p - ir_p]

q5 <- function(x) { x <- x[is.finite(x)]; sprintf("n=%d min %.4f q25 %.4f med %.4f q75 %.4f max %.4f",
  length(x), min(x), quantile(x, .25), median(x), quantile(x, .75), max(x)) }

cat("=== [분포] arm1 무조건부 (전 기간)\n")
cat(" cor    :", q5(P$cor_u), "\n")
cat(" sleeve IR:", q5(P$ir_u), "\n")
cat(" dIR@w0.20:", q5(P$d20_u), "\n")
cat(" dIR best-over-w:", q5(P$bd_u), "\n")
cat(" cor<0.2:", sum(P$cor_u < 0.2, na.rm = TRUE), " cor<0:", sum(P$cor_u < 0, na.rm = TRUE),
    " IR>0.5:", sum(P$ir_u > 0.5, na.rm = TRUE), " IR>0:", sum(P$ir_u > 0, na.rm = TRUE),
    " bd>0:", sum(P$bd_u > 0, na.rm = TRUE), " bd>=0.05:", sum(P$bd_u >= 0.05, na.rm = TRUE), "\n\n")

cat("=== [분포] arm2 파킹 (FQ-191, 73개월)\n")
cat(" cor    :", q5(P$cor_p), "\n")
cat(" sleeve IR:", q5(P$ir_p), "\n")
cat(" dIR@w0.20:", q5(P$d20_p), "\n")
cat(" dIR best-over-w:", q5(P$bd_p), "\n")
cat(" cor<0.2:", sum(P$cor_p < 0.2, na.rm = TRUE), " cor<0:", sum(P$cor_p < 0, na.rm = TRUE),
    " IR>0.5:", sum(P$ir_p > 0.5, na.rm = TRUE), " IR>0:", sum(P$ir_p > 0, na.rm = TRUE),
    " bd>0:", sum(P$bd_p > 0, na.rm = TRUE), " bd>=0.05:", sum(P$bd_p >= 0.05, na.rm = TRUE), "\n\n")

cat("=== [부족분] need_ir(w=0.20) - 실측 IR\n")
cat(" uncond:", q5(P$short_u), "\n")
cat(" parked:", q5(P$short_p), "\n")
P[, best_arm := ifelse(!is.na(bd_p) & !is.na(bd_u) & bd_p > bd_u, "parked",
                ifelse(is.na(bd_u), "parked", "uncond"))]
P[, best_d := pmax(bd_u, bd_p, na.rm = TRUE)]
P[, short_best := pmin(short_u, short_p, na.rm = TRUE)]
cat(" 팩터별 최소 부족분(양 arm 중):", q5(P$short_best), "\n\n")

cat("=== [생존] best-over-w, 양 arm 중 최대\n")
cat(" best_d > 0 :", sum(P$best_d > 0, na.rm = TRUE), " / ", nrow(P), "\n")
cat(" best_d >=0.05:", sum(P$best_d >= 0.05, na.rm = TRUE), "\n")
print(P[best_d > 0][order(-best_d), .(factor, shard, best_arm, cor_u, ir_u, bd_u, cor_p, ir_p, bd_p, best_d)])
cat("\n")

## --- 파킹 레버 전수 paired
pp <- P[!is.na(cor_p) & !is.na(cor_u)]
tc <- t.test(pp$cor_p, pp$cor_u, paired = TRUE)
td <- t.test(pp$bd_p, pp$bd_u, paired = TRUE)
ti <- t.test(pp$ir_p, pp$ir_u, paired = TRUE)
cat("=== [파킹 레버 전수 paired] n =", nrow(pp), "\n")
cat(" cor  : mean diff", sprintf("%.4f", mean(pp$cor_p - pp$cor_u)), " t", sprintf("%.3f", tc$statistic),
    " p", format.pval(tc$p.value, digits = 3), " 인하 건수", sum(pp$cor_p < pp$cor_u), "/", nrow(pp), "\n")
cat(" IR   : mean diff", sprintf("%.4f", mean(pp$ir_p - pp$ir_u)), " t", sprintf("%.3f", ti$statistic),
    " p", format.pval(ti$p.value, digits = 3), " 개선 건수", sum(pp$ir_p > pp$ir_u), "/", nrow(pp), "\n")
cat(" bestd: mean diff", sprintf("%.4f", mean(pp$bd_p - pp$bd_u)), " t", sprintf("%.3f", td$statistic),
    " p", format.pval(td$p.value, digits = 3), " 개선 건수", sum(pp$bd_p > pp$bd_u), "/", nrow(pp), "\n")
cat(" 부족분: mean diff", sprintf("%.4f", mean(pp$short_p - pp$short_u)),
    " 개선(감소) 건수", sum(pp$short_p < pp$short_u), "/", nrow(pp), "\n\n")

## --- 근접 10건
setorder(P, short_best)
top <- head(P, 12)
cat("=== [근접 12건] 최소 부족분 순 (best arm)\n")
print(top[, .(factor, shard, arm = ifelse(short_p <= short_u | is.na(short_u), "parked", "uncond"),
  cor = ifelse(short_p <= short_u | is.na(short_u), cor_p, cor_u),
  ir = ifelse(short_p <= short_u | is.na(short_u), ir_p, ir_u),
  req = ifelse(short_p <= short_u | is.na(short_u), req_p, req_u),
  short = short_best, best_d, best_arm)], nrows = 20)
cat("\n")

## --- 기전 유형 분해 (best arm 기준)
P[, `:=`(cor_b = ifelse(short_p <= short_u | is.na(short_u), cor_p, cor_u),
         ir_b  = ifelse(short_p <= short_u | is.na(short_u), ir_p, ir_u))]
P[, mech := fifelse(is.na(cor_p) | is.na(cor_u), "COVERAGE",
             fifelse(ir_b >= 0.5 & cor_b >= 0.3, "COR_ONLY",
              fifelse(ir_b < 0.5 & cor_b < 0.3, "IR_ONLY",
               fifelse(ir_b < 0.5 & cor_b >= 0.3, "BOTH", "OTHER"))))]
cat("=== [기전 유형] best arm 기준 (COR_ONLY = IR 충분·상관 과다 / IR_ONLY = 직교 확보·신호 부족 / BOTH = 동시부족)\n")
print(P[, .N, by = mech][order(-N)])
cat(" IR>=0.5 인 팩터 (양 arm 중 최대):", sum(pmax(P$ir_u, P$ir_p, na.rm = TRUE) >= 0.5, na.rm = TRUE), "\n")
cat(" cor<0.2 인 팩터 (양 arm 중 최소):", sum(pmin(P$cor_u, P$cor_p, na.rm = TRUE) < 0.2, na.rm = TRUE), "\n")
cat(" cor<0.3 인 팩터 (양 arm 중 최소):", sum(pmin(P$cor_u, P$cor_p, na.rm = TRUE) < 0.3, na.rm = TRUE), "\n")
cat(" 둘 다 충족(cor<0.3 & IR>=0.5, 동일 arm):",
    sum((P$cor_u < 0.3 & P$ir_u >= 0.5) | (P$cor_p < 0.3 & P$ir_p >= 0.5), na.rm = TRUE), "\n\n")

## --- 중복 벡터 탐지
P[, key := paste(round(cor_u, 6), round(ir_u, 6))]
dup <- P[!is.na(cor_u), .N, by = key][N > 1]
cat("=== [중복 벡터] (cor_u, ir_u) 6자리 동일 그룹:", nrow(dup), "그룹\n")
if (nrow(dup)) for (k in dup$key) cat("  ", paste(P[key == k]$factor, collapse = " == "), "\n")
cat(" 유효 독립 재료 =", uniqueN(P[!is.na(cor_u)]$key) + sum(is.na(P$cor_u)), "\n\n")

fwrite(P, file.path(d, "z1_pooled.csv"))
saveRDS(P, file.path(d, "z1_pooled.rds"))
cat("saved: z1_pooled.csv\n")
