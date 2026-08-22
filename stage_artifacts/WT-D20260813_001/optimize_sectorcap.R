## EW vs EW+semiconductor-cap(50%) walk-forward — does sector cap help net SR / MDD?
## sector per-date from RAWDATA (PIT: sector at holding month). semi cap redistributes to non-semis EW.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SA <- "stage_artifacts/WT-D20260813_001"; SRC <- "stage_artifacts/fq233_probe0_20260813"
inp <- readRDS(file.path(SRC,"r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[,.(Date=as.Date(Date),Ticker=as.character(Ticker),Ret_1m=as.numeric(Ret_1m))][is.finite(Ret_1m)]
scores <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))[,.(Date=as.Date(Date),sig_date=as.Date(sig_date),Ticker=as.character(Ticker),score=as.numeric(alpha_score))]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[,Date:=as.Date(Date)][is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret,order.by=bm$Date),Return.cumulative)
bench_m <- data.table(ym=format(as.Date(index(bmm)),"%Y%m"),BM_Ret=as.numeric(bmm[,1]))
returns_dt[,ym:=format(Date,"%Y%m")]
bench_dt <- merge(unique(returns_dt[,.(Date,ym)]),bench_m,by="ym")[,.(Date,BM_Ret)]
# sector map per Ticker-Date from RAWDATA (monthly last obs)
ds <- open_dataset(".cache/RAWDATA.parquet")
tks_all <- unique(scores$Ticker)
sec <- ds |> dplyr::filter(Ticker %in% tks_all) |> dplyr::select(Date,Ticker,Sector) |> dplyr::collect() |> as.data.table()
sec[, ym := format(as.Date(Date), "%Y%m")]
sec_m <- sec[, .(Sector = tail(Sector,1)), by = .(Ticker, ym)]

TOP_N<-25L;COST<-0.0015;BHI<-0.20
nwt<-function(x,lag=3L){x<-x[is.finite(x)];n<-length(x);m<-mean(x);e<-x-m;s<-sum(e^2)/n;for(l in 1:lag){w<-1-l/(lag+1);s<-s+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n};m/sqrt(s/n)}

semi_cap_w <- function(tk, semi, cap=0.50){
  n<-length(tk); w<-rep(1/n,n); names(w)<-tk
  sw<-sum(w[semi]); if(sw<=cap+1e-9) return(w)
  w[semi]<-w[semi]*(cap/sw); freed<-1-sum(w); ns<-!semi
  if(any(ns)) w[ns]<-w[ns]+freed*(w[ns]/sum(w[ns]))
  for(i in 1:50){ov<-w>BHI;if(!any(ov))break;ex<-sum(w[ov]-BHI);w[ov]<-BHI;rm2<-(!ov)&(w<BHI);if(!any(rm2))break;w[rm2]<-w[rm2]+ex*(w[rm2]/sum(w[rm2]))}
  w/sum(w)
}

evalm <- function(mode){
 dts<-sort(unique(scores$sig_date));md<-unique(scores[,.(sig_date,Date)]);rows<-list();pw0<-NULL;semi_track<-c()
 for(sd_ in dts){scd<-scores[sig_date==sd_][order(-score)][1:TOP_N];hd<-md[sig_date==sd_]$Date[1]
  rr<-returns_dt[Date==hd & Ticker%in%scd$Ticker];if(nrow(rr)<TOP_N*0.8)next
  tk<-scd$Ticker;n<-length(tk)
  hym<-format(hd,"%Y%m"); secmap<-sec_m[ym==hym & Ticker%in%tk]
  semflag<-setNames(rep(FALSE,n),tk); sv<-setNames(secmap$Sector,secmap$Ticker)[tk]; semflag[which(sv=="반도체")]<-TRUE
  if(mode=="EW") w<-setNames(rep(1/n,n),tk) else w<-semi_cap_w(tk,semflag,0.50)
  cm<-intersect(names(w),rr$Ticker);w<-w[cm];w<-w/sum(w);rv<-setNames(rr$Ret_1m,rr$Ticker)[cm];g<-sum(w*rv)
  semi_track<-c(semi_track, sum(w[names(w)%in%tk[semflag]]))
  if(is.null(pw0))to<-sum(w) else{an<-union(names(pw0),names(w));p<-setNames(rep(0,length(an)),an);p[names(pw0)]<-pw0;c<-setNames(rep(0,length(an)),an);c[names(w)]<-w;to<-sum(abs(c-p))}
  rows[[length(rows)+1]]<-data.table(date=hd,net=g-to*COST,to=to);pw0<-w}
 d<-rbindlist(rows);px<-xts(d$net,order.by=d$date);ba<-bench_dt[Date%in%d$date][order(Date)];act<-d$net-ba$BM_Ret[match(d$date,ba$Date)]
 data.table(mode=mode,n=nrow(d),net_sr=as.numeric(SharpeRatio.annualized(px,Rf=0,scale=12,geometric=FALSE)),
  cagr=as.numeric(Return.annualized(px,scale=12,geometric=TRUE)),mdd=as.numeric(maxDrawdown(px)),
  to=mean(d$to)*12,ir=(mean(act,na.rm=TRUE)/sd(act,na.rm=TRUE))*sqrt(12),pt=nwt(act,3),
  avg_semi=mean(semi_track))
}
r<-rbindlist(lapply(c("EW","SemiCap50"),evalm));r[,calmar:=cagr/mdd];print(r)
fwrite(r, file.path(SA,"sectorcap_comparison.csv"))
cat("SECTORCAP_DONE\n")
