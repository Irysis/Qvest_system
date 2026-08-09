## z3_probe_design.R — 근접 후보에 대해 (a) 통과에 필요한 상관 상한 (b) 스택 필요 배율 g / 상호상관 상한 / 필요 k
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- as.data.table(fread(file.path(d, "z2_pooled_ceiling.csv")))
IRi <- 1.4160; THR <- 0.05
wgrid <- seq(0.001, 0.999, by = 0.001)
dir_w <- function(w, rho, irs, iri = IRi)
  ((1 - w) * iri + w * irs) / sqrt((1 - w)^2 + w^2 + 2 * w * (1 - w) * rho) - iri
ceilf <- function(rho, irs) max(dir_w(wgrid, rho, irs))

## (a) 관측 IR 을 유지한 채 통과하려면 상관을 얼마까지 내려야 하나
rho_max_for <- function(irs) {
  if (ceilf(-0.999, irs) < THR) return(NA_real_)   # 상관 -1 에서도 불가
  rg <- seq(-0.999, 0.999, by = 0.001)
  v <- sapply(rg, function(r) ceilf(r, irs))
  ok <- which(v >= THR); if (!length(ok)) NA_real_ else max(rg[ok])
}
## (b) 관측 (rho, IR) 을 배율 g 로 함께 키울 때 통과에 필요한 최소 g
req_g_for <- function(rho, irs) {
  gg <- seq(1, 8, by = 0.005); gg <- gg[gg * rho < 0.999]
  if (!length(gg)) return(NA_real_)
  v <- sapply(gg, function(g) ceilf(rho * g, irs * g))
  ok <- which(v >= THR); if (!length(ok)) NA_real_ else gg[ok[1]]
}

P[, arm_b := ifelse(is.na(short_u) | (!is.na(short_p) & short_p <= short_u), "parked", "uncond")]
P[, rho_b := ifelse(arm_b == "parked", cor_p, cor_u)]
P[, irs_b := ifelse(arm_b == "parked", ir_p, ir_u)]
setorder(P, short_best)
T15 <- head(P, 15)

res <- rbindlist(lapply(seq_len(nrow(T15)), function(i) {
  r <- T15[i]
  rmax <- rho_max_for(r$irs_b)
  g <- req_g_for(r$rho_b, r$irs_b)
  cmax <- if (is.na(g)) NA_real_ else 1 / g^2      # k->inf 에서 g_max = 1/sqrt(c) 이므로
  k0 <- if (is.na(g)) NA_real_ else ceiling(g^2)   # 상호상관 0 가정 필요 k
  k3 <- if (is.na(g) || 0.3 >= cmax) NA_real_ else {
    kx <- 2:500; kx[which(sqrt(kx / (1 + (kx - 1) * 0.3)) >= g)[1]] }
  data.table(factor = r$factor, arm = r$arm_b, n = ifelse(r$arm_b == "parked", r$n_p, r$n_u),
    rho = r$rho_b, ir = r$irs_b, req_ir = ifelse(r$arm_b == "parked", r$req_p, r$req_u),
    short = r$short_best, ceil_w_free = r$ceil_best,
    rho_needed_at_obs_ir = rmax, gap_rho = r$rho_b - ifelse(is.na(rmax), NA, rmax),
    req_g = g, c_max = cmax, k_at_c0 = k0, k_at_c03 = k3)
}))
cat("=== [근접 15 · 통과 요건 분해] ceil_w_free = weight 무제약 ΔIR 천장\n")
print(res, digits = 4)
cat("\n해설 필드: rho_needed_at_obs_ir = 현재 IR 을 유지한 채 통과하려면 상관이 이 값 이하여야 함\n")
cat("           gap_rho = 현재 상관 - 필요 상관 (파킹/라벨 연구가 더 내려야 할 폭)\n")
cat("           req_g = 스택 배율(IR 과 상관을 함께 g 배) 최소치, c_max = 스택 구성원 간 허용 최대 상호상관\n\n")

## 계약수주 슬리브(메인 세션 확정치) 동일 프레임 대조
cat("=== [대조] 계약수주 국면규칙 슬리브 (메인 세션 확정: rho 0.140, IR 0.758)\n")
cat(" weight 무제약 천장:", sprintf("%+.4f", ceilf(0.140, 0.758)),
    " | 통과 필요 상관 상한:", sprintf("%.3f", rho_max_for(0.758)),
    " | req_g:", sprintf("%.2f", req_g_for(0.140, 0.758)), "(=단독 통과)\n")
cat(" 331 재료 중 IR>=0.758 인 건수:", sum(pmax(P$ir_u, P$ir_p, na.rm = TRUE) >= 0.758, na.rm = TRUE),
    " / 상관<=0.140 인 건수:", sum(pmin(P$cor_u, P$cor_p, na.rm = TRUE) <= 0.140, na.rm = TRUE),
    " / 둘 다(동일 arm):", sum((P$cor_u <= 0.14 & P$ir_u >= 0.758) | (P$cor_p <= 0.14 & P$ir_p >= 0.758), na.rm = TRUE), "\n\n")

## 통과 가능 영역 대비 관측 산점 요약
cat("=== [통과 영역과의 거리] 각 arm 에서 (rho, IR) 이 통과영역에 든 건수\n")
for (a in c("u", "p")) {
  rho <- P[[paste0("cor_", a)]]; irs <- P[[paste0("ir_", a)]]
  ok <- is.finite(rho) & is.finite(irs)
  pass <- mapply(function(r1, i1) ceilf(r1, i1) >= THR, rho[ok], irs[ok])
  cat(sprintf("  arm=%s : %d / %d\n", ifelse(a == "u", "uncond", "parked"), sum(pass), sum(ok)))
}
fwrite(res, file.path(d, "z3_probe_design.csv"))
cat("\nsaved z3_probe_design.csv\n")
