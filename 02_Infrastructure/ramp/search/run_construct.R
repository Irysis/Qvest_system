## run_construct.R — 구성요소7(구성)·4(가중) 강화로 BOOK 돌파 (25종목준수). book base + 위성/가중 변형.
## ① book base(score_eff top-25, 256mo) ② book20+5 모멘텀위성(full book+무상관) ③ book-select+모멘텀-가중. vs 배포 book.
suppressPackageStartupMessages({library(arrow);library(data.table)}); setDTthreads(1); setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/canonical_screen_bt.R");source("02_Infrastructure/contracts/weighted_screen_bt.R");suppressMessages({library(sandwich);library(lmtest)})
C<-readRDS(".cache/_search_cache.rds");FN<-C$FN;dts<-C$dts;ND<-C$ND;SIG<-C$SIG;fwd_ret<-C$fwd_ret;bench<-C$bench;liq<-C$liq;UNI<-C$UNI
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)};calf<-function(r){nav<-cumprod(1+r);cagr<-prod(1+r)^(12/length(r))-1;cagr/abs(min(nav/cummax(nav)-1))}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s};ny<-function(d){m<-as.integer(format(d,"%m"));y<-as.integer(format(d,"%Y"));sprintf("%04d-%02d",ifelse(m==12,y+1,y),ifelse(m==12,1,m+1))}
## book z (예측월 정렬) + 모멘텀 z(M05_Trended)
bk<-as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))[,.(ym=format(as.Date(Date),"%Y-%m"),Ticker,se=score_eff)][is.finite(se)]
MOMID<-"M05_Trended_Mom"
SC<-list();for(i in seq_len(ND)){fw<-C$ZL[[as.character(dts[i])]];b<-bk[ym==ny(dts[i]),.(Ticker,bz=zc(se))]
  d<-data.table(Ticker=fw$Ticker);d[,mz:=if(MOMID%in%names(fw))zc(fw[[MOMID]]) else 0];d<-merge(d,b,by="Ticker",all.x=TRUE);d[!is.finite(bz),bz:=NA];d[!is.finite(mz),mz:=0]
  d<-merge(d,UNI[Date==dts[i]],by="Ticker");d<-merge(d,liq[Date==dts[i],.(Ticker,adv)],by="Ticker",all.x=TRUE);d<-d[is.na(adv)|adv>=2e8];d[,Date:=dts[i]];SC[[i]]<-d}
SCdt<-rbindlist(SC,fill=TRUE)
## 측정기: EW top-25 by score(canonical) | 위성 | 가중
gobk<-function(scoreexpr,lab){d<-copy(SCdt);d[,score:=eval(scoreexpr)];d<-d[is.finite(score)]
  cs<-canonical_screen_bt(d[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="c",strategy_id=lab)
  pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  data.table(strat=lab,n=n,pt=nwt(act),pt_OOS=nwt(act[(k+1):n]),oos_ret=oosr(act),SR=IRf(pr$ret_net),calmar=calf(pr$ret_net),TO=cs$turnover_annual)}
## 위성: book top-20 ∪ mom top-5(book밖). weighted_screen_bt EW.
sat<-function(Nb,Ns,lab){W<-list();for(i in seq_len(ND)){d<-SCdt[Date==dts[i]];db<-d[is.finite(bz)][order(-bz)];bn<-head(db$Ticker,Nb)
    dm<-d[!Ticker%in%bn][order(-mz)];mn<-head(dm$Ticker,Ns);held<-c(bn,mn);if(length(held)<5)next;W[[i]]<-data.table(Date=dts[i],Ticker=held,w=1/length(held))}
  Wd<-rbindlist(W);r<-weighted_screen_bt(Wd,fwd_ret,bench,cost_bps_oneway=15,run_id="sat",strategy_id=lab);pr<-as.data.table(r$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  data.table(strat=lab,n=n,pt=nwt(act),pt_OOS=nwt(act[(k+1):n]),oos_ret=oosr(act),SR=IRf(pr$ret_net),calmar=calf(pr$ret_net),TO=r$turnover_annual)}
bkret<-merge(data.table(date=dts,book=C$book),data.table(date=dts,bm=merge(data.table(Date=dts),bench,by="Date",all.x=T)$BM_Ret),by="date")[is.finite(book)&is.finite(bm)]
R<-rbindlist(list(
  data.table(strat="배포Book(gross256)",n=nrow(bkret),pt=nwt(bkret$book-bkret$bm),pt_OOS=NA,oos_ret=oosr(bkret$book-bkret$bm),SR=IRf(bkret$book),calmar=calf(bkret$book),TO=NA),
  gobk(quote(bz),"book_base(EW)"),
  gobk(quote(bz+0.3*mz),"book+0.3mom 가중선택"),
  gobk(quote(bz+0.5*mz),"book+0.5mom 가중선택"),
  sat(20,5,"book20+mom5위성"),
  sat(18,7,"book18+mom7위성"),
  sat(22,3,"book22+mom3위성")),fill=TRUE)
cat("=== 구성/가중 강화 (25종목준수) vs 배포Book(gross 256mo pt5.01/SR1.57/cal1.16) ===\n")
cat(sprintf("  %-22s %4s %6s %7s %7s %5s %6s %5s\n","strat","n","pt","pt_OOS","oos_ret","SR","calmar","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-22s %4d %6.2f %7.2f %7.2f %5.2f %6.2f %5.1f\n",r$strat,r$n,r$pt,r$pt_OOS,r$oos_ret,r$SR,r$calmar,ifelse(is.na(r$TO),0,r$TO)))}
saveRDS(R,".cache/_construct.rds");cat("CONSTRUCT_DONE\n")
