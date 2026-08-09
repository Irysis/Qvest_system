#!/usr/bin/env Rscript
# =============================================================================
# p4_final_bars.R — FQ-174 착수 전 검정력 바 최종 확정 + prereg_power_bars.json 발행
#
# p1 의 바는 **무작위** K=12 arm 의 diff sd 로 만들어 3.5배 느슨했다(p2 L1).
# 최종 바는 **선택된 arm**(상태/잔차 성과로 고른 로스터)의 diff sd 로 만든다.
#
# 추가 확정 사항:
#   · P0 §5 rho(+0.462/+0.498/-0.436) 출처 = p0e.log = **191 비-dedup**.
#     같은 창·같은 split 을 dedup 85 로 재산출하면 +0.7075/+0.7446/-0.0051 (p0g.log 일치).
#     브리프 규약("모든 통계는 dedup 85 위에서")상 dedup 값이 정본 → 바에는 dedup 값 사용.
#   · 잔차-직교 축(P0 §6, n(t>2)=16 vs 음성대조 q95=2.0)의 바를 추가 산출 — narrowing 후보.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p4_final.log"), split = TRUE)
set.seed(20260809); T_THR <- 2.0; K <- 12L

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0 <- as.matrix(sub[, ..scrap_ok]); cov_m <- colSums(is.finite(M0)); keep <- which(cov_m>=253)
rows <- complete.cases(M0[,keep,drop=FALSE]); M <- M0[rows,keep,drop=FALSE]
bmv <- sub$bm[rows]; ymv <- sub$ym[rows]; n_all <- nrow(M)
C <- cor(M); diag(C) <- 0; hi <- which(C>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); fnd<-function(x){while(par[x]!=x) x<-par[x]; x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-fnd(hi[r,1]);b<-fnd(hi[r,2]);if(a!=b) par[b]<-a}
  vapply(seq_len(ncol(M)),fnd,integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[,reps,drop=FALSE]; idu <- scrap_ok[keep][reps]; NU <- ncol(Mu)
dts <- as.Date(paste0(substr(ymv,1,4),"-",substr(ymv,5,6),"-01")); Xu <- xts(Mu, order.by=dts)
base85 <- as.numeric(Return.portfolio(Xu, weights=rep(1/NU,NU), rebalance_on="months"))
Ab <- Mu - matrix(base85, n_all, NU)      # arm 이 실제로 버는 축: base 대비
st <- ifelse(bmv<=-0.05,"DOWN",ifelse(bmv>=0.05,"SURGE","FLAT")); stL <- c(NA, st[-n_all])
h <- floor(n_all/2)
cat(sprintf("=== [0] %d months x dedup %d ; base=EW(85) ===\n", n_all, NU))

armK <- function(selv) as.numeric(Return.portfolio(Xu[,selv,drop=FALSE], rep(1/length(selv),length(selv)),
                                                   rebalance_on="months")) - base85
bar <- function(name, dvec, mask, ceil, rho, note="") {
  dd <- dvec[mask]; n <- sum(mask); s <- sd(dd)
  req <- T_THR*s/sqrt(n); exp_oos <- ceil*max(rho,0)
  list(arm_or_bucket=name, n=n, sd_monthly_pct=100*s,
       required_effect_pct_per_month=100*req, required_pct_per_year=100*req*12,
       book_annual_contrib_pct=100*req*12*n/n_all,
       is_ceiling_pct_per_month=100*ceil, persistence_rho=rho,
       expected_oos_pct_per_month=100*exp_oos,
       required_over_expected=if(exp_oos>0) req/exp_oos else Inf,
       plausible=(exp_oos>0 && req/exp_oos < 1), note=note, metric_type="diagnostic_precheck")
}

## ---- rho 정본 (dedup 85, p0g 규칙) — 브리프 규약대로 dedup 값 사용
Abm <- Mu - matrix(bmv, n_all, NU)
rho_state <- vapply(c("DOWN","SURGE","FLAT"), function(s){
  i1 <- which(st==s & seq_len(n_all)<=h); i2 <- which(st==s & seq_len(n_all)>h)
  cor(colMeans(Abm[i1,,drop=FALSE]), colMeans(Abm[i2,,drop=FALSE]), method="spearman")}, numeric(1))
cat("=== [1] rho 정본 (dedup 85) : "); print(round(rho_state,4))
cat("    [P0 §5 인용값 = 191 비-dedup: DOWN +0.462 SURGE +0.498 FLAT -0.436] — 브리프 규약상 위 dedup 값이 정본\n")

## ---- 무조건부 지속성 (음성 대조 arm)
ir1 <- colMeans(Ab[1:h,])/apply(Ab[1:h,],2,sd); a2 <- colMeans(Ab[(h+1):n_all,])
rho_uncond <- cor(ir1, a2, method="spearman")
cat(sprintf("=== [2] 무조건부 half-split spearman(IS IR, OOS act|base) = %+.4f  [P0 §4: -0.130 vs bm]\n", rho_uncond))

## ---- 바 1~4 : 선택된 arm sd 사용
BARS <- list()
selv_full <- order(colMeans(Ab), decreasing=TRUE)[1:K]
d_full <- armK(selv_full)
BARS[[1]] <- bar("FULL_254m_uncond", d_full, rep(TRUE,n_all), mean(d_full), rho_uncond,
                 "무조건부 trailing 선택 = P0 §4 음성대조 arm")
for (s in c("DOWN","SURGE","FLAT")) {
  m <- st==s; selv <- order(colMeans(Ab[m,,drop=FALSE]), decreasing=TRUE)[1:K]; d <- armK(selv)
  BARS[[length(BARS)+1]] <- bar(sprintf("%s_n%d_contemp", s, sum(m)), d, m, mean(d[m]), rho_state[[s]],
                                "동월 상태라벨 = PIT 불가(참고용 상한)")
}
## ---- PIT 판본 (t-1 라벨) — 실제로 굴릴 수 있는 유일한 형태
for (s in c("DOWN","SURGE","FLAT")) {
  m <- !is.na(stL) & stL==s; selv <- order(colMeans(Ab[m,,drop=FALSE]), decreasing=TRUE)[1:K]; d <- armK(selv)
  i1 <- which(m & seq_len(n_all)<=h); i2 <- which(m & seq_len(n_all)>h)
  rr <- cor(colMeans(Abm[i1,,drop=FALSE]), colMeans(Abm[i2,,drop=FALSE]), method="spearman")
  BARS[[length(BARS)+1]] <- bar(sprintf("lag1_%s_n%d_PIT", s, sum(m)), d, m, mean(d[m]), rr,
                                "PIT 적법 t-1 라벨")
}
cat("=== [3] 바 (선택된 arm sd 기준, paired |t|>=2.0) ===\n")
for (b in BARS) cat(sprintf("  %-22s n=%3d sd=%.3f%%/m 필요 %+.4f%%/m (연 %+.2f%%p) | 천장 %+.3f rho %+.3f 기대 %+.3f | 필요/기대=%s %s\n",
  b$arm_or_bucket,b$n,b$sd_monthly_pct,b$required_effect_pct_per_month,b$required_pct_per_year,
  b$is_ceiling_pct_per_month,b$persistence_rho,b$expected_oos_pct_per_month,
  ifelse(is.finite(b$required_over_expected),sprintf("%.2f",b$required_over_expected),"Inf"),
  ifelse(b$plausible,"OK","MISS")))

## ---- 바 5 : MDD 축 (block bootstrap, paired)
cat("=== [4] MDD 축 block bootstrap (block=12, rep=1000) ===\n")
mdd_of <- function(v) as.numeric(maxDrawdown(xts(v, order.by=dts)))
boot_idx <- function(n,blk){ s <- sample.int(n-blk+1L, ceiling(n/blk), replace=TRUE)
  as.integer(unlist(lapply(s,function(x) x:(x+blk-1L))))[1:n] }
set.seed(20260810); BI <- lapply(seq_len(1000L), function(i) boot_idx(n_all,12L))
cand <- lapply(seq_len(400L), function(i){ sv <- sample.int(NU,K)
  as.numeric(Return.portfolio(Xu[,sv,drop=FALSE], rep(1/K,K), rebalance_on="months")) })
cmdd <- vapply(cand, mdd_of, numeric(1))
mb_base <- vapply(BI, function(ix) mdd_of(base85[ix]), numeric(1))
ses <- vapply(list(cand[[order(cmdd)[200]]], cand[[which.min(cmdd)]]), function(v){
  sd(mb_base - vapply(BI, function(ix) mdd_of(v[ix]), numeric(1))) }, numeric(1))
se_med <- median(ses); req_mdd <- T_THR*se_med
ach <- mdd_of(base85) - min(cmdd)
cat(sprintf("  base MDD=%.1f%%  paired SE(ΔMDD)=%.2f%%p → 필요 ΔMDD=%.2f%%p\n",
            100*mdd_of(base85), 100*se_med, 100*req_mdd))
cat(sprintf("  400 draw IS-argmax 달성 ΔMDD=%+.2f%%p (t=%+.2f) | 잡음 max|t| 기대(400 trial)=%.2f → %s\n",
            100*ach, ach/se_med, qnorm(1-1/(2*400+2)),
            ifelse(ach/se_med > qnorm(1-1/(2*400+2)),"통과","선택잡음에 묻힘")))
mdd_bar <- list(arm_or_bucket="MDD_axis_blockboot", n=n_all, sd_monthly_pct=100*se_med,
  required_effect_pct_per_month=100*req_mdd, required_pct_per_year=100*req_mdd,
  unit_note="단위 %p (ΔMDD). 월수익률 아님",
  base_mdd_pct=100*mdd_of(base85), achievable_delta_pp=100*ach, achievable_t=ach/se_med,
  noise_max_t_400trials=qnorm(1-1/(2*400+2)),
  plausible=(ach/se_med > qnorm(1-1/(2*400+2))),
  note="달성치는 400회 IS-argmax 산물 — 다중검정 보정 후 판단", metric_type="diagnostic_precheck")
cat(sprintf("  %-22s → %s\n","MDD_axis", ifelse(mdd_bar$plausible,"OK","MISS")))

## ---- 바 6 (추가) : 잔차-직교 축 (P0 §6, narrowing 후보)
cat("=== [5] 잔차-직교 축 (P0 §6: n(t>2)=16 vs 음성대조 q95=2.0) ===\n")
resid_t <- function(Amat){ pcx <- prcomp(scale(Amat), center=FALSE); f <- as.numeric(pcx$x[,1]); f <- f/sd(f)
  apply(Amat, 2, function(y) summary(lm(y ~ f))$coefficients[1,3]) }
tv_all <- resid_t(Ab)
cat(sprintf("  전표본 잔차 t: n(t>+2)=%d / %d\n", sum(tv_all>2), NU))
selv_r <- order(tv_all, decreasing=TRUE)[1:K]; d_r <- armK(selv_r)
# 지속성: 전반 잔차-t 순위 → 후반 실현 active(base 대비)
t1 <- resid_t(Ab[1:h,,drop=FALSE]); a2b <- colMeans(Ab[(h+1):n_all,,drop=FALSE])
rho_r <- cor(t1, a2b, method="spearman")
se_rho <- 1/sqrt(NU-3)
cat(sprintf("  지속성 spearman(전반 잔차-t, 후반 실현 active) = %+.4f  (SE≈%.3f → t=%+.2f)\n",
            rho_r, se_rho, rho_r/se_rho))
cat(sprintf("  [대조] 무조건부 IR 순위의 같은 전이 = %+.4f\n", rho_uncond))
BARS[[length(BARS)+1]] <- bar("RESID_ORTHO_254m", d_r, rep(TRUE,n_all), mean(d_r), rho_r,
                              "PC1 잔차-알파 선택 (P0 §6 축). 전표본 PC1 = 상한")
b <- BARS[[length(BARS)]]
cat(sprintf("  %-22s n=%3d sd=%.3f%%/m 필요 %+.4f%%/m (연 %+.2f%%p) | 천장 %+.3f rho %+.3f 기대 %+.3f | 필요/기대=%s %s\n",
  b$arm_or_bucket,b$n,b$sd_monthly_pct,b$required_effect_pct_per_month,b$required_pct_per_year,
  b$is_ceiling_pct_per_month,b$persistence_rho,b$expected_oos_pct_per_month,
  ifelse(is.finite(b$required_over_expected),sprintf("%.2f",b$required_over_expected),"Inf"),
  ifelse(b$plausible,"OK","MISS")))

## ---- DSR / 다중검정
cat("=== [6] DSR/다중검정 — 본 라운드는 arm 다수 = sweep\n")
for (k in c(6,20,100)) cat(sprintf("    n_trials=%3d → Bonferroni t=%.2f (문턱 2.0 이 아님)\n", k, qnorm(1-0.05/(2*k))))

ALL <- c(BARS, list(mdd_bar))
write_json(list(
  meta=list(round="FQ-174 scrap ensemble", stage="prereg_power_bars_FINAL",
    window=sprintf("%s..%s", ymv[1], ymv[n_all]), n_months=n_all, universe_dedup=NU,
    base="EW(dedup 85) via Return.portfolio", t_threshold=T_THR, K=K,
    sd_basis="선택된 arm 의 paired diff sd (무작위 arm 아님 — p2 L1 수정)",
    contract="02_Infrastructure/contracts/required_effect_size.R 공식 동등, sd 실측 대체",
    metric_type="diagnostic_precheck"),
  reconciliation=list(
    p0_sec5_rho_source="p0e.log = 191 비-dedup 모듈",
    dedup85_rho=as.list(round(rho_state,4)),
    note="브리프 규약(dedup 85)상 dedup 값이 정본. DOWN/SURGE 는 P0 인용보다 높고 FLAT 반지속성은 소멸."),
  mechanism=list(
    beta_rank_corr_DOWN=-0.9751, beta_rank_corr_SURGE=0.9851,
    beta_residual_rho_DOWN=-0.4008, beta_residual_rho_SURGE=-0.7159,
    label_persistence=list(DOWN=0.133, SURGE=0.245, FLAT=0.718),
    label_base_rate=list(DOWN=31/254, SURGE=49/254, FLAT=174/254),
    verdict="상태-조건부 순위 = beta (rank R^2 0.95~0.97). beta 잔차화 시 지속성 음수. 노출 스케일 축 = WT-D20260809_002 소관"),
  bars=ALL), file.path(OUT,"prereg_power_bars.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[saved] prereg_power_bars.json\n"); sink()
