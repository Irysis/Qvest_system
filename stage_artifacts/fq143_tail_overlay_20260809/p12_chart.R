## FQ-143 P12 — 보고용 차트 2종
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")

## ── 차트 1: 사건 정의별 라벨 적중배수 (동월정렬 vs C5정렬 vs 배포창) ──────────
tab <- fread(file.path(DIR, "p3_eligibility_table.csv"))
dep <- fread(file.path(DIR, "p4_eligibility_windows.csv"))
ev <- c("ret < 0%", "ret < -5%", "ret < -10%")
a <- tab[alignment=="A_same"][match(ev, event)]$lift
b <- tab[alignment=="B_clean"][match(ev, event)]$lift
d <- dep[window=="deploy 2004-01~2026-05" & basis=="market bm_ret"][match(c("< 0%","< -5%","< -10%"), event)]$lift

png(file.path(DIR, "chart_lift.png"), width=1000, height=620, res=110)
par(mar=c(5,5,4,2), family="sans")
M <- rbind(a,b,d)
bp <- barplot(M, beside=TRUE, names.arg=c("월 -0% 미만\n(아무 하락)","월 -5% 미만","월 -10% 미만\n(심한 하락)"),
        col=c("#c9c9c9","#2c7fb8","#f4a259"), ylim=c(0,3.6),
        ylab="적중배수 (라벨 발화 시 사건확률 / 평시 사건확률)",
        main="국면 라벨의 하락 적중배수 — 정렬과 측정창에 따라 달라진다")
abline(h=1, lty=2, col="grey40")
text(bp, M+0.11, sprintf("%.2f", M), cex=0.78)
legend("topleft", bty="n", cex=0.82, fill=c("#c9c9c9","#2c7fb8","#f4a259"),
       legend=c("동월 정렬 (미래참조 — 브리핑 인용치)",
                "C5 정렬 전표본 428개월 (정본)",
                "C5 정렬 배포창 269개월 (검정력 0.32)"))
mtext("배수 1.0 = 정보 없음. 심할수록 잘 맞히나, 배포창은 표본이 작아 판정 불가(무자격 아님)",
      side=1, line=3.6, cex=0.72, col="grey30")
dev.off()

## ── 차트 2: 오라클 천장 vs 실측 (incumbent 위 한계기여) ────────────────────────
inc <- fread(file.path(DIR, "p6_increment.csv"))
png(file.path(DIR, "chart_ceiling.png"), width=1000, height=620, res=110)
par(mar=c(8.5,5,4,2), family="sans")
lab <- c("실측 라벨\n-30%", "실측 라벨\n-50%", "실측 라벨\n-70%",
         "오라클\n(-5% 예지)", "오라클\n(-10% 예지)")
v <- inc$paired_t_nw3
cols <- ifelse(v > 0, "#2c7fb8", "#d1495b")
bp <- barplot(v, names.arg=lab, col=cols, ylim=c(-3, 7), las=2, cex.names=0.78,
        ylab="현행 배포 오버레이 대비 짝지은 t값 (NW lag-3)",
        main="레버 천장 — 완전 예지로도 상금이 작다")
abline(h=c(0,2), lty=c(1,2), col=c("black","grey40"))
text(bp, v + ifelse(v>0, 0.42, -0.42), sprintf("%+.2f", v), cex=0.82)
text(par("usr")[2]*0.98, 2.28, "판정 문턱 t=2.0", adj=1, cex=0.72, col="grey30")
mtext("실측 라벨은 깊이를 바꿔도 t 가 -1.84 로 불변(선형 스케일). 오라클(미래 예지)조차 +3.18 이 상한",
      side=1, line=6.6, cex=0.72, col="grey30")
dev.off()
cat("[P12] charts written\n")
