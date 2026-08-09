#!/usr/bin/env Rscript
# =============================================================================
# p3_rho_control.R — 상태-조건부 지속성 rho 의 정체 확인 (바의 분모를 확정)
#
# p2 에서 내 split-half rho 가 P0 §5 와 불일치했다 (FLAT: 내 +0.042 vs P0 -0.436).
# 원인 후보를 코드로 확정하고, rho 를 바의 분모로 쓰기 전에 3가지를 검사한다.
#
#  R1. 재현 — P0g 의 split 규칙(전역 중점 h 로 자른 뒤 상태월 선별)을 정확히 복제.
#      내 규칙(상태월만 모아 반으로)과 비교 → 불일치 원인 확정 + rho 의 규칙 민감도.
#  R2. ★음성 대조 — 같은 크기의 **무작위 월 부분집합**에서도 같은 rho 가 나오는가.
#      나오면 "상태-조건부 지속성"은 상태와 무관한 일반 지속성이다.
#  R3. ★★기전/소관 — rho 가 **베타 지속성**이면 이 축은 멤버십이 아니라 노출 스케일이고
#      WT-D20260809_002 소관이다. beta 상관 + beta 잔차화 후 rho 붕괴 여부로 판정.
#
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p3_rho.log"), split = TRUE)
set.seed(20260809); T_THR <- 2.0

P <- readRDS(file.path(OUT, "p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0 <- as.matrix(sub[, ..scrap_ok]); cov_m <- colSums(is.finite(M0)); keep <- which(cov_m >= 253)
rows <- complete.cases(M0[, keep, drop=FALSE]); M <- M0[rows, keep, drop=FALSE]
bmv <- sub$bm[rows]; ymv <- sub$ym[rows]; n_all <- nrow(M)
C <- cor(M); diag(C) <- 0; hi <- which(C >= 0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par <- seq_len(ncol(M)); fnd <- function(x){while(par[x]!=x) x<-par[x]; x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-fnd(hi[r,1]);b<-fnd(hi[r,2]);if(a!=b) par[b]<-a}
  vapply(seq_len(ncol(M)), fnd, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; NU <- ncol(Mu)
dts <- as.Date(paste0(substr(ymv,1,4),"-",substr(ymv,5,6),"-01")); Xu <- xts(Mu, order.by=dts)
Abm <- Mu - matrix(bmv, n_all, NU)          # P0 정의: active vs benchmark
st  <- ifelse(bmv <= -0.05, "DOWN", ifelse(bmv >= 0.05, "SURGE", "FLAT"))
stL <- c(NA, st[-n_all])
h   <- floor(n_all/2)
cat(sprintf("=== [0] %d months, dedup %d, 전역 중점 h=%d ===\n", n_all, NU, h))

## ============================================ R1. 재현 + split 규칙 민감도
rho_of <- function(i1, i2) if (length(i1)<3 || length(i2)<3) NA_real_ else
  suppressWarnings(cor(colMeans(Abm[i1,,drop=FALSE]), colMeans(Abm[i2,,drop=FALSE]), method="spearman"))
cat("\n=== [R1] split 규칙별 상태-조건부 rho ===\n")
cat(sprintf("  %-6s %-28s %-28s\n", "state", "P0g규칙(전역중점)", "p2규칙(상태월 반분)"))
r1 <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  i1 <- which(st==s & seq_len(n_all) <= h); i2 <- which(st==s & seq_len(n_all) > h)
  rA <- rho_of(i1, i2)
  im <- which(st==s); j1 <- im[1:floor(length(im)/2)]; j2 <- setdiff(im, j1)
  rB <- rho_of(j1, j2)
  r1[[s]] <- list(state=s, n=length(im), rho_p0g=rA, n1_p0g=length(i1), n2_p0g=length(i2),
                  rho_evensplit=rB, n1_even=length(j1), n2_even=length(j2))
  cat(sprintf("  %-6s rho=%+.4f (n1=%2d,n2=%2d)      rho=%+.4f (n1=%2d,n2=%2d)\n",
              s, rA, length(i1), length(i2), rB, length(j1), length(j2)))
}
cat("  [P0 §5 보고값] DOWN +0.462 · SURGE +0.498 · FLAT -0.436\n")
cat("  ⇒ 재현되는 규칙이 P0 정본. 두 규칙 차이가 크면 rho 는 split 규칙에 취약하다.\n")

## ============================================ R2. 음성 대조 (무작위 월 부분집합)
cat("\n=== [R2] ★음성 대조 — 같은 크기 무작위 월 부분집합의 rho 분포 ===\n")
NPERM <- 400L
r2 <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  k <- sum(st==s)
  nullr <- replicate(NPERM, {
    idx <- sort(sample.int(n_all, k))
    rho_of(idx[idx <= h], idx[idx > h])
  })
  obs <- r1[[s]]$rho_p0g
  pv  <- mean(abs(nullr) >= abs(obs), na.rm=TRUE)
  r2[[s]] <- list(state=s, n=k, obs_rho=obs, null_mean=mean(nullr,na.rm=TRUE),
                  null_sd=sd(nullr,na.rm=TRUE),
                  null_q05=unname(quantile(nullr,.05,na.rm=TRUE)),
                  null_q95=unname(quantile(nullr,.95,na.rm=TRUE)), p_two_sided=pv)
  cat(sprintf("  %-6s 관측 rho=%+.4f | 무작위 동일크기: mean=%+.4f sd=%.3f [5%%,95%%]=[%+.3f,%+.3f]  p=%.3f\n",
              s, obs, mean(nullr,na.rm=TRUE), sd(nullr,na.rm=TRUE),
              quantile(nullr,.05,na.rm=TRUE), quantile(nullr,.95,na.rm=TRUE), pv))
}
cat("  ⇒ 무작위 부분집합도 같은 rho 를 내면 '상태-조건부'는 라벨일 뿐 정보가 아니다.\n")

## ============================================ R3. 기전 — 베타인가
cat("\n=== [R3] ★★기전 — 상태-조건부 순위가 베타 지속성인가 (소관 경계 판정) ===\n")
beta <- apply(Mu, 2, function(y) cov(y, bmv)/var(bmv))
cat(sprintf("  모듈 beta: median=%.3f  [5%%,95%%]=[%.3f,%.3f]\n",
            median(beta), quantile(beta,.05), quantile(beta,.95)))
r3 <- list(beta_median=median(beta))
for (s in c("DOWN","SURGE","FLAT")) {
  mu_s <- colMeans(Abm[st==s,,drop=FALSE])
  cb <- cor(beta, mu_s, method="spearman")
  cat(sprintf("  %-6s spearman(beta, 상태평균 active) = %+.4f   (R^2_rank=%.3f)\n", s, cb, cb^2))
  r3[[paste0("beta_corr_", s)]] <- cb
}
# beta 잔차화 후 rho 재계산
cat("\n  [beta 잔차화 후] 각 반기 상태평균을 beta 에 회귀시킨 잔차의 순위 지속성\n")
for (s in c("DOWN","SURGE","FLAT")) {
  i1 <- which(st==s & seq_len(n_all) <= h); i2 <- which(st==s & seq_len(n_all) > h)
  if (length(i1)<3 || length(i2)<3) next
  y1 <- colMeans(Abm[i1,,drop=FALSE]); y2 <- colMeans(Abm[i2,,drop=FALSE])
  e1 <- residuals(lm(y1 ~ beta)); e2 <- residuals(lm(y2 ~ beta))
  rr <- cor(e1, e2, method="spearman")
  cat(sprintf("    %-6s raw rho=%+.4f → beta-잔차 rho=%+.4f  (감쇠 %.0f%%)\n",
              s, r1[[s]]$rho_p0g, rr, 100*(1 - rr/max(r1[[s]]$rho_p0g, 1e-9))))
  r3[[paste0("resid_rho_", s)]] <- rr
}
cat("  ⇒ 잔차 rho 가 붕괴하면 상태-조건부 선택 = 베타 베팅 = **노출 스케일 축**\n")
cat("     (WT-D20260809_002 소관). 본 라운드(멤버십/배합)가 다룰 축이 아니다.\n")

## ====================== R4. PIT 지연라벨 스위치의 **최대 관대 상한** (roster 도 지연마스크 최적)
cat("\n=== [R4] PIT 지연라벨 스위치 — 전지식 상한 (roster 를 지연마스크에 직접 최적) ===\n")
base85 <- as.numeric(Return.portfolio(Xu, weights=rep(1/NU,NU), rebalance_on="months"))
Ab <- Mu - matrix(base85, n_all, NU)
W <- matrix(1/NU, n_all, NU)
info <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  m_use <- !is.na(stL) & stL == s
  selv  <- order(colMeans(Ab[m_use,,drop=FALSE]), decreasing=TRUE)[1:12]
  W[m_use, ] <- 0; W[m_use, selv] <- 1/12
  info[[s]] <- sum(m_use)
}
pr <- Return.portfolio(Xu, weights = xts(W, order.by=dts), rebalance_on = NA)
ix <- match(index(pr), dts); d <- as.numeric(pr) - base85[ix]
nn <- length(d); tt <- mean(d)/(sd(d)/sqrt(nn))
req <- T_THR*sd(d)/sqrt(nn)
cat(sprintf("  전지식 상한: 평균=%+.4f%%/m sd=%.3f%%/m n=%d  t=%+.2f  (필요 %.4f%%/m)\n",
            100*mean(d), 100*sd(d), nn, tt, 100*req))
# rho 로 할인한 기대 OOS (상태별 rho 는 P0g 규칙값 사용, 음수는 0)
disc <- rep(0, nn)
stL_ix <- stL[ix]
for (s in c("DOWN","SURGE","FLAT")) {
  m <- !is.na(stL_ix) & stL_ix == s
  disc[m] <- max(r1[[s]]$rho_p0g, 0)
}
exp_mean <- mean(d * disc)
cat(sprintf("  rho-할인 기대 OOS 평균=%+.4f%%/m → 기대 t=%+.2f  (필요/기대=%.2f)\n",
            100*exp_mean, exp_mean/(sd(d)/sqrt(nn)), req/max(exp_mean,1e-12)))
cat("  ★강도 불변성: arm 을 lambda 배로 약화하면 평균·sd 가 함께 lambda 배 → t 불변.\n")
cat("    ⇒ 이 t 는 arm 세기 조절로 넘을 수 없다. 바 판정은 강도-불변이다.\n")

write_json(list(meta=list(stage="prereg_rho_control", n_months=n_all, dedup=NU,
                          metric_type="diagnostic_precheck"),
  R1_split_rule=unname(r1), R2_negative_control=unname(r2), R3_beta_mechanism=r3,
  R4_pit_upper_bound=list(mean_pct=100*mean(d), sd_pct=100*sd(d), n=nn, t=tt,
                          required_pct=100*req, expected_oos_pct=100*exp_mean,
                          expected_t=exp_mean/(sd(d)/sqrt(nn)),
                          required_over_expected=req/max(exp_mean,1e-12),
                          bucket_n=info)),
  file.path(OUT,"prereg_rho_control.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[saved]\n"); sink()
