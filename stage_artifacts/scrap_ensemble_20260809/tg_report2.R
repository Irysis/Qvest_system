#!/usr/bin/env Rscript
# =============================================================================
# tg_report2.R — FQ-174 워크포워드 회수율 결과 텔레그램 보고 (v7 SOT, 원칙 9 차트 의무)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
CH <- file.path(OUT, "charts"); dir.create(CH, showWarnings = FALSE, recursive = TRUE)

## ── 데이터 + WF K=30 시계열 재산출 ────────────────────────────────────
P <- readRDS(file.path(OUT, "p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0; hi <- which(C >= 0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu)
A <- Mu - matrix(bmw, n, K); IS0 <- 60L; KK <- 30L

W <- matrix(0, n, K)
for (t in IS0:(n-1)) {
  Ais <- A[1:t, , drop=FALSE]
  pc <- prcomp(scale(Ais), center = FALSE); f1 <- as.numeric(pc$x[,1]); f1 <- f1/sd(f1)
  tv <- apply(Ais, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3])
  W[t+1, order(tv, decreasing = TRUE)[1:KK]] <- 1/KK
}
rows <- (IS0+1):n
pr <- Return.portfolio(xts(Mu[rows, , drop=FALSE], order.by=dtw[rows]),
                       weights=xts(W[rows, , drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
nn <- length(pr); rr <- tail(rows, nn)
ar <- table.AnnualizedReturns(pr, scale=12); mdd <- as.numeric(maxDrawdown(pr))
cat(sprintf("[실측] WF K=30  CAGR=%.2f%% SR=%.3f MDD=%.1f%% Calmar=%.3f (n=%d)\n",
            100*ar[1,1], ar[3,1], 100*mdd, ar[1,1]/mdd, nn))

## ── 차트 (표준 생성기 경유) ───────────────────────────────────────────
source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
PRDF <- data.frame(date = dtw[rr], ret_net = as.numeric(pr), benchmark_ret = bmw[rr])
p1 <- tg_chart_pack(PRDF, out_dir = CH, title = "폐지 풀 잔차-직교 선별 (워크포워드 K=30)",
                    metrics_note = sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f · 초과 t값 1.912",
                                           ar[3,1], 100*mdd, ar[1,1]/mdd),
                    prefix = "wf30_")
p2 <- tg_chart_sweep(
  labels = c("무작위 선별 K=30", "무작위 선별 K=10", "워크포워드 K=10", "워크포워드 K=20",
             "워크포워드 K=30", "완전예지 상한 K=30", "완전예지 상한 K=10"),
  values = c(-0.046, -0.124, 1.227, 1.310, 1.912, 3.326, 4.085),
  out_dir = CH, title = "초과성과 t값 — 선별은 작동하나 문턱 미달",
  value_label = "기준선 대비 짝지은 t값 (NW lag-3)", hline = 2.0, hline_label = "문턱 2.0",
  highlight = "워크포워드 K=30", filename = "wf_tstat.png")
p3 <- tg_chart_sweep(
  labels = c("K=10", "K=20", "K=30"), values = c(27.2, 26.5, 33.2),
  out_dir = CH, title = "회수율 — 완전예지 상한의 몇 %를 실제로 가져왔나",
  value_label = "회수율 (%)", hline = 100, hline_label = "상한 100%",
  highlight = "K=30", filename = "wf_recovery.png")
charts <- c(p1, p2, p3)
cat("[charts]", length(charts), "장\n")

## ── 발송 ──────────────────────────────────────────────────────────────
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "폐지 전략 재활용 — 시장과 무관한 알파를 골라내니 3분의 1이 넘어왔습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "버려둔 전략 85개에서 시장 무관 알파를 선별 — 완전예지 상한의 33%를 실제 회수했습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 등급 미달 전략 중 시장 흐름과 무관하게 버는 것만 골라 담았습니다",
           "방법: 과거 데이터만 보고 매달 다시 고르는 방식으로 194개월 모의 운용했습니다",
           "결과: 미리 정답을 아는 경우의 3분의 1을 실제로 회수했습니다",
           "대조: 아무렇게나 고른 경우는 t값 -0.05 — 선별이 진짜 작동했습니다",
           "한계: 자본 투입 문턱에는 못 미쳤고 최대낙폭은 오히려 늘었습니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "재료"     = "폐지 195개 중 중복 제거 후 85개",
           "기준선"   = "샤프 0.659 · 최대낙폭 40.5% · 칼마 0.258",
           "선별결과" = sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f", ar[3,1], 100*mdd, ar[1,1]/mdd),
           "초과성과" = "월 +0.102% · t값 1.912 (문턱 2.0)",
           "회수율"   = "완전예지 상한의 33.2% · 회전율 33%")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "t값 1.912 로 문턱 2.0 미달 · 칼마 0.272 는 합격선 0.64 의 절반 이하",
           "최대낙폭은 40.5% 에서 42.3% 로 오히려 늘었습니다",
           "상한의 70% 는 선별 잡음이 먹습니다 — 거래비용 탓이 아닙니다",
           "국면 타이밍 축은 정체가 베타로 밝혀져 다른 연구 소관으로 넘겼습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "종목 수를 늘릴수록 t값이 오르는 추세라 40·50 을 사전등록 후 확인합니다",
           "회수 실패분이 추정 오차인지 신호 감쇠인지 분리합니다",
           "베타 축이 따로 처리되면 수익과 낙폭의 맞교환이 풀립니다",
           "판정: 현재 자본 배정 없음 — 참고용 스크린 등급입니다"))
  ),
  charts = charts,
  footer = "📚 FQ-174 · p0l_wf_residual.json · metric_type=diagnostic_precheck"
)
cat("[tg] 발송 완료\n")
