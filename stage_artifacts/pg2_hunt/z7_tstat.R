## z7_tstat.R — 슬리브 IR 의 함의 t (IR*sqrt(n/12)) 분포 + 선별 잡음 대조
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- fread(file.path(d, "z2_pooled_ceiling.csv"))
P[, t_u := ir_u * sqrt(n_u / 12)]
P[, t_p := ir_p * sqrt(n_p / 12)]
q <- function(x) { x <- x[is.finite(x)]; sprintf("n=%d min %.3f med %.3f q75 %.3f max %.3f | |t|>2 %d건",
  length(x), min(x), median(x), quantile(x, .75), max(x), sum(abs(x) > 2)) }
cat("=== 슬리브 IR 의 함의 t = IR*sqrt(n/12)  (독립월 가정 — 파킹 arm 은 에피소드 14 라 과대추정)\n")
cat(" uncond:", q(P$t_u), "\n")
cat(" parked:", q(P$t_p), "\n\n")
cat("=== 상위 8 (파킹 t)\n")
print(head(P[order(-t_p), .(factor, n_p, cor_p, ir_p, t_p, best_d)], 8), digits = 4)
cat("\n=== 상위 5 (무조건부 t)\n")
print(head(P[order(-t_u), .(factor, n_u, cor_u, ir_u, t_u, bd_u)], 5), digits = 4)
cat("\n=== 통과에 필요한 IR 의 함의 t (파킹 73m 기준)\n")
cat(" req_ir 중앙 0.9142+ir_p 중앙 => 필요 IR 이 t 로 환산하면:", "\n")
for (r in c(0.20, 0.25, 0.30, 0.35)) {
  need <- ((1.4160 + 0.05) * sqrt(0.64 + 0.04 + 2 * 0.2 * 0.8 * r) - 0.8 * 1.4160) / 0.2
  cat(sprintf("  rho %.2f -> 필요 IR %.3f -> 73개월 기준 함의 t %.2f (268개월 기준 %.2f)\n",
      r, need, need * sqrt(73 / 12), need * sqrt(268 / 12)))
}
cat("\n에피소드 보정: 파킹 ON 26개월 / 에피소드 14 -> 유효표본이 개월수가 아니라 에피소드에 묶이면\n")
cat("  t 는 sqrt(14/73)=", sprintf("%.3f", sqrt(14/73)), " 배로 축소 (V18_AM t 1.420 -> ",
    sprintf("%.3f", 1.4197 * sqrt(14/73)), ")\n")
