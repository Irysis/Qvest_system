## WT-D20260822_007 P5 — 자기 적대검증(Self-Adversarial)이 요구한 추가 실측
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months; icm <- PB$icm
K <- A4$K; TOPN <- A4$TOPN; NM <- length(months)
PC <- readRDS(file.path(OUT,"p1c_parity.rds")); c0 <- PC$a_uni
PA <- readRDS(file.path(OUT,"p2_partA.rds")); FB <- readRDS(file.path(OUT,"p1b_form.rds"))
H <- PA$HEADROOM
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
Zl <- lapply(seq_along(months), function(m) { fsm <- A4$sel_rank[[months[m]]]
  d <- panh[anchor == as.Date(months[m])]
  list(Z=as.matrix(d[, ..fsm]), tick=as.character(d$Ticker), fwd=d$fwd_ret_1m) })
build_from_W <- function(W) rbindlist(lapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; w <- W[m,]; Wm <- matrix(w, nrow=nrow(Z), ncol=K, byrow=TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0; den <- rowSums(Wm)
  data.table(Date=as.Date(months[m]), Ticker=Zl[[m]]$tick,
             score=ifelse(den>0, rowSums(Z0*Wm)/den, NA_real_))[is.finite(score)] }))
runbt <- function(s, id) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[,.(Date,Ticker,score)], A4$returns_dt, A4$bench_dt, top_n=TOPN,
    cost_bps_oneway=15, run_id=id, strategy_id=id, diag_dual_basis=FALSE) }
actof <- function(b) as.data.table(b$period_returns)[, ret_net - benchmark_ret]

cat("=== C1) FA 단조성 수치 (P4 출력 재게시) ===\n")
CURVE <- PA$CURVE
CS <- CURVE[grepl("^O_softmax|^O_top", arm)]
cat(sprintf("  Spearman(n_eff, recovery): 전체 %d점 %+.4f | softmax %+.4f | topJ %+.4f\n",
  nrow(CS), cor(CS$n_eff, CS$recovery, method="spearman"),
  cor(CURVE[grepl("^O_softmax",arm), n_eff], CURVE[grepl("^O_softmax",arm), recovery], method="spearman"),
  cor(CURVE[grepl("^O_top",arm), n_eff], CURVE[grepl("^O_top",arm), recovery], method="spearman")))

cat("\n=== C2) [적대검증 CONCERN-1] 'N_eff 평균 일치' 가 '집중도 일치' 인가 — 월별 분포 대조 ===\n")
neff_series <- function(W) apply(W, 1, function(w) 1/sum(w^2))
W_soft <- function(lam) t(apply(FB$zrow, 1, function(z){ w<-exp(lam*z); w/sum(w) }))
C4 <- readRDS("stage_artifacts/WT-D20260822_006/p4_conduit.rds")
GV <- PB$P6$GV; Z0v <- rep(0, NM)
neff_fq <- function(ua, ud) vapply(seq_along(months), function(m) {
  fs <- A4$sel_rank[[months[m]]]; Z <- Zl[[m]]$Z; keep <- colSums(is.finite(Z)) >= 30L
  if (sum(keep) < 2L) return(NA_real_)
  Zk <- Z[,keep,drop=FALSE]; fk <- fs[keep]; lw <- rep(0, ncol(Zk))
  if (ua[m]!=0) { cm <- suppressWarnings(cor(Zk, method="spearman", use="pairwise.complete.obs"))
    cen <- rowMeans(cm-diag(diag(cm)), na.rm=TRUE)*(ncol(cm)/(ncol(cm)-1))
    ct <- if (sd(cen,na.rm=TRUE)>0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
    ct[!is.finite(ct)] <- 0; lw <- lw + ua[m]*ct }
  if (ud[m]!=0) { gk <- as.numeric(GV[fk]); gk[!is.finite(gk)] <- 0; lw <- lw + ud[m]*gk }
  w <- exp(lw); w <- w/sum(w); 1/sum(w^2) }, 0)
n_m2 <- neff_series(W_soft(PA$LAM_T2)); n_f2 <- neff_fq(C4$UO_A, Z0v)
n_m3 <- neff_series(W_soft(PA$LAM_T3)); n_f3 <- neff_fq(Z0v, C4$UO_D)
NEC <- data.table(pair=c("T2","T3"),
  matched_mean=c(mean(n_m2), mean(n_m3)), fq246_mean=c(mean(n_f2), mean(n_f3)),
  matched_sd=c(sd(n_m2), sd(n_m3)), fq246_sd=c(sd(n_f2), sd(n_f3)),
  cor_paths=c(cor(n_m2, n_f2), cor(n_m3, n_f3)))
print(NEC[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat("  ★평균은 설계상 일치. 월별 sd·경로 상관이 낮으면 '같은 집중도' 는 평균에서만 참이며\n")
cat("    결정 대조가 '언제 집중하나' 축과 부분 교락된다 — 한계로 기록.\n")

cat("\n=== C3) [적대검증 CONCERN-2] ORACLE_K 4.647 은 하드 선택 족의 **진짜** 상한인가 ===\n")
cat("    ORACLE_K 는 실현 rank-IC argmax 다. 그러나 소비면은 top-25 이므로 IC 최대 팩터가\n")
cat("    그 달 top-25 수익 최대 팩터라는 보장이 없다. 진짜 상한 = 실현 top-25 수익 argmax.\n")
ret_by_factor <- t(vapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; f <- Zl[[m]]$fwd
  vapply(seq_len(K), function(k) { v <- Z[,k]; ok <- is.finite(v) & is.finite(f)
    if (sum(ok) < TOPN) return(-Inf)
    mean(f[ok][order(v[ok], decreasing=TRUE)[seq_len(TOPN)]]) }, 0) }, numeric(K)))
W_retarg <- t(vapply(seq_len(NM), function(m){ w <- rep(0,K); w[which.max(ret_by_factor[m,])] <- 1; w },
                     numeric(K)))
BR <- runbt(build_from_W(W_retarg), "NP1_ORACLE_K_RETARGMAX")
aR <- actof(BR); dR <- aR - c0
cat(sprintf("  ORACLE_K_IC   (기존): PORT_t %.4f · paired %+.4f %%p/yr (t %.3f) · recovery 100.00%%\n",
    4.64699909, H, 4.28970507043012))
cat(sprintf("  ORACLE_K_RET  (진짜): PORT_t %.4f · paired %+.4f %%p/yr (t %.3f) · IC판 대비 %.2fx\n",
    BR$portfolio_alpha_t_nw_lag3, mean(dR)*12*100, .nw_t_mean(dR, lag=3L), mean(dR)*12*100/H))
cat("  ★해석: RET 판이 더 크면 4.647 은 하드 족의 **하한 추정**이고, 형태 귀속분은 더 커진다\n")
cat("    (= '형태 손실 우세' 결론은 이 방향으로 보수적).\n")

cat("\n=== C4) [적대검증 CONCERN-3] 상위 선별기가 K=5 를 동질화해 고를 게 없었나 ===\n")
cat(sprintf("  월내 K개 실현 IC 의 sd 평균 = %.5f · best-worst 스프레드 평균 = %.5f\n",
    mean(apply(icm,1,sd)), mean(apply(icm,1,function(x) diff(range(x))))))
cat(sprintf("  월내 top-25 실현수익의 best-worst 스프레드 평균 = %.4f (연 %.2f %%p 상당)\n",
    mean(apply(ret_by_factor,1,function(x){ x<-x[is.finite(x)]; diff(range(x)) })),
    mean(apply(ret_by_factor,1,function(x){ x<-x[is.finite(x)]; diff(range(x)) }))*12*100))
cat("  ★스프레드가 크면 '고를 게 없었다' 는 반론은 실측으로 기각된다.\n")

cat("\n=== C5) [적대검증 CONCERN-4] 단측 검정 보충 (방향 예측이 있었으므로) ===\n")
P4 <- readRDS(file.path(OUT,"p4_verdict.rds")); CMP <- P4$CMP
CMP[, p_two_sided := 2*(1-pnorm(abs(t_nw3)))]
CMP[, p_one_sided := 1-pnorm(t_nw3)]
print(CMP[, .(contrast, t=round(t_nw3,3), p_two=round(p_two_sided,4), p_one=round(p_one_sided,4))])
cat("  ★사전등록 규칙은 양측 |t| 기준이었다 — 단측은 **보충 정보**이며 라벨을 바꾸지 않는다.\n")

cat("\n=== C6) [적대검증 CONCERN-5] 형태 비용은 '분산 상실' 인가 '비용 증가' 인가 ===\n")
ADV <- readRDS(file.path(OUT,"p3_partB.rds"))$ADV
cat("  C0 rank_ic 0.0373 (ic_t 5.30) vs 하드 arm 0.0164~0.0212 (ic_t 2.90~3.13)\n")
cat("  ⇒ 집중은 횡단면 순위력 자체를 절반 가까이 깎는다(잡음 평균화 상실). 회전율 채널과 병존.\n")
NULLD <- PA$NULLD
cat(sprintf("  정보 없는 단일-팩터 집중의 순비용 = %+.3f %%p/yr (sd %.3f, n=%d)\n",
    mean(NULLD$N_top1), sd(NULLD$N_top1), length(NULLD$N_top1)))
cat("  ★이 항의 정직한 이름 = '정보 없는 단일-팩터 집중의 순비용' (분산 상실 + 회전율 + 특이위험).\n")
cat("    '형태 비용' 은 축약어이며 세 성분을 본 라운드가 분리하지 않았다 — 한계로 기록.\n")

saveRDS(list(NEC=NEC, oracle_ret_port_t=BR$portfolio_alpha_t_nw_lag3,
             oracle_ret_paired_ann=mean(dR)*12*100, oracle_ret_paired_t=.nw_t_mean(dR, lag=3L),
             ic_spread=mean(apply(icm,1,function(x) diff(range(x)))),
             ret_spread=mean(apply(ret_by_factor,1,function(x){x<-x[is.finite(x)];diff(range(x))})),
             CMP=CMP), file.path(OUT,"p5_adversarial.rds"))
cat("\n[saved] p5_adversarial.rds\nOK\n")
