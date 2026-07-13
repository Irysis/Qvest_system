#==============================================================================
# R20 Step 04 — mandated charts (principle 9) + telegram v7 verdict brief
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_004")
M <- readRDS(file.path(OUT,"measure_r20.rds"))
US <- c("K200","KQ150","KOSPI_all","KOSDAQ_all"); ULAB <- c("K200","KQ150","KOSPI전체","KOSDAQ전체")
capw_mdd_eff <- sapply(US, function(U) as.numeric(M$primary[[U]]$capw$rand["mdd"]-M$primary[[U]]$capw$exfl["mdd"]))
ew_mdd_eff   <- sapply(US, function(U) as.numeric(M$primary[[U]]$ew$rand["mdd"]-M$primary[[U]]$ew$exfl["mdd"]))

# ---- Chart 1: audit-quality gradient (MDD improvement exfl-vs-random) ----
png(file.path(OUT,"grad_line.png"), width=1000, height=560, res=110)
par(mar=c(5,5,4,2))
yr <- range(c(capw_mdd_eff, ew_mdd_eff, 0.025, -0.01))
plot(1:4, capw_mdd_eff, type="b", pch=19, col="#c0392b", lwd=2.5, ylim=yr, xaxt="n",
     xlab="Audit-quality order (most-audited -> least-audited)", ylab="MDD improvement (random - exflagged)",
     main="R20 Gradient: Benford-removal tail benefit vs audit quality")
lines(1:4, ew_mdd_eff, type="b", pch=17, col="#2980b9", lwd=2.5, lty=2)
axis(1, at=1:4, labels=ULAB)
abline(h=0, col="grey50", lty=3)
# predicted direction (dashed grey rising arrow)
segments(1, 0.001, 4, 0.020, col="#27ae60", lwd=2, lty=4)
text(3.5, 0.021, "predicted (monotone up)", col="#27ae60", cex=0.85)
legend("topright", c("cap-weighted (authoritative)","equal-weighted (diagnostic)","predicted"),
       col=c("#c0392b","#2980b9","#27ae60"), pch=c(19,17,NA), lty=c(1,2,4), lwd=2, bty="n", cex=0.85)
text(2.5, min(yr)+0.003, sprintf("Spearman(order,effect)= -0.40 (predicted +1) -> gradient FALSIFIED"), cex=0.9, font=2)
dev.off()

# ---- Chart 2: per-universe MDD bars (base / exflag / random) ----
png(file.path(OUT,"tail_bars.png"), width=1000, height=560, res=110)
par(mar=c(5,5,4,2))
mat <- sapply(US, function(U){ r<-M$primary[[U]]; c(base=r$capw$base["mdd"], exflag=r$capw$exfl["mdd"], random=r$capw$rand["mdd"]) })
rownames(mat) <- c("base","ex-flagged","random")
bp <- barplot(mat, beside=TRUE, col=c("#7f8c8d","#c0392b","#f1c40f"), names.arg=ULAB,
        ylab="Max Drawdown (lower = safer)", main="R20 per-universe MDD: ex-flagged vs random control (cap-w, 2010-2015)")
legend("topright", rownames(mat), fill=c("#7f8c8d","#c0392b","#f1c40f"), bty="n", cex=0.9)
text(mean(bp), max(mat)*1.02, "ex-flagged ~ random in every universe (all CIs straddle 0)", cex=0.85, font=2)
dev.off()

# ---- Chart 3: cumulative base vs ex-flagged, KOSDAQ_all (predicted-strongest) ----
S <- M$primary$KOSDAQ_all$series
wf <- function(r) cumprod(1+ifelse(is.na(r),0,r))   # visualization only
png(file.path(OUT,"cum_kosdaq.png"), width=1000, height=560, res=110)
par(mar=c(5,5,4,2))
d <- as.Date(sprintf("%d-%02d-01", S$months%/%100L, S$months%%100L))
yb <- wf(S$base); ye <- wf(S$exfl); yr2 <- wf(S$randmean)
plot(d, yb, type="l", col="#7f8c8d", lwd=2, ylim=range(c(yb,ye,yr2)),
     xlab="", ylab="cumulative wealth (index=1)", main="R20 KOSDAQ-all: base vs Benford-ex-flagged vs random (predicted-strongest arm)")
lines(d, ye, col="#c0392b", lwd=2); lines(d, yr2, col="#f1c40f", lwd=2, lty=2)
legend("topleft", c("base index","ex-flagged (Benford)","random control"),
       col=c("#7f8c8d","#c0392b","#f1c40f"), lwd=2, lty=c(1,1,2), bty="n", cex=0.9)
text(d[length(d)%/%2], min(c(yb,ye,yr2))*1.05, "curves overlap -> no filter benefit", cex=0.9, font=2)
dev.off()
cat("[04] 3 charts written\n")

# ---- telegram v7 ----
src <- file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R")
if(file.exists(src)){
  tryCatch({
    source(src)
    charts <- file.path(OUT, c("grad_line.png","tail_bars.png","cum_kosdaq.png"))
    tg_agent_brief(
      agent = "Alpha",
      relaxed = TRUE,
      title = "R20 포렌식 필터 지수-레벨 검증 — config-scoped negative (감사품질 구배 FALSIFIED)",
      sections = list(
        list(type="summary", body="포렌식 Benford 필터로 지수 위험종목을 빼도 무작위 제거와 차이 없음 — 4개 지수 전부, 감사품질 구배 예측 깨짐"),
        list(type="text", heading="쉬운 설명", body="재무제표 숫자가 자연법칙(Benford)에서 벗어나는 정도로 분식 의심 종목을 골라 지수에서 빼봤습니다. 가설은 감사가 느슨한 작은 종목일수록 효과가 커야 한다였지만, 실측은 정반대(가장 큰 효과가 가장 감사 잘되는 대형지수) + 무작위 제거와 차이 없음. R18 null과 일치."),
        list(type="kv", heading="핵심 비교", kv=list(
          "기간(primary)"="2010-2015 72개월 (전 지수 Benford 커버리지 98%+)",
          "구배 Spearman"="-0.40 (예측 +1) → 비단조 (falsified)",
          "cap-w MDD개선"="K200 +0.021 / KQ150 -0.006 / KOSPI전체 +0.010 / KOSDAQ전체 -0.004",
          "EW 진단"="전 지수 ~0 (K200 +0.002)",
          "신뢰구간"="모든 지수·모든 꼬리지표 0 교차 (구별불가)",
          "판정"="config-scoped negative + frontier"
        )),
        list(type="bullet", heading="판정 평문", items=list(
          "도훈 설계(지수 기질로 전략-필터 교란 제거)로도 Benford 포렌식 필터는 구제 안 됨",
          "감사품질 구배(대형지수~0 → 소형지수 최대) 예측이 깨짐 — 필터 정보실재의 결정적 반증",
          "대형지수 단일 양수(낙폭 +0.021)=시총집중 단일경로 아티팩트(균등가중 소멸·비정합·구간 0교차)",
          "power 주의: clean 구간이 2008·2020 크래시 제외 → 절대 꼬리검출력 제한(구배 shape는 무관)"
        )),
        list(type="bullet", heading="다음 탐침 (2건+, AX-000)", items=list(
          "상장폐지·불성실공시 event 예측(rawdata 플래그) 정확도 검정 — 지수수익 꼬리보다 구성타당·고민감",
          "커버리지 복구 소형지수 재검(분기 자료·항목문턱 완화) — 예측 최강 구간이 현재 데이터-차단",
          "2008·2020 커버리지 복구 시 crisis 구간 꼬리 재검(절대 검출력 보강)"
        )),
        list(type="bullet", heading="정직 라벨", items=list(
          "KOSPI전체·KOSDAQ전체 = 배포 봉투 밖 (진단 전용, 자본전략 아님·봉투 불변)",
          "metric_type=diagnostic (지수 재구성, canonical_screen 아님)",
          "survivorship: 8.5% 상폐 소형주 거래소라벨 결손 → 긍정주장에 보수적(bias against)"
        ))
      ),
      charts = charts
    )
    cat("[04] telegram sent\n")
  }, error=function(e) cat("[04] telegram ERROR:", conditionMessage(e), "\n"))
} else cat("[04] telegram_notify.R not found — charts saved only\n")
cat("[04] DONE\n")
