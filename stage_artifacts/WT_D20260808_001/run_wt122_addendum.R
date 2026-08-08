# =============================================================================
# run_wt122_addendum.R — WT-D20260808_001 자기 적대검증에서 나온 두 통제
#   ① F2 사이즈 교락 통제: 개인 순매수는 대형주에서 구조적으로 낮다 —
#      log(Size) 통제 후에도 필터 z 집중이 남는가 (남지 않으면 F2 = 사이즈 대용)
#   ② subperiod 상세 (Q01 subperiod_stability 0.33 의 정체)
#   ③ 직교 통제 arm 의 차이 자체가 유의한가 (paired: Q01 arm − Q01⊥D03 arm)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/run_wt122_addendum.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[add] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

FILT <- c("D03_EWMA","Q01_EB"); Q_PRIMARY <- 0.20
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Size","K200","KQ150")))[, Date := as.Date(Date)]
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
nw_ci <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(c(NA,NA));f<-lm(x~1)
  se<-tryCatch(sqrt(sandwich::NeweyWest(f,lag=lag,prewhite=FALSE)[1,1]),error=function(e)NA_real_)
  mean(x)+c(-1,1)*qt(0.975,df=length(x)-1L)*se}
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]
ADD <- list()

# ── ① F2 사이즈 교락 통제 ────────────────────────────────────────────────────
say("=== ① F2 사이즈 교락 통제 — 개인 순매수 ~ 필터z + log(Size) ===")
IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date),
    min(IND$Date), max(IND$Date))
IND[, ym:=format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym:=format(Date,"%Y-%m")]
INM <- merge(INM, SIGM, by="ym")[, ym:=NULL]
INM <- merge(INM, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
INM[, `:=`(nb_norm=nb/Size, lsz=log(Size))]
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)], INM[,.(Date,Ticker,nb_norm,lsz)], by=c("Date","Ticker"))
  s <- D[, {
    ok <- is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)
    if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12 && sd(lsz[ok])>1e-8) {
      yz <- (nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok])
      xz <- (fz[ok]-mean(fz[ok]))/sd(fz[ok]); sz <- (lsz[ok]-mean(lsz[ok]))/sd(lsz[ok])
      cf <- coef(lm(yz ~ xz + sz))
      cf1 <- coef(lm(yz ~ xz))
      .(b_ctl=unname(cf[2]), b_size=unname(cf[3]), b_raw=unname(cf1[2]), n=sum(ok))
    } else .(b_ctl=NA_real_,b_size=NA_real_,b_raw=NA_real_,n=sum(ok))
  }, by=Date][is.finite(b_ctl)]
  ci <- nw_ci(s$b_ctl)
  ADD[[paste0("F2_size_ctl_",f)]] <- list(b_raw=mean(s$b_raw), t_raw=nw_t(s$b_raw),
    b_size_ctl=mean(s$b_ctl), t_size_ctl=nw_t(s$b_ctl), ci_size_ctl=ci,
    b_on_size=mean(s$b_size), t_on_size=nw_t(s$b_size),
    retention=mean(s$b_ctl)/mean(s$b_raw), n_month=nrow(s), n_avg=mean(s$n))
  say("  %s: 원 기울기 %+.4f (t %+.2f) → log(Size) 통제 후 %+.4f (t %+.2f) CI[%+.4f,%+.4f] 잔존 %.2f | size 자체 %+.4f (t %+.2f)",
      f, mean(s$b_raw), nw_t(s$b_raw), mean(s$b_ctl), nw_t(s$b_ctl), ci[1], ci[2],
      mean(s$b_ctl)/mean(s$b_raw), mean(s$b_size), nw_t(s$b_size))
}

# ── ② subperiod 상세 ─────────────────────────────────────────────────────────
say("=== ② subperiod 상세 (rank IC) ===")
for (f in c("M01_PATHQ", FILT)) {
  sc <- if (f=="M01_PATHQ") E[,.(Date,Ticker,score)] else FZ[F_==f,.(Date,Ticker,score=fz)]
  D <- merge(sc, returns_dt, by=c("Date","Ticker"))
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  ic[, p:=fifelse(Date<as.Date("2015-01-01"),"P1_2001_2014",
        fifelse(Date<as.Date("2020-01-01"),"P2_2015_2019","P3_2020_2026"))]
  tb <- ic[, .(ic_mean=mean(ic), ic_t_nw=nw_t(ic), n=.N), by=p][order(p)]
  ADD[[paste0("subperiod_",f)]] <- as.list(tb)
  say("  %s: %s", f, paste(sprintf("%s IC %+.4f (t %+.2f, n=%d)", tb$p, tb$ic_mean, tb$ic_t_nw, tb$n), collapse=" | "))
}

# ── ③ 직교 통제 arm 과 원 arm 의 차이 자체가 유의한가 ────────────────────────
say("=== ③ paired: EXCL_Q01 vs EXCL_Q01⊥D03 (차이 자체의 유의성) ===")
W <- dcast(FZ[,.(Date,Ticker,F_,fz)], Date+Ticker~F_, value.var="fz")
setnames(W, c("D03_EWMA","Q01_EB"), c("d03","q01"))
W[, q01_res := { ok<-is.finite(d03)&is.finite(q01); r<-rep(NA_real_,.N)
  if (sum(ok)>=20L && sd(d03[ok])>1e-8) r[ok]<-residuals(lm(q01[ok]~d03[ok])); r }, by=Date]
ORTH <- W[is.finite(q01_res), .(Date,Ticker,fz=q01_res)][, q_rank:=frank(fz)/.N, by=Date]
arm <- function(excl, tag) {
  S <- merge(E[,.(Date,Ticker,score)], excl[,.(Date,Ticker,drop_=TRUE)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(drop_)][, drop_:=NULL]
  canonical_screen_bt(S, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt,
    liq_min=2e8, run_id=paste0("add_",tag), strategy_id=tag, diag_dual_basis=FALSE)
}
c1 <- arm(FZ[F_=="Q01_EB" & q_rank<=Q_PRIMARY], "A_EXCL_Q01")
c2 <- arm(ORTH[q_rank<=Q_PRIMARY], "A_EXCL_Q01ORTH")
d <- merge(as.data.table(c1$period_returns)[,.(date,a=ret_net)],
           as.data.table(c2$period_returns)[,.(date,b=ret_net)], by="date")
d[, diff:=a-b]
ci <- nw_ci(d$diff)
ADD$orth_gap <- list(diff_ann_pct=100*12*mean(d$diff), t_nw=nw_t(d$diff),
  ci_ann_pct=100*12*ci, n=nrow(d))
say("  (Q01 arm − Q01⊥D03 arm) 연 %+.2f%%  NW t=%+.2f  CI[%+.2f,%+.2f]  n=%d",
    100*12*mean(d$diff), nw_t(d$diff), 100*12*ci[1], 100*12*ci[2], nrow(d))
say("  → 이 차이가 비유의면 '직교화가 효과를 없앴다'고 말할 수 없다 (두 arm 이 서로 구별되지 않음)")

saveRDS(ADD, file.path(OUT,"wt122_addendum.rds"))
say("=== addendum 완료 → wt122_addendum.rds ===")
