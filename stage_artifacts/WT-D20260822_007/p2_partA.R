## WT-D20260822_007 (FQ-246 NP1) P2 — PART A: 상한 분해 (진단 · 자본 자격 없음)
## ★오라클(실현 rank-IC)은 구성상 look-ahead. 전 수치 metric_type=canonical_screen_diag_oracle,
##   capital_eligible=FALSE. 이 값으로 자본/졸업 주장 금지(AX-002).
## 설계: **정보를 고정**(K차원 오라클 IC 벡터)한 채 **형태만** 교체 → 회수율 곡선 r(N_eff).
##   비교 좌표 = FQ-246 오라클-상태 소프트 틸트(N_eff 3.910050 / 4.343690, 회수 25.1%).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
W002 <- "stage_artifacts/WT-D20260822_002"; W006 <- "stage_artifacts/WT-D20260822_006"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; P6 <- PB$P6
months <- PB$months; icm <- PB$icm; K <- A4$K; TOPN <- A4$TOPN; NM <- length(months)
FB <- readRDS(file.path(OUT,"p1b_form.rds")); zrow <- FB$zrow
PC <- readRDS(file.path(OUT,"p1c_parity.rds"))
PR <- jsonlite::fromJSON(file.path(OUT,"PREREG.json"), simplifyVector = FALSE)
HEADROOM <- 13.6929981793759            # ORACLE_K − C0 paired 연 %p (FQ-244 공표, 본 하네스 재현 Δ −2e-14)
UCLIP <- P6$UCLIP                       # = 2 (FQ-246 형태의 clip)
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
p0 <- readRDS(file.path(W002,"p0_returns.rds"))
bench_parent <- as.data.table(p0$bench)[, .(Date, BM_Ret)]

## ---------- 공통 가중 프레임 (P1c 패리티 검증 완료) ----------
Zl <- lapply(seq_along(months), function(m) {
  fsm <- A4$sel_rank[[months[m]]]
  d <- panh[anchor == as.Date(months[m])]
  list(Z = as.matrix(d[, ..fsm]), tick = as.character(d$Ticker)) })
build_from_W <- function(W) rbindlist(lapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; w <- W[m, ]
  Wm <- matrix(w, nrow = nrow(Z), ncol = K, byrow = TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0
  den <- rowSums(Wm); sc <- ifelse(den > 0, rowSums(Z0*Wm)/den, NA_real_)
  data.table(Date = as.Date(months[m]), Ticker = Zl[[m]]$tick, score = sc)[is.finite(score)] }))
runbt <- function(s, id, bench = A4$bench_dt, dual = FALSE) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[, .(Date,Ticker,score)], A4$returns_dt, bench, top_n = TOPN,
    cost_bps_oneway = 15, run_id = id, strategy_id = id, diag_dual_basis = dual) }
actof <- function(b) as.data.table(b$period_returns)[, ret_net - benchmark_ret]
c0 <- PC$a_uni
paired <- function(x, lab, neff = NA_real_) { d <- x - c0; t <- .nw_t_mean(d, lag = 3L)
  ann <- mean(d)*12*100; se_a <- abs(ann/t)
  data.table(arm = lab, n_eff = neff, ann_pct = ann, t_nw3 = t, se_ann_pct = se_a,
             ci95_lo = ann - 1.96*se_a, ci95_hi = ann + 1.96*se_a,
             recovery = ann/HEADROOM, ar1_diff = as.numeric(acf(d, lag.max=1, plot=FALSE)$acf[2])) }
neff_of_W <- function(W) mean(apply(W, 1, function(w) 1/sum(w^2)))

W_softmax <- function(lam, Zm = zrow) t(apply(Zm, 1, function(z) { w <- exp(lam*z); w/sum(w) }))
W_topJ    <- function(J, M = icm) t(apply(M, 1, function(x) {
  w <- rep(0, K); w[order(x, decreasing = TRUE)[seq_len(J)]] <- 1/J; w }))
W_fq246   <- function(Zm = zrow) t(apply(Zm, 1, function(z) {
  w <- exp(pmax(-UCLIP, pmin(UCLIP, z))); w/sum(w) }))
## N_eff 목표를 만족하는 lambda (가중 기하만으로 이분법 — 수익률 미사용)
lam_for_neff <- function(target) { f <- function(l) neff_of_W(W_softmax(l)) - target
  uniroot(f, c(1e-4, 40))$root }

cat("=== A-0) FQ-246 좌표에 맞춘 lambda 해 (가중 기하만) ===\n")
LAM_T2 <- lam_for_neff(3.910050); LAM_T3 <- lam_for_neff(4.343690)
cat(sprintf("  lambda_matched_T2 = %.6f (N_eff %.6f)\n", LAM_T2, neff_of_W(W_softmax(LAM_T2))))
cat(sprintf("  lambda_matched_T3 = %.6f (N_eff %.6f)\n", LAM_T3, neff_of_W(W_softmax(LAM_T3))))

cat("\n=== A-1) 오라클 정보 고정 · 형태 사다리 ===\n")
LAMS <- c(0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0)
SPEC <- c(
  setNames(lapply(LAMS, function(l) W_softmax(l)), sprintf("O_softmax_lam%g", LAMS)),
  list(O_softmax_lamMATCH_T2 = W_softmax(LAM_T2), O_softmax_lamMATCH_T3 = W_softmax(LAM_T3)),
  list(O_fq246_form_clip = W_fq246()),
  setNames(lapply(1:4, function(J) W_topJ(J)), sprintf("O_top%d_EW", 1:4)))
RESA <- lapply(names(SPEC), function(a) { b <- runbt(build_from_W(SPEC[[a]]), paste0("NP1_", a))
  list(act = actof(b), port_t = b$portfolio_alpha_t_nw_lag3, to = b$turnover_annual) })
names(RESA) <- names(SPEC)
CURVE <- rbindlist(lapply(names(SPEC), function(a)
  paired(RESA[[a]]$act, a, neff_of_W(SPEC[[a]]))))
CURVE[, port_t := vapply(names(SPEC), function(a) RESA[[a]]$port_t, 0)]
CURVE[, turnover := vapply(names(SPEC), function(a) RESA[[a]]$to, 0)]
setorder(CURVE, -n_eff)
print(CURVE[, .(arm, n_eff = round(n_eff,3), ann_pct = round(ann_pct,3), t = round(t_nw3,3),
                recovery_pct = round(recovery*100,2), port_t = round(port_t,4), TO = round(turnover,2))])

cat("\n=== A-2) FQ-246 오라클-상태 소프트 틸트 재현 (같은 하네스 · 패리티) ===\n")
C4 <- readRDS(file.path(W006,"p4_conduit.rds")); GV <- P6$GV; Z0v <- rep(0, NM)
build_w_fq246 <- function(ua, ud) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; Z <- Zl[[m]]$Z
  keep <- colSums(is.finite(Z)) >= 30L
  sc <- if (sum(keep) < 2L) rowMeans(Z, na.rm=TRUE) else {
    Zk <- Z[, keep, drop=FALSE]; fk <- fs[keep]; lw <- rep(0, ncol(Zk))
    if (ua[m] != 0) { cm <- suppressWarnings(cor(Zk, method="spearman", use="pairwise.complete.obs"))
      cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE)*(ncol(cm)/(ncol(cm)-1))
      ct <- if (sd(cen,na.rm=TRUE)>0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
      ct[!is.finite(ct)] <- 0; lw <- lw + ua[m]*ct }
    if (ud[m] != 0) { gk <- as.numeric(GV[fk]); gk[!is.finite(gk)] <- 0; lw <- lw + ud[m]*gk }
    w <- exp(lw); w <- w/sum(w)
    Wm <- matrix(w, nrow=nrow(Zk), ncol=length(w), byrow=TRUE); Wm[!is.finite(Zk)] <- 0
    Zk0 <- Zk; Zk0[!is.finite(Zk0)] <- 0; den <- rowSums(Wm)
    ifelse(den > 0, rowSums(Zk0*Wm)/den, NA_real_) }
  nv <- rowSums(is.finite(Z))
  data.table(Date=as.Date(nm), Ticker=Zl[[m]]$tick,
             score=ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)] }))
BF2 <- runbt(build_w_fq246(C4$UO_A, Z0v), "NP1_repro_FQ246_ORACLE_T2")
BF3 <- runbt(build_w_fq246(Z0v, C4$UO_D), "NP1_repro_FQ246_ORACLE_T3")
FQR <- rbind(paired(actof(BF2), "FQ246_ORACLE_T2_form", 3.910050),
             paired(actof(BF3), "FQ246_ORACLE_T3_form", 4.343690))
FQR[, port_t := c(BF2$portfolio_alpha_t_nw_lag3, BF3$portfolio_alpha_t_nw_lag3)]
FQR[, published_port_t := c(1.69937575, 1.82208106)]
FQR[, delta_port_t := port_t - published_port_t]
print(FQR[, .(arm, n_eff, ann_pct=round(ann_pct,4), t=round(t_nw3,4),
              recovery_pct=round(recovery*100,2), port_t=round(port_t,6),
              published_port_t, delta_port_t=signif(delta_port_t,3))])

cat("\n=== A-3) 형태 귀무분포 (같은 형태 · 정보 제거: 월내 IC 벡터 치환) ===\n")
NPERM <- 60L
perm_forms <- list(
  N_top1 = function(M) W_topJ(1, M), N_top2 = function(M) W_topJ(2, M),
  N_lam1 = function(M) W_softmax(1.0, t(apply(M,1,function(x){s<-sd(x);if(!is.finite(s)||s==0) x*0 else (x-mean(x))/s}))),
  N_lamMATCH_T2 = function(M) W_softmax(LAM_T2, t(apply(M,1,function(x){s<-sd(x);if(!is.finite(s)||s==0) x*0 else (x-mean(x))/s}))))
set.seed(20260901L)
NULLD <- list()
for (fn in names(perm_forms)) {
  v <- vapply(seq_len(NPERM), function(i) {
    Mp <- t(apply(icm, 1, sample))
    b <- runbt(build_from_W(perm_forms[[fn]](Mp)), sprintf("NP1_%s_%d", fn, i))
    mean(actof(b) - c0)*12*100 }, 0)
  NULLD[[fn]] <- v
  cat(sprintf("  %-14s n=%d  mean %+7.3f %%p/yr  sd %6.3f  [q05 %+7.3f, q95 %+7.3f]\n",
      fn, NPERM, mean(v), sd(v), quantile(v,.05), quantile(v,.95)))
}
cat("  ★이 분포가 '형태 자체의 비용' 이다 — 정보 없이 그 집중도를 쓰면 C0 대비 얼마를 잃는가.\n")

cat("\n=== A-4) 여유폭 2-way 분해: [형태 비용] + [그 형태 안의 정보 가치] ===\n")
mapf <- c(N_top1 = "O_top1_EW", N_top2 = "O_top2_EW",
          N_lam1 = "O_softmax_lam1", N_lamMATCH_T2 = "O_softmax_lamMATCH_T2")
DEC <- rbindlist(lapply(names(mapf), function(fn) { a <- mapf[[fn]]
  o <- CURVE[arm == a]; fc <- mean(NULLD[[fn]])
  data.table(form = a, n_eff = o$n_eff, oracle_ann = o$ann_pct, form_cost_ann = fc,
             info_value_ann = o$ann_pct - fc,
             perm_pctile = mean(NULLD[[fn]] < o$ann_pct),
             recovery_pct = o$recovery*100,
             form_cost_share_of_headroom_pct = fc/HEADROOM*100) }))
print(DEC[, lapply(.SD, function(x) if (is.numeric(x)) round(x,3) else x)])

cat("\n=== A-5) 결정적 대조: 같은 집중도에서 오라클 IC 벡터 vs FQ-246 오라클 상태 ===\n")
DECIDE <- rbindlist(list(
  data.table(pair = "N_eff 3.910 (T2 좌표)",
    fq246_recovery_pct = FQR[arm=="FQ246_ORACLE_T2_form", recovery*100],
    oracle_ic_recovery_pct = CURVE[arm=="O_softmax_lamMATCH_T2", recovery*100]),
  data.table(pair = "N_eff 4.344 (T3 좌표)",
    fq246_recovery_pct = FQR[arm=="FQ246_ORACLE_T3_form", recovery*100],
    oracle_ic_recovery_pct = CURVE[arm=="O_softmax_lamMATCH_T3", recovery*100])))
DECIDE[, gap_pp := oracle_ic_recovery_pct - fq246_recovery_pct]
## paired 검정 (두 arm 의 active 계열 직접 차)
dm2 <- RESA$O_softmax_lamMATCH_T2$act - actof(BF2)
dm3 <- RESA$O_softmax_lamMATCH_T3$act - actof(BF3)
DECIDE[, paired_ann_pct := c(mean(dm2)*12*100, mean(dm3)*12*100)]
DECIDE[, paired_t_nw3 := c(.nw_t_mean(dm2, lag=3L), .nw_t_mean(dm3, lag=3L))]
print(DECIDE[, lapply(.SD, function(x) if (is.numeric(x)) round(x,3) else x)])
cat("  ★사전등록 판정 규칙(PREREG A-decision) 적용은 P4 에서.\n")

cat("\n=== A-6) basis 3종 (헤드라인 arm 만) ===\n")
head_arms <- c("O_top1_EW","O_top2_EW","O_softmax_lam1","O_softmax_lamMATCH_T2","O_fq246_form_clip")
BAS <- rbindlist(lapply(head_arms, function(a) {
  b1 <- runbt(build_from_W(SPEC[[a]]), paste0("NP1b_",a), A4$bench_dt, dual = TRUE)
  b2 <- runbt(build_from_W(SPEC[[a]]), paste0("NP1p_",a), bench_parent, dual = FALSE)
  data.table(arm = a, port_t_IKS200 = b1$portfolio_alpha_t_nw_lag3,
             port_t_parent_capw = b2$portfolio_alpha_t_nw_lag3,
             port_t_EW_universe = b1$diag_ew_universe$portfolio_alpha_t_nw_lag3,
             ir_IKS200 = b1$information_ratio, turnover = b1$turnover_annual) }))
b0 <- runbt(build_from_W(matrix(1/K, NM, K)), "NP1b_C0", A4$bench_dt, dual = TRUE)
b0p <- runbt(build_from_W(matrix(1/K, NM, K)), "NP1p_C0", bench_parent)
BAS <- rbind(data.table(arm="C0_uniform", port_t_IKS200=b0$portfolio_alpha_t_nw_lag3,
  port_t_parent_capw=b0p$portfolio_alpha_t_nw_lag3,
  port_t_EW_universe=b0$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  ir_IKS200=b0$information_ratio, turnover=b0$turnover_annual), BAS)
print(BAS[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat("  benchmark_id caveat: canonical_screen_bt 는 'KOSPI200_total_return' 하드코딩 —\n")
cat("  실제 계열 primary=.cache/benchmark.parquet(IKS200) / parent=WT-D20260822_002 p0_returns.rds cap-w.\n")

saveRDS(list(CURVE=CURVE, FQR=FQR, NULLD=NULLD, DEC=DEC, DECIDE=DECIDE, BAS=BAS,
             RESA=RESA, SPEC_neff=vapply(SPEC, neff_of_W, 0), LAM_T2=LAM_T2, LAM_T3=LAM_T3,
             act_FQ2=actof(BF2), act_FQ3=actof(BF3), HEADROOM=HEADROOM, NPERM=NPERM),
        file.path(OUT,"p2_partA.rds"))
cat("\n[saved] p2_partA.rds\nOK\n")
