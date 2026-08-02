## run_wt003_adversarial_checks.R — WT-D20260802_003 Self-Adversarial 보강 실측 3종
##  ① lag-1 스트레스: W_portt 가중 창을 [a-37, a-2]로 1개월 추가 지연 — 저장 파생 패널
##     (r6_factor_deployzone_active) 소비의 동월-누출 의심 검증 (붕괴 시 누출 의심)
##  ② theta 희소성: clip-at-zero가 실제로 몇 팩터를 0으로 만드는가 — "가중 개선"이
##     실은 soft-선별(membership) 효과인지 기전 귀속
##  ③ W_portt 양-theta 집합 vs Ppure top-20 풀 Jaccard — 정렬 정보의 membership 수렴도
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
OUT <- "stage_artifacts/WT_D20260802_003"
W36 <- 36L; K20 <- 20L; CADENCE <- 6L; TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8

af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_dates <- sort(unique(as.Date(g$signal_date))); n_sig <- length(sig_dates); rm(g)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawme_f, sig_dates); rm(rawdata, rawme_f); invisible(gc())
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ret <- fwd$returns_dt[,.(signal_date=as.Date(Date), security_id=Ticker, Ret_1m)]

sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(sort(unique(sc$factor_id)), names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())

PANEL <- as.data.table(read_parquet("outputs/ramp/r6_factor_deployzone_active.parquet"))
PANEL[, signal_date := as.Date(signal_date)]
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
PANEL_FACS <- setdiff(names(Pw), "signal_date")
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(Pw$signal_date)
n_pm <- nrow(Pmat)

## IC 패널 (선별 재현용 — 본판 자구동일)
IC_rows <- vector("list", n_sig-1L)
for(i in seq_len(n_sig-1L)){
  sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
  rr <- ret[signal_date==sig_dates[i], .(security_id, Ret_1m)]
  m <- merge(sub, rr, by="security_id"); if(nrow(m) < 30) next
  X <- as.matrix(m[, ..FW_FACS])
  IC_rows[[i]] <- suppressWarnings(as.numeric(cor(X, m$Ret_1m, method="spearman", use="pairwise.complete.obs")))
}
ICmat <- do.call(rbind, lapply(seq_len(n_sig-1L), function(i)
  if(is.null(IC_rows[[i]])) rep(NA_real_, length(FW_FACS)) else IC_rows[[i]]))
colnames(ICmat) <- FW_FACS

trail_icir <- function(a){ lo<-a-W36; hi<-a-1L; if(lo<1L) return(NULL)
  sub <- ICmat[lo:min(hi, nrow(ICmat)), , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); mean(x)/s }) }
trail_tt_win <- function(lo, hi){ if(lo<1L) return(NULL); hi <- min(hi, n_pm)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }) }

anchors <- seq(W36+1L, n_sig-1L, by=CADENCE)
ANCH <- list()
for(a in anchors){
  icir_a <- trail_icir(a)
  fin <- icir_a[is.finite(icir_a)]
  pool <- names(sort(fin, decreasing=TRUE))[seq_len(min(K20, length(fin)))]
  tt_base <- trail_tt_win(a-W36, a-1L)        # 본판
  tt_lag1 <- trail_tt_win(a-W36-1L, a-2L)     # lag-1 스트레스
  tt_sel  <- trail_tt_win(a-W36, a-1L)        # Ppure 선별 재현용 (동일)
  fin_t <- tt_sel[is.finite(tt_sel)]
  ppure_pool <- names(sort(fin_t, decreasing=TRUE))[seq_len(min(K20, length(fin_t)))]
  ANCH[[as.character(a)]] <- list(a=a, pool=pool, tt_base=tt_base, tt_lag1=tt_lag1, ppure_pool=ppure_pool)
}

build_wportt <- function(which_tt){
  rows <- list()
  for(i in (W36+1L):(n_sig-1L)){
    ga <- max(anchors[anchors <= i]); an <- ANCH[[as.character(ga)]]
    F <- intersect(an$pool, FW_FACS); if(length(F)==0) next
    tt <- an[[which_tt]][F]; v <- pmax(tt, 0); v[!is.finite(v)] <- 0
    th <- if(sum(v)<=0) rep(1/length(F), length(F)) else v/sum(v)
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=F]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id,
                                          score=as.numeric(Xm %*% th))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
build_base <- function(){
  rows <- list()
  for(i in (W36+1L):(n_sig-1L)){
    ga <- max(anchors[anchors <= i]); an <- ANCH[[as.character(ga)]]
    F <- intersect(an$pool, FW_FACS); if(length(F)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=F]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
run_gate <- function(comp, lab){
  cs <- canonical_screen_bt(comp[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="wt003adv", strategy_id=paste0("WT003adv_",lab),
        diag_dual_basis=FALSE)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr[, act_bm := ret_net - benchmark_ret]
  list(pt=nwt(pr$act_bm), pr=pr)
}

cat("=== ① lag-1 스트레스 ===\n")
g_base  <- run_gate(build_base(), "base")
g_p0    <- run_gate(build_wportt("tt_base"), "portt")
g_p1    <- run_gate(build_wportt("tt_lag1"), "portt_lag1")
m0 <- merge(g_p0$pr[,.(date,a=act_bm)], g_base$pr[,.(date,b=act_bm)], by="date")
m1 <- merge(g_p1$pr[,.(date,a=act_bm)], g_base$pr[,.(date,b=act_bm)], by="date")
cat(sprintf("  본판  W_portt PORT_t=%.3f | paired vs base = %+.3f (재현 대조)\n", g_p0$pt, nwt(m0$a-m0$b)))
cat(sprintf("  lag-1 W_portt PORT_t=%.3f | paired vs base = %+.3f\n", g_p1$pt, nwt(m1$a-m1$b)))

cat("\n=== ② theta 희소성 (clip-at-zero가 0으로 만든 팩터 수 / K=20) ===\n")
zs <- sapply(ANCH, function(an){ F <- intersect(an$pool, FW_FACS)
  tt <- an$tt_base[F]; sum(!is.finite(tt) | tt <= 0) })
cat(sprintf("  anchor별 zero-theta 수: mean=%.2f median=%d min=%d max=%d (n_anchor=%d)\n",
    mean(zs), as.integer(median(zs)), min(zs), max(zs), length(zs)))
## 유효 팩터수 (1/sum(theta^2), Herfindahl 역수)
neff <- sapply(ANCH, function(an){ F <- intersect(an$pool, FW_FACS)
  tt <- an$tt_base[F]; v <- pmax(tt,0); v[!is.finite(v)] <- 0
  if(sum(v)<=0) return(length(F)); th <- v/sum(v); 1/sum(th^2) })
cat(sprintf("  유효 팩터수 n_eff: mean=%.2f median=%.2f (EW면 20)\n", mean(neff), median(neff)))

cat("\n=== ③ W_portt 양-theta 집합 vs Ppure top-20 Jaccard ===\n")
jac <- sapply(ANCH, function(an){ F <- intersect(an$pool, FW_FACS)
  tt <- an$tt_base[F]; pos <- F[is.finite(tt) & tt > 0]
  pp <- an$ppure_pool
  if(length(pos)==0 || length(pp)==0) return(NA_real_)
  length(intersect(pos, pp)) / length(union(pos, pp)) })
cat(sprintf("  Jaccard(양-theta ICIR풀 ∩ Ppure풀): mean=%.3f median=%.3f\n",
    mean(jac,na.rm=TRUE), median(jac,na.rm=TRUE)))
## ICIR 풀과 Ppure 풀 자체의 겹침 (선별 규율 간 disjoint 정도)
jac_pool <- sapply(ANCH, function(an){ length(intersect(an$pool, an$ppure_pool)) /
  length(union(an$pool, an$ppure_pool)) })
cat(sprintf("  Jaccard(ICIR풀 ∩ Ppure풀 자체): mean=%.3f median=%.3f\n",
    mean(jac_pool,na.rm=TRUE), median(jac_pool,na.rm=TRUE)))

saveRDS(list(lag1=list(pt0=g_p0$pt, pt1=g_p1$pt, paired0=nwt(m0$a-m0$b), paired1=nwt(m1$a-m1$b)),
             zero_theta=zs, n_eff=neff, jaccard_postheta_ppure=jac, jaccard_pools=jac_pool),
        file.path(OUT, "wt003_adversarial_checks.rds"))
cat("ADV_DONE\n")
