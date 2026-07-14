## run_r33_sizeneutral.R — Branch B net-buy 클러스터 +3.36 신호의 size-confound 검정.
## 우려: 임원 순매수가 소형주에 집중 → forward-gap 이 size 프리미엄 아티팩트일 수 있음.
## 검정: (a) 월별 forward-ret 을 log(Size_{t-1}) 에 회귀한 잔차 gap (flag-nonflag) NW-t
##        (b) size 3분위(소/중/대) 내 gap — 국소성 확인
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
ym <- function(d) as.integer(format(as.Date(d),"%Y"))*100L+as.integer(format(as.Date(d),"%m"))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
nwt <- function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA_real_);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"

clean <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
clean[,Date:=as.Date(Date)]; clean[,hold_ym:=ym(Date)]
raw <- as.data.table(read_parquet(RAW_P, col_select=c("Date","Ticker","Close","K200","KQ150","Size")))
raw[,Date:=as.Date(Date)]; raw <- raw[!is.na(Close)&Close>0]; raw[,yq:=ym(Date)]
me <- merge(raw, raw[,.(me=max(Date)),by=yq], by="yq")[Date==me]; setorder(me,Ticker,yq)
me[,`:=`(yq_prev=shift(yq),Size_prev=shift(Size),uni_prev=shift(K200==TRUE|KQ150==TRUE)),by=Ticker]
me[,cons:=(ymshift(yq_prev,1L)==yq)]
sz <- me[cons==TRUE & uni_prev==TRUE & !is.na(Size_prev)&Size_prev>0, .(hold_ym=yq, Ticker, Size_prev)]
rm(raw,me); invisible(gc())

ins <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet")); ins[,signal_date:=as.Date(signal_date)]
ins[,hold_ym:=ymshift(ym(signal_date),1L)]
insw <- dcast(ins, hold_ym+security_id~factor_id, value.var="z"); setnames(insw,"security_id","Ticker")

uni <- clean[,.(hold_ym, Ticker, Ret_1m)]
uni <- merge(uni, sz, by=c("hold_ym","Ticker"))            # size(t-1) 부착 → 유니버스 = clean∩size
fl <- insw[!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=1.0, .(hold_ym,Ticker,f=1L)]
uni <- merge(uni, fl, by=c("hold_ym","Ticker"), all.x=TRUE); uni[is.na(f),f:=0L]
uni[,lsz:=log(Size_prev)]

## (a) size-잔차 gap: 월별 Ret_1m ~ lsz 회귀 잔차, flag-nonflag 월별 gap NW-t
uni[, resid := { m<-lm(Ret_1m~lsz); as.numeric(residuals(m)) }, by=hold_ym]
g <- uni[,.(gap_raw=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE),
            gap_resid=mean(resid[f==1L],na.rm=TRUE)-mean(resid[f==0L],na.rm=TRUE),
            nf=sum(f==1L)), by=hold_ym][nf>0]
raw_t <- nwt(g$gap_raw); resid_t <- nwt(g$gap_resid)
raw_ann <- mean(g$gap_raw,na.rm=TRUE)*12; resid_ann <- mean(g$gap_resid,na.rm=TRUE)*12

## (b) size 3분위 내 gap
uni[, sz_tercile := cut(frank(Size_prev)/.N, breaks=c(0,1/3,2/3,1), labels=c("small","mid","large")), by=hold_ym]
terc <- uni[,.(gap=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L), nn=sum(f==0L)), by=.(hold_ym,sz_tercile)][nf>0]
tsum <- terc[,.(gap_ann=mean(gap,na.rm=TRUE)*12, gap_t=nwt(gap), months=.N, avg_flag=mean(nf)), by=sz_tercile]
## flag 의 size 분포
flag_sz_dist <- uni[f==1L, .N, by=sz_tercile][order(sz_tercile)]

cat(sprintf("[size-neutral] net-buy cluster forward-gap:\n"))
cat(sprintf("  raw gap: ann=%+.4f NW-t=%+.2f (months=%d)\n", raw_ann, raw_t, nrow(g)))
cat(sprintf("  size-resid gap: ann=%+.4f NW-t=%+.2f  <- size 통제 후\n", resid_ann, resid_t))
cat("  tercile gaps:\n"); print(tsum)
cat("  flag size distribution:\n"); print(flag_sz_dist)

res <- list(raw_gap_ann=raw_ann, raw_gap_t=raw_t, size_resid_gap_ann=resid_ann, size_resid_gap_t=resid_t,
  n_months=nrow(g), tercile=tsum, flag_size_dist=flag_sz_dist)
write_json(res, "stage_artifacts/WT_D20260715_002/r33_sizeneutral.json", auto_unbox=TRUE, pretty=TRUE, digits=5)
cat("[SAVED] r33_sizeneutral.json\n")
