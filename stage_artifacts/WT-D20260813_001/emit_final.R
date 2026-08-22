## Emit final weights.csv (full walk-forward schedule, EW + semi-cap50) + snapshot target_weights
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT<-"WT-D20260813_001";SA<-file.path("stage_artifacts",WT);MB<-file.path("qepm/mailbox/worktask",WT)
scores <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))[,.(Date=as.Date(Date),sig_date=as.Date(sig_date),Ticker=as.character(Ticker),score=as.numeric(alpha_score))]
ds <- open_dataset(".cache/RAWDATA.parquet")
tks_all <- unique(scores$Ticker)
sec <- ds |> dplyr::filter(Ticker %in% tks_all) |> dplyr::select(Date,Ticker,Sector) |> dplyr::collect() |> as.data.table()
sec[, ym := format(as.Date(Date),"%Y%m")]
sec_m <- sec[, .(Sector=tail(Sector,1)), by=.(Ticker,ym)]
TOP_N<-25L;BHI<-0.20;SEMI_CAP<-0.50
semi_cap_w<-function(tk,semi,cap=0.50){n<-length(tk);w<-rep(1/n,n);names(w)<-tk;sw<-sum(w[semi])
 if(sw>cap+1e-9){w[semi]<-w[semi]*(cap/sw);freed<-1-sum(w);ns<-!semi;if(any(ns))w[ns]<-w[ns]+freed*(w[ns]/sum(w[ns]))
  for(i in 1:50){ov<-w>BHI;if(!any(ov))break;ex<-sum(w[ov]-BHI);w[ov]<-BHI;rm2<-(!ov)&(w<BHI);if(!any(rm2))break;w[rm2]<-w[rm2]+ex*(w[rm2]/sum(w[rm2]))}}
 w/sum(w)}
dts<-sort(unique(scores$sig_date));md<-unique(scores[,.(sig_date,Date)]);rows<-list()
setorder(sec_m, Ticker, ym)
for(sd_ in dts){scd<-scores[sig_date==sd_][order(-score)][1:TOP_N];hd<-md[sig_date==sd_]$Date[1]
 tk<-scd$Ticker;hym<-format(hd,"%Y%m")
 # PIT sector: last available sector obs with ym <= holding month (sector slow-moving, <= sig-based ok)
 secmap<-sec_m[ym<=hym&Ticker%in%tk][, .(Sector=Sector[.N]), by=Ticker]
 sv<-setNames(secmap$Sector,secmap$Ticker)[tk];semflag<-!is.na(sv)&sv=="반도체"
 w<-semi_cap_w(tk,semflag,SEMI_CAP)
 rows[[length(rows)+1]]<-data.table(as_of_date=sd_,holding_month=hd,Ticker=tk,weight=round(as.numeric(w),6),
   sector=ifelse(is.na(sv),"UNKNOWN",sv))}
sched<-rbindlist(rows)
# integrity per date
chk<-sched[,.(sumw=sum(weight),maxw=max(weight),minw=min(weight),n=.N),by=as_of_date]
stopifnot(all(abs(chk$sumw-1)<1e-4), all(chk$maxw<=0.2001), all(chk$minw>=-1e-9), all(chk$n<=25))
fwrite(sched, file.path(SA,"weights.csv"))
cat("weights.csv rows:",nrow(sched)," unique_dates:",uniqueN(sched$as_of_date),"/ sig_dates:",uniqueN(scores$sig_date),"\n")
cat("density_ratio:", round(uniqueN(sched$as_of_date)/uniqueN(scores$sig_date),4),"\n")

# snapshot target_weights (current book, as_of 2026-07-31)
snap<-sched[as_of_date==max(as_of_date)]
tw<-setNames(snap$weight,snap$Ticker)
# align to alpha_vector order
ap<-fromJSON(file.path(MB,"alpha_package.json"),simplifyVector=FALSE)
av<-names(unlist(ap$alpha_vector))
tw<-tw[av]; tw[is.na(tw)]<-0
saveRDS(list(sched=sched,tw=tw,snap=snap),file.path(SA,"final_weights.rds"))
cat("SNAP semi_wt:",round(sum(snap[sector=="반도체"]$weight),4)," max_w:",round(max(tw),4)," sumw:",round(sum(tw),6),"\n")
cat("EMIT_FINAL_DONE\n")
