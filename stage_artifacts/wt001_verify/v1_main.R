# v1_main.R — WT-D20260808_001 (FQ-122) 주장 A/B/D 반증 시도 (READ-ONLY 재현)
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
VER <- file.path(ROOT, "stage_artifacts/wt001_verify")
say <- function(fmt, ...) cat(sprintf(paste0("[ver] ", fmt, "\n"), ...))
FILT <- c("D03_EWMA","Q01_EB")

nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_); f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f, lag=lag, prewhite=FALSE))[1,3]), error=function(e) NA_real_) }

# ── 입력 실측 (가정 금지) ────────────────────────────────────────────────────
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
say("INPUT returns_dt nrow=%d MONTHLY n_month=%d %s~%s", nrow(returns_dt), uniqueN(returns_dt$Date), min(returns_dt$Date), max(returns_dt$Date))

BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
say("INPUT base_panel nrow=%d n_month=%d | tuned nrow=%d n_month=%d", nrow(BASE), uniqueN(BASE$Date), nrow(TUNED), uniqueN(TUNED$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date:=as.Date(Date)]
say("INPUT RAWDATA nrow=%d DAILY n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym:=format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]

score_of <- function(f){ sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f, .(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f, .(Date,Ticker,score=score)]; merge(sc[!is.na(score)], UNIV, by=c("Date","Ticker")) }

E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
say("eligible set nrow=%d n_month=%d 월평균 %.1f종목", nrow(E), uniqueN(E$Date), nrow(E)/uniqueN(E$Date))
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank := frank(fz)/.N, by=.(Date,F_)]
say("FZ nrow=%d (factor x stock-month)", nrow(FZ))

RES <- list()

# ══ A. β-drag 재현 + 시계열 의존 진단 ═══════════════════════════════════════
say("=== A. beta (trailing 60m, min24, 당월 미포함) ===")
RM <- merge(returns_dt, bench_dt, by="Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[, { ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
    if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_) }, by=Ticker][is.finite(beta)]
  bb[, Date := dts[i]]; beta_l[[i]] <- bb[, .(Date,Ticker,beta)]
}
BETA <- rbindlist(beta_l)
say("beta panel nrow=%d n_month=%d", nrow(BETA), uniqueN(BETA$Date))
Ares <- list()
for (f in FILT) {
  D <- merge(FZ[F_==f, .(Date,Ticker,fz,q_rank)], BETA, by=c("Date","Ticker"))
  s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), b_bot=median(beta[q_rank<=0.2])), by=Date]
  s <- s[is.finite(b_top)&is.finite(b_med)][order(Date)]
  d <- s$b_top - s$b_med
  ac <- acf(d, lag.max=72, plot=FALSE)$acf[-1]
  rho1 <- ac[1]
  n <- length(d)
  n_eff <- n*(1-rho1)/(1+rho1)
  # 횡단면 상관: 팩터 z vs beta (기계적 동일성 여부)
  cs <- D[, .(sp=suppressWarnings(cor(fz,beta,method="spearman"))), by=Date]
  Ares[[f]] <- list(beta_top=mean(s$b_top), beta_univ=mean(s$b_med), diff=mean(d),
    t_nw3=nw_t(d,3L), t_nw12=nw_t(d,12L), t_nw36=nw_t(d,36L), t_nw60=nw_t(d,60L),
    t_iid=mean(d)/(sd(d)/sqrt(n)), n=n, rho1=rho1, rho12=ac[12], rho36=ac[36], rho60=ac[60],
    n_eff_ar1=n_eff, t_eff_ar1=mean(d)/(sd(d)/sqrt(n_eff)),
    cs_spearman_fz_beta=median(cs$sp, na.rm=TRUE))
  a <- Ares[[f]]
  say("  %s: top %.3f vs univ %.3f diff %+.3f | t_iid %+.2f NW3 %+.2f NW12 %+.2f NW36 %+.2f NW60 %+.2f | rho1 %.3f rho12 %.3f rho36 %.3f | n=%d n_eff=%.1f t_eff %+.2f | CS spearman(fz,beta) med %+.3f",
      f, a$beta_top, a$beta_univ, a$diff, a$t_iid, a$t_nw3, a$t_nw12, a$t_nw36, a$t_nw60,
      a$rho1, a$rho12, a$rho36, a$n, a$n_eff_ar1, a$t_eff_ar1, a$cs_spearman_fz_beta)
}
RES$A <- Ares

# ══ B. 분위 평균 vs 순위 — 왜도 직접 측정 ═══════════════════════════════════
say("=== B. quintile mean/median/skew (D03, Q01, M01) ===")
skew1 <- function(x){ x<-x[is.finite(x)]; if(length(x)<8) return(NA_real_); m<-mean(x); s<-sd(x); if(s<=0) return(NA_real_); mean((x-m)^3)/s^3 }
winz <- function(x,p=0.01){ q<-quantile(x, c(p,1-p), na.rm=TRUE); pmin(pmax(x,q[1]),q[2]) }
specs <- list(M01_PATHQ=E[,.(Date,Ticker,score)],
              D03_EWMA=FZ[F_=="D03_EWMA",.(Date,Ticker,score=fz)],
              Q01_EB  =FZ[F_=="Q01_EB",  .(Date,Ticker,score=fz)])
Bres <- list()
for (nm in names(specs)) {
  D <- merge(specs[[nm]], returns_dt, by=c("Date","Ticker"))
  M <- D[, { q <- cut(frank(score), breaks=5, labels=FALSE)
    .(q=q, r=Ret_1m) }, by=Date]
  # 월별 분위 EW 수익 (= 분위 평균) 시계열
  P <- M[, .(mu=mean(r,na.rm=TRUE), med=median(r,na.rm=TRUE), mu_w=mean(winz(r),na.rm=TRUE),
             sk=skew1(r), sdv=sd(r,na.rm=TRUE), n=.N), by=.(Date,q)]
  W <- dcast(P, Date~q, value.var="mu")
  setnames(W, as.character(1:5), paste0("m",1:5))
  W[, dq15 := m1 - m5]
  Wm <- dcast(P, Date~q, value.var="med"); setnames(Wm, as.character(1:5), paste0("md",1:5))
  Ww <- dcast(P, Date~q, value.var="mu_w"); setnames(Ww, as.character(1:5), paste0("w",1:5))
  qm  <- sapply(paste0("m",1:5), function(k) mean(W[[k]], na.rm=TRUE))*12*100
  qmd <- sapply(paste0("md",1:5), function(k) mean(Wm[[k]], na.rm=TRUE))*12*100
  qmw <- sapply(paste0("w",1:5), function(k) mean(Ww[[k]], na.rm=TRUE))*12*100
  qsk <- P[, .(sk=mean(sk,na.rm=TRUE), sdv=mean(sdv,na.rm=TRUE)), by=q][order(q)]
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  Bres[[nm]] <- list(quintile_mean_ann=qm, quintile_median_ann=qmd, quintile_winz1pct_ann=qmw,
    quintile_skew=qsk$sk, quintile_sd_monthly=qsk$sdv,
    mono_mean=mean(diff(qm)>0), mono_median=mean(diff(qmd)>0), mono_winz=mean(diff(qmw)>0),
    dq15_ann=100*12*mean(W$dq15,na.rm=TRUE), dq15_t_nw3=nw_t(W$dq15,3L),
    dq15_t_iid=mean(W$dq15,na.rm=TRUE)/(sd(W$dq15,na.rm=TRUE)/sqrt(sum(is.finite(W$dq15)))),
    rank_ic=mean(ic$ic), harvey_t=nw_t(ic$ic), n_month=nrow(ic))
  b <- Bres[[nm]]
  say("  %-10s rank_IC %+.4f Harvey-t %+.2f | mono(mean) %.2f", nm, b$rank_ic, b$harvey_t, b$mono_mean)
  say("     Q1..Q5 mean   ann %%: %s", paste(sprintf("%+.1f",qm), collapse=" "))
  say("     Q1..Q5 median ann %%: %s   mono %.2f", paste(sprintf("%+.1f",qmd), collapse=" "), b$mono_median)
  say("     Q1..Q5 winz1%% ann %%: %s   mono %.2f", paste(sprintf("%+.1f",qmw), collapse=" "), b$mono_winz)
  say("     Q1..Q5 skew(월평균 횡단면): %s", paste(sprintf("%+.2f",qsk$sk), collapse=" "))
  say("     Q1..Q5 sd(월 횡단면):       %s", paste(sprintf("%.3f",qsk$sdv), collapse=" "))
  say("     Q1-Q5 spread ann %+.2f%%  NW3 t %+.2f  iid t %+.2f  (n=%d)", b$dq15_ann, b$dq15_t_nw3, b$dq15_t_iid, b$n_month)
}
RES$B <- Bres

saveRDS(RES, file.path(VER,"v1_res.rds"))
say("=== v1 완료 ===")
