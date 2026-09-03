# RK7 — active 위험분해 · 예측 beta · 구간별 Σ 이질성 · 국면 상관 · vol/liq 잔차 진단
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); o4<-readRDS(file.path(OUT,"rk4_objects.rds")); o6<-readRDS(file.path(OUT,"rk6_objects.rds"))
Sig<-o6$Sig; wf<-o6$wf; w_cap<-o6$w_cap; w_ew<-o6$w_ew; B<-o4$B; Om<-o4$Om_lw; Dv<-o6$Dv; STY<-o3$STY
Fw<-o3$Fw; X<-o3$X; RES<-o3$RES
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
PR <- fread(file.path(OUT,"period_returns_production.csv")); PR[,signal_date:=as.Date(signal_date)]

## ── 예측 beta (Σ 기반) ──
bet_cap <- as.numeric(t(wf)%*%Sig%*%w_cap)/as.numeric(t(w_cap)%*%Sig%*%w_cap)
bet_ew  <- as.numeric(t(wf)%*%Sig%*%w_ew)/as.numeric(t(w_ew)%*%Sig%*%w_ew)
cat(sprintf("[RK7] 예측 beta vs cap-w %.3f · vs EW-uni %.3f (alpha 실현 beta 0.737)\n", bet_cap, bet_ew))

## ── active 위험 분해 (vs cap-w) ──
d <- wf-w_cap; av2 <- as.numeric(t(d)%*%Sig%*%d)
Bd <- as.numeric(t(B)%*%d); names(Bd)<-colnames(B)
contrib_a <- Bd*as.numeric(Om%*%Bd); spec_a <- sum(d^2*Dv)
grp <- c(MKT="MKT", setNames(rep("SECTOR",length(o4$secs_a)),o4$secs_a), setNames(STY,STY))
cs_a <- tapply(contrib_a, grp[names(contrib_a)], sum)/av2
cat(sprintf("[RK7] active(vs cap-w) TE %.2f%%/yr · 요인 %.1f%% · 특이 %.1f%%\n",100*sqrt(av2*12),100*sum(contrib_a)/av2,100*spec_a/av2))
print(round(100*sort(cs_a,decreasing=TRUE),2))
d2 <- wf-w_ew; av2e <- as.numeric(t(d2)%*%Sig%*%d2); Bde <- as.numeric(t(B)%*%d2); names(Bde)<-colnames(B)
cs_ae <- tapply(Bde*as.numeric(Om%*%Bde), grp[names(Bde)], sum)/av2e
cat(sprintf("[RK7] active(vs EW-uni) TE %.2f%%/yr\n",100*sqrt(av2e*12))); print(round(100*sort(cs_ae,decreasing=TRUE),2))
cat("[RK7] book 스타일 노출 B'w:\n"); print(round(o6$Bw[STY],3))
cat("[RK7] active 스타일 노출 (vs cap-w):\n"); print(round(Bd[STY],3))

## ── 구간별 Σ 이질성 ──
day <- fread(file.path(OUT,"rk_book_daily.csv")); day[,Date:=as.Date(Date)]
rl <- load_rawdata(use_cache=TRUE); RAW <- as.data.table(rl$RAWDATA); rm(rl); gc(verbose=FALSE)
RAW[,Date:=as.Date(Date)]; RAW <- RAW[Date>=as.Date("2005-01-01") & is.finite(Ret)]
hold <- A[in_top25==TRUE,.(sd=Date,Ticker)]
hold <- merge(hold, PR[,.(sd=signal_date,ym=holding_ym)], by="sd")
RAW[,ym:=format(Date,"%Y-%m")]
HD <- merge(hold[,.(ym,Ticker)], RAW[,.(ym,Ticker,Date,Ret)], by=c("ym","Ticker"), allow.cartesian=TRUE)
# 월별 평균 개별분산 + book 분산 → 내재 평균상관
mstat <- HD[,.(vi=var(Ret,na.rm=TRUE)),by=.(ym,Ticker)][,.(avg_var=mean(vi,na.rm=TRUE), n=.N),by=ym]
bstat <- day[,.(var_b=var(ret_d,na.rm=TRUE), nd=.N, bm_var=var(BM_Ret,na.rm=TRUE),
                cov_bm=stats::cov(ret_d,BM_Ret,use="complete.obs")),by=ym]
MS <- merge(mstat,bstat,by="ym")
MS[, avg_corr := (n*var_b - avg_var)/((n-1)*avg_var)]
MS[, beta_d := cov_bm/bm_var]
MS[, dt := as.Date(paste0(ym,"-01"))]
regime_of <- function(dt) fifelse(dt<as.Date("2015-01-01"),"P1_2005_2014", fifelse(dt<as.Date("2020-01-01"),"P2_2015_2019","P3_2020_2026"))
MS[, sub := regime_of(dt)]
sp <- MS[,.(months=.N, book_vol_ann=sqrt(mean(var_b))*sqrt(252), avg_name_vol_ann=sqrt(mean(avg_var))*sqrt(252),
            avg_pairwise_corr=mean(avg_corr,na.rm=TRUE), bm_vol_ann=sqrt(mean(bm_var))*sqrt(252),
            beta_daily=mean(beta_d,na.rm=TRUE)), by=sub][order(sub)]
print(sp)
## 구간별 요인 공분산 (Ω_sub) + 그 구간 평균 노출로 예측한 book 위험 구성
Fm <- as.matrix(Fw[,-1]); rownames(Fm)<-as.character(Fw$Date); Fm[!is.finite(Fm)]<-0
FD <- data.table(Date=as.Date(rownames(Fm)))
FD[, sub := regime_of(Date+31)]
sub_om <- list(); sub_fvol <- list()
for(s in unique(sp$sub)){
  idx <- which(FD$sub==s); Fs <- Fm[idx,,drop=FALSE]
  Oms <- cov(Fs); sub_om[[s]] <- Oms
  sub_fvol[[s]] <- sqrt(diag(Oms)*12)
}
FV <- do.call(cbind, lapply(sub_fvol, function(v) v[c("MKT",STY)]))
cat("[RK7] 구간별 요인 연율변동성:\n"); print(round(100*FV,2))
# 구간별 요인 상관 (핵심 축)
cormat <- lapply(sub_om, function(M){ s<-sqrt(diag(M)); C<-M/outer(s,s); C[c("MKT",STY),c("MKT",STY)] })
for(s in names(cormat)){ cat("[RK7] 요인상관",s,"(MKT vs styles):\n"); print(round(cormat[[s]]["MKT",],3)) }

## 위기 국면
crisis <- list(GFC_2008=c("2007-11-01","2009-03-31"), EuDebt_2011=c("2011-05-01","2011-12-31"),
  China_2015=c("2015-06-01","2016-02-29"), COVID_2020=c("2020-02-01","2020-04-30"),
  RateHike_2022=c("2022-01-01","2022-10-31"), KR_Bear_2018=c("2018-01-29","2019-01-03"))
cr <- rbindlist(lapply(names(crisis), function(nm){
  w0 <- as.Date(crisis[[nm]][1]); w1 <- as.Date(crisis[[nm]][2])
  dd <- day[Date>=w0 & Date<=w1]; if(nrow(dd)<10) return(NULL)
  ms <- MS[dt>=as.Date(format(w0,"%Y-%m-01")) & dt<=w1]
  data.table(regime=nm, start=as.character(w0), end=as.character(w1), n_days=nrow(dd),
    book_ret=prod(1+dd$ret_d)-1, bm_ret=prod(1+dd$BM_Ret)-1,
    book_vol_ann=sd(dd$ret_d)*sqrt(252), max_dd=min(cumprod(1+dd$ret_d)/cummax(cumprod(1+dd$ret_d))-1),
    avg_pairwise_corr=mean(ms$avg_corr,na.rm=TRUE), beta=mean(ms$beta_d,na.rm=TRUE),
    coverage=mean(ms$n,na.rm=TRUE)/25) }))
print(cr)
## 상시 vs 위기 상관
calm <- MS[!(dt %in% unlist(lapply(crisis,function(z) MS[dt>=as.Date(format(as.Date(z[1]),"%Y-%m-01")) & dt<=as.Date(z[2]),dt])))]
cat(sprintf("[RK7] 평시 평균 pairwise corr %.4f vs 위기 %.4f\n", mean(calm$avg_corr,na.rm=TRUE),
    mean(MS[!(ym %in% calm$ym),avg_corr],na.rm=TRUE)))

## ── vol / liquidity 잔차 잔존 진단 ──
held <- o6$top
hb <- X[Date==o4$asof & Ticker %in% held]
sv <- sqrt(Dv[held]*12)
cat(sprintf("[RK7] 보유25 특이변동성 vs VOL노출 corr %.3f · vs LIQ노출 corr %.3f\n",
  cor(sv, hb$VOL[match(held,hb$Ticker)]), cor(sv, hb$LIQ[match(held,hb$Ticker)])))
# 전 구간: 월별 보유 book 의 VOL/LIQ 노출 시계열
mono <- rbindlist(lapply(sort(unique(A[in_top25==TRUE]$Date)), function(d){
  hh <- A[Date==d & in_top25==TRUE,Ticker]; xd <- X[Date==d & Ticker %in% hh]
  cw <- X[Date==d]; cwv <- cw$Size/sum(cw$Size,na.rm=TRUE)
  data.table(Date=d, VOL=mean(xd$VOL), LIQ=mean(xd$LIQ), SIZE=mean(xd$SIZE), MOM=mean(xd$MOM), SIGNAL=mean(xd$SIGNAL),
    VOL_a=mean(xd$VOL)-sum(cwv*cw$VOL,na.rm=TRUE), LIQ_a=mean(xd$LIQ)-sum(cwv*cw$LIQ,na.rm=TRUE),
    SIZE_a=mean(xd$SIZE)-sum(cwv*cw$SIZE,na.rm=TRUE))}))
mono[, sub := regime_of(Date+31)]
print(mono[,.(VOL=mean(VOL),LIQ=mean(LIQ),SIZE=mean(SIZE),MOM=mean(MOM),SIGNAL=mean(SIGNAL),
              VOL_a=mean(VOL_a),LIQ_a=mean(LIQ_a),SIZE_a=mean(SIZE_a)),by=sub][order(sub)])
# 잔차 수익(book 특이수익) 이 rv63/amihud 팩터로 흡수되는가 — 위험축 회귀
Fdt <- as.data.table(Fw); Fdt[,Date:=as.Date(Date)]
bk <- PR[,.(Date=signal_date, r=ret_gross, bm=benchmark_ret)]
mm <- merge(bk, Fdt, by="Date")
fit <- lm(I(r-bm) ~ MKT+SIZE+MOM+REV+VOL+LIQ+INDMOM, data=mm)
print(summary(fit)$coefficients)
cat(sprintf("[RK7] active~risk factors R2 %.3f\n", summary(fit)$r.squared))
saveRDS(list(bet_cap=bet_cap,bet_ew=bet_ew,cs_a=cs_a,cs_ae=cs_ae,av2=av2,av2e=av2e,Bd=Bd,
  spec_a=spec_a,contrib_a=contrib_a,sp=sp,FV=FV,cormat=cormat,cr=cr,MS=MS,mono=mono,fit=fit,
  sub_om=sub_om), file.path(OUT,"rk7_objects.rds"))
fwrite(MS, file.path(OUT,"rk_monthly_regime_stats.csv"))
cat("[RK7] done\n")
