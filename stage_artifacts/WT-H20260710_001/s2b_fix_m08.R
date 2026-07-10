# WT-H20260710_001 Stage 2b — FIX Block B M08 CAPM formation.
# Bug: previous code fit CAPM on the summation slice -> residuals sum ~0 (degenerate).
# Fix (matches compute_momentum.R): fit CAPM on FULL trailing window, slice residuals [n-lb+1 : n-sk], sum.
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")
inp<-readRDS(file.path(SA,"inputs.rds")); scope<-inp$scope; dts<-inp$dts
zc <- function(x){ s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) return(x*0); (x-mean(x,na.rm=TRUE))/s }
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Ret","BM_Ret")))
raw[,Date:=as.Date(Date)]; raw<-raw[!is.na(Ret)&!is.na(BM_Ret)]; setkey(raw,Ticker,Date)
Bvar<-list(B0_inc_252_21_capm=list(lb=252L,sk=21L,resid="capm"),
           B1_126_21_capm=list(lb=126L,sk=21L,resid="capm"),
           B2_378_21_capm=list(lb=378L,sk=21L,resid="capm"),
           B3_252_0_capm =list(lb=252L,sk=0L, resid="capm"),
           B4_252_21_raw =list(lb=252L,sk=21L,resid="raw"))
out<-vector("list",length(dts))
for(i in seq_along(dts)){
  SD<-dts[i]; W<-raw[Date<=SD & Date>=(SD-620)]
  if(!nrow(W)) next
  res<-W[,{
    n<-.N; o<-as.list(rep(NA_real_,length(Bvar))); names(o)<-names(Bvar)
    if(n>=30L){
      r<-Ret; b<-BM_Ret
      capm_res<-NULL
      # fit CAPM once on FULL window
      fit<-tryCatch(.lm.fit(cbind(1,b),r),error=function(e) NULL)
      if(!is.null(fit)) capm_res<-fit$residuals
      for(vn in names(Bvar)){ vv<-Bvar[[vn]]; lb<-vv$lb; sk<-vv$sk
        if(n>=lb){
          ie<-n-sk; is<-max(1L,n-lb+1L)
          if(ie>is){
            if(vv$resid=="capm"){ if(!is.null(capm_res)) o[[vn]]<-sum(capm_res[is:ie]) }
            else o[[vn]]<-prod(1+r[is:ie])-1
          }
        }
      }
    }
    o
  },by=Ticker]
  res[,Date:=SD]; out[[i]]<-res
  if(i%%50==0) cat(" B-fix",i,"/",length(dts),"\n")
}
mp<-rbindlist(out,use.names=TRUE,fill=TRUE); mp<-merge(scope,mp,by=c("Date","Ticker"))
for(vn in names(Bvar)) mp[,(paste0("z_",vn)):=zc(get(vn)),by=Date]
saveRDS(mp,file.path(SA,"m08_variants.rds"))
# sanity vs stored
d<-merge(mp[,.(Date,Ticker,z_B0_inc_252_21_capm,z_B1_126_21_capm,z_B2_378_21_capm,z_B3_252_0_capm,z_B4_252_21_raw)],
         inp$def_panel[,.(Date,Ticker,M08s=M08_Residual_Mom)],by=c("Date","Ticker"))
sc<-function(col) d[!is.na(get(col))&!is.na(M08s),.(c=cor(get(col),M08s)),by=Date][,mean(c,na.rm=TRUE)]
for(col in c("z_B0_inc_252_21_capm","z_B1_126_21_capm","z_B2_378_21_capm","z_B3_252_0_capm","z_B4_252_21_raw"))
  cat(sprintf("%-24s vs stored M08 aligned-Z: %.4f\n",col,sc(col)))
# inter-variant cor
cat(sprintf("B0 vs B1(126): %.3f | B0 vs B2(378): %.3f | B0 vs B3(skip0): %.3f | B0 vs B4(raw): %.3f\n",
  d[!is.na(z_B0_inc_252_21_capm)&!is.na(z_B1_126_21_capm),.(c=cor(z_B0_inc_252_21_capm,z_B1_126_21_capm)),by=Date][,mean(c,na.rm=T)],
  d[!is.na(z_B0_inc_252_21_capm)&!is.na(z_B2_378_21_capm),.(c=cor(z_B0_inc_252_21_capm,z_B2_378_21_capm)),by=Date][,mean(c,na.rm=T)],
  d[!is.na(z_B0_inc_252_21_capm)&!is.na(z_B3_252_0_capm),.(c=cor(z_B0_inc_252_21_capm,z_B3_252_0_capm)),by=Date][,mean(c,na.rm=T)],
  d[!is.na(z_B0_inc_252_21_capm)&!is.na(z_B4_252_21_raw),.(c=cor(z_B0_inc_252_21_capm,z_B4_252_21_raw)),by=Date][,mean(c,na.rm=T)]))
cat("[saved] m08_variants.rds (FIXED)\n")
