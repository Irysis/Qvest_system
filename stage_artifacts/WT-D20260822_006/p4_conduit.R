## WT-D20260822_006 (FQ-246) P4 — 규칙-형태 전도성(conduit) 검사 + 순열 귀무분포 + F3
## 목적: 'null 이 상태 부재인가, 규칙 형태가 상태를 성과로 못 옮기는가' 를 가른다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
SRC <- "stage_artifacts/fq233_probe0_20260813"
P <- readRDS(file.path(OUT,"p2_arms.rds")); V3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
A4 <- readRDS(file.path(W004,"p1_arms.rds")); sel_rank <- A4$sel_rank; months <- names(sel_rank)
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet"))); pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
GV <- P$GV; TOPN <- P$TOPN; U <- P$U; act <- P$act; c0 <- act$C0$act; MATERIAL <- P$MATERIAL
MIN_WARM <- P$MIN_WARM; UCLIP <- P$UCLIP
std <- function(x) (x-mean(x))/sd(x)
pt <- function(x, lab) { d <- x - c0; t <- .nw_t_mean(d, lag=3L); ann <- mean(d)*12*100
  se_a <- abs(ann/t); data.table(contrast=lab, ann_pct=ann, t_nw3=t,
  ci95_lo=ann-1.96*se_a, ci95_hi=ann+1.96*se_a) }

wavg <- function(Z, w) { Wm <- matrix(w, nrow=nrow(Z), ncol=length(w), byrow=TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0
  den <- rowSums(Wm); ifelse(den > 0, rowSums(Z0*Wm)/den, NA_real_) }
build_w <- function(ua, ud) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); nv <- rowSums(is.finite(Z))
  keep <- colSums(is.finite(Z)) >= 30L
  sc <- if (sum(keep) < 2L) rowMeans(Z, na.rm=TRUE) else {
    Zk <- Z[, keep, drop=FALSE]; fk <- fs[keep]; lw <- rep(0, ncol(Zk))
    if (ua[m] != 0) { cm <- suppressWarnings(cor(Zk, method="spearman", use="pairwise.complete.obs"))
      cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE)*(ncol(cm)/(ncol(cm)-1))
      ct <- if (sd(cen,na.rm=TRUE)>0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
      ct[!is.finite(ct)] <- 0; lw <- lw + ua[m]*ct }
    if (ud[m] != 0) { gk <- as.numeric(GV[fk]); gk[!is.finite(gk)] <- 0; lw <- lw + ud[m]*gk }
    w <- exp(lw); w <- w/sum(w); wavg(Zk, w) }
  data.table(Date=as.Date(nm), Ticker=as.character(d$Ticker),
             score=ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)] }))
runact <- function(s, id) { s <- copy(s); setorder(s, Date, Ticker)
  b <- canonical_screen_bt(s[,.(Date,Ticker,score)], A4$returns_dt, A4$bench_dt, top_n=TOPN,
        cost_bps_oneway=15, run_id=id, strategy_id=id, diag_dual_basis=FALSE)
  list(act = as.data.table(b$period_returns)[, ret_net-benchmark_ret], port_t = b$portfolio_alpha_t_nw_lag3) }
Z0 <- rep(0, 221L)

cat("=== A) 완전예지 상태 — 규칙 형태별 전도성 (rule-form conduit) ===\n")
## 축1 오라클: 중심성 틸트(u=+1)가 EW 보다 그 달 실제로 나았는가
ic_of <- function(sc, f) { ok <- is.finite(sc) & is.finite(f); if (sum(ok) < 30L) return(NA_real_)
  cor(rank(sc[ok]), rank(f[ok])) }
oa <- vapply(seq_along(months), function(m){ nm<-months[m]; fs<-sel_rank[[nm]]; d<-panh[anchor==as.Date(nm)]
  Z<-as.matrix(d[,..fs]); f<-d$fwd_ret_1m; keep<-colSums(is.finite(Z))>=30L
  if (sum(keep)<2L) return(0); Zk<-Z[,keep,drop=FALSE]
  cm<-suppressWarnings(cor(Zk,method="spearman",use="pairwise.complete.obs"))
  cen<-rowMeans(cm-diag(diag(cm)),na.rm=TRUE)*(ncol(cm)/(ncol(cm)-1))
  ct<-if(sd(cen,na.rm=TRUE)>0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
  ct[!is.finite(ct)]<-0; w<-exp(ct); w<-w/sum(w)
  v <- ic_of(wavg(Zk,w), f) - ic_of(rowMeans(Zk,na.rm=TRUE), f); if (is.finite(v)) v else 0 }, 0)
UO_A <- pmax(-UCLIP, pmin(UCLIP, std(oa)))
## 축2 오라클 = D_t (계열군 IC 차) 표준화
D <- V3$D; Dz <- D; Dz[!is.finite(Dz)] <- 0
UO_D <- pmax(-UCLIP, pmin(UCLIP, std(Dz)))
RA <- runact(build_w(UO_A, Z0), "FQ246_ORACLE_T2")
RD <- runact(build_w(Z0, UO_D), "FQ246_ORACLE_T3")
CON <- rbind(pt(RA$act, "ORACLE_STATE_T2_form"), pt(RD$act, "ORACLE_STATE_T3_form"))
CON[, port_t := c(RA$port_t, RD$port_t)][, conduit_pass := t_nw3 >= 2.0]
print(CON[, .(contrast, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4),
              port_t=round(port_t,4), conduit_pass)])
cat("  ★해석: 완전예지 상태를 넣어도 t < 2 이면 그 규칙 형태가 상태를 성과로 옮기지 못한다 =\n")
cat("        해당 arm 의 null 은 '상태 부재' 가 아니라 '전도성 부재' 로 라벨해야 한다.\n")

cat("\n=== B) 순열 귀무분포 (단일 셔플 대조의 운 배제) ===\n")
NPERM <- 40L
set.seed(20260825L)
permA <- vapply(seq_len(NPERM), function(i) {
  u <- U$AGREE[sample.int(221L)]; r <- runact(build_w(u, Z0), paste0("FQ246_permA_", i))
  .nw_t_mean(r$act - c0, lag=3L) }, 0)
set.seed(20260826L)
permD <- vapply(seq_len(NPERM), function(i) {
  u <- U$DISP[sample.int(221L)]; r <- runact(build_w(Z0, u), paste0("FQ246_permD_", i))
  .nw_t_mean(r$act - c0, lag=3L) }, 0)
tA <- V3$PRI[contrast=="T2_AGREE", t_nw3]; tD <- V3$PRI[contrast=="T3_DISP", t_nw3]
PERM <- data.table(
  axis = c("axis1_disagreement(T2)","axis2_dispersion(T3)"),
  observed_t = c(tA, tD), n_perm = NPERM,
  perm_mean_t = c(mean(permA), mean(permD)), perm_sd_t = c(sd(permA), sd(permD)),
  perm_q05 = c(quantile(permA,.05), quantile(permD,.05)),
  perm_q95 = c(quantile(permA,.95), quantile(permD,.95)),
  pct_of_perm_below_obs = c(mean(permA < tA), mean(permD < tD)),
  p_one_sided_greater = c(mean(permA >= tA), mean(permD >= tD)))
print(PERM)
cat("  ★규칙-형태 비용: 셔플 상태의 평균 paired t 가 0 이 아니면 규칙 자체가 편향을 만든다.\n")
cat("  ★상태 정보량: 관측 t 가 셔플 분포 상위(백분위 높음)면 실제 상태가 무작위보다 낫다.\n")

cat("\n=== C) F3 agent 실재 (개인 순매수 집중 vs 분산 상태) ===\n")
iw <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
iw[, Date := as.Date(Date)]
iw[, ym := format(Date, "%Y%m")]
mm <- iw[is.finite(Individual), .(net = sum(Individual, na.rm=TRUE)), by=.(ym, Ticker)]
conc <- mm[, { v <- abs(net); v <- v[is.finite(v) & v > 0]
  if (length(v) < 30L) .(hhi = NA_real_, top10 = NA_real_) else {
    s <- sum(v); p <- sort(v/s, decreasing=TRUE)
    .(hhi = sum(p^2), top10 = sum(head(p, ceiling(0.1*length(p))))) } }, by=ym]
mo <- data.table(Date = as.Date(months))[, ym := format(Date, "%Y%m")]
cj <- merge(mo, conc, by="ym", all.x=TRUE)[order(Date)]
ok3 <- is.finite(cj$hhi)
cat(sprintf("  월간 집중도 유효 %d/221 (%s ~ %s)\n", sum(ok3),
            if (any(ok3)) format(min(cj$Date[ok3])) else "-", if (any(ok3)) format(max(cj$Date[ok3])) else "-"))
if (sum(ok3) >= 60L) {
  ud <- U$DISP[ok3]
  h <- cj$hhi[ok3]; t10 <- cj$top10[ok3]
  f3h <- .nw_t_mean(std(h)*std(ud), lag=3L)
  cat(sprintf("  cor(HHI, u_disp) = %+.4f · 표준화 곱 평균 NW3 t = %+.4f\n", cor(h, ud), f3h))
  cat(sprintf("  cor(top10 share, u_disp) = %+.4f\n", cor(t10, ud)))
  F3 <- list(n=sum(ok3), cor_hhi=cor(h,ud), t_nw3=f3h, cor_top10=cor(t10,ud),
             threshold="t >= +1.5", passed = f3h >= 1.5,
             verdict = if (f3h >= 1.5) "agent 서술 지지 — 고분산 월에 개인 순매수 집중 상승" else
                       "agent 서술 미지지 — 기전 강등(가설 전체 기각 아님)")
} else { cat("  유효 월 부족 — 미검\n"); F3 <- list(verdict="UNMEASURED_INSUFFICIENT_MONTHS", n=sum(ok3)) }
cat("  ->", F3$verdict, "\n")

cat("\n=== D) 중복성 / 비용 / DSR 진단 ===\n")
RED <- rbindlist(lapply(c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH"), function(a)
  data.table(arm=a, cor_active_vs_C0=round(cor(act[[a]]$act, c0),4),
             turnover_annual=round(P$BT[[a]]$turnover_annual,3),
             turnover_vs_C0=round(P$BT[[a]]$turnover_annual - P$BT$C0$turnover_annual,3))))
print(RED)
sr <- function(x) mean(x)/sd(x)*sqrt(12)
n_tr <- 4L
dsr <- { s <- sr(act$T3_DISP$act); n <- 221
  sk <- mean((act$T3_DISP$act-mean(act$T3_DISP$act))^3)/sd(act$T3_DISP$act)^3
  ku <- mean((act$T3_DISP$act-mean(act$T3_DISP$act))^4)/sd(act$T3_DISP$act)^4
  s0 <- sd(vapply(c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH"), function(a) sr(act[[a]]$act), 0))
  emax <- s0*((1-0.5772)*qnorm(1-1/n_tr) + 0.5772*qnorm(1-1/(n_tr*exp(1))))
  pnorm(((s/sqrt(12)-emax/sqrt(12))*sqrt(n-1))/sqrt(1-sk*(s/sqrt(12))+((ku-1)/4)*(s/sqrt(12))^2)) }
cat(sprintf("  n_trials=%d · selection_type=preregistered_arms_no_champion (sweep 아님 → DSR 게이트 비발동)\n", n_tr))
cat(sprintf("  DSR 진단(최선 arm T3_DISP 기준) = %.4f\n", dsr))

cat("\n=== E) AX-001 v2 (방어형 조건부 축) ===\n")
dts <- act$C0$Date
bmm <- A4$bench_dt[order(Date)]
bad <- bmm$BM_Ret < quantile(bmm$BM_Ret, 0.20)
AX <- rbindlist(lapply(c("T2_AGREE","T3_DISP"), function(a){ d <- act[[a]]$act - c0
  data.table(arm=a, crisis_alpha_ann=round(mean(d[bad])*12*100,4), normal_alpha_ann=round(mean(d[!bad])*12*100,4),
             bad_over_normal=round(mean(d[bad])/mean(d[!bad]),4)) }))
print(AX)
cat("  (방어형 팩터 라운드 아님 — AX-001 v2 는 조건부 축 기록 의무 이행용)\n")

saveRDS(list(CON=CON, PERM=PERM, permA=permA, permD=permD, F3=F3, RED=RED, dsr=dsr, AX=AX,
             UO_A=UO_A, UO_D=UO_D, conc=cj), file.path(OUT,"p4_conduit.rds"))
cat("\n[saved] p4_conduit.rds\nOK\n")
