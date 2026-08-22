## WT-D20260822_008 (FQ-246 NP2) P1 — 대조 패리티 + 정답지 구조 실측 (측정 아님, 사전등록 입력)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
W7  <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260822_008"

PB <- readRDS(file.path(W7,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months; icm <- PB$icm
K <- A4$K; TOPN <- A4$TOPN; NM <- length(months)
P3 <- readRDS(file.path(W7,"p3_partB.rds")); CRIT <- P3$CRIT; TG7 <- P3$TG
P5 <- readRDS(file.path(W7,"p5_adversarial.rds"))
cat(sprintf("승계: K=%d TOPN=%d NM=%d · CRIT dim %s · TG7 rows %d\n",
            K, TOPN, NM, paste(dim(CRIT), collapse="x"), nrow(TG7)))

pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
Zl <- lapply(seq_along(months), function(m) { fsm <- A4$sel_rank[[months[m]]]
  d <- panh[anchor == as.Date(months[m])]
  list(Z=as.matrix(d[, ..fsm]), tick=as.character(d$Ticker), fwd=d$fwd_ret_1m) })

## ---- (1) 소비면 정답지 재현: ret_by_factor (WT-007 p5 정의 비트-동일) ----
ret_by_factor <- t(vapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; f <- Zl[[m]]$fwd
  vapply(seq_len(K), function(k) { v <- Z[,k]; ok <- is.finite(v) & is.finite(f)
    if (sum(ok) < TOPN) return(-Inf)
    mean(f[ok][order(v[ok], decreasing=TRUE)[seq_len(TOPN)]]) }, 0) }, numeric(K)))
cat(sprintf("ret_by_factor: %dx%d · finite %d/%d · -Inf %d\n", nrow(ret_by_factor), ncol(ret_by_factor),
    sum(is.finite(ret_by_factor)), length(ret_by_factor), sum(is.infinite(ret_by_factor))))

## 패리티 A: ORACLE_K_RET 재현 (WT-007 공표 PORT_t 8.8381268503 / paired 31.492557813)
build_from_W <- function(W) rbindlist(lapply(seq_along(months), function(m) {
  Z <- Zl[[m]]$Z; w <- W[m,]; Wm <- matrix(w, nrow=nrow(Z), ncol=K, byrow=TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0; den <- rowSums(Wm)
  data.table(Date=as.Date(months[m]), Ticker=Zl[[m]]$tick,
             score=ifelse(den>0, rowSums(Z0*Wm)/den, NA_real_))[is.finite(score)] }))
runbt <- function(s, id) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[,.(Date,Ticker,score)], A4$returns_dt, A4$bench_dt, top_n=TOPN,
    cost_bps_oneway=15, run_id=id, strategy_id=id, diag_dual_basis=FALSE) }
actof <- function(b) as.data.table(b$period_returns)[, ret_net - benchmark_ret]
PC <- readRDS(file.path(W7,"p1c_parity.rds")); c0 <- PC$a_uni
W_retarg <- t(vapply(seq_len(NM), function(m){ w <- rep(0,K); w[which.max(ret_by_factor[m,])] <- 1; w },
                     numeric(K)))
BR <- runbt(build_from_W(W_retarg), "NP2_PARITY_ORACLE_K_RETARGMAX")
dR <- actof(BR) - c0
PAR <- data.table(
  check = c("ORACLE_K_RET port_t","ORACLE_K_RET paired_ann_pct","ORACLE_K_RET paired_t"),
  published = c(8.8381268503, 31.492557813, 11.4390753094),
  reproduced = c(BR$portfolio_alpha_t_nw_lag3, mean(dR)*12*100, .nw_t_mean(dR, lag=3L)))
PAR[, abs_diff := abs(reproduced - published)]
print(PAR)

## ---- (2) 패리티 B: WT-007 IC-정답지 FC 게이트 9행 재현 ----
argmax_of <- function(M, decreasing=TRUE) vapply(seq_len(NM), function(m) {
  x <- M[m,]; if (all(!is.finite(x))) return(NA_integer_)
  x[!is.finite(x)] <- if (decreasing) -Inf else Inf
  as.integer(order(x, decreasing=decreasing)[1]) }, 0L)
DIRS <- list(breadth_MAX=list("breadth",TRUE), margin_MAX=list("margin",TRUE),
             centrality_MIN=list("centrality",FALSE), stability_MAX=list("stability",TRUE),
             centrality_MAX=list("centrality",TRUE), breadth_MIN=list("breadth",FALSE),
             margin_MIN=list("margin",FALSE), stability_MIN=list("stability",FALSE))
AM <- lapply(names(DIRS), function(nmd) argmax_of(CRIT[,,DIRS[[nmd]][[1]]], DIRS[[nmd]][[2]]))
names(AM) <- names(DIRS)
ic_best  <- apply(icm, 1, which.max)
gate_one <- function(am, key_best, M, keyM, dec) {
  ok <- is.finite(am); hit <- mean(am[ok] == key_best[ok])
  bt <- binom.test(sum(am[ok]==key_best[ok]), sum(ok), p=1/K, alternative="greater")
  rho <- vapply(seq_len(NM), function(m){ a <- M[m,]; b <- keyM[m,]
    o2 <- is.finite(a) & is.finite(b); if (sum(o2)<3L || sd(a[o2])==0) return(NA_real_)
    cor(rank(a[o2]), rank(b[o2])) }, 0)
  rr <- rho[is.finite(rho)]; if (!dec) rr <- -rr
  list(n=sum(ok), hit=hit, p=bt$p.value, rho_mean=mean(rr), rho_t=.nw_t_mean(rr,lag=3L),
       rho_mde95=1.96*sd(rr)/sqrt(length(rr)), rho_series=rr) }
IC7 <- rbindlist(lapply(names(DIRS), function(nmd) {
  g <- gate_one(AM[[nmd]], ic_best, CRIT[,,DIRS[[nmd]][[1]]], icm, DIRS[[nmd]][[2]])
  data.table(criterion=nmd, n=g$n, hit=g$hit, p=g$p, rho=g$rho_mean, rho_t=g$rho_t, mde=g$rho_mde95) }))
CMPP <- merge(IC7, TG7[, .(criterion, hit7=hit_rate, p7=hit_p_binom, rho7=mean_rho_signed,
                           rho_t7=rho_t_nw3, mde7=rho_mde95)], by="criterion", sort=FALSE)
CMPP[, `:=`(d_hit=abs(hit-hit7), d_rho=abs(rho-rho7), d_rhot=abs(rho_t-rho_t7))]
print(CMPP[, .(criterion, hit=round(hit,8), hit7=round(hit7,8), d_hit=signif(d_hit,3),
               d_rho=signif(d_rho,3), d_rhot=signif(d_rhot,3))])
cat(sprintf("★대조 패리티: max|Δhit| = %.3e · max|Δrho| = %.3e · max|Δrho_t| = %.3e\n",
            max(CMPP$d_hit), max(CMPP$d_rho), max(CMPP$d_rhot)))

## ---- (3) 정답지 구조 (사전등록 입력 — 결과 아님) ----
ret_best <- apply(ret_by_factor, 1, function(x){ x[!is.finite(x)] <- -Inf; which.max(x) })
agree <- mean(ic_best == ret_best)
rho_keys <- vapply(seq_len(NM), function(m){ a <- icm[m,]; b <- ret_by_factor[m,]
  o <- is.finite(a)&is.finite(b); if (sum(o)<3L) return(NA_real_); cor(rank(a[o]),rank(b[o])) }, 0)
cat(sprintf("\n★정답지 일치율 P(ic_best==ret_best) = %.8f (n=%d, 우연 %.4f)\n", agree, NM, 1/K))
cat(sprintf("★정답지 간 월별 순위상관 평균 = %+.6f (sd %.4f · NW3 t %.3f)\n",
            mean(rho_keys,na.rm=TRUE), sd(rho_keys,na.rm=TRUE), .nw_t_mean(rho_keys[is.finite(rho_keys)],lag=3L)))
top2_of <- function(M) lapply(seq_len(NM), function(m){ x <- M[m,]; x[!is.finite(x)] <- -Inf
  order(x, decreasing=TRUE)[1:2] })
rt2 <- top2_of(ret_by_factor)
cat(sprintf("★ic_best 가 ret top-2 에 드는 비율 = %.6f (우연 %.4f)\n",
            mean(vapply(seq_len(NM), function(m) ic_best[m] %in% rt2[[m]], TRUE)), 2/K))

## 선택-공간 헤드룸 (★ORACLE_K_RET paired 31.492557813 %p/yr 와 다른 양 — 이름 분리)
selspace_head <- mean(apply(ret_by_factor,1,function(x){x<-x[is.finite(x)]; max(x)-mean(x)}))*12*100
selspace_head_ic <- mean(vapply(seq_len(NM), function(m){
  b <- ret_by_factor[m,]; ret_by_factor[m, ic_best[m]] - mean(b[is.finite(b)]) },0))*12*100
cat(sprintf("★SELSPACE_headroom_ann_pct (RET-oracle, 선택공간 내부) = %+.6f %%p/yr\n", selspace_head))
cat(sprintf("★SELSPACE_value_of_IC_key_ann_pct (IC-argmax 가 선택공간에서 내는 값) = %+.6f %%p/yr\n", selspace_head_ic))
cat("  ⚠이 두 양은 canonical_screen_bt 를 통과한 ORACLE_K_RET paired 31.492557813 %p/yr 와 **다른 양**이다\n")
cat("    (분모·경로 상이: 여기는 K개 단일-팩터 top-25 평균수익 공간, 저기는 C0 결합 대비 포트 net active).\n")

saveRDS(list(A4=A4, months=months, icm=icm, CRIT=CRIT, TG7=TG7, ret_by_factor=ret_by_factor,
             Zl=Zl, K=K, TOPN=TOPN, NM=NM, c0=c0, PAR=PAR, CMPP=CMPP, AM=AM,
             ic_best=ic_best, ret_best=ret_best, agree=agree, rho_keys=rho_keys,
             selspace_head=selspace_head, selspace_head_ic=selspace_head_ic, DIRS=DIRS),
        file.path(OUT,"p1_parity.rds"))
cat("\n[saved] p1_parity.rds\nOK\n")
