# p18_k2_ablation.R — K2: 타이밍 83% 의 성분별 ablation (m4 vs β_R05)
# D3 는 '타이밍 전체'만 쟀다. base 가 100% 재현되는 지금(J1) 누가 얼마를 만드는지 분해한다.
# 각 성분마다 **평균 노출 일치 상수 arm**을 짝지어, 그 성분의 기여를 '타이밍'과 '노출축소'로 재분리.
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015
M <- fread("stage_artifacts/tilt_realign_20260808/p16_j1_close.csv"); M[, decision_date := as.Date(decision_date)]
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
D <- merge(M[, .(decision_date, regime, beta_R05, m4, invested)],
           R[, .(decision_date, eval_date, gross=gA, turn=tA)], by="decision_date")
setorder(D, decision_date)
cat(sprintf("[base] %d개월 | m4<1 %d달(%.1f%%) | beta<1 %d달(%.1f%%) | 둘 다 <1 %d달\n",
  nrow(D), sum(D$m4<0.999), 100*mean(D$m4<0.999), sum(D$beta_R05<0.999), 100*mean(D$beta_R05<0.999),
  sum(D$m4<0.999 & D$beta_R05<0.999)))

mk <- function(inv, lbl) {
  net <- D$gross*inv - BPS*D$turn*inv
  x <- xts(net, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, 평균노출=round(mean(inv),4), SR=round(as.numeric(t[3,1]),3),
             CAGR=round(as.numeric(t[1,1])*100,2), MDD=round(as.numeric(maxDrawdown(x))*100,2),
             Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3))
}
inv_full <- D$beta_R05 * D$m4
inv_b    <- D$beta_R05                 # m4 제거
inv_m    <- D$m4                       # β_R05 제거
one      <- rep(1, nrow(D))
arms <- rbindlist(list(
  mk(one,      "0. bare (성분 없음)"),
  mk(inv_m,    "1. m4 단독"),
  mk(inv_b,    "2. β_R05 단독"),
  mk(inv_full, "3. 둘 다 (현행)"),
  mk(rep(mean(inv_m),nrow(D)),    "1c. m4 평균 상수(타이밍 제거)"),
  mk(rep(mean(inv_b),nrow(D)),    "2c. β 평균 상수(타이밍 제거)"),
  mk(rep(mean(inv_full),nrow(D)), "3c. 현행 평균 상수(타이밍 제거)")))
cat("\n===== 성분 ablation =====\n"); print(arms[order(MDD)])

g <- function(k) arms[arm == k]
bare <- g("0. bare (성분 없음)"); m1 <- g("1. m4 단독"); b2 <- g("2. β_R05 단독"); f3 <- g("3. 둘 다 (현행)")
m1c <- g("1c. m4 평균 상수(타이밍 제거)"); b2c <- g("2c. β 평균 상수(타이밍 제거)"); f3c <- g("3c. 현행 평균 상수(타이밍 제거)")
cat(sprintf("\n[MDD 기여 분해] bare %.2f%% → 현행 %.2f%% (총 −%.2f%%pt)\n", bare$MDD, f3$MDD, bare$MDD-f3$MDD))
cat(sprintf("  m4 단독      : %.2f%% (−%.2f%%pt) | 그중 타이밍 %.2f%%pt · 노출축소 %.2f%%pt\n",
    m1$MDD, bare$MDD-m1$MDD, m1c$MDD-m1$MDD, bare$MDD-m1c$MDD))
cat(sprintf("  β_R05 단독   : %.2f%% (−%.2f%%pt) | 그중 타이밍 %.2f%%pt · 노출축소 %.2f%%pt\n",
    b2$MDD, bare$MDD-b2$MDD, b2c$MDD-b2$MDD, bare$MDD-b2c$MDD))
cat(sprintf("  둘 다        : %.2f%% (−%.2f%%pt) | 그중 타이밍 %.2f%%pt · 노출축소 %.2f%%pt\n",
    f3$MDD, bare$MDD-f3$MDD, f3c$MDD-f3$MDD, bare$MDD-f3c$MDD))
add_m <- (b2$MDD - f3$MDD); add_b <- (m1$MDD - f3$MDD)
cat(sprintf("\n[한계 기여(다른 성분이 이미 있을 때)] m4 추가 %+.2f%%pt · β_R05 추가 %+.2f%%pt\n", -add_m, -add_b))
cat(sprintf("[상호작용] 단독 합 %.2f%%pt vs 결합 %.2f%%pt → %s (%.2f%%pt)\n",
    (bare$MDD-m1$MDD)+(bare$MDD-b2$MDD), bare$MDD-f3$MDD,
    ifelse((bare$MDD-m1$MDD)+(bare$MDD-b2$MDD) > bare$MDD-f3$MDD, "부분 중복(합보다 작음)", "상승효과"),
    abs((bare$MDD-m1$MDD)+(bare$MDD-b2$MDD) - (bare$MDD-f3$MDD))))
cat(sprintf("\n[Calmar] bare %.3f · m4 %.3f · β %.3f · 현행 %.3f\n", bare$Calmar, m1$Calmar, b2$Calmar, f3$Calmar))
fwrite(arms, "stage_artifacts/tilt_realign_20260808/p18_k2_ablation.csv")
