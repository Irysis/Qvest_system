#!/usr/bin/env Rscript
# =============================================================================
# p3_np1_pool_hygiene.R — NP-1: FR 풀 위생 규칙 A/B (지속-패자 배제 전처리)
#
# ── 사전등록 (결과 도착 전 확정 — 이 헤더가 사전등록 문서다) ──────────────
# 가설: FR 이 넓은 모듈 풀을 소비할 때, RCMA/배분 전에 "지속-패자 배제"를
#   전처리로 걸면 앙상블이 개선된다. 근거 = 폐지 풀 단독 실측(하위10 배제 t 3.21)
#   + 기전(지속되는 것은 승자가 아니라 패자 — IS 최악 4분위만 OOS 최악 유지).
# 검정 풀: **통합 풀** = 우량(A/B) + 폐지(C/F) 전체, dedup(corr>=0.999) 후.
#   폐지-단독이 아닌 통합 풀에서 재현돼야 FR 소비 규칙으로 승격 가능.
# arm (전량 보고, argmax 금지):
#   A0 base    = 통합 dedup 풀 EW (워크포워드 창 동일)
#   A1 hyg10   = 매월 trailing active 하위 10 배제 후 EW   (t-1 정보만)
#   A2 hyg20   = 하위 20 배제 후 EW
#   A3 hygQ1   = 하위 25% 배제 후 EW (풀 크기 비례 판본)
#   [음성 대조] A4 rand10 = 무작위 10 배제 (배제 행위 자체의 효과 분리, 5시드)
# 판정 규칙 (사전 고정):
#   주지표 = arm − base paired t_NW3 (basis = 앙상블 상대 — 풀 위생의 정당 basis, 자본 주장 아님)
#   부지표 = MDD/Calmar 변화, 절대 PORT_t(벤치 대비, 참고 병기 — 분모 혼동 방지)
#   승격 후보 조건: 주지표 t >= 2.0 ∧ 무작위 대조와 명확 분리 ∧ MDD 비악화
#   arm 3 + 시드 대조 → n_trials 소폭, Bonferroni 참고치 병기
# metric_type = diagnostic_precheck (FR 승격은 별도 사전등록 라운드에서)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p3_np1_hygiene.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

## ── 통합 풀 구축 (우량 + 폐지, dedup) ────────────────────────────────
P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN
all_ids <- intersect(c(P$scrap_ok, P$elite_ok), names(PAN))
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[, ..all_ids]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop=FALSE])
M <- M0[rowsc, keepc, drop=FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
ids <- all_ids[keepc]
Cc <- cor(M); diag(Cc) <- 0; hi <- which(Cc>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; idu <- ids[reps]
n <- nrow(Mu); K <- ncol(Mu); A <- Mu - matrix(bmw, n, K)
MPg <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)$modules
gr <- vapply(idu, function(s) as.character(MPg[[s]]$grade %||% NA), character(1))
`%||%` <- function(a,b) if (is.null(a)) b else a
gr <- vapply(idu, function(s) if (is.null(MPg[[s]]$grade)) NA_character_ else as.character(MPg[[s]]$grade), character(1))
cat(sprintf("[0] 통합 풀: %d months x %d dedup modules (A/B %d · C/F %d)\n",
            n, K, sum(gr %in% c("A","B")), sum(gr %in% c("C","F"))))

IS0 <- 60L; rows <- (IS0+1):n
run_port <- function(W) {
  pr <- Return.portfolio(xts(Mu[rows,,drop=FALSE], order.by=dtw[rows]),
        weights=xts(W[rows,,drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  as.numeric(pr)
}
pnw <- function(d){ m<-lm(d~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3,prewhite=FALSE))[1,1]) }
stats_of <- function(r) {
  prx <- xts(r, order.by=dtw[tail(rows,length(r))])
  ar <- table.AnnualizedReturns(prx, scale=12); md <- as.numeric(maxDrawdown(prx))
  bb <- bmw[tail(rows,length(r))]; act <- r - bb
  list(sharpe=as.numeric(ar[3,1]), cagr=as.numeric(ar[1,1]), mdd=md,
       calmar=as.numeric(ar[1,1])/md, port_t_abs=pnw(act))
}

## A0 base
ewW <- matrix(0, n, K); ewW[rows, ] <- 1/K
r0 <- run_port(ewW); s0 <- stats_of(r0)
cat(sprintf("\n[A0 base 통합EW] SR=%.3f CAGR=%.2f%% MDD=%.1f%% Calmar=%.3f | 절대 PORT_t=%+.3f\n",
            s0$sharpe, 100*s0$cagr, 100*s0$mdd, s0$calmar, s0$port_t_abs))

## 위생 arm 공통 빌더
hyg_W <- function(k_ex_fun) {
  W <- matrix(0, n, K)
  for (t in IS0:(n-1)) {
    sc <- colMeans(A[1:t, , drop=FALSE])
    kex <- k_ex_fun(K)
    keep <- order(sc)[(kex+1):K]
    W[t+1, keep] <- 1/length(keep)
  }
  W
}
R <- list(base=s0)
cat("\n[arm 전량] ------------------------------------------------------------\n")
for (nm in c("hyg10","hyg20","hygQ1")) {
  kfun <- switch(nm, hyg10=function(K) 10L, hyg20=function(K) 20L, hygQ1=function(K) as.integer(K*0.25))
  r1 <- run_port(hyg_W(kfun)); L <- min(length(r1), length(r0))
  d <- r1[1:L] - r0[1:L]; s1 <- stats_of(r1)
  cat(sprintf("  %-6s Δvs base %+.4f%%/m t_NW3=%+.3f | SR=%.3f MDD=%.1f%% Calmar=%.3f | 절대 PORT_t=%+.3f\n",
              nm, 100*mean(d), pnw(d), s1$sharpe, 100*s1$mdd, s1$calmar, s1$port_t_abs))
  R[[nm]] <- c(s1, list(delta_pm=mean(d), t_vs_base=pnw(d)))
}
## 음성 대조: 무작위 10 배제 x 5시드
cat("\n[음성 대조 — 무작위 10 배제, 5시드]\n")
ts_r <- c()
for (sd_ in 1:5) {
  set.seed(3000+sd_)
  W <- matrix(0, n, K)
  for (t in IS0:(n-1)) { keep <- setdiff(seq_len(K), sample(K, 10)); W[t+1, keep] <- 1/length(keep) }
  r1 <- run_port(W); L <- min(length(r1), length(r0))
  ts_r <- c(ts_r, pnw(r1[1:L]-r0[1:L]))
}
cat(sprintf("  rand10 t 5시드: [%s] median=%+.3f\n", paste(sprintf("%+.2f", ts_r), collapse=", "), median(ts_r)))
R$rand10 <- list(t_seeds=as.list(ts_r), median=median(ts_r))

## 배제 대상의 정체 진단 — 위생이 실질적으로 무엇을 자르는가
cat("\n[진단] 마지막 시점 하위 20 의 등급 구성:\n")
sc_last <- colMeans(A)
bot20 <- order(sc_last)[1:20]
print(table(gr[bot20], useNA="ifany"))
cat(sprintf("  하위 20 중 폐지(C|F) 비율 = %.0f%%\n", 100*mean(gr[bot20] %in% c("C","F"), na.rm=TRUE)))

## 판정 (사전등록 규칙 적용)
cat("\n[판정 — 사전등록 규칙: t>=2 AND 무작위 분리 AND MDD 비악화]\n")
verdict <- list()
for (nm in c("hyg10","hyg20","hygQ1")) {
  z <- R[[nm]]
  ok_t <- z$t_vs_base >= 2.0
  ok_sep <- z$t_vs_base > max(unlist(R$rand10$t_seeds)) + 0.5
  ok_mdd <- z$mdd <= s0$mdd + 0.005
  v <- if (ok_t && ok_sep && ok_mdd) "PROMOTE_CANDIDATE" else "NEGATIVE"
  cat(sprintf("  %-6s t=%.3f(%s) sep=%s mdd=%s → %s\n", nm, z$t_vs_base,
              ifelse(ok_t,"ok","x"), ifelse(ok_sep,"ok","x"), ifelse(ok_mdd,"ok","x"), v))
  verdict[[nm]] <- v
}
cat("  ※ arm 3개 Bonferroni 참고 문턱 t≈2.39 — PROMOTE 후보는 이 값 병기.\n")
R$verdict <- verdict
R$meta <- list(metric_type="diagnostic_precheck",
               basis="ensemble-relative (풀 위생의 정당 basis — 자본 주장 아님. 절대 PORT_t 는 참고 병기)",
               pool=sprintf("통합 dedup %d (A/B %d + C/F %d)", K, sum(gr %in% c("A","B")), sum(gr %in% c("C","F"))),
               prereg="스크립트 헤더 = 사전등록 (arm/판정규칙 결과 도착 전 고정)")
write_json(R, file.path(OUT,"p3_np1_hygiene.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
