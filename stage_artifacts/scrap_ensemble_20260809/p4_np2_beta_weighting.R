#!/usr/bin/env Rscript
# =============================================================================
# p4_np2_beta_weighting.R — NP-2: beta-인지 연속 비중 배분 (weighting 층 A/B)
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# 층 구분 (이 라운드의 3층 지도):
#   멤버십(선택)   = 실측 완료 — 천장 2.04, MDD 레버 없음 (FR_002)
#   노출 스케일    = WT-D20260809_002 소관 (침범 금지)
#   ★비중(연속 가중) = 본 검정 — 미검증 칸. FQ-058 은 분산-최적화 계열(MVO/MinVar/
#     MinCDaR/MinCVaR)만 쟀고 inverse-beta 비중은 미포함. 모듈 beta 산포(0.34~0.96)
#     + 지속성(rho 0.564, t 15.4)이 재료.
# 가설: 선택은 이산이라 저beta 로 몰면 breadth 붕괴로 수익이 죽었다(저beta-20 Calmar
#   0.192 < base 0.258). 연속 비중은 breadth 를 유지하며 기울이므로 Calmar 교환비가
#   나을 수 있다.
# arm (전량 보고): A0 EW(base) · A1 inverse-vol(dispatcher RP 앵커 동형) ·
#   A2 inverse-beta(w∝1/β_trailing) · A3 inverse-beta²(강틸트) · A4 β-cap 혼합(β>0.85 반비중)
#   전부 trailing 36m 추정(t-1 정보만), 월 리밸, Σw=1, w≥0.
# 판정 (사전 고정, 도훈 관심축 = MDD):
#   주지표 = Calmar (base 대비 개선 여부) + MDD Δ.
#   MDD 유의 바 = 4.49%p (p1 블록 부트스트랩 실측 — 이보다 작은 개선은 '방향'만 기록).
#   수익 paired t_NW3 병기(basis = 앙상블 상대). 절대 PORT_t 참고 병기.
#   선례 대조: 저beta-20 **선택**(Calmar 0.192)보다 나으면 "연속>이산" 기전 확인.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p4_np2_weighting.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

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
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu)
IS0 <- 60L; rows <- (IS0+1):n
cat(sprintf("[0] 통합 풀 %d months x %d dedup modules | OOS %d개월\n", n, K, length(rows)))

## trailing 추정치 (t 시점까지 36m — t+1 적용)
H <- 36L
trail_beta <- matrix(NA_real_, n, K); trail_vol <- matrix(NA_real_, n, K)
for (t in IS0:(n-1)) {
  win <- max(1, t-H+1):t
  bv <- bmw[win]
  trail_beta[t+1, ] <- apply(Mu[win, , drop=FALSE], 2, function(y) as.numeric(coef(lm(y ~ bv))[2]))
  trail_vol[t+1, ]  <- apply(Mu[win, , drop=FALSE], 2, sd)
}
mkW <- function(score_fun) {
  W <- matrix(0, n, K)
  for (t in rows) {
    s <- score_fun(trail_beta[t, ], trail_vol[t, ])
    s[!is.finite(s) | s < 0] <- 0
    if (sum(s) <= 0) next
    W[t, ] <- s / sum(s)
  }
  W
}
ARMS <- list(
  A0_EW       = function(b, v) rep(1, K),
  A1_invvol   = function(b, v) 1 / pmax(v, quantile(v, .05, na.rm=TRUE)),
  A2_invbeta  = function(b, v) 1 / pmax(b, 0.2),
  A3_invbeta2 = function(b, v) 1 / pmax(b, 0.2)^2,
  A4_betacap  = function(b, v) ifelse(b > 0.85, 0.5, 1)
)
run_port <- function(W) {
  pr <- Return.portfolio(xts(Mu[rows,,drop=FALSE], order.by=dtw[rows]),
        weights=xts(W[rows,,drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  as.numeric(pr)
}
pnw <- function(d){ m<-lm(d~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3,prewhite=FALSE))[1,1]) }
stat <- function(r) {
  prx <- xts(r, order.by=dtw[tail(rows,length(r))])
  ar <- table.AnnualizedReturns(prx, scale=12); md <- as.numeric(maxDrawdown(prx))
  bb <- bmw[tail(rows,length(r))]
  list(sharpe=as.numeric(ar[3,1]), cagr=as.numeric(ar[1,1]), mdd=md,
       calmar=as.numeric(ar[1,1])/md, port_t=pnw(r-bb),
       beta=as.numeric(coef(lm(r ~ bb))[2]))
}

res <- list(); r0 <- NULL
cat("\n[arm 전량 — trailing 36m 추정, t-1 정보만] --------------------------------\n")
for (nm in names(ARMS)) {
  r1 <- run_port(mkW(ARMS[[nm]]))
  s <- stat(r1)
  if (nm == "A0_EW") { r0 <- r1
    cat(sprintf("  %-11s CAGR=%6.2f%% SR=%.3f MDD=%5.1f%% Calmar=%.3f beta=%.3f PORT_t=%+.3f  [base]\n",
                nm, 100*s$cagr, s$sharpe, 100*s$mdd, s$calmar, s$beta, s$port_t))
  } else {
    L <- min(length(r1), length(r0)); d <- r1[1:L]-r0[1:L]
    s$t_vs_base <- pnw(d); s$delta_pm <- mean(d)
    cat(sprintf("  %-11s CAGR=%6.2f%% SR=%.3f MDD=%5.1f%% Calmar=%.3f beta=%.3f PORT_t=%+.3f | ΔMDD=%+.1f%%p Δt=%+.3f\n",
                nm, 100*s$cagr, s$sharpe, 100*s$mdd, s$calmar, s$beta, s$port_t,
                100*(s$mdd - res$A0_EW$mdd), s$t_vs_base))
  }
  res[[nm]] <- s
}

cat("\n[판정 — 사전등록 규칙] -----------------------------------------------------\n")
b0 <- res$A0_EW
cat(sprintf("  base: MDD %.1f%% Calmar %.3f | MDD 유의 바 = 4.49%%p | 이산-선택 선례 저beta-20 Calmar 0.192\n",
            100*b0$mdd, b0$calmar))
for (nm in setdiff(names(res), "A0_EW")) {
  z <- res[[nm]]
  dmdd <- 100*(b0$mdd - z$mdd)
  cal_ok <- z$calmar > b0$calmar
  mdd_sig <- dmdd >= 4.49
  beats_discrete <- z$calmar > 0.192
  cat(sprintf("  %-11s Calmar %s(%.3f vs %.3f) · MDD %+.1f%%p(%s) · 이산선택 대비 %s → %s\n",
              nm, ifelse(cal_ok,"개선","악화"), z$calmar, b0$calmar, dmdd,
              ifelse(mdd_sig,"유의","방향만"), ifelse(beats_discrete,"우위","열위"),
              if (cal_ok && mdd_sig) "PROMOTE_CANDIDATE" else if (cal_ok) "DIRECTIONAL_ONLY" else "NEGATIVE"))
}
cat("\n  ※ 연속>이산 기전: 어느 arm 이든 Calmar 가 저beta-20 선택(0.192)을 넘으면 확인.\n")
write_json(c(res, list(meta=list(metric_type="diagnostic_precheck",
  prereg="스크립트 헤더 = 사전등록", mdd_sig_bar_pp=4.49,
  discrete_precedent=list(lowbeta20_calmar=0.192)))),
  file.path(OUT,"p4_np2_weighting.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
