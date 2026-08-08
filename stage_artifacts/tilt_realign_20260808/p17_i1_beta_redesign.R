# p17_i1_beta_redesign.R — I1 재개: β 매핑 재설계 (100% 충실 base 위에서)
# base = 원장 저장 beta_R05·m4 (J1: invested == beta_R05×m4 100% 일치)
# z-flag = beta_R05 + regime 에서 역산(2×2 표가 정확히 성립하므로 가역)
# 연속 z = production 저장 R05_z_avg (재계산 금지 — §7b, 내 재계산은 cor 0.712 로 갈림)
# ★selection_type=sweep — 본 산출은 곡선 보고, 채택 시 DSR + holdout 사전등록 필수
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015

M <- fread("stage_artifacts/tilt_realign_20260808/p16_j1_close.csv")
M[, decision_date := as.Date(decision_date)]
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
D <- merge(M[, .(decision_date, key, regime, beta_R05, m4, invested)],
           R[, .(decision_date, eval_date, gross=gA, turn=tA)], by="decision_date")
prl <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
D <- merge(D, prl[is.finite(R05_z_avg), .(key=as.character(realized_ym), z=R05_z_avg)], by="key", all.x=TRUE)
setorder(D, decision_date)
cat(sprintf("[base] %d개월 | z 결측 %d | invested==beta×m4 %.1f%%\n", nrow(D), sum(!is.finite(D$z)),
            100*mean(abs(D$invested - D$beta_R05*D$m4) < 1e-9)))

## z-flag 역산 (2×2 표 가역)
D[, base_beta := fcase(regime=="CRISIS", 0.50, regime=="CAUTION", 0.70, default=1.00)]
D[, flag := beta_R05 < base_beta - 1e-9]
cat(sprintf("[flag 역산] 발화 %d개월 (%.1f%%) | regime별: %s\n", sum(D$flag), 100*mean(D$flag),
    paste(D[, sprintf("%s %d/%d", regime, sum(flag), .N), by=regime]$V1, collapse=" · ")))

mk <- function(beta, lbl) {
  inv <- pmin(pmax(beta * D$m4, 0), 1)
  net <- D$gross*inv - BPS*D$turn*inv
  x <- xts(net, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  list(row = data.table(arm=lbl, 평균노출=round(mean(inv),3), SR=round(as.numeric(t[3,1]),3),
        CAGR=round(as.numeric(t[1,1])*100,2), MDD=round(as.numeric(maxDrawdown(x))*100,2),
        Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3)), net = net)
}
A <- mk(D$beta_R05, "A. 현행 (이산 2×2)")
arms <- list(A$row, mk(D$base_beta, "B. 라벨만 (flag 무시)")$row)
# C: flag 발화월에서 한 단계 더 깊게 (0.30 하한)
for (extra in c(0.10, 0.20)) arms[[length(arms)+1L]] <-
  mk(pmax(0.30, D$beta_R05 - ifelse(D$flag, extra, 0)), sprintf("C. flag 심화 −%.2f", extra))$row
# D: 연속 매핑 — flag 이분법 대신 z 백분위 연속 (expanding, past-only)
D[, zpct := sapply(seq_len(.N), function(i) if (i<=36L) NA_real_ else mean(z[1:(i-1)] < z[i], na.rm=TRUE))]
D[!is.finite(zpct), zpct := 0.5]
for (k in c(0.3, 0.5, 0.7)) arms[[length(arms)+1L]] <-
  mk(pmax(0.30, D$base_beta * (1 - k * pmax(0, 0.30 - D$zpct)/0.30)), sprintf("D. 연속 f(z) k=%.1f", k))$row
out <- rbindlist(arms); setorder(out, -Calmar)
cat("\n===== β 매핑 arm (n_trials=7 sweep → 채택 시 DSR) =====\n"); print(out)

best <- out[1]
cat(sprintf("\n[최선 Calmar] %s : Calmar %.3f (현행 %.3f) · MDD %.2f%% (현행 %.2f%%) · SR %.3f (현행 %.3f)\n",
    best$arm, best$Calmar, A$row$Calmar, best$MDD, A$row$MDD, best$SR, A$row$SR))
for (nm in out[arm != "A. 현행 (이산 2×2)", arm]) {
  b <- switch(substr(nm,1,1),
    "B" = D$base_beta,
    "C" = pmax(0.30, D$beta_R05 - ifelse(D$flag, as.numeric(sub(".*−","",nm)), 0)),
    "D" = pmax(0.30, D$base_beta*(1 - as.numeric(sub(".*k=","",nm))*pmax(0,0.30-D$zpct)/0.30)))
  nn <- mk(b, nm)$net; tt <- t.test(nn - A$net)
  cat(sprintf("  paired vs 현행 [%s]: %+.4f%%/월 · t=%.2f · p=%.4f\n", nm, mean(nn-A$net)*100, tt$statistic, tt$p.value))
}
cat("\n[판정 규약] MDD<25% 유지 ∧ Calmar 개선 ∧ paired p<0.05 를 동시 충족해야 후보 자격.\n")
fwrite(out, "stage_artifacts/tilt_realign_20260808/p17_i1_beta_redesign.csv")
