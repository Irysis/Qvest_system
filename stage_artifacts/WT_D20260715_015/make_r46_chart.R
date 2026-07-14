# make_r46_chart.R — R46 무결성 라인 완결 차트 (텔레그램 첨부·시각화 전용, 수치는 계약값)
suppressWarnings(suppressMessages(library(data.table)))
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260715_015"
png(file.path(OUT,"chart_r46_integrity.png"), width=1280, height=1360, res=140)
par(mfrow=c(3,1), mar=c(4.2,4.8,3.4,1.4), family="sans")

# ── Panel A: 방화벽 분류 R44 → R46 (date-gap seam 39건 = NA-drop → stored 보존) ──
cats <- c("HARD\n(NA 격리)","RESTORE\n(stored 보존·신규)","SUSPECT\n(값유지 flag)")
r44 <- c(672, 0, 2121); r46 <- c(633, 39, 2121)
m <- rbind(r44, r46)
bp <- barplot(m, beside=TRUE, names.arg=cats, col=c("#c0504d","#4472c4"),
              ylim=c(0,2400), border=NA, ylab="종목-일 (전역)",
              main="[A] Ret sanity 방화벽 분류: R44 → R46 (P3 date-gap 정련)")
legend("topright", c("R44 (정련 전)","R46 (정련 후)"), fill=c("#c0504d","#4472c4"), bty="n", cex=0.95)
text(bp[1,], m[1,]+70, m[1,], cex=0.85, col="#7f2f2c")
text(bp[2,], m[2,]+70, m[2,], cex=0.85, col="#2f4d8f", font=2)
mtext("date-gap ∧ stored 물리타당 39건: OLD=NA-drop → NEW=stored 참값 복원 (HARD 672→633, RESTORE +39)",
      side=1, line=2.7, cex=0.72, col="#333333")

# ── Panel B: R45 196 seam 케이스 처리 결과 (RESTORE vs 미발화) ──
b <- c(39, 157)
bcol <- c("#4472c4","#a6a6a6")
bp2 <- barplot(b, names.arg=c("RESTORE 39\n(|recompute|>0.31·복원)","미발화 157\n(|recompute|≤0.31·불변)"),
               col=bcol, border=NA, ylim=c(0,190), ylab="종목-일",
               main="[B] R45 196 seam 케이스 (전량 비-유니버스·라이브 무영향)")
text(bp2, b+8, b, cex=0.95, font=2, col=c("#2f4d8f","#595959"))
mtext("worked example A004415@07-02: recompute +489%(Close-hole span) → stored +2.93% 참값 보존",
      side=1, line=2.7, cex=0.72, col="#333333")

# ── Panel C: Close 연속성 tripwire (현 rawdata, gate clean) ──
tw <- c(245, 218, 234, 0)
tcol <- c("#7f7f7f","#ed7d31","#70ad47","#c0504d")
bp3 <- barplot(tw, names.arg=c("전체 구멍\n(gapdays>20)","source-seam\n(krx 이음매)","활성상장","유니버스內\n(게이트)"),
               col=tcol, border=NA, ylim=c(0,290), ylab="구멍 (행)",
               main="[C] Close 연속성 tripwire — 현 rawdata (P2, 리빌드 전 조기감지)")
text(bp3, tw+10, tw, cex=0.95, font=2, col=tcol)
mtext("유니버스內 활성 구멍 0 → gate CLEAN(리빌드 안전). 245 구멍 전량 비-유니버스 April/July seam(KRX 백필 표적)",
      side=1, line=2.7, cex=0.72, col="#333333")

dev.off()
cat("chart written:", file.path(OUT,"chart_r46_integrity.png"), "\n")
