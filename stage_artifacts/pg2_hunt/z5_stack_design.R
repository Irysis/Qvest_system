## z5_stack_design.R — 구체 스택 후보의 사전등록 통과조건 (허용 상호상관 상한)
suppressPackageStartupMessages({library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- file.path(root, "stage_artifacts", "pg2_hunt")
P <- fread(file.path(d, "z2_pooled_ceiling.csv"))
IRi <- 1.4160; THR <- 0.05
wg <- seq(0.001, 0.999, by = 0.001)
ceilf <- function(rho, irs) max(((1 - wg) * IRi + wg * irs) /
  sqrt((1 - wg)^2 + wg^2 + 2 * wg * (1 - wg) * rho) - IRi)
req_g <- function(rho, irs) { gg <- seq(1, 8, by = 0.002); gg <- gg[gg * rho < 0.999]
  if (!length(gg)) return(NA_real_); v <- sapply(gg, function(g) ceilf(rho * g, irs * g))
  ok <- which(v >= THR); if (!length(ok)) NA_real_ else gg[ok[1]] }

stacks <- list(
  A = c("V18_AM", "L25_Amihud_Vol", "R17_Market_Leverage"),
  B = c("V18_AM", "R17_Market_Leverage", "L11_Kyle_Lambda", "V08_PSR", "L25_Amihud_Vol"),
  C = c("V18_AM", "L25_Amihud_Vol"),
  D = c("V18_AM", "L25_Amihud_Vol", "R17_Market_Leverage", "V08_PSR", "L11_Kyle_Lambda",
        "XF_LL02_NetDebt", "V06_fDY", "V05_fPBR", "L01_Amihud", "R18_Book_Leverage"),
  E = c("V18_AM", "L25_Amihud_Vol", "R17_Market_Leverage", "V08_PSR", "L11_Kyle_Lambda",
        "XF_LL02_NetDebt", "V06_fDY", "V05_fPBR", "L01_Amihud", "R18_Book_Leverage",
        "V13_EV_Sales", "Q24_Altman_Z", "D41_Vol_of_Vol", "V24_Residual_Income", "M07_IndMom"))
for (nm in names(stacks)) {
  f <- stacks[[nm]]; S <- P[factor %in% f]
  k <- nrow(S); mIR <- mean(S$ir_p); mRho <- mean(S$cor_p)
  g <- req_g(mRho, mIR)
  cmax <- if (is.na(g)) NA else max(0, (k - g^2) / (g^2 * (k - 1)))
  cat(sprintf("스택 %s (k=%d, 파킹 arm 73m): mean IR %+.4f · mean rho %.4f\n", nm, k, mIR, mRho))
  cat(sprintf("   단일수준 천장 %+.5f | 통과 필요 g %s | 이 k 에서 허용 최대 상호상관 c* = %s\n",
      ceilf(mRho, mIR), ifelse(is.na(g), "도달불가", sprintf("%.3f", g)),
      ifelse(is.na(cmax), "-", sprintf("%.3f", cmax))))
  cat("   구성:", paste(S$factor, collapse = ", "), "\n\n")
}
cat("판정 규칙: 스택 구성원 간 실측 평균 상호상관이 c* 미만이면 ΔIR>=0.05 도달 가능, 이상이면 불가.\n")
cat("(EW 스택 항등: IR 과 incumbent 상관이 동일 배율 g=sqrt(k/(1+(k-1)c)) 로 함께 확대)\n")
