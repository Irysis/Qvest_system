# p5_crisis_label_diagnosis.R — CRISIS cap 무효가 '규칙 문제'인가 '라벨 문제'인가
suppressMessages(library(data.table))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, ym := format(as.Date(eval_date), "%Y-%m")]
cat(sprintf("[전체] %d개월 (%s~%s)\n", nrow(R), R$ym[1], R$ym[nrow(R)]))
cat("\n[국면 라벨 분포]\n")
print(R[, .(개월=.N, 비중=sprintf("%.1f%%", 100*.N/nrow(R))), by=regime][order(-개월)])
cat("\n[CRISIS 발화 월 전체]\n")
print(R[regime=="CRISIS", .(ym, netA_pct=round(netA*100,2), netC_pct=round(netC*100,2),
                            maxA=round(maxA,4), maxC=round(maxC,4))])
cat("\n[알려진 위기 구간에서 라벨이 무엇이었나]\n")
wins <- list(c("2008-09","2009-03"), c("2020-02","2020-05"), c("2022-01","2022-10"), c("2026-05","2026-08"))
for (w in wins) {
  s <- R[ym >= w[1] & ym <= w[2]]
  if (!nrow(s)) { cat(sprintf("  %s~%s : 표본 없음\n", w[1], w[2])); next }
  tb <- s[, .N, by=regime][order(-N)]
  cat(sprintf("  %s~%s (%d개월): %s | 최악월 %.2f%%\n", w[1], w[2], nrow(s),
              paste(sprintf("%s %d", tb$regime, tb$N), collapse=", "), min(s$netA)*100))
}
cr <- R[regime=="CRISIS"]
cat("\n[cap 도달 가능성]\n")
cat(sprintf("  CRISIS %d개월 중 cap(0.10) 정확 구속 %d개월 | 비-CRISIS 정본 최대비중 평균 %.4f\n",
            nrow(cr), sum(abs(cr$maxA-0.10) < 1e-6), R[regime!="CRISIS", mean(maxA)]))
cat(sprintf("  → cap 축 전기간 SR 영향이 0.001 인 이유 = 발화 표본 %d/%d (%.1f%%)\n",
            nrow(cr), nrow(R), 100*nrow(cr)/nrow(R)))
q <- quantile(R$netA, 0.05)
worst <- R[netA <= q][order(netA)]
cat(sprintf("\n[최악 5%% 월(%d개)의 라벨 구성] %s\n", nrow(worst),
            paste(worst[, .N, by=regime][order(-N)][, sprintf("%s %d", regime, N)], collapse=", ")))
cat(sprintf("  그중 CRISIS 라벨 비율 = %.1f%% (전체 기저율 %.1f%%)\n",
            100*mean(worst$regime=="CRISIS"), 100*mean(R$regime=="CRISIS")))
