#!/usr/bin/env Rscript
# tg_report3.R — FQ-174 라운드 최종 보고 (정정 포함, v7 SOT · 원칙 9 차트 의무)
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
CH <- file.path(OUT, "charts"); dir.create(CH, showWarnings=FALSE, recursive=TRUE)

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN<-P$PAN; scrap_ok<-P$scrap_ok
sub <- PAN[ym>=P$start_ym & is.finite(bm)]; setorder(sub,ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[,..scrap_ok]); keepc <- which(colSums(is.finite(M0))>=253)
rowsc <- complete.cases(M0[,keepc,drop=FALSE]); M<-M0[rowsc,keepc,drop=FALSE]
bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C<-cor(M);diag(C)<-0;hi<-which(C>=0.999,arr.ind=TRUE);hi<-hi[hi[,1]<hi[,2],,drop=FALSE]
comp<-local({par<-seq_len(ncol(M));f<-function(x){while(par[x]!=x)x<-par[x];x}
 if(nrow(hi))for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a};vapply(seq_len(ncol(M)),f,integer(1))})
reps<-vapply(unique(comp),function(g)which(comp==g)[1],integer(1))
Mu<-M[,reps,drop=FALSE]; n<-nrow(Mu); K<-ncol(Mu); A<-Mu-matrix(bmw,n,K)
IS0<-60L; rows<-(IS0+1):n; KK<-10L
W <- matrix(0,n,K)
for (t in IS0:(n-1)) W[t+1, order(colMeans(A[1:t,,drop=FALSE]), decreasing=TRUE)[1:KK]] <- 1/KK
pr <- Return.portfolio(xts(Mu[rows,,drop=FALSE],order.by=dtw[rows]),
                       weights=xts(W[rows,,drop=FALSE],order.by=dtw[rows]), rebalance_on=NA)
nn<-length(pr); rr<-tail(rows,nn)
ar<-table.AnnualizedReturns(pr,scale=12); mdd<-as.numeric(maxDrawdown(pr))
cat(sprintf("[실측] 무조건부평균 K=10  CAGR=%.2f%% SR=%.3f MDD=%.1f%% Calmar=%.3f (n=%d)\n",
            100*ar[1,1], ar[3,1], 100*mdd, ar[1,1]/mdd, nn))

source(file.path(PROJ,"02_Infrastructure/telegram/tg_chart_pack.R"))
PRDF <- data.frame(date=dtw[rr], ret_net=as.numeric(pr), benchmark_ret=bmw[rr])
p1 <- tg_chart_pack(PRDF, out_dir=CH, title="폐지 풀 무조건부 성과 선별 (워크포워드 10종)",
       metrics_note=sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f · 초과 t값 2.598",
                            ar[3,1], 100*mdd, ar[1,1]/mdd), prefix="uncond10_")
p2 <- tg_chart_sweep(
  labels=c("잔차-직교 10종","잔차-직교 30종","무조건부 IR 50종","무조건부 평균 10종",
           "무조건부 평균 30종","무조건부 평균 50종"),
  values=c(1.227,1.912,2.723,2.598,2.620,2.856),
  out_dir=CH, title="선별 규칙 비교 — 가장 밋밋한 규칙이 이겼다",
  value_label="기준선 대비 짝지은 t값 (NW lag-3)", hline=2.94,
  hline_label="다중검정 문턱 2.94", highlight="무조건부 평균 50종", filename="rule_compare.png")
p3 <- tg_chart_sweep(
  labels=c("국면 라벨 예측력","최대낙폭 개선","선별 회수율","무조건부 선별 t값"),
  values=c(9.0, 64.6, 33.2, 97.1),
  out_dir=CH, title="네 축의 문턱 도달률 — 하나만 문턱 근처",
  value_label="필요 수준 대비 달성 비율 (%)", hline=100, hline_label="문턱 100%",
  highlight="무조건부 선별 t값", filename="axis_attainment.png")
charts <- c(p1,p2,p3)
cat("[charts]", length(charts), "\n")

source(file.path(PROJ,"02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent="Q-Lead",
  title="폐지 전략 재활용 최종 — 화려한 방법은 전부 지고 가장 밋밋한 규칙만 남았습니다",
  sections=list(
    list(type="summary", emoji="📌",
         body="국면 타이밍도 직교성도 실패하고, '과거에 잘한 것 고르기'만 문턱 근처까지 왔습니다."),

    list(type="bullet", emoji="📖", heading="쉬운 설명",
         items=c(
           "시도: 버려둔 전략 85개를 다시 쓸 수 있는지 세 가지 방식으로 검증했습니다",
           "실패1: 국면 따라 갈아타기 — 정체가 그냥 시장 민감도였습니다",
           "실패2: 시장과 무관한 것만 고르기 — 단순 방식보다 오히려 못했습니다",
           "성공: 과거 성적 좋은 것 고르기 — t값 2.86 까지 올라왔습니다",
           "의미: 문턱 2.94 직전이라 아직 실제 돈은 넣지 않습니다")),

    list(type="kv", emoji="📊", heading="핵심 수치",
         kv=list(
           "재료"     = "폐지 195개 중 중복 제거 후 85개",
           "기준선"   = "샤프 0.659 · 최대낙폭 40.5% · 칼마 0.258",
           "최선안"   = sprintf("초과 월 +0.327%% · t값 2.598 · 칼마 %.3f", ar[1,1]/mdd),
           "최고t값"  = "무조건부 평균 50종 t값 2.856 (문턱 2.94)",
           "머신러닝" = "미실행 — 학습 대상 축이 시장 민감도로 판명")),

    list(type="bullet", emoji="🚩", heading="주의",
         items=c(
           "국면 라벨에 다음 달 예측력이 없습니다 (0.133 대 기저 0.122)",
           "최대낙폭 개선은 필요 4.49%p 대비 실측 2.90%p 로 미달입니다",
           "낙폭을 낮추면 수익이 함께 죽어 칼마가 오히려 나빠집니다",
           "종목수 25종 제약 미충족이라 자본 심사 대상이 아닙니다",
           "제 측정 결함 4건을 라운드 중 검거해 수리했습니다")),

    list(type="bullet", emoji="➡️", heading="다음",
         items=c(
           "선별 잡음이 상한의 70% 를 먹으므로 축소추정으로 분산을 줄입니다",
           "머신러닝은 예측기가 아니라 축소추정기로 재배치합니다",
           "시장 민감도 축은 노출 조절 연구로 이관했습니다",
           "판정: 현재 자본 배정 없음 — 참고용 스크린 등급입니다"))
  ),
  charts=charts,
  footer="📚 FQ-174 · p0m_uncond_control.json · metric_type=diagnostic_precheck")
cat("[tg] 발송 완료\n")
