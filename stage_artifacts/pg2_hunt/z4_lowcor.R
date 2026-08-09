suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- fread(file.path(d, "z2_pooled_ceiling.csv"))
cat("=== 저상관 재료 (양 arm 중 최소 상관 < 0.25)\n")
P[, cmin := pmin(cor_u, cor_p, na.rm = TRUE)]
print(P[cmin < 0.25][order(cmin), .(factor, shard, n_u, cor_u, ir_u, n_p, cor_p, ir_p, best_d, short_best)], nrows = 40)
cat("\n=== 파킹 미측정 3건\n")
print(P[is.na(cor_p), .(factor, shard, st_p, n_u, cor_u, ir_u, bd_u, n_p)])
cat("\n=== 고IR 재료 (양 arm 중 최대 IR >= 0.35)\n")
P[, imax := pmax(ir_u, ir_p, na.rm = TRUE)]
print(P[imax >= 0.35][order(-imax), .(factor, cor_u, ir_u, cor_p, ir_p, best_d, short_best)], nrows = 40)
cat("\n=== 무조건부 arm 에서 IR>0 이면서 상관<0.35 인 재료 수:",
    nrow(P[ir_u > 0 & cor_u < 0.35]), "\n")
cat("=== 파킹 arm 에서 IR>0.2 이면서 상관<0.30 인 재료 수:",
    nrow(P[ir_p > 0.2 & cor_p < 0.30]), "\n")
print(P[ir_p > 0.2 & cor_p < 0.30][order(-ir_p), .(factor, cor_p, ir_p, best_d)], nrows = 30)
