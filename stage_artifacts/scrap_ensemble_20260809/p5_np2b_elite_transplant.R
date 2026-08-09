#!/usr/bin/env Rscript
# =============================================================================
# p5_np2b_elite_transplant.R — NP-2b: 연속 beta-틸트를 알파 풀에 이식
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# 배경: NP-2 가 폐지+우량 통합 풀에서 inverse-beta² 비중의 MDD −8.9%p(유의)를 확립.
#   단 그 풀은 벤치 대비 알파 ~0 이라 위험 "모양"만 개선. 본 검정 = 알파 있는 풀
#   (FR_001 module_pool 12 — legacy QEPM grade A)에서 같은 비중이 실질 기여로 전이되는가.
# arm (NP-2 와 동일 고정 — 신규 탐색 없음): A0 EW / A1 inv-vol / A2 inv-beta / A3 inv-beta²
#   전부 trailing-36m 추정(t-1 정보만), 월 리밸, w>=0, Σw=1. RCMA 국면 배분과 별개의
#   정적 비중 A/B (FR_001 자체와의 비교는 참고 병기 — 배분정책이 다르므로 동렬 비교 아님).
# 판정 (사전 고정):
#   ①주지표 = Calmar 개선 ∧ MDD 개선 유의(바 = 본 풀 블록 부트스트랩 재산출, b=12 rep=500,
#     paired SE x 2) ∧ 절대 PORT_t 비훼손(base 대비 -0.3 이내)
#   ②전이 판정: 통과 시 "위험 형태 개선이 알파 재료에서 실질 기여로 전이" 확립 →
#     FR Track2 dispatcher 비중 계열 승격 검토(별도 사전등록 라운드). 실패 시 config-scoped.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p5_np2b.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

## FR_001 풀 로드
FRR <- fromJSON(file.path(PROJ,"06_Registry/factor_rotation_registry.json"), simplifyVector = FALSE)
pool_fr1 <- unlist(FRR$factor_rotations$FR_001$module_pool)
cat(sprintf("[0] FR_001 module_pool = %d modules\n", length(pool_fr1)))

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN
miss <- setdiff(pool_fr1, names(PAN))
if (length(miss)) cat(sprintf("  ★패널 미수록 %d건 제외: %s\n", length(miss), paste(miss, collapse=", ")))
pool <- intersect(pool_fr1, names(PAN))
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[, ..pool])
## NA-인지: 완전 커버 요구 대신 결측 소수 모듈은 로그 후 유지 (p2_adv: STR_1393 1m·STR_1469 6m 결측)
covm <- colSums(is.finite(M0))
cat("  coverage: "); print(setNames(covm, abbreviate(pool, 18)))
rowsc <- rowSums(is.finite(M0)) >= max(3, ncol(M0) - 2)   # 월 단위: 결측 2개 이하 허용
Mu <- M0[rowsc, , drop=FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
n <- nrow(Mu); K <- ncol(Mu)
cat(sprintf("[0b] 패널: %d months x %d modules (%s..%s)\n", n, K,
            format(min(dtw),"%Y-%m"), format(max(dtw),"%Y-%m")))

IS0 <- 60L; rows <- (IS0+1):n
H <- 36L
trail_beta <- matrix(NA_real_, n, K); trail_vol <- matrix(NA_real_, n, K)
for (t in IS0:(n-1)) {
  win <- max(1, t-H+1):t; bv <- bmw[win]
  trail_beta[t+1, ] <- apply(Mu[win, , drop=FALSE], 2, function(y) {
    ok <- is.finite(y); if (sum(ok) < 24) return(NA_real_)
    as.numeric(coef(lm(y[ok] ~ bv[ok]))[2]) })
  trail_vol[t+1, ] <- apply(Mu[win, , drop=FALSE], 2, sd, na.rm=TRUE)
}
mkW <- function(score_fun) {
  W <- matrix(0, n, K)
  for (t in rows) {
    s <- score_fun(trail_beta[t, ], trail_vol[t, ])
    avail <- is.finite(Mu[t, ]) & is.finite(s) & s > 0
    if (sum(avail) < 3) next
    s[!avail] <- 0; W[t, ] <- s / sum(s)
  }
  W
}
ARMS <- list(
  A0_EW       = function(b, v) rep(1, K),
  A1_invvol   = function(b, v) 1 / pmax(v, quantile(v, .05, na.rm=TRUE)),
  A2_invbeta  = function(b, v) 1 / pmax(b, 0.2),
  A3_invbeta2 = function(b, v) 1 / pmax(b, 0.2)^2
)
run_port <- function(W) {
  Mz <- Mu[rows, , drop=FALSE]; Mz[!is.finite(Mz)] <- 0
  pr <- Return.portfolio(xts(Mz, order.by=dtw[rows]),
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
       beta=as.numeric(coef(lm(r ~ bb))[2]), series=r)
}

res <- list(); r0 <- NULL
cat("\n[arm 전량] ------------------------------------------------------------\n")
for (nm in names(ARMS)) {
  r1 <- run_port(mkW(ARMS[[nm]])); s <- stat(r1)
  if (nm == "A0_EW") { r0 <- r1
    cat(sprintf("  %-11s CAGR=%6.2f%% SR=%.3f MDD=%5.1f%% Calmar=%.3f beta=%.3f PORT_t=%+.3f  [base]\n",
                nm, 100*s$cagr, s$sharpe, 100*s$mdd, s$calmar, s$beta, s$port_t))
  } else {
    L <- min(length(r1), length(r0)); d <- r1[1:L]-r0[1:L]
    s$t_vs_base <- pnw(d)
    cat(sprintf("  %-11s CAGR=%6.2f%% SR=%.3f MDD=%5.1f%% Calmar=%.3f beta=%.3f PORT_t=%+.3f | ΔMDD=%+.1f%%p Δt=%+.3f\n",
                nm, 100*s$cagr, s$sharpe, 100*s$mdd, s$calmar, s$beta, s$port_t,
                100*(s$mdd - res$A0_EW$mdd), s$t_vs_base))
  }
  res[[nm]] <- s
}

## MDD 유의 바 재산출 (본 풀, 최선 arm vs base paired 블록 부트스트랩 b=12 rep=500)
cat("\n[MDD 유의 바 — 본 풀 재산출] ------------------------------------------\n")
best_nm <- names(ARMS)[-1][which.max(sapply(names(ARMS)[-1], function(z) {
  b0 <- res$A0_EW; 100*(b0$mdd - res[[z]]$mdd) })) ]
rb <- res[[best_nm]]$series; r00 <- res$A0_EW$series
L <- min(length(rb), length(r00)); blk <- 12L
set.seed(20260809)
dd <- replicate(500, {
  starts <- sample(seq_len(L - blk + 1), ceiling(L/blk), replace=TRUE)
  ix <- head(unlist(lapply(starts, function(s2) s2:(s2+blk-1))), L)
  m1 <- as.numeric(maxDrawdown(xts(rb[ix],  order.by=dtw[rows][1:L])))
  m0 <- as.numeric(maxDrawdown(xts(r00[ix], order.by=dtw[rows][1:L])))
  m0 - m1
})
se <- sd(dd); bar <- 2*se
obs <- res$A0_EW$mdd - res[[best_nm]]$mdd
cat(sprintf("  best=%s  관측 ΔMDD=%+.2f%%p  paired SE=%.2f%%p  유의 바(2SE)=%.2f%%p → %s\n",
            best_nm, 100*obs, 100*se, 100*bar, ifelse(obs >= bar, "유의", "미달")))

cat("\n[판정 — 사전등록 규칙: Calmar 개선 ∧ MDD 유의 ∧ PORT_t 비훼손(-0.3 이내)] ---\n")
b0 <- res$A0_EW
for (nm in setdiff(names(res), "A0_EW")) {
  z <- res[[nm]]
  ok_cal <- z$calmar > b0$calmar
  ok_mdd <- (b0$mdd - z$mdd) >= bar
  ok_pt  <- z$port_t >= b0$port_t - 0.3
  v <- if (ok_cal && ok_mdd && ok_pt) "TRANSFER_CONFIRMED" else "CONFIG_SCOPED"
  cat(sprintf("  %-11s Calmar %s · MDD%s · PORT_t %s(%.2f vs %.2f) → %s\n", nm,
              ifelse(ok_cal,"개선","악화"), ifelse(ok_mdd," 유의"," 미달"),
              ifelse(ok_pt,"보존","훼손"), z$port_t, b0$port_t, v))
}
cat(sprintf("\n  [참고] FR_001 등재치(국면 배분, 동렬 비교 아님): SR 1.097 · PORT_t 1.296 · Calmar 0.732\n"))

strip <- function(x){ x$series <- NULL; x }
write_json(c(lapply(res, strip),
             list(meta=list(metric_type="diagnostic_precheck", pool=pool, n_months=n,
                            mdd_bar_pp=100*bar, best_arm=best_nm,
                            prereg="스크립트 헤더 = 사전등록"))),
           file.path(OUT,"p5_np2b.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
