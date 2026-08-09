## z6_stack_sweep.R — 스택 크기 k 를 쓸어 최적 조합 크기와 허용 상호상관 상한을 구한다
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- fread(file.path(d, "z2_pooled_ceiling.csv"))
IRi <- 1.4160; THR <- 0.05
wg <- seq(0.001, 0.999, by = 0.001)
ceilf <- function(rho, irs) max(((1 - wg) * IRi + wg * irs) /
  sqrt((1 - wg)^2 + wg^2 + 2 * wg * (1 - wg) * rho) - IRi)
req_g <- function(rho, irs) { gg <- seq(1, 12, by = 0.002); gg <- gg[gg * rho < 0.999]
  if (!length(gg)) return(NA_real_); v <- sapply(gg, function(g) ceilf(rho * g, irs * g))
  ok <- which(v >= THR); if (!length(ok)) NA_real_ else gg[ok[1]] }

## 중복 벡터 제거 (파킹 arm 키)
P[, keyp := paste(round(cor_p, 6), round(ir_p, 6))]
U <- P[!is.na(cor_p)][, .SD[1], by = keyp]
cat("파킹 arm 유효 독립 재료:", nrow(U), " (명목", sum(!is.na(P$cor_p)), ")\n\n")

## 스택 적합도 = IR - slope*rho (요구조건 지도 기울기 ~1.31). 높을수록 스택으로 확대 시 유리
slope <- (0.925 - 0.380) / 0.4
U[, stackability := ir_p - slope * cor_p]
setorder(U, -stackability)
cat("=== 스택 적합도 상위 15 (파킹 arm)\n")
print(head(U[, .(factor, cor_p, ir_p, stackability)], 15), digits = 4)
cat("\n=== k 스윕: 적합도 상위 k 개를 EW 스택했을 때\n")
res <- rbindlist(lapply(2:20, function(k) {
  S <- head(U, k); mIR <- mean(S$ir_p); mR <- mean(S$cor_p)
  g <- req_g(mR, mIR)
  cst <- if (is.na(g)) NA_real_ else (k - g^2) / (g^2 * (k - 1))
  data.table(k = k, mean_ir = mIR, mean_rho = mR, single_ceiling = ceilf(mR, mIR),
             req_g = g, g_at_c0 = sqrt(k), feasible_c0 = !is.na(g) && sqrt(k) >= g,
             c_star = cst)
}))
print(res, digits = 4)
cat("\nc_star = 이 k 에서 통과에 필요한 '구성원 간 최대 허용 상호상관'. 음수/NA = c=0(완전 직교)이어도 불가.\n")
best <- res[is.finite(c_star)][order(-c_star)]
if (nrow(best)) { cat("\n최선 k:", best$k[1], " c* =", sprintf("%.3f", best$c_star[1]), "\n")
} else cat("\n어떤 k 에서도 c=0(완전 상호직교) 가정하에서조차 통과 불가.\n")

## 무조건부 arm 도 동일 절차
P[, keyu := paste(round(cor_u, 6), round(ir_u, 6))]
V <- P[, .SD[1], by = keyu]
V[, stackability := ir_u - slope * cor_u]
setorder(V, -stackability)
cat("\n=== [무조건부 arm] 유효 독립", nrow(V), " · 적합도 상위 8\n")
print(head(V[, .(factor, cor_u, ir_u, stackability)], 8), digits = 4)
res2 <- rbindlist(lapply(2:20, function(k) {
  S <- head(V, k); mIR <- mean(S$ir_u); mR <- mean(S$cor_u); g <- req_g(mR, mIR)
  data.table(k = k, mean_ir = mIR, mean_rho = mR, req_g = g, g_at_c0 = sqrt(k),
             c_star = if (is.na(g)) NA_real_ else (k - g^2) / (g^2 * (k - 1)))
}))
print(res2, digits = 4)
