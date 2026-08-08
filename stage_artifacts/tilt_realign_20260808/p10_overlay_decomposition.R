# p10_overlay_decomposition.R — D3: overlay 가 MDD 를 만드는 기전 분해
# 질문: overlay 의 MDD 개선(bare 40.74% → 23.28%)은 **타이밍**의 산물인가, 단순 **평균 노출 축소**의 산물인가?
#   타이밍이면 → overlay 설계 개선으로 MDD 를 더 낮출 여지 있음(D3 lane 유효)
#   노출 축소면 → 수익과 1:1 교환일 뿐, MDD 개선은 CAGR 희생의 다른 이름(설계 개선 여지 작음)
# ★핵심 통제 = **평균 노출 일치 상수 arm**(같은 평균 exposure, 타이밍 제거). 이게 없으면
#   "overlay 가 MDD 를 낮췄다"는 진술이 "노출을 줄였다"와 구별되지 않는다.
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
E <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA)],
           unique(car[, .(decision_date, invested)]), by="decision_date")
setorder(E, decision_date)
cat(sprintf("[표본] %d개월 | 평균 invested %.4f | invested<1 인 달 %d (%.1f%%)\n",
            nrow(E), mean(E$invested), sum(E$invested < 0.999), 100*mean(E$invested < 0.999)))

mk <- function(inv, lbl) {
  net <- E$gross*inv - BPS*E$turn*inv
  x <- xts(net, order.by=E$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, 평균노출=round(mean(inv),3),
             SR=round(as.numeric(t[3,1]),3), CAGR=round(as.numeric(t[1,1])*100,2),
             MDD=round(as.numeric(maxDrawdown(x))*100,2),
             Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3))
}
mean_inv <- mean(E$invested)
# regime-only 매핑(z 조건 제거): CRISIS 0.50 / CAUTION 0.70 / else 1.00
inv_reg <- fifelse(E$regime=="CRISIS", 0.50, fifelse(E$regime=="CAUTION", 0.70, 1.00))
arms <- rbindlist(list(
  mk(rep(1, nrow(E)),            "C. bare (overlay 없음)"),
  mk(E$invested,                 "A. 실제 overlay (gate×β_R05)"),
  mk(rep(mean_inv, nrow(E)),     "B. ★상수 노출 (평균 일치·타이밍 제거)"),
  mk(inv_reg,                    "D. regime-only 매핑 (z 조건 제거)"),
  mk(pmin(E$invested, 1)*0 + 0.50, "E. 상수 0.50 (참고)")))
setorder(arms, MDD)
cat("\n===== overlay 분해 =====\n"); print(arms)

A <- arms[grepl("^A\\.", arm)]; B <- arms[grepl("^B\\.", arm)]; C <- arms[grepl("^C\\.", arm)]
cat(sprintf("\n[핵심 대조] 같은 평균 노출(%.3f)에서 타이밍 유무:\n", mean_inv))
cat(sprintf("  실제 overlay MDD %.2f%% vs 상수 노출 MDD %.2f%%  → 타이밍 기여 %+.2f%%pt\n",
            A$MDD, B$MDD, A$MDD - B$MDD))
cat(sprintf("  실제 CAGR %.2f%% vs 상수 %.2f%%  → 타이밍 기여 %+.2f%%pt | Calmar %.3f vs %.3f\n",
            A$CAGR, B$CAGR, A$CAGR - B$CAGR, A$Calmar, B$Calmar))
cat(sprintf("  bare 대비 총 MDD 개선 %.2f%%pt 중 노출축소 몫 %.2f%%pt (%.0f%%) · 타이밍 몫 %.2f%%pt (%.0f%%)\n",
            C$MDD - A$MDD, C$MDD - B$MDD, 100*(C$MDD-B$MDD)/(C$MDD-A$MDD),
            B$MDD - A$MDD, 100*(B$MDD-A$MDD)/(C$MDD-A$MDD)))

cat("\n[해석 규약] 타이밍 몫이 크면 overlay '설계'(gate 규칙·β 매핑)가 MDD 레버 — D3 lane 유효.\n")
cat("            노출축소 몫이 지배하면 MDD 개선은 CAGR 희생의 다른 이름 — 목표는 다른 축에서 찾아야.\n")
fwrite(arms, "stage_artifacts/tilt_realign_20260808/p10_overlay_decomposition.csv")
