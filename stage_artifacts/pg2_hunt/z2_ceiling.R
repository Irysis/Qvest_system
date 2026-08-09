## z2_ceiling.R — (1) weight 무제약 ΔIR 천장 (2) 스택 조합 가능성 경계 (3) 파킹 중복 검사
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- readRDS(file.path(d, "z1_pooled.rds"))
IRi <- 1.4160; THR <- 0.05

## ΔIR(w | rho, ir_s) — sd 정규화(k=1). w 를 자유롭게 두면 sd 비율은 w 에 흡수되므로
## "가중 무제약 천장"은 (rho, ir_s) 만의 함수다.
dir_w <- function(w, rho, irs, iri = IRi) {
  ((1 - w) * iri + w * irs) / sqrt((1 - w)^2 + w^2 + 2 * w * (1 - w) * rho) - iri
}
wgrid <- seq(0.001, 0.999, by = 0.001)
ceil1 <- function(rho, irs) { v <- dir_w(wgrid, rho, irs); c(max(v), wgrid[which.max(v)]) }

cat("=== [검산] 천장 함수 vs 요구조건 지도\n")
cat(" rho 0.4, irs 0.925 -> 천장", sprintf("%.5f", ceil1(0.4, 0.925)[1]),
    "@w", ceil1(0.4, 0.925)[2], " (문턱 0.05 이면 w=0.20 에서 정확히 달성해야 함)\n")
cat(" rho 0.4, irs 1.4160(동등IR) -> 천장", sprintf("%.4f", ceil1(0.4, 1.4160)[1]), "\n")
cat(" rho 0.0, irs 1.4160(무상관·IR동등) -> 천장", sprintf("%.4f", ceil1(0.0, 1.4160)[1]),
    " (메인 세션 실측 +0.3012 대조)\n")
cat(" rho 1.0, irs 1.4160 -> 천장", sprintf("%.4f", ceil1(0.999, 1.4160)[1]), " (실측 0.0000 대조)\n\n")

for (a in c("u", "p")) {
  rho <- P[[paste0("cor_", a)]]; irs <- P[[paste0("ir_", a)]]
  ok <- is.finite(rho) & is.finite(irs)
  res <- t(mapply(ceil1, rho[ok], irs[ok]))
  P[[paste0("ceil_", a)]] <- NA_real_; P[[paste0("ceilw_", a)]] <- NA_real_
  P[[paste0("ceil_", a)]][ok] <- res[, 1]; P[[paste0("ceilw_", a)]][ok] <- res[, 2]
}
P[, ceil_best := pmax(ceil_u, ceil_p, na.rm = TRUE)]

qq <- function(x) { x <- x[is.finite(x)]; sprintf("n=%d min %.4f med %.4f q75 %.4f max %.4f",
  length(x), min(x), median(x), quantile(x, .75), max(x)) }
cat("=== [가중 무제약 ΔIR 천장] w 를 0.001~0.999 전 구간 자유롭게 줘도 도달 가능한 최대\n")
cat(" uncond:", qq(P$ceil_u), " | >=0.05:", sum(P$ceil_u >= 0.05, na.rm = TRUE),
    " >0:", sum(P$ceil_u > 0, na.rm = TRUE), "\n")
cat(" parked:", qq(P$ceil_p), " | >=0.05:", sum(P$ceil_p >= 0.05, na.rm = TRUE),
    " >0:", sum(P$ceil_p > 0, na.rm = TRUE), "\n")
cat(" 팩터별 최대:", qq(P$ceil_best), " | >=0.05:", sum(P$ceil_best >= 0.05, na.rm = TRUE),
    " >0:", sum(P$ceil_best > 0, na.rm = TRUE), "\n")
cat(" 천장 상위 8:\n")
print(head(P[order(-ceil_best), .(factor, cor_u, ir_u, ceil_u, ceilw_u, cor_p, ir_p, ceil_p, ceilw_p, ceil_best)], 8))
cat("\n")

## --- 스택 조합 경계: k개 슬리브 EW, 상호상관 c 이면
## IR 과 rho 가 동일 배율 g = sqrt(k/(1+(k-1)c)) 로 함께 확대된다 (rho*g <= 1 제약).
gfun <- function(k, cc) sqrt(k / (1 + (k - 1) * cc))
stack_ceiling <- function(rho, irs, gmax) {
  gg <- seq(1, gmax, length.out = 400); gg <- gg[gg * rho < 0.999]
  if (!length(gg)) return(c(NA_real_, NA_real_))
  v <- sapply(gg, function(g) ceil1(rho * g, irs * g)[1])
  c(max(v), gg[which.max(v)])
}
cat("=== [스택 조합 경계] k 슬리브 EW(상호상관 c) 는 IR 과 상관을 같은 배율 g=sqrt(k/(1+(k-1)c)) 로 확대\n")
cat(" g 표 (c=0.0 / 0.3 / 0.5):\n")
for (k in c(2, 3, 5, 8, 12)) cat(sprintf("  k=%2d : g = %.3f / %.3f / %.3f\n", k,
  gfun(k, 0), gfun(k, 0.3), gfun(k, 0.5)))
cat("\n 대표점 스택 천장 (g 무제약, rho*g<1):\n")
reps <- list(
  c(0.324, -0.090, "파킹 중앙(rho .324, IR -.090)"),
  c(0.292,  0.140, "파킹 q75(rho .292, IR +.140)"),
  c(0.243,  0.576, "V18_AM 파킹(최강)"),
  c(0.260,  0.455, "R17/V19 파킹"),
  c(0.085,  0.169, "R11_Systematic_Risk 무조건부(최저상관)"),
  c(0.140,  0.758, "계약수주 국면슬리브(메인 세션)"))
for (r in reps) {
  rho <- as.numeric(r[1]); irs <- as.numeric(r[2])
  sc <- stack_ceiling(rho, irs, gmax = 6)
  need_g <- NA_real_
  gg <- seq(1, 6, by = 0.001); gg <- gg[gg * rho < 0.999]
  vv <- sapply(gg, function(g) ceil1(rho * g, irs * g)[1])
  hit <- which(vv >= THR); if (length(hit)) need_g <- gg[hit[1]]
  kk0 <- if (is.na(need_g)) NA else ceiling(need_g^2)
  kk3 <- if (is.na(need_g)) NA else {
    kx <- 2:200; kx[which(gfun(kx, 0.3) >= need_g)[1]] }
  cat(sprintf("  %-40s 단일천장 %+.4f | 스택천장 %+.4f @g %.2f | 0.05 도달 g %s | 필요 k (c=0) %s / (c=0.3) %s\n",
    r[3], ceil1(rho, irs)[1], sc[1], sc[2],
    ifelse(is.na(need_g), "도달불가", sprintf("%.2f", need_g)),
    ifelse(is.na(kk0), "-", kk0), ifelse(is.na(kk3) || is.na(kk0), "-", kk3)))
}
cat("\n 331 전수: 스택으로(상호상관 0 가정, k 무제한) ΔIR 0.05 도달 가능한 재료 수\n")
for (a in c("u", "p")) {
  rho <- P[[paste0("cor_", a)]]; irs <- P[[paste0("ir_", a)]]
  ok <- is.finite(rho) & is.finite(irs)
  reach <- rep(NA_real_, nrow(P))
  gg <- seq(1, 6, by = 0.005)
  reach[ok] <- mapply(function(r1, i1) {
    g2 <- gg[gg * r1 < 0.999]
    if (!length(g2)) return(NA_real_)
    v <- sapply(g2, function(g) ceil1(r1 * g, i1 * g)[1]); max(v)
  }, rho[ok], irs[ok])
  P[[paste0("stackceil_", a)]] <- reach
  cat(sprintf("  arm=%s : 스택천장 >=0.05 인 재료 %d / %d  (중앙 %+.4f, 최대 %+.4f)\n",
    ifelse(a == "u", "uncond", "parked"), sum(reach >= THR, na.rm = TRUE), sum(ok),
    median(reach, na.rm = TRUE), max(reach, na.rm = TRUE)))
}
P[, stackceil_best := pmax(stackceil_u, stackceil_p, na.rm = TRUE)]
cat("  팩터별 최대 스택천장 >=0.05 :", sum(P$stackceil_best >= THR, na.rm = TRUE), "/", nrow(P), "\n")
cat("  스택천장 상위 12:\n")
print(head(P[order(-stackceil_best), .(factor, cor_p, ir_p, ceil_best, stackceil_u, stackceil_p, stackceil_best)], 12))
cat("\n")

## --- 파킹 arm 중복 벡터
P[, keyp := paste(round(cor_p, 6), round(ir_p, 6))]
dp <- P[!is.na(cor_p), .N, by = keyp][N > 1]
cat("=== [중복 벡터 · 파킹 arm] 그룹", nrow(dp), "\n")
if (nrow(dp)) for (k in dp$keyp) cat("  ", paste(P[keyp == k]$factor, collapse = " == "), "\n")
cat("\n")

fwrite(P, file.path(d, "z2_pooled_ceiling.csv"))
cat("saved z2_pooled_ceiling.csv\n")
