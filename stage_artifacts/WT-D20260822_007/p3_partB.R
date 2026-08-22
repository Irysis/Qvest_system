## WT-D20260822_007 (FQ-246 NP1) P3 — PART B: 실현 가능 하드 선택 (오라클 없음)
## ★유일하게 α̂ 를 낼 수 있는 부분. 선택 기준은 전부 **성과-비파생** + PIT-safe(당월 z 횡단면만).
## 판정 순서(사전등록): ①FC 전이 게이트(기준이 실현 IC 서열을 아는가) → ②FB 매개 이동 → ③성과.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
W002 <- "stage_artifacts/WT-D20260822_002"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months; icm <- PB$icm
K <- A4$K; TOPN <- A4$TOPN; NM <- length(months)
PC <- readRDS(file.path(OUT,"p1c_parity.rds")); c0 <- PC$a_uni
PA <- readRDS(file.path(OUT,"p2_partA.rds")); HEADROOM <- PA$HEADROOM
MATERIAL <- PB$P6$MATERIAL
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
ALLA <- sort(unique(pan$anchor))
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
p0 <- readRDS(file.path(W002,"p0_returns.rds")); bench_parent <- as.data.table(p0$bench)[, .(Date, BM_Ret)]

Zl <- lapply(seq_along(months), function(m) {
  fsm <- A4$sel_rank[[months[m]]]
  d <- panh[anchor == as.Date(months[m])]
  list(Z = as.matrix(d[, ..fsm]), tick = as.character(d$Ticker)) })
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

cat("=== B-1) 선택 기준 4종 (성과-비파생 · 당월 z 횡단면만 · PIT-safe) ===\n")
CN <- c("breadth","margin","centrality","stability")
CRIT <- array(NA_real_, dim=c(NM, K, length(CN)), dimnames=list(NULL,NULL,CN))
for (m in seq_along(months)) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; Z <- Zl[[m]]$Z; tick <- Zl[[m]]$tick
  cm <- suppressWarnings(cor(Z, method="spearman", use="pairwise.complete.obs"))
  CRIT[m, , "centrality"] <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE)*(K/(K-1))
  i <- match(as.Date(nm), ALLA)
  if (!is.na(i) && i > 1L) { prv <- pan[anchor == ALLA[i-1L]]
    idx <- match(tick, as.character(prv$Ticker))
    for (k in seq_len(K)) { a <- Z[,k]; b <- prv[[fs[k]]][idx]; ok <- is.finite(a) & is.finite(b)
      CRIT[m,k,"stability"] <- if (sum(ok) >= 30L) cor(rank(a[ok]), rank(b[ok])) else NA_real_ } }
  for (k in seq_len(K)) { v <- Z[,k]; ok <- is.finite(v)
    if (sum(ok) >= TOPN + 10L) { s <- sd(v[ok]); vs <- sort(v[ok], decreasing=TRUE)
      if (s > 0) { CRIT[m,k,"breadth"] <- (mean(vs[seq_len(TOPN)]) - mean(v[ok]))/s
                   CRIT[m,k,"margin"]  <- (vs[TOPN] - vs[TOPN+5L])/s } } }
}
for (cn in CN) cat(sprintf("  %-11s finite %4d/%d  mean %+7.4f  월내 sd 평균 %.4f\n",
  cn, sum(is.finite(CRIT[,,cn])), NM*K, mean(CRIT[,,cn], na.rm=TRUE),
  mean(apply(CRIT[,,cn], 1, sd, na.rm=TRUE), na.rm=TRUE)))

cat("\n=== B-2) ★FC 전이 게이트 — 기준이 실현 IC 서열을 아는가 (성과 판정 前) ===\n")
cat("    실현 IC = 진단용 정답지(look-ahead). 미통과 = '기준이 무지' 이지 '하드 선택 불가' 아님.\n")
argmax_of <- function(M, decreasing=TRUE) vapply(seq_len(NM), function(m) {
  x <- M[m,]; if (all(!is.finite(x))) return(NA_integer_)
  x[!is.finite(x)] <- if (decreasing) -Inf else Inf
  as.integer(order(x, decreasing=decreasing)[1]) }, 0L)
ic_best <- apply(icm, 1, which.max)
DIRS <- list(breadth_MAX=list("breadth",TRUE), margin_MAX=list("margin",TRUE),
             centrality_MIN=list("centrality",FALSE), stability_MAX=list("stability",TRUE),
             centrality_MAX=list("centrality",TRUE), breadth_MIN=list("breadth",FALSE),
             margin_MIN=list("margin",FALSE), stability_MIN=list("stability",FALSE))
TG <- rbindlist(lapply(names(DIRS), function(nmd) {
  cn <- DIRS[[nmd]][[1]]; dec <- DIRS[[nmd]][[2]]
  am <- argmax_of(CRIT[,,cn], dec); ok <- is.finite(am)
  hit <- mean(am[ok] == ic_best[ok])
  bt <- binom.test(sum(am[ok] == ic_best[ok]), sum(ok), p = 1/K, alternative="greater")
  rho <- vapply(seq_len(NM), function(m) { a <- CRIT[m,,cn]; b <- icm[m,]
    o2 <- is.finite(a) & is.finite(b)
    if (sum(o2) < 3L || sd(a[o2]) == 0) return(NA_real_); cor(rank(a[o2]), rank(b[o2])) }, 0)
  rr <- rho[is.finite(rho)]; if (!dec) rr <- -rr
  data.table(criterion=nmd, n_months=sum(ok), hit_rate=hit, hit_p_binom=bt$p.value,
             mean_rho_signed=mean(rr), rho_t_nw3=.nw_t_mean(rr, lag=3L),
             rho_mde95=1.96*sd(rr)/sqrt(length(rr))) }))
## 성과-파생 대조: sel_rank 위치 1
am_r1 <- rep(1L, NM)
TG <- rbind(TG, data.table(criterion="selrank1(perf-derived ctrl)", n_months=NM,
  hit_rate=mean(am_r1 == ic_best),
  hit_p_binom=binom.test(sum(am_r1 == ic_best), NM, p=1/K, alternative="greater")$p.value,
  mean_rho_signed=mean(vapply(seq_len(NM), function(m) cor(rank(-seq_len(K)), rank(icm[m,])), 0)),
  rho_t_nw3=.nw_t_mean(vapply(seq_len(NM), function(m) cor(rank(-seq_len(K)), rank(icm[m,])), 0), lag=3L),
  rho_mde95=NA_real_))
TG[, hit_excess_pp := (hit_rate - 1/K)*100]
TG[, passed := hit_p_binom < 0.05 | abs(rho_t_nw3) >= 1.5]
TG[, label := fifelse(passed, "TRANSPORT_ESTABLISHED",
              fifelse(abs(mean_rho_signed) + rho_mde95 < 0.15,
                      "POWERED_NULL_CRITERION_UNINFORMATIVE", "UNRESOLVED_UNDERPOWERED"))]
print(TG[, .(criterion, n=n_months, hit=round(hit_rate,4), excess_pp=round(hit_excess_pp,2),
             p_binom=signif(hit_p_binom,3), rho=round(mean_rho_signed,4),
             rho_t=round(rho_t_nw3,3), mde=round(rho_mde95,4), passed, label)])
cat(sprintf("\n  ★게이트 검정력: 적중률 이항 MDE(단측 5%%, n=%d, p0=0.2) = %.4f (= 우연 대비 +%.2f pp)\n",
  NM, qbinom(0.95, NM, 1/K)/NM, (qbinom(0.95, NM, 1/K)/NM - 0.2)*100))
cat(sprintf("  ★순위상관 게이트 MDE95 평균 = %.4f (rho 단위)\n", mean(TG$rho_mde95, na.rm=TRUE)))

cat("\n=== B-3) 실현 가능 하드 선택 arm 측정 ===\n")
W_argsel <- function(M, J=1L, decreasing=TRUE) t(vapply(seq_len(NM), function(m) {
  x <- M[m,]; w <- rep(0, K)
  if (all(!is.finite(x))) { w[] <- 1/K; return(w) }
  x[!is.finite(x)] <- if (decreasing) -Inf else Inf
  w[order(x, decreasing=decreasing)[seq_len(J)]] <- 1/J; w }, numeric(K)))
Mrank <- matrix(rep(K:1, each=NM), nrow=NM)
SPECB <- list(
  B3a_BREADTH_MAX_top1 = W_argsel(CRIT[,,"breadth"],    1L, TRUE),
  B5a_MARGIN_MAX_top1  = W_argsel(CRIT[,,"margin"],     1L, TRUE),
  B1a_INDEP_MIN_top1   = W_argsel(CRIT[,,"centrality"], 1L, FALSE),
  B4a_STABLE_MAX_top1  = W_argsel(CRIT[,,"stability"],  1L, TRUE),
  B3b_BREADTH_MIN_top1 = W_argsel(CRIT[,,"breadth"],    1L, FALSE),
  B5b_MARGIN_MIN_top1  = W_argsel(CRIT[,,"margin"],     1L, FALSE),
  B1b_INDEP_MAX_top1   = W_argsel(CRIT[,,"centrality"], 1L, TRUE),
  B4b_STABLE_MIN_top1  = W_argsel(CRIT[,,"stability"],  1L, FALSE),
  B0_SELRANK1_top1     = W_argsel(Mrank,                1L, TRUE),
  B3a_BREADTH_MAX_top2 = W_argsel(CRIT[,,"breadth"],    2L, TRUE),
  B5a_MARGIN_MAX_top2  = W_argsel(CRIT[,,"margin"],     2L, TRUE),
  B1a_INDEP_MIN_top2   = W_argsel(CRIT[,,"centrality"], 2L, FALSE),
  B4a_STABLE_MAX_top2  = W_argsel(CRIT[,,"stability"],  2L, TRUE))
SCB  <- lapply(SPECB, build_from_W)
RESB <- lapply(names(SPECB), function(a) { b <- runbt(SCB[[a]], paste0("NP1_",a))
  list(act=actof(b), port_t=b$portfolio_alpha_t_nw_lag3, to=b$turnover_annual, hold=b$holdings) })
names(RESB) <- names(SPECB)
PB2 <- rbindlist(lapply(names(SPECB), function(a)
  paired(RESB[[a]]$act, a, mean(apply(SPECB[[a]], 1, function(w) 1/sum(w^2))))))
PB2[, port_t := vapply(names(SPECB), function(a) RESB[[a]]$port_t, 0)]
PB2[, turnover := vapply(names(SPECB), function(a) RESB[[a]]$to, 0)]
nd <- list(top1 = PA$NULLD$N_top1, top2 = PA$NULLD$N_top2)
PB2[, null_ref := fifelse(grepl("top2$", arm), "top2", "top1")]
PB2[, perm_pctile := mapply(function(v, r) mean(nd[[r]] < v), ann_pct, null_ref)]
PB2[, vs_null_mean_pp := ann_pct - vapply(null_ref, function(r) mean(nd[[r]]), 0)]
PB2[, vs_null_sd := vs_null_mean_pp / vapply(null_ref, function(r) sd(nd[[r]]), 0)]
print(PB2[, .(arm, n_eff=round(n_eff,2), ann_pct=round(ann_pct,3), t=round(t_nw3,3),
              ci95=paste0("[",round(ci95_lo,2),", ",round(ci95_hi,2),"]"), port_t=round(port_t,4),
              pctile=round(perm_pctile,3), vs_null_sd=round(vs_null_sd,2), TO=round(turnover,2))])

cat("\n=== B-4) ★FB 매개 게이트 — top-25 멤버십이 실제로 움직였나 (Jaccard vs C0) ===\n")
top_of <- function(sc) sc[, .(tk = list(Ticker[order(-score)][seq_len(min(TOPN,.N))])), by=Date]
sc0 <- build_from_W(matrix(1/K, NM, K)); T0 <- top_of(sc0)
JAC <- rbindlist(lapply(names(SPECB), function(a) { Ta <- top_of(SCB[[a]])
  mm <- merge(T0, Ta, by="Date");
  j <- mapply(function(x,y) length(intersect(x,y))/length(union(x,y)), mm$tk.x, mm$tk.y)
  data.table(arm=a, jaccard_median=median(j), jaccard_mean=mean(j),
             names_changed_median=median(vapply(seq_along(j), function(i)
               TOPN - length(intersect(mm$tk.x[[i]], mm$tk.y[[i]])), 0))) }))
JAC[, mediator := fifelse(jaccard_median >= 0.90, "TREATMENT_INERT",
             fifelse(jaccard_median <= 0.79, "TREATMENT_EFFECTIVE", "PARTIAL"))]
print(JAC)

cat("\n=== B-5) 검정력 선언 (순열 분포 바 — 자기-diff 퇴화 배제) ===\n")
POW <- rbindlist(lapply(names(nd), function(r) data.table(null_ref=r,
  null_mean_ann_pct=mean(nd[[r]]), null_sd_ann_pct=sd(nd[[r]]),
  mde95_vs_null_ann_pct=1.96*sd(nd[[r]]), MATERIAL_ann_pct=MATERIAL,
  material_detectable = MATERIAL - mean(nd[[r]]) >= 1.96*sd(nd[[r]]),
  breakeven_vs_C0_pp = -mean(nd[[r]]))))
print(POW)
oracle_info_top1 <- PA$DEC[form=="O_top1_EW", info_value_ann]
cat(sprintf("\n  ★하드 선택의 손익분기 — 정보 없는 one-hot 은 C0 대비 %+.3f %%p/yr (형태 비용).\n",
            mean(nd$top1)))
cat(sprintf("    오라클 정보 가치(one-hot) = %+.3f %%p/yr ⇒ 실현 기준이 손익분기(C0 동률)에 도달하려면\n",
            oracle_info_top1))
cat(sprintf("    오라클 정보의 %.1f%% 를, MATERIAL(%.4f %%p/yr) 도달엔 %.1f%% 를 포착해야 한다.\n",
            -mean(nd$top1)/oracle_info_top1*100, MATERIAL,
            (MATERIAL - mean(nd$top1))/oracle_info_top1*100))
PB2[, label := fifelse(t_nw3 >= 2 & perm_pctile >= 0.95, "EFFECT_POSITIVE",
              fifelse(t_nw3 <= -2, "EFFECT_NEGATIVE",
              fifelse(ci95_hi < MATERIAL, "POWERED_NULL_NO_MATERIAL_EFFECT", "UNRESOLVED_UNDERPOWERED")))]
PB2 <- merge(PB2, JAC[, .(arm, jaccard_median, mediator)], by="arm", sort=FALSE)
PB2[mediator == "TREATMENT_INERT" & !label %in% c("EFFECT_POSITIVE","EFFECT_NEGATIVE"),
    label := "TREATMENT_INERT"]
print(PB2[, .(arm, label, ann_pct=round(ann_pct,3), pctile=round(perm_pctile,3),
              jac=round(jaccard_median,3), ar1=round(ar1_diff,4))])

saveRDS(list(CRIT=CRIT, TG=TG, PB2=PB2, JAC=JAC, POW=POW, SPECB=SPECB, SCB=SCB, RESB=RESB,
             MATERIAL=MATERIAL, oracle_info_top1=oracle_info_top1, sc0=sc0),
        file.path(OUT,"p3_partB_ckpt.rds"))
cat("[ckpt] p3_partB_ckpt.rds saved\n")

cat("\n=== B-5b) 회전율 채널 진단 — arm 성과가 IC 정보가 아니라 비용에서 오는가 ===\n")
TOCH <- PB2[, .(arm, ann_pct, turnover, perm_pctile)]
cat(sprintf("  cor(turnover, ann_pct) across %d arms = %+.4f (Pearson) / %+.4f (Spearman)\n",
    nrow(TOCH), cor(TOCH$turnover, TOCH$ann_pct), cor(rank(TOCH$turnover), rank(TOCH$ann_pct))))
cat(sprintf("  cor(turnover, perm_pctile) = %+.4f\n", cor(TOCH$turnover, TOCH$perm_pctile)))
cat("  ★FC 게이트가 정보 0 을 powered 로 확정했으므로, 순열 분포 대비 상위 백분위는\n")
cat("    '어느 팩터가 맞나' 가 아니라 '어느 팩터가 싼가' 로 설명되는지 확인한다.\n")

cat("\n=== B-6) basis 3종 + AX-001 v2 (사전등록 co-primary 3종) ===\n")
prim <- c("B3a_BREADTH_MAX_top1","B5a_MARGIN_MAX_top1","B1a_INDEP_MIN_top1")
BASB <- rbindlist(lapply(prim, function(a) {
  b1 <- runbt(SCB[[a]], paste0("NP1Bb_",a), A4$bench_dt, dual=TRUE)
  b2 <- runbt(SCB[[a]], paste0("NP1Bp_",a), bench_parent)
  data.table(arm=a, port_t_IKS200=b1$portfolio_alpha_t_nw_lag3,
             port_t_parent_capw=b2$portfolio_alpha_t_nw_lag3,
             port_t_EW_universe=b1$diag_ew_universe$portfolio_alpha_t_nw_lag3,
             post2017_t_EWuni=b1$diag_ew_universe$post2017_t_nw_lag3, ir=b1$information_ratio) }))
b0 <- runbt(sc0, "NP1Bb_C0", A4$bench_dt, dual=TRUE); b0p <- runbt(sc0, "NP1Bp_C0", bench_parent)
BASB <- rbind(data.table(arm="C0_uniform", port_t_IKS200=b0$portfolio_alpha_t_nw_lag3,
  port_t_parent_capw=b0p$portfolio_alpha_t_nw_lag3,
  port_t_EW_universe=b0$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  post2017_t_EWuni=b0$diag_ew_universe$post2017_t_nw_lag3, ir=b0$information_ratio), BASB)
print(BASB[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
bmm <- A4$bench_dt[Date %in% PC$dates][order(Date)]
bad <- bmm$BM_Ret < quantile(bmm$BM_Ret, 0.20)
AX <- rbindlist(lapply(prim, function(a) { d <- RESB[[a]]$act - c0
  data.table(arm=a, crisis_alpha_ann=mean(d[bad])*12*100, normal_alpha_ann=mean(d[!bad])*12*100,
             crisis_t=.nw_t_mean(d[bad], lag=3L)) }))
AX[, `:=`(bad_months=sum(bad), normal_months=sum(!bad))]
print(AX[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])

cat("\n=== B-7) advisory 배터리 (rank-IC 계열 — 게이트 아님) ===\n")
fwddt <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
adv <- function(sc) { s <- merge(sc, fwddt, by=c("Date","Ticker"))
  ic <- s[, { ok <- is.finite(score) & is.finite(fwd)
    if (sum(ok) < 30L) NA_real_ else cor(rank(score[ok]), rank(fwd[ok])) }, by=Date]$V1
  ic <- ic[is.finite(ic)]
  data.table(rank_ic=mean(ic), icir=mean(ic)/sd(ic), ic_t_nw3=.nw_t_mean(ic, lag=3L)) }
ADV <- rbindlist(c(list(cbind(arm="C0_uniform", adv(sc0))),
  lapply(c(prim,"B4a_STABLE_MAX_top1"), function(a) cbind(arm=a, adv(SCB[[a]])))))
print(ADV[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])

cat("\n=== B-8) DSR 진단 (게이트 비발동 — 챔피언 선발 없음) ===\n")
sr <- function(x) mean(x)/sd(x)*sqrt(12)
n_tr <- length(SPECB); s_all <- vapply(names(SPECB), function(a) sr(RESB[[a]]$act), 0)
bestv <- max(PB2$ann_pct); besta <- PB2$arm[which.max(PB2$ann_pct)]
x <- RESB[[besta]]$act; s <- sr(x); n <- length(x)
sk <- mean((x-mean(x))^3)/sd(x)^3; ku <- mean((x-mean(x))^4)/sd(x)^4
s0 <- sd(s_all); emax <- s0*((1-0.5772)*qnorm(1-1/n_tr) + 0.5772*qnorm(1-1/(n_tr*exp(1))))
DSR <- pnorm(((s/sqrt(12)-emax/sqrt(12))*sqrt(n-1))/sqrt(1-sk*(s/sqrt(12))+((ku-1)/4)*(s/sqrt(12))^2))
cat(sprintf("  n_trials=%d · selection_type=preregistered_grid_no_champion · DSR(사후 최선 arm %s) = %.4f\n",
            n_tr, besta, DSR))
cat("  ★위 '최선 arm' 은 보고용 사후 식별이며 판정·승격에 쓰지 않는다(챔피언 선발 시 sweep 재분류 + DSR HARD).\n")

saveRDS(list(CRIT=CRIT, TG=TG, PB2=PB2, JAC=JAC, POW=POW, BASB=BASB, AX=AX, ADV=ADV,
             SPECB=SPECB, SCB=SCB, RESB=RESB, MATERIAL=MATERIAL, DSR=DSR, n_tr=n_tr,
             oracle_info_top1=oracle_info_top1, sc0=sc0), file.path(OUT,"p3_partB.rds"))
cat("\n[saved] p3_partB.rds\nOK\n")
