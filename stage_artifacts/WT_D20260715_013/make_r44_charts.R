# make_r44_charts.R — R44 방화벽 보고 차트 2종 (시각화 전용, 수치는 검증 산출값)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_013")
col_hard <- "#d62728"; col_susp <- "#ff7f0e"; col_ok <- "#2ca02c"; col_str <- "#1f77b4"; col_bm <- "#888888"

# ── Chart A: 방화벽 격리 분해 (원인별 · 전체 vs 유니버스) ─────────────────────
grDevices::png(file.path(OUT, "chartA_isolation_breakdown.png"), width=1040, height=580, res=110)
graphics::par(mar=c(6.5,4.6,3.4,1.2), family="")
labs <- c("HARD:물리불가\n(|Ret|>1)","HARD:0원제수\n(전일가<=10)","HARD:날짜갭\n(>20일)","SUSPECT:제한초과\n(값유지·flag)")
tot  <- c(257, 373, 42, 2121)
univ <- c(1, 0, 0, 16)
mat <- rbind(tot, univ)
bp <- barplot(mat, beside=TRUE, names.arg=labs, las=1, cex.names=0.72,
              col=c("#c6c6c6", col_str), border=NA, ylim=c(0, max(tot)*1.15),
              ylab="종목-일 (rows)", main="R44 Ret 방화벽 — 격리 분해 (전체 vs 투자유니버스)")
text(bp[1,], tot, labels=tot, pos=3, cex=0.72, col="#555555")
text(bp[2,], univ, labels=univ, pos=3, cex=0.74, col=col_str, font=2)
graphics::legend("topleft", legend=c("전체 (14M행 중)","유니버스內 K200∪KQ150"),
       fill=c("#c6c6c6", col_str), border=NA, bty="n", cex=0.82)
graphics::mtext("HARD 3종 = Ret:=NA 자동격리(오염 제거) · SUSPECT = 값유지·격리리스트만(분할 back-adjust는 R2/R3 리빌드)",
      side=1, line=5.0, cex=0.68, col="#666666")
grDevices::dev.off()

# ── Chart B: 회귀 parity — 정당 데이터 불변 실증 ──────────────────────────────
grDevices::png(file.path(OUT, "chartB_regression_parity.png"), width=1040, height=580, res=110)
graphics::par(mar=c(5.6,12.5,3.4,2.2), family="")
tests <- c("현 북 14보유 격리 (기대 0)",
           "유니버스 월패널 前/後 max|Δ| (기대 0)",
           "canonical 가드 — clean 경고 (기대 0)",
           "canonical 가드 — monster 주입 격리 (기대 1)",
           "monster 주입 후 결과 = clean과 일치")
vals  <- c(0, 0, 0, 1, 1)           # 시각화용 상태값
disp  <- c("0 행", "0.0e+00", "0 회", "1 회 발화", "bit-일치")
cols  <- c(col_ok, col_ok, col_ok, col_ok, col_ok)
bp <- barplot(rev(vals+0.02), horiz=TRUE, names.arg=rev(tests), las=1, cex.names=0.76,
              col=rev(cols), border=NA, xlim=c(0,1.35), xaxt="n",
              main="R44 회귀검증 — 정당 데이터 불변 (known-case parity) 실증")
text(rep(0.03,5), bp, labels=rev(disp), pos=4, cex=0.82, font=2, col="#1a1a1a")
text(rep(1.05,5), bp, labels="PASS", pos=4, cex=0.86, font=2, col=col_ok)
graphics::mtext("방화벽은 오염(HARD 672행)만 제거 · 정당 데이터·현 북·월패널 전부 불변 · 가드는 clean 무해·monster 격리",
      side=1, line=2.6, cex=0.7, col="#666666")
grDevices::dev.off()

cat("charts written:\n", file.path(OUT,"chartA_isolation_breakdown.png"), "\n",
    file.path(OUT,"chartB_regression_parity.png"), "\n")
