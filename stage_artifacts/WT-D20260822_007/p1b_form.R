## WT-D20260822_007 P1b — 형태(가중 집중도) 공통 축 설계 입력 산출
##   ★수익률 측정 없음. 가중치 기하만 계산 — 사전등록의 설계 입력(FQ-246 arm 을 곡선 위에 놓을 좌표).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
W006 <- "stage_artifacts/WT-D20260822_006"
PB <- readRDS(file.path(OUT, "p1_probe.rds")); A4 <- PB$A4; P6 <- PB$P6; months <- PB$months
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]

cat("=== 1) 패널 팩터 컬럼 척도 확인 (z-점수인가) ===\n")
fs1 <- A4$sel_rank[[1]]
d1 <- panh[anchor == as.Date(months[1])]
for (f in fs1) cat(sprintf("  %-32s mean %+.4f sd %.4f min %+.3f max %+.3f n %d\n",
  f, mean(d1[[f]], na.rm=TRUE), sd(d1[[f]], na.rm=TRUE),
  min(d1[[f]], na.rm=TRUE), max(d1[[f]], na.rm=TRUE), sum(is.finite(d1[[f]]))))

cat("\n=== 2) FQ-246 소프트 틸트 arm 의 유효 팩터 수 N_eff = 1/sum(w^2) ===\n")
C4 <- readRDS(file.path(W006, "p4_conduit.rds"))
GV <- P6$GV
neff_of <- function(ua, ud) vapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); keep <- colSums(is.finite(Z)) >= 30L
  if (sum(keep) < 2L) return(NA_real_)
  Zk <- Z[, keep, drop=FALSE]; fk <- fs[keep]; lw <- rep(0, ncol(Zk))
  if (ua[m] != 0) { cm <- suppressWarnings(cor(Zk, method="spearman", use="pairwise.complete.obs"))
    cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE)*(ncol(cm)/(ncol(cm)-1))
    ct <- if (sd(cen,na.rm=TRUE)>0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
    ct[!is.finite(ct)] <- 0; lw <- lw + ua[m]*ct }
  if (ud[m] != 0) { gk <- as.numeric(GV[fk]); gk[!is.finite(gk)] <- 0; lw <- lw + ud[m]*gk }
  w <- exp(lw); w <- w/sum(w); 1/sum(w^2) }, 0)
Z0 <- rep(0, 221L)
NE <- data.table(
  arm = c("C0_uniform","FQ246_T2_AGREE(obs)","FQ246_T3_DISP(obs)",
          "FQ246_ORACLE_T2_form","FQ246_ORACLE_T3_form"),
  n_eff_mean = c(5,
    mean(neff_of(P6$U$AGREE, Z0)), mean(neff_of(Z0, P6$U$DISP)),
    mean(neff_of(C4$UO_A, Z0)),    mean(neff_of(Z0, C4$UO_D))))
NE[, log_w_sd_mean := NA_real_]
print(NE)
cat("\n  ★해석: FQ-246 의 오라클-상태 소프트 틸트는 N_eff 가 5(균등)에서 얼마나 내려갔나 —\n")
cat("        이 좌표에서 회수율 25.2%% 를 기록했다. Part A 곡선의 같은 N_eff 지점과 비교하면\n")
cat("        '형태 손실' 과 '정보 차원 손실' 이 갈린다.\n")

cat("\n=== 3) softmax(lambda * z(IC)) 사다리의 N_eff (정보 고정, 형태만 변주) ===\n")
icm <- PB$icm
zrow <- t(apply(icm, 1, function(x) { s <- sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) x*0 else (x-mean(x,na.rm=TRUE))/s }))
lams <- c(0, 0.5, 1, 1.5, 2, 3, 5, 8, 12)
LAD <- rbindlist(lapply(lams, function(l) {
  ne <- apply(zrow, 1, function(z) { w <- exp(l*z); w <- w/sum(w); 1/sum(w^2) })
  data.table(form=sprintf("softmax_lam%.1f", l), lambda=l, n_eff_mean=mean(ne)) }))
HARD <- rbindlist(lapply(1:5, function(j)
  data.table(form=sprintf("topJ_%d_EW", j), lambda=NA_real_, n_eff_mean=as.numeric(j))))
print(rbind(LAD, HARD))
saveRDS(list(NE=NE, LAD=LAD, zrow=zrow, lams=lams), file.path(OUT, "p1b_form.rds"))
cat("\n[saved] p1b_form.rds\nOK\n")
