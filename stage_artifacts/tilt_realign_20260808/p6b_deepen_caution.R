# p6b_deepen_caution.R — 라벨 lane R1 후속: CAUTION 대응 심화의 회수 가능분
# P6 발견: 현 라벨 CRISIS+CAUTION 이 recall 0.556 · precision 0.476(기저 6.2×, p<0.0001) 로
#   자격 관문 PASS. 벤치 파생 순진 신호 4종은 전부 판별력 0(precision≈기저).
#   → 병목은 '라벨의 판별력'이 아니라 '라벨에 대한 대응 깊이'(β_R05 매핑)일 수 있다.
# 시험: CAUTION 월의 β_R05 를 0.70 → {0.60, 0.50(CRISIS급)} 로 심화. **PIT 안전**(기존 라벨만 사용).
# ★selection_type=sweep(3값) — argmax 채택 시 DSR 게이트 대상. 본 산출은 곡선 보고.
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
D <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA)],
           unique(car[, .(decision_date, invested)]), by="decision_date")
setorder(D, decision_date)
cat(sprintf("[panel] %d개월 %s~%s\n", nrow(D), min(D$eval_date), max(D$eval_date)))
cat("\n[CAUTION 월의 실제 invested 분포 — gate=1 가정 검증]\n")
print(D[regime=="CAUTION", .N, by=.(invested=round(invested,3))][order(-N)])

mets <- function(v, lbl) { x <- xts(v, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, SR=round(as.numeric(t[3,1]),3), CAGR_pct=round(as.numeric(t[1,1])*100,2),
             MDD_pct=round(as.numeric(maxDrawdown(x))*100,2)) }

D[, net_actual := gross*invested - BPS*turn*invested]
rows <- list(mets(D$net_actual, "현행 (CAUTION β 0.70)"))
for (tgt in c(0.60, 0.50)) {
  D[, inv_cf := invested]
  # CAUTION 월만 심화: 현행 β(0.70 또는 z<q20 시 0.50) 에 스케일 적용. 이미 tgt 이하면 유지.
  D[regime=="CAUTION", inv_cf := pmin(invested, invested * (tgt/0.70))]
  D[, net_cf := gross*inv_cf - BPS*turn*inv_cf]
  rows[[length(rows)+1L]] <- mets(D$net_cf, sprintf("CAUTION β→%.2f", tgt))
}
out <- rbindlist(rows)
cat("\n===== CAUTION 대응 심화 (PIT 안전 — 기존 라벨만 사용) =====\n"); print(out)
base <- out[1]
cat(sprintf("\n[vs 현행] β→0.60: ΔSR %+.3f · ΔMDD %+.2f%%pt · ΔCAGR %+.2f%%pt\n",
            out[2,SR]-base$SR, out[2,MDD_pct]-base$MDD_pct, out[2,CAGR_pct]-base$CAGR_pct))
cat(sprintf("[vs 현행] β→0.50: ΔSR %+.3f · ΔMDD %+.2f%%pt · ΔCAGR %+.2f%%pt\n",
            out[3,SR]-base$SR, out[3,MDD_pct]-base$MDD_pct, out[3,CAGR_pct]-base$CAGR_pct))
D[, inv_cf := invested][regime=="CAUTION", inv_cf := pmin(invested, invested*(0.50/0.70))]
D[, net_cf := gross*inv_cf - BPS*turn*inv_cf]
tt <- t.test(D$net_cf - D$net_actual)
cat(sprintf("[paired β→0.50 vs 현행] mean %+.4f%%/월 · t=%.3f · p=%.4f\n", mean(D$net_cf-D$net_actual)*100, tt$statistic, tt$p.value))
cat(sprintf("\n[오라클 상한 대비 회수율] 오라클 ΔSR +0.397 / ΔMDD -5.61%%pt 중\n"))
cat(sprintf("  β→0.50 실현: ΔSR %+.3f (%.0f%%) · ΔMDD %+.2f%%pt (%.0f%%)\n",
            out[3,SR]-base$SR, 100*(out[3,SR]-base$SR)/0.397,
            out[3,MDD_pct]-base$MDD_pct, 100*(out[3,MDD_pct]-base$MDD_pct)/(-5.61)))
cat("\n[2020 COVID 4개월 재확인]\n")
print(D[eval_date>=as.Date("2020-02-01") & eval_date<=as.Date("2020-06-30"),
        .(ym=format(eval_date,"%Y-%m"), regime, invested=round(invested,3), inv_cf=round(inv_cf,3),
          actual_pct=round(net_actual*100,2), cf_pct=round(net_cf*100,2))])
fwrite(out, "stage_artifacts/tilt_realign_20260808/p6b_deepen_caution.csv")
