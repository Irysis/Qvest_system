# p5b_label_prize.R — 국면 라벨 개선의 상금 크기 (β_R05 오버레이 단계)
# 질문: CRISIS 라벨이 271개월 중 4회(1.5%)만 발화하고 2020 COVID 를 통째로 놓쳤다.
#       그 미발화가 β_R05 단계에서 방어를 얼마나 놓쳤나?
# ★★오라클 상한 — 실현수익으로 위기월을 지목하므로 **구성상 미래참조**. 실행 가능 전략이 아니라
#   "라벨을 고치면 되찾을 수 있는 최대치"의 크기만 잰다(metric_type=oracle_upper_bound).
#   PIT 준수 전략으로 이 상금을 실제로 회수할 수 있는지는 별개 문제(라벨 자격 관문 lane).
# β_R05_V5 매핑: CRISIS&z<q20 0.30 / CRISIS 0.50 / CAUTION&z<q20 0.50 / CAUTION 0.70 /
#                BULL·NORMAL&z<q20 0.85 / else 1.00
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
ovl <- unique(car[, .(decision_date, invested)])
D <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA)], ovl, by="decision_date")
D[, ym := format(eval_date, "%Y-%m")]
cat(sprintf("[panel] %d개월 (%s~%s) | invested 중앙 %.2f\n", nrow(D), D$ym[1], D$ym[nrow(D)], median(D$invested)))

mets <- function(v, lbl) {
  x <- xts(v, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, SR=round(as.numeric(t[3,1]),3), CAGR_pct=round(as.numeric(t[1,1])*100,2),
             MDD_pct=round(as.numeric(maxDrawdown(x))*100,2))
}
# 실제 (현 라벨)
D[, net_actual := gross*invested - BPS*turn*invested]

# 오라클 위기 정의 2종 (실현 sleeve 수익 기준 — 미래참조, 상금 측정 전용)
D[, oracle_d10 := gross <= quantile(gross, 0.10)]
D[, oracle_m10 := gross <= -0.10]
for (ocol in c("oracle_d10","oracle_m10")) {
  D[, inv_cf := invested]
  D[get(ocol) == TRUE, inv_cf := pmin(invested, 0.50)]   # CRISIS 라벨이 켜졌다면 β_R05 ≤ 0.50
  D[, net_cf := gross*inv_cf - BPS*turn*inv_cf]
  n_o <- sum(D[[ocol]]); n_missed <- sum(D[[ocol]] & D$regime != "CRISIS")
  cat(sprintf("\n===== 오라클 정의 %s : 위기월 %d개 중 현 라벨이 CRISIS 로 잡은 것 %d개 (놓친 것 %d개, %.0f%%) =====\n",
              ocol, n_o, n_o - n_missed, n_missed, 100*n_missed/n_o))
  print(rbindlist(list(mets(D$net_actual, "현 라벨 (실제)"), mets(D$net_cf, "오라클 라벨 (상한)"))))
  cat(sprintf("  ΔMDD = %+.2f%%pt | ΔCAGR = %+.2f%%pt | ΔSR = %+.3f\n",
              mets(D$net_cf,"")$MDD_pct - mets(D$net_actual,"")$MDD_pct,
              mets(D$net_cf,"")$CAGR_pct - mets(D$net_actual,"")$CAGR_pct,
              mets(D$net_cf,"")$SR - mets(D$net_actual,"")$SR))
}

cat("\n[2020 COVID 구간 상세 — 라벨이 CRISIS 를 0회 발화한 구간]\n")
cv <- D[ym >= "2020-02" & ym <= "2020-05", .(ym, regime, gross_pct=round(gross*100,2),
        invested=round(invested,3), net_actual_pct=round(net_actual*100,2),
        net_if_crisis_pct=round((gross*pmin(invested,0.50) - BPS*turn*pmin(invested,0.50))*100,2))]
print(cv)
cat(sprintf("  4개월 누적: 실제 %.2f%% vs CRISIS 라벨 시 %.2f%% → 놓친 방어 %.2f%%pt\n",
            (prod(1+D[ym>="2020-02"&ym<="2020-05", net_actual])-1)*100,
            (prod(1+D[ym>="2020-02"&ym<="2020-05", gross*pmin(invested,0.50)-BPS*turn*pmin(invested,0.50)])-1)*100,
            ((prod(1+D[ym>="2020-02"&ym<="2020-05", gross*pmin(invested,0.50)-BPS*turn*pmin(invested,0.50)])-1) -
             (prod(1+D[ym>="2020-02"&ym<="2020-05", net_actual])-1))*100))
cat("\n★ 위 수치는 오라클 상한(미래참조 구성) — 실행 가능 전략 아님. 라벨 개선 lane 의 상금 크기 지표.\n")
