## WT-D20260822_007 (FQ-246 NP1) P3 — PART B: 실현 가능 하드 선택 (오라클 없음)
## ★유일하게 α̂ 를 낼 수 있는 부분. 선택 기준은 전부 **성과-비파생** + PIT-safe(anchor ≤ m).
## 판정 순서: ①전이 게이트(기준이 실현 IC 서열을 아는가) → ②성과. FQ-246 규약 승계.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
W002 <- "stage_artifacts/WT-D20260822_002"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months; icm <- PB$icm
K <- A4$K; TOPN <- A4$TOPN; NM <- length(months)
PC <- readRDS(file.path(OUT,"p1c_parity.rds")); c0 <- PC$a_uni
PA <- readRDS(file.path(OUT,"p2_partA.rds")); HEADROOM <- PA$HEADROOM
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
ALLA <- sort(unique(pan$anchor))
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
p0 <- readRDS(file.path(W002,"p0_returns.rds")); bench_parent <- as.data.table(p0$bench)[, .(Date, BM_Ret)]

Zl <- lapply(seq_along(months), function(m) {
  d <- panh[anchor == as.Date(months[m])]
  list(Z = as.matrix(d[, ..(A4$sel_rank[[months[m]]])]), tick = as.character(d$Ticker)) })
build_from_W <- function(W) rbindlist(lapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; w <- W[m, ]
  Wm <- matrix(w, nrow=nrow(Z), ncol=K, byrow=TRUE); Wm[!is.finite(Z)] <- 0
  Z0 <- Z; Z0[!is.finite(Z0)] <- 0; den <- rowSums(Wm)
  data.table(Date=as.Date(months[m]), Ticker=Zl[[m]]$tick,
             score=ifelse(den>0, rowSums(Z0*Wm)/den, NA_real_))[is.finite(score)] }))
runbt <- function(s, id, bench = A4$bench_dt, dual = FALSE) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[, .(Date,Ticker,score)], A4$returns_dt, bench, top_n=TOPN,
    cost_bps_oneway=15, run_id=id, strategy_id=id, diag_dual_basis=dual) }
actof <- function(b) as.data.table(b$period_returns)[, ret_net - benchmark_ret]
paired <- function(x, lab, neff=NA_real_) { d <- x - c0; t <- .nw_t_mean(d, lag=3L)
  ann <- mean(d)*12*100; se <- abs(ann/t)
  data.table(arm=lab, n_eff=neff, ann_pct=ann, t_nw3=t, se_ann_pct=se,
             ci95_lo=ann-1.96*se, ci95_hi=ann+1.96*se, recovery=ann/HEADROOM,
             ar1_diff=as.numeric(acf(d, lag.max=1, plot=FALSE)$acf[2])) }

cat("=== B-1) 선택 기준 3종 산출 (성과-비파생 · PIT-safe) ===\n")
CRIT <- array(NA_real_, dim=c(NM, K, 3),
              dimnames=list(NULL, NULL, c("centrality","stability","breadth")))
for (m in seq_along(months)) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; Z <- Zl[[m]]$Z; tick <- Zl[[m]]$tick
  ## ① 중복도(centrality): 당월 횡단면에서 팩터 k 가 나머지와 얼마나 겹치나
  cm <- suppressWarnings(cor(Z, method="spearman", use="pairwise.complete.obs"))
  cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE)*(K/(K-1))
  CRIT[m, , "centrality"] <- cen
  ## ② 지속성(stability): anchor m 과 anchor m-1 의 횡단면 순위 상관 (둘 다 <= m)
  i <- match(as.Date(nm), ALLA)
  if (!is.na(i) && i > 1L) {
    prv <- pan[anchor == ALLA[i-1L]]
    idx <- match(tick, as.character(prv$Ticker))
    for (k in seq_len(K)) { a <- Z[, k]; b <- prv[[fs[k]]][idx]
      ok <- is.finite(a) & is.finite(b)
      CRIT[m, k, "stability"] <- if (sum(ok) >= 30L) cor(rank(a[ok]), rank(b[ok])) else NA_real_ } }
  ## ③ 꼬리 분리도(breadth): 상위 TOPN 평균 z 가 횡단면 평균에서 몇 sd 떨어져 있나
  for (k in seq_len(K)) { v <- Z[, k]; ok <- is.finite(v)
    if (sum(ok) >= TOPN + 10L) { s <- sd(v[ok]); vt <- sort(v[ok], decreasing=TRUE)[seq_len(TOPN)]
      CRIT[m, k, "breadth"] <- if (s > 0) (mean(vt) - mean(v[ok]))/s else NA_real_ } }
}
for (cn in dimnames(CRIT)[[3]]) cat(sprintf("  %-11s finite %4d/%d  mean %+7.4f  월내 sd 평균 %.4f\n",
  cn, sum(is.finite(CRIT[,,cn])), NM*K, mean(CRIT[,,cn], na.rm=TRUE),
  mean(apply(CRIT[,,cn], 1, sd, na.rm=TRUE), na.rm=TRUE)))

cat("\n=== B-2) ★전이 게이트 — 관측 기준이 실현 IC 서열을 아는가 (성과 판정 전) ===\n")
cat("    (실현 IC 는 진단용 look-ahead. 게이트 통과 실패 = '기준이 무지' 이지 '하드 선택 불가' 아님)\n")
TG <- rbindlist(lapply(dimnames(CRIT)[[3]], function(cn) {
  rho <- vapply(seq_len(NM), function(m) { a <- CRIT[m,,cn]; b <- icm[m,]
    ok <- is.finite(a) & is.finite(b)
    if (sum(ok) < 3L || sd(a[ok]) == 0) return(NA_real_); cor(rank(a[ok]), rank(b[ok])) }, 0)
  rr <- rho[is.finite(rho)]
  data.table(criterion=cn, n_months=length(rr), mean_rho=mean(rr),
             t_nw3=.nw_t_mean(rr, lag=3L), sd_rho=sd(rr)) }))
## 성과-파생 대조: sel_rank 순위 (1 = 상위)
rho_r1 <- vapply(seq_len(NM), function(m) cor(rank(-seq_len(K)), rank(icm[m,])), 0)
TG <- rbind(TG, data.table(criterion="sel_rank_position(perf-derived ctrl)", n_months=NM,
  mean_rho=mean(rho_r1), t_nw3=.nw_t_mean(rho_r1, lag=3L), sd_rho=sd(rho_r1)))
TG[, mde_rho_95 := 1.96*sd_rho/sqrt(n_months)]
TG[, passed := abs(t_nw3) >= 1.5]
TG[, label := fifelse(passed, "TRANSPORT_ESTABLISHED",
              fifelse(abs(mean_rho) + mde_rho_95 < 0.15, "POWERED_NULL_CRITERION_UNINFORMATIVE",
                      "UNRESOLVED_UNDERPOWERED"))]
print(TG[, .(criterion, n=n_months, mean_rho=round(mean_rho,4), t=round(t_nw3,3),
             mde_rho95=round(mde_rho_95,4), passed, label)])

cat("\n=== B-3) 실현 가능 하드 선택 arm 측정 ===\n")
W_argsel <- function(M, J=1L, decreasing=TRUE) t(vapply(seq_len(NM), function(m) {
  x <- M[m, ]; w <- rep(0, K)
  if (all(!is.finite(x))) { w[] <- 1/K; return(w) }
  x[!is.finite(x)] <- if (decreasing) -Inf else Inf
  w[order(x, decreasing=decreasing)[seq_len(J)]] <- 1/J; w }, numeric(K)))
Mrank <- matrix(rep(K:1, each=NM), nrow=NM)   # sel_rank 위치 1 -> 가장 큰 값
SPECB <- list(
  B1a_INDEP_MIN_top1   = W_argsel(CRIT[,,"centrality"], 1L, decreasing=FALSE),
  B1b_INDEP_MAX_top1   = W_argsel(CRIT[,,"centrality"], 1L, decreasing=TRUE),
  B2a_STABLE_MAX_top1  = W_argsel(CRIT[,,"stability"],  1L, decreasing=TRUE),
  B2b_STABLE_MIN_top1  = W_argsel(CRIT[,,"stability"],  1L, decreasing=FALSE),
  B3a_BREADTH_MAX_top1 = W_argsel(CRIT[,,"breadth"],    1L, decreasing=TRUE),
  B3b_BREADTH_MIN_top1 = W_argsel(CRIT[,,"breadth"],    1L, decreasing=FALSE),
  B0_SELRANK1_top1     = W_argsel(Mrank, 1L, decreasing=TRUE),
  B1a_INDEP_MIN_top2   = W_argsel(CRIT[,,"centrality"], 2L, decreasing=FALSE),
  B2a_STABLE_MAX_top2  = W_argsel(CRIT[,,"stability"],  2L, decreasing=TRUE),
  B3a_BREADTH_MAX_top2 = W_argsel(CRIT[,,"breadth"],    2L, decreasing=TRUE))
RESB <- lapply(names(SPECB), function(a) { b <- runbt(build_from_W(SPECB[[a]]), paste0("NP1_",a))
  list(act=actof(b), port_t=b$portfolio_alpha_t_nw_lag3, to=b$turnover_annual) })
names(RESB) <- names(SPECB)
PB2 <- rbindlist(lapply(names(SPECB), function(a)
  paired(RESB[[a]]$act, a, mean(apply(SPECB[[a]], 1, function(w) 1/sum(w^2))))))
PB2[, port_t := vapply(names(SPECB), function(a) RESB[[a]]$port_t, 0)]
PB2[, turnover := vapply(names(SPECB), function(a) RESB[[a]]$to, 0)]
## 형태 귀무분포(Part A) 대비 백분위 — 정보량의 정직한 척도
nd <- list(top1 = PA$NULLD$N_top1, top2 = PA$NULLD$N_top2)
PB2[, null_ref := fifelse(grepl("top2$", arm), "top2", "top1")]
PB2[, perm_pctile := mapply(function(v, r) mean(nd[[r]] < v), ann_pct, null_ref)]
PB2[, p_one_sided := 1 - perm_pctile]
PB2[, vs_null_mean_pp := ann_pct - mapply(function(r) mean(nd[[r]]), null_ref)]
print(PB2[, .(arm, n_eff=round(n_eff,2), ann_pct=round(ann_pct,3), t=round(t_nw3,3),
              ci95=paste0("[",round(ci95_lo,2),", ",round(ci95_hi,2),"]"),
              port_t=round(port_t,4), pctile=round(perm_pctile,3), TO=round(turnover,2))])

cat("\n=== B-4) 검정력: 관측 위치 vs MDE (자기-diff 퇴화 배제) ===\n")
MATERIAL <- readRDS(file.path(OUT,"p1_probe.rds"))$P6$MATERIAL
se_bar <- c(top1 = sd(nd$top1), top2 = sd(nd$top2))
POW <- data.table(null_ref=names(se_bar), null_sd_ann_pct=as.numeric(se_bar),
                  mde95_ann_pct = 1.96*as.numeric(se_bar),
                  MATERIAL_ann_pct = MATERIAL)
POW[, material_detectable := MATERIAL >= mde95_ann_pct]
print(POW)
cat("  ★바 산출 원천 = 순열 arm 분포(처치 없음)이므로 자기-diff 퇴화(implied_t_own=2.0)를 피한다.\n")
PB2[, label := fifelse(t_nw3 >= 2, "EFFECT_POSITIVE",
              fifelse(t_nw3 <= -2, "EFFECT_NEGATIVE",
              fifelse(ci95_hi < MATERIAL, "POWERED_NULL_NO_MATERIAL_EFFECT", "UNRESOLVED_UNDERPOWERED")))]
print(PB2[, .(arm, label, pctile=round(perm_pctile,3))])

cat("\n=== B-5) basis 3종 + AX-001 v2 (사전등록 primary 2종) ===\n")
prim <- c("B2a_STABLE_MAX_top1","B3a_BREADTH_MAX_top1")
BASB <- rbindlist(lapply(prim, function(a) {
  b1 <- runbt(build_from_W(SPECB[[a]]), paste0("NP1Bb_",a), A4$bench_dt, dual=TRUE)
  b2 <- runbt(build_from_W(SPECB[[a]]), paste0("NP1Bp_",a), bench_parent)
  data.table(arm=a, port_t_IKS200=b1$portfolio_alpha_t_nw_lag3,
             port_t_parent_capw=b2$portfolio_alpha_t_nw_lag3,
             port_t_EW_universe=b1$diag_ew_universe$portfolio_alpha_t_nw_lag3,
             post2017_t_EWuni=b1$diag_ew_universe$post2017_t_nw_lag3,
             ir=b1$information_ratio) }))
print(BASB[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
bmm <- A4$bench_dt[Date %in% PC$dates][order(Date)]
bad <- bmm$BM_Ret < quantile(bmm$BM_Ret, 0.20)
AX <- rbindlist(lapply(prim, function(a) { d <- RESB[[a]]$act - c0
  data.table(arm=a, crisis_alpha_ann=mean(d[bad])*12*100, normal_alpha_ann=mean(d[!bad])*12*100,
             bad_months=sum(bad), normal_months=sum(!bad)) }))
print(AX[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])

cat("\n=== B-6) advisory 배터리 (rank-IC 계열 — 게이트 아님) ===\n")
adv <- function(sc) { s <- merge(sc, panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)],
    by=c("Date","Ticker"))
  ic <- s[, { ok <- is.finite(score) & is.finite(fwd)
    if (sum(ok) < 30L) NA_real_ else cor(rank(score[ok]), rank(fwd[ok])) }, by=Date]$V1
  ic <- ic[is.finite(ic)]
  list(rank_ic=mean(ic), icir=mean(ic)/sd(ic), ic_t_nw3=.nw_t_mean(ic, lag=3L)) }
ADV <- rbindlist(lapply(c("B2a_STABLE_MAX_top1","B3a_BREADTH_MAX_top1","B1a_INDEP_MIN_top1"), function(a) {
  x <- adv(build_from_W(SPECB[[a]])); data.table(arm=a, rank_ic=x$rank_ic, icir=x$icir, ic_t_nw3=x$ic_t_nw3) }))
x0 <- adv(build_from_W(matrix(1/K, NM, K)))
ADV <- rbind(data.table(arm="C0_uniform", rank_ic=x0$rank_ic, icir=x0$icir, ic_t_nw3=x0$ic_t_nw3), ADV)
print(ADV[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])

saveRDS(list(CRIT=CRIT, TG=TG, PB2=PB2, POW=POW, BASB=BASB, AX=AX, ADV=ADV,
             SPECB=SPECB, RESB=RESB, MATERIAL=MATERIAL), file.path(OUT,"p3_partB.rds"))
cat("\n[saved] p3_partB.rds\nOK\n")
