# =============================================================
# WT-D20260529_001 FLOW — Optimizer FINALIZE
# (1) EW-50 buffered FLOW sleeve monthly net returns (TO-feasible method)
# (2) multi-sleeve blend with STR_1715 (realized monthly basis) + sweep + LOO
# (3) portfolio-level monthly CVaR cap check
# (4) honest SR 2.5 judgment (AX-000)
# (5) weights.csv schedule emission (as_of_date column, RF-O9 walk-forward)
# (6) schedule density check (-> infeasibility_report if quarterly forced by TO mandate)
# No self-synthesis: metrics via PerformanceAnalytics; blend = linear combo of 2 realized streams.
# =============================================================
suppressMessages({library(data.table);library(arrow);library(xts);library(PerformanceAnalytics)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT<-file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
LOCKBOX<-as.Date("2023-12-22"); COST_OW<-0.0015; SEL<-"EW 50"; SEL_LABEL<-"EW_hysteresis_buffer_en50"

b  <- readRDS(file.path(OUT,"opt_buffer2.rds"))
wl <- b$best_wl[[SEL]]                       # 76 quarterly weight sets (named vec, sum=1)
G  <- b$G

# ---- monthly machinery (same as buffer2) ----
rd<-as.data.table(read_parquet(".cache/rawdata.parquet"))[Date<=LOCKBOX,.(Date,Ticker,Ret,BM_Ret)]
rd[,ym:=format(Date,"%Y-%m")]
mret<-rd[!is.na(Ret),.(mret=prod(1+Ret)-1),by=.(Ticker,ym)]; setkey(mret,Ticker,ym)
bm_m<-unique(rd[!is.na(BM_Ret),.(Date,BM_Ret,ym)])[,.(bm=prod(1+BM_Ret)-1),by=ym]; setkey(bm_m,ym)
months_all<-sort(unique(rd$ym))
nextm<-function(m){i<-match(m,months_all);if(is.na(i)||i==length(months_all))NA_character_ else months_all[i+1]}

# rebal schedule: sig date -> hold starts next month
rb<-data.table(rebal=names(wl),
               start_month=sapply(names(wl),function(d)nextm(format(as.Date(d),"%Y-%m"))))[!is.na(start_month)][order(start_month)]
out<-data.table(ym=character(),ret_net=numeric(),turnover=numeric()); prev_w<-NULL; cur<-NA
for(m in months_all){
  cand<-rb[start_month<=m]; if(nrow(cand)==0)next
  r<-cand[.N,rebal]; w0<-wl[[r]]; if(is.null(w0))next
  isnew<-!identical(r,cur); to<-0
  if(isnew){
    if(is.null(prev_w)) to<-sum(abs(w0)) else{
      al<-union(names(prev_w),names(w0)); pw<-setNames(rep(0,length(al)),al); pw[names(prev_w)]<-prev_w
      nw<-setNames(rep(0,length(al)),al); nw[names(w0)]<-w0; to<-sum(abs(nw-pw))}
    cur<-r; w<-w0
  } else w<-prev_w
  gr<-mret[ym==m & Ticker%in%names(w)]; if(nrow(gr)==0)next
  wv<-w[gr$Ticker]; wv[is.na(wv)]<-0; rg<-sum(wv*gr$mret,na.rm=T); rn<-rg-to*COST_OW
  out<-rbind(out,data.table(ym=m,ret_net=rn,turnover=to))
  g<-setNames(gr$mret,gr$Ticker)[names(w)]; g[is.na(g)]<-0; w<-w*(1+g); w<-w/sum(w); prev_w<-w
}
flow<-out[,.(ym,flow_ret=ret_net,flow_to=turnover)]
cat(sprintf("[final] FLOW(%s) sleeve months: %d\n", SEL_LABEL, nrow(flow)))

# ---- blend with STR_1715 (realized monthly, Charter v1.4 standard basis) ----
s<-fread("qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv")
s[,ym:=format(as.Date(Date),"%Y-%m")]; s<-s[,.(ym,s1715=monthly_ret)]
M<-Reduce(function(a,b) merge(a,b,by="ym"), list(flow, s, bm_m))
setorder(M,ym); M<-M[ym<="2023-12"]
dts<-as.Date(paste0(M$ym,"-01"))
asr <-function(r) as.numeric(SharpeRatio.annualized(xts(r,dts),Rf=0,scale=12))
acagr<-function(r) as.numeric(Return.annualized(xts(r,dts),scale=12))
amdd<-function(r) as.numeric(maxDrawdown(xts(r,dts)))
air <-function(r,bb) as.numeric(SharpeRatio.annualized(xts(r-bb,dts),Rf=0,scale=12))
cvar_m<-function(r){q<-quantile(r,0.05); -mean(r[r<=q])}

sr1715<-asr(M$s1715); srflow<-asr(M$flow_ret); corR<-cor(M$s1715,M$flow_ret)
cat(sprintf("[final] common months %d (%s..%s) | STR_1715 SR=%.3f | FLOW SR=%.3f | cor=%.3f\n",
            nrow(M),min(M$ym),max(M$ym),sr1715,srflow,corR))

grid<-seq(0,0.5,0.05)
sweep<-rbindlist(lapply(grid,function(y){x<-1-y; r<-x*M$s1715+y*M$flow_ret
  data.table(flow_w=y,str1715_w=x,book_sr=round(asr(r),4),book_cagr=round(acagr(r),4),
             book_mdd=round(amdd(r),4),book_ir=round(air(r,M$bm),4),book_cvar95_m=round(cvar_m(r),4))}))
print(sweep); fwrite(sweep,file.path(OUT,"blend_sweep.csv"))

# selection: max book IR (active mgmt objective vs benchmark; net basis) within sane FLOW alloc
best<-sweep[which.max(book_ir)]
cat(sprintf("[final] max book IR @ FLOW=%.0f%%: SR=%.3f IR=%.3f CAGR=%.1f%% MDD=%.1f%%\n",
            best$flow_w*100,best$book_sr,best$book_ir,best$book_cagr*100,best$book_mdd*100))

# LOO
loo<-data.table(config=c("STR_1715 only","STR_1715 + FLOW"),
  book_sr=c(round(sr1715,4),best$book_sr),
  book_ir=c(round(air(M$s1715,M$bm),4),best$book_ir),
  book_cagr=c(round(acagr(M$s1715),4),best$book_cagr),
  book_mdd=c(round(amdd(M$s1715),4),best$book_mdd),
  book_cvar95_m=c(round(cvar_m(M$s1715),4),best$book_cvar95_m))
print(loo); fwrite(loo,file.path(OUT,"blend_loo.csv"))

# portfolio-level monthly CVaR cap (risk rec #3): cap set below sleeve monthly 0.157
CVAR_CAP_M<-0.15
book_best<-best$str1715_w*M$s1715+best$flow_w*M$flow_ret
book_cvar<-cvar_m(book_best); cvar_pass<-book_cvar<=CVAR_CAP_M
cat(sprintf("[CVaR] portfolio monthly CVaR95 cap=%.3f | realized book=%.4f | PASS=%s\n",CVAR_CAP_M,book_cvar,cvar_pass))

# SR 2.5 honest judgment
max_sr<-max(sweep$book_sr); reach<-max_sr>=2.5
cat(sprintf("[SR2.5] max achievable book SR (2-sleeve, lockbox window) = %.3f | reach 2.5 = %s\n",max_sr,reach))

# ---- weights.csv schedule emission (FLOW sleeve target weights, as_of_date column) ----
wrows<-rbindlist(lapply(names(wl),function(d){w<-wl[[d]]
  data.table(as_of_date=d, Ticker=names(w), weight=as.numeric(w))}))
setorder(wrows,as_of_date,-weight)
# constraint asserts
stopifnot(all(wrows$weight>=0), all(wrows$weight<=0.20+1e-9))
chk<-wrows[,.(n=.N,sw=sum(weight)),by=as_of_date]
stopifnot(all(chk$n<=20), all(abs(chk$sw-1)<1e-6))
fwrite(wrows,file.path(OUT,"weights.csv"))
cat(sprintf("[weights] emitted %d rows, %d unique as_of_dates, names/date max=%d, Sigma w in [%.4f,%.4f]\n",
            nrow(wrows),uniqueN(wrows$as_of_date),max(chk$n),min(chk$sw),max(chk$sw)))

# schedule density vs alpha sig_dates
alpha<-as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[Date<=LOCKBOX]
sig_n<-uniqueN(alpha$Date); sched_n<-uniqueN(wrows$as_of_date)
dens<-sched_n/sig_n
cat(sprintf("[density] alpha sig_dates=%d | schedule unique_dates=%d | ratio=%.3f (mandate>=0.95)\n",sig_n,sched_n,dens))

saveRDS(list(M=M,flow=flow,sweep=sweep,best=best,loo=loo,sel=SEL_LABEL,G=G,
  sr1715=sr1715,srflow=srflow,corR=corR,book_cvar=book_cvar,cvar_cap=CVAR_CAP_M,cvar_pass=cvar_pass,
  max_sr=max_sr,reach=reach,sig_n=sig_n,sched_n=sched_n,density=dens,
  flow_to_yr=G[method=="EW"&entry_n==50,rt_to_yr], wrows_n=nrow(wrows)),
  file.path(OUT,"opt_final.rds"))
cat("\n[done finalize]\n")
