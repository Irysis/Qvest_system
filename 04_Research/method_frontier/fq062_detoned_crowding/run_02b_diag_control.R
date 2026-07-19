# =============================================================================
# FQ-062 run_02b — diagonal-control probe (cheap, decisive)
#
# Q: correlation-basis mfix 발산(lwnls~sample pearson 0.53)이 lw_nls의 "잔차 dispersion
#    보존"(off-diagonal co-movement) 때문인가, 아니면 분산-수축(대각선)이 cov2cor로
#    누출된 것인가?
# Test: lw_nls 공분산 Sig_nls를 SAMPLE 표준편차로 재스케일 → C_ctrl.
#       D = diag(sd_sample); C_ctrl = D^{-1} Sig_nls D^{-1} (그 후 diag=1 정규화 아님 —
#       분산 confound 제거 목적이므로 sample-vol로 rescale한 cor).
#   실제로 "대각 통제" = lw_nls의 off-diagonal 구조를 sample-vol로 정규화한 상관.
#   만약 C_ctrl 기반 mfix가 sample과 붕괴(near-identical)하면 → 상관-발산 = 분산-수축
#   대각 confound 확정(off-diagonal co-movement 정보 아님).
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier/fq062")
WIN <- 60L; MIN_P <- 40L; K_RES <- 9L
mr <- as.data.table(read_parquet(file.path(OUT_DIR,"fq062_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(OUT_DIR,"fq062_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym)); end_candidates <- yms[seq_len(length(yms)) >= WIN]

mfix_of <- function(M, k_info) {
  eg <- sort(eigen(M, symmetric=TRUE, only.values=TRUE)$values, decreasing=TRUE); eg[eg<0]<-0
  res <- eg[-1]; kk <- min(K_RES,length(res)); ki <- min(k_info,length(res))
  d <- sum(res[seq_len(ki)]); if (d>0) sum(res[seq_len(min(kk,ki))])/d else NA_real_
}
rows <- list()
for (ye in end_candidates) {
  win <- tail(yms[yms<=ye], WIN); if (length(win)<WIN) next
  memb <- sn[ym==ye & member==1L & !is.na(size), Ticker]; if (length(memb)<MIN_P) next
  sub <- mr[ym %in% win & Ticker %in% memb]; cnt <- sub[,.N,by=Ticker][N==WIN,Ticker]
  if (length(cnt)<MIN_P) next
  W <- dcast(sub[Ticker %in% cnt], ym~Ticker, value.var="ret_m"); R <- as.matrix(W[,-1])
  p <- ncol(R); n <- nrow(R); k_info <- n-2L
  C_s <- cor(R); C_s[is.na(C_s)]<-0
  Sig <- tryCatch(.lw_nls_cov(R), error=function(e) NULL); if (is.null(Sig)) next
  sd_l <- sqrt(diag(Sig)); C_l <- Sig/outer(sd_l,sd_l); diag(C_l)<-1; C_l[is.na(C_l)]<-0
  # diagonal control: rescale lw_nls covariance by SAMPLE sd (remove variance-shrink diag)
  sd_s <- apply(R,2,sd); Dinv <- 1/sd_s
  C_ctrl <- Sig * outer(Dinv,Dinv); diag(C_ctrl)<-1; C_ctrl[is.na(C_ctrl)]<-0
  rows[[length(rows)+1L]] <- data.table(ym=ye,
    mfix_sample=mfix_of(C_s,k_info), mfix_lwnls=mfix_of(C_l,k_info),
    mfix_ctrl=mfix_of(C_ctrl,k_info))
}
DT <- rbindlist(rows)
res <- list(
  n=nrow(DT),
  lwnls_vs_sample = list(pearson=cor(DT$mfix_sample,DT$mfix_lwnls),
                         spearman=cor(DT$mfix_sample,DT$mfix_lwnls,method="spearman")),
  ctrl_vs_sample  = list(pearson=cor(DT$mfix_sample,DT$mfix_ctrl),
                         spearman=cor(DT$mfix_sample,DT$mfix_ctrl,method="spearman")),
  interpretation = "ctrl = lw_nls off-diagonal normalized by SAMPLE vol (variance-shrink diagonal removed). If ctrl_vs_sample >> lwnls_vs_sample => correlation-basis divergence is variance-shrink cov2cor confound, NOT residual co-movement info."
)
write_json(res, file.path(OUT_DIR,"fq062_diag_control.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("\n[diag-control] cor-mfix time series, lwnls~sample pearson=", sprintf("%.3f",res$lwnls_vs_sample$pearson),
    " spearman=", sprintf("%.3f",res$lwnls_vs_sample$spearman), "\n")
cat("[diag-control] cor-mfix, CTRL(sample-vol rescaled)~sample pearson=", sprintf("%.3f",res$ctrl_vs_sample$pearson),
    " spearman=", sprintf("%.3f",res$ctrl_vs_sample$spearman), "\n")
cat("[diag-control]", if (res$ctrl_vs_sample$pearson > res$lwnls_vs_sample$pearson + 0.15)
    "=> variance-shrink DIAGONAL CONFOUND confirmed (off-diagonal co-movement info NOT the driver)"
    else "=> divergence persists after diagonal control (off-diagonal co-movement differs)", "\n")
