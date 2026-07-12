## d3_charts_tg.R — D3 결정 패키지 차트 3종 + 텔레그램 v7 보고 (2026-07-13)
## 차트 = 시각화 전용(수치는 build_d3_dossier.R 실측값만 캡션 인용). 발송 = tg_agent_brief 단일 진입점.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/d3_dossier"
S <- readRDS(file.path(OUT, "_d3_series.rds"))
SUM <- fromJSON(file.path(OUT, "d3_summary.json"))
source("02_Infrastructure/telegram/tg_chart_pack.R")

## ── 차트 1: 수용력 시계열 (cap_1d, 로그, 억원) ────────────────────────────────
cp <- as.data.table(S$capm_pp)[order(Date)]; cv <- as.data.table(S$capm_v02)[order(Date)]
f1 <- file.path(OUT, "capacity_timeseries.png")
grDevices::png(f1, width=1000, height=560, res=110)
graphics::par(mar=c(4,4.6,3.2,1), family="")
yl <- range(c(cp$cap_1d, cv$cap_1d)/1e8, na.rm=TRUE)
plot(as.Date(cp$Date), cp$cap_1d/1e8, type="l", lwd=2.2, col="#1f77b4", log="y", ylim=yl,
     xlab="", ylab="1일 구축 가능 포트 규모 상한 (억원, 로그)",
     main="수용력 — 참여율 10%/일, 최소유동성 종목 기준 (실사 산술)")
lines(as.Date(cv$Date), cv$cap_1d/1e8, lwd=1.8, col="#d62728", lty=1)
abline(h=c(10,50,100), col="#999999", lty=3)
text(as.Date(cp$Date)[8], c(10,50,100)*1.15, c("10억","50억","100억"), cex=0.7, col="#777777")
graphics::legend("topleft", legend=c("P-pure W36_K20 (최근36m 중앙값 49억)","V02_EP (최근36m 중앙값 17억)"),
       col=c("#1f77b4","#d62728"), lwd=c(2.2,1.8), bty="n", cex=0.85)
mtext("2008-01~2026-04 · 5일 분할 구축 시 x5 (P-pure 최근36m 245억) · 게이트/판정 비바인딩", side=3, line=0.2, cex=0.75, col="#555555")
dev.off()

## ── 차트 2: 비용 시나리오 막대 (EW PORT_t, hline 2.95) ───────────────────────
cs <- rbind(as.data.table(S$CS_PP), as.data.table(S$CS_V02))
lab <- sprintf("%s %dbps", ifelse(cs$model=="Ppure_W36_K20","P-pure","V02_EP"), cs$bps_oneway)
f2 <- tg_chart_sweep(labels=lab, values=cs$ew_port_t, out_dir=OUT,
        title="비용 시나리오 — EW-유니버스 대비 초과수익 t값 (실사 산술)",
        value_label="EW PORT_t (NW lag-3)", hline=2.95, hline_label="졸업 기준선",
        highlight=c("P-pure 15bps"), filename="cost_scenarios.png")

## ── 차트 3: cap-tier 보유 비중 (R7 E2 실측 재인용) ───────────────────────────
tb <- as.data.table(read_parquet("outputs/ramp/r7_ewbasis_e2_captier_bymonth_20260712.parquet"))
tb[, Date := as.Date(Date)]
wds <- dcast(tb, Date ~ tier, value.var="weight_share", fill=0)[order(Date)]
for(cc in c("MEGA","MID","OTHER")) if(!cc %in% names(wds)) wds[[cc]] <- 0
f3 <- file.path(OUT, "captier_weights.png")
grDevices::png(f3, width=1000, height=560, res=110)
graphics::par(mar=c(4,4.4,3.2,1), family="")
d <- wds$Date
plot(d, rep(1,length(d)), type="n", ylim=c(0,1), xlab="", ylab="보유 비중",
     main="P-pure 보유의 시총 tier 구성 (R7 E2 실측)")
y0 <- rep(0, length(d)); cols <- c(OTHER="#1f77b4", MID="#ff7f0e", MEGA="#2ca02c")
for(cc in c("OTHER","MID","MEGA")){
  y1 <- y0 + wds[[cc]]
  polygon(c(d, rev(d)), c(y1, rev(y0)), col=grDevices::adjustcolor(cols[[cc]], 0.75), border=NA)
  y0 <- y1
}
graphics::legend("bottomleft", legend=c("OTHER(시총 31위 밖, 평균 90.6%)","MID(11~30위, 6.0%)","MEGA(top10, 3.4%)"),
       fill=grDevices::adjustcolor(cols[c("OTHER","MID","MEGA")],0.75), border=NA, bty="n", cex=0.8, bg="white")
mtext("소형 국소화 = 캐파 제약·cap-w 미달의 공통 원인 · metric_type=canonical_screen_diag", side=3, line=0.2, cex=0.75, col="#555555")
dev.off()

cat("charts:", f1, "\n", f2, "\n", f3, "\n")

## ── 텔레그램 v7 (결정 요청 재료 — 판정 평문 명시) ─────────────────────────────
source("02_Infrastructure/telegram/telegram_notify.R")
pp <- SUM$ppure; ve <- SUM$v02ep
res <- tg_agent_brief(
  agent = "Q-Lead",
  title = "D3 결정 재료 — 벤치-상대 배포 실사 완료",
  sections = list(
    list(type="summary", emoji="📌",
         body="자본 배정도 북 변경도 아닙니다 — 도훈 결정을 요청드리는 재료입니다. R6 P-pure와 V02_EP를 '시장 동일가중 평균 대비' 별도 트랙으로 굴릴지에 대한 수용력·비용·간섭 실사를 마쳤습니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
         items=c("대상: 시장평균 대비로는 강하지만(t 3.92) 대형주 지수 대비로는 기준 미달(t 2.61)인 소형주 쏠림 전략입니다",
                 "질문: 이걸 기존 운용과 별개의 작은 트랙으로 담을 가치가 있는가입니다",
                 "실사: 소형주라 얼마까지 담을 수 있는지(수용력), 거래비용이 더 들면 버티는지, 기존 운용과 겹치는지를 쟀습니다",
                 "결과: 소액(수억~수십억)에선 수용력·비용 모두 견딥니다. 다만 기존 북에 보태면 오히려 효율이 줄어드는 건 그대로입니다")),
    list(type="kv", emoji="📊", heading="P-pure W36_K20 (220개월 실측)",
         kv=list("EW 초과수익 t" = "3.92 (cap-w 2.61)",
                 "수용력(1일구축, 최근3년)" = "중앙값 49억",
                 "5일 분할 구축 시" = "245억",
                 "비용 한계선" = "편도 46bps까지 t 2.95 유지",
                 "월 리밸 소요(50억 가정)" = "0.7일",
                 "기존 북과 수익 상관" = "0.32 (R8 실측 · 종목 중첩은 미보존=미측정)")),
    list(type="kv", emoji="📉", heading="V02_EP (256개월 실측)",
         kv=list("EW 초과수익 t" = "3.57 (cap-w 2.05)",
                 "수용력(1일구축, 최근3년)" = "중앙값 17억",
                 "EW 과적합 지표(oos)" = "0.47 — 밴드 하한 0.5 미달",
                 "P-pure와 보유 중첩" = "32.5% (active 상관 0.34)")),
    list(type="bullet", emoji="🚩", heading="정직 캐비앗",
         items=c("EW-자격은 밴드-조건부(oos 0.51)이고 최근 구간 신호 감쇠(t 4.2→1.7→1.5)가 있습니다",
                 "북에 섞으면 한계 기여 음수(ΔIR -0.005) — '별도 트랙'으로만 의미가 있습니다",
                 "보유 90.6%가 시총 31위 밖 소형주 — 스프레드가 편도 46bps를 넘으면 우위 소멸",
                 "V02_EP는 이 측정틀에서 밴드 자격조차 미달 — 독립 트랙 근거 약함")),
    list(type="bullet", emoji="➡️", heading="결정 옵션 (아침 15분)",
         items=c("A안 실계좌 소액 트랙(1~3억): 수용력·비용 여유 큼. 전제=실현 슬리피지 월간 실측",
                 "B안 페이퍼 트래킹 6개월(권고): 비용 0으로 EW-알파 실재·감쇠 여부 라이브 판별",
                 "C안 보류: e3 음수·소형 국소화 근거. 비-return 패널(R9) 이후 재평가",
                 "권고 1줄: B안 — P-pure 단독(V02_EP는 중첩·oos 미달로 흡수), 실자본은 보류"))
  ),
  charts = c(f1, f2, f3),
  as_of = "2026-07-13"
)
cat("tg ok:", isTRUE(res$ok), "\n")
