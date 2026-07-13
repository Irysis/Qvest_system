#==============================================================================
# WT-D20260713_002 R18 — Step 08: 제2 독립 소형 기질 교차확인 (V02_EP EW-sleeve)
#   동일 사전등록 프레임: worst-decile p90 고정 · 무작위 3seed 대조 · 승격 4종. F-B 단독.
#   재측정·신규엔진 없음 — F-B broad worst-decile(기존 정의) + d3 holdings_monthly_v02ep 소비.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/factor_validation.R")
OUT <- "stage_artifacts/WT_D20260713_002"; COST_BPS <- 15
ym_of <- function(d){ d<-as.Date(d); as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m")) }
ym_add <- function(ym,k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }

## returns/size (d3 pipeline)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); raw[, Date:=as.Date(Date)]
raw[, ym:=ym_of(Date)]; me_dates<-raw[, .(Date=max(Date)), by=ym]$Date; rawm<-raw[Date %in% me_dates]
fwd <- build_monthly_forward_returns(rawm, sort(unique(rawm$Date)))
RET  <- as.data.table(fwd$returns_dt)[,.(ym=ym_of(Date),Ticker,Ret_1m)][!is.na(Ret_1m)]
SIZE <- rawm[, .(ym=ym_of(Date),Ticker,Size)][!is.na(Size)]; setorder(SIZE,ym,-Size)
SIZE[, cap_rank:=seq_len(.N), by=ym]; SIZE[, tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]

## F-B broad worst-decile (same signal def as gate/06)
FUND<-as.data.table(read_parquet(".cache/fundamental_merged.parquet")); FUND[, fy:=as.integer(substr(Period,1,4))]; FUND[, pm:=as.integer(substr(Period,5,6))]
ann<-FUND[pm==12L & is.finite(Value)]
RAW_MON<-c("TotalAssets","TotalLiab","TotalEquity","CurrentAssets","NonCurrentAssets","CurrentLiab","NonCurrentLiab","CashAndEquiv","AccountsRecv","Inventory","TangibleAssets","IntangibleAssets","ShortTermBorr","LongTermBorr","AccountsPay","LongTermPay","LongTermRecv","RetainedEarnings","CapitalStock","TotalDebt","NetDebt","WorkingCapital","Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","NetIncome","TaxExpense","InterestExp","InterestIncome","DepAmort","EBITDA","EBIT","NOPAT","RandD","Dividends","OperatingCF","InvestCF","FinanceCF","FCF1","FCF2")
bexp<-log10(1+1/(1:9)); bf<-ann[Item %in% RAW_MON][abs(Value)>0&is.finite(Value)]
bf[, x:=abs(Value)][, fd:=as.integer(floor(x/10^floor(log10(x))))]; bf<-bf[fd>=1L&fd<=9L]
fsd<-bf[, { n<-.N; if(n>=15L) .(Factor_Date=max(Factor_Date),fsd=mean(abs(tabulate(fd,9L)/n-bexp))) else .(Factor_Date=as.Date(NA),fsd=NA_real_) }, by=.(Ticker,fy)][is.finite(fsd)]
# expand-hold broad (usable = Factor_Date month +1, hold 12), most-recent
fb<-fsd[, .(Ticker,rcept_ym=ym_of(Factor_Date),raw=fsd)][is.finite(raw)]
fb[, us:=ym_add(rcept_ym,1L)]
FB_raw<-fb[, { dm<-vapply(0:11,function(k) ym_add(us,k),integer(1)); .(ym=dm,raw=raw,rcept_ym=rcept_ym) }, by=.(Ticker,seq_len(nrow(fb)))]
FB_raw[, seq_len:=NULL]; setorder(FB_raw,Ticker,ym,-rcept_ym); FB_raw<-FB_raw[, .SD[1L], by=.(Ticker,ym)]
FB_raw[, p90:=quantile(raw,0.90,na.rm=TRUE), by=ym]; WD_FB<-FB_raw[raw>=p90, .(ym,Ticker)]
wd_key<-WD_FB[, paste(ym,Ticker)]

## ── generic substrate evaluator (identical frame to 06) ──────────────────────
port_series<-function(W){ WR<-merge(W,RET,by=c("ym","Ticker"),all.x=TRUE); WR[is.na(Ret_1m),Ret_1m:=0]
  g<-WR[, .(gross=sum(w*Ret_1m)), by=ym]; setorder(g,ym); yms<-sort(unique(W$ym))
  tr<-numeric(length(yms)); names(tr)<-as.character(yms); prev<-data.table(Ticker=character(0),w=numeric(0))
  for(i in seq_along(yms)){ cur<-W[ym==yms[i],.(Ticker,w)]; m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
    m[is.na(w_c),w_c:=0];m[is.na(w_p),w_p:=0]; tr[i]<-sum(abs(m$w_c-m$w_p)); prev<-cur }
  g[, traded:=tr[as.character(ym)]][, net:=gross-traded*COST_BPS/1e4]; g }
tailm<-function(g){ r<-g$net; nav<-cumprod(1+r); list(mdd=-min(nav/cummax(nav)-1),worst_month=min(r),
  downside_dev=sqrt(mean(pmin(r,0)^2))*sqrt(12), worst5=sum(sort(r)[1:min(5,length(r))]), sr=mean(r)/sd(r)*sqrt(12), g=g) }
paired<-function(ge,gb){ m<-merge(ge[,.(ym,ne=net)],gb[,.(ym,nb=net)],by="ym"); d<-m$ne-m$nb
  fit<-lm(d~1); list(t=as.numeric(coeftest(fit,vcov=NeweyWest(fit,lag=3,prewhite=FALSE))[1,3]),mean=mean(d),n=length(d)) }

eval_substrate<-function(HOLD, name){
  H<-copy(HOLD); H[, ym:=ym_of(Date)]; H<-H[ym>=200906 & ym<=202506]
  base_W<-H[, .(ym,Ticker,w=1/.N), by=ym][, .(ym,Ticker,w)]
  base_g<-port_series(base_W); bt<-tailm(base_g)
  # binding (cap-tier)
  B<-merge(H[,.(ym,Ticker)], SIZE[,.(ym,Ticker,tier)], by=c("ym","Ticker"), all.x=TRUE); B[is.na(tier),tier:="UNRANKED"]
  B[, bound:=paste(ym,Ticker) %in% wd_key]; byt<-B[, .(held=.N,bound=sum(bound),rate=mean(bound)), by=tier][order(-held)]
  # exclusion (F-B), drop+renormalize
  He<-merge(H[,.(ym,Ticker)], WD_FB[, .(ym,Ticker,drop=1L)], by=c("ym","Ticker"), all.x=TRUE); He<-He[is.na(drop)]
  He[, w:=1/.N, by=ym]; eW<-He[, .(ym,Ticker,w)]; eg<-port_series(eW); et<-tailm(eg)
  kc<-merge(H[,.N,by=ym], eW[,.N,by=ym], by="ym", suffixes=c("_a","_k")); k_by<-setNames(as.list(kc$N_a-kc$N_k),as.character(kc$ym))
  rseeds<-c(101L,202L,303L); rdd<-sapply(rseeds,function(s){ set.seed(s)
    kp<-H[, { k<-k_by[[as.character(ym[1])]]; k<-ifelse(is.null(k)||is.na(k),0L,k); idx<-if(k>0&&k<.N) sample(.N,.N-k) else seq_len(.N); .(Ticker=Ticker[idx]) }, by=ym]
    kp[, w:=1/.N, by=ym]; tailm(port_series(kp[,.(ym,Ticker,w)]))$downside_dev })
  rmdd<-sapply(rseeds,function(s){ set.seed(s+7L)
    kp<-H[, { k<-k_by[[as.character(ym[1])]]; k<-ifelse(is.null(k)||is.na(k),0L,k); idx<-if(k>0&&k<.N) sample(.N,.N-k) else seq_len(.N); .(Ticker=Ticker[idx]) }, by=ym]
    kp[, w:=1/.N, by=ym]; tailm(port_series(kp[,.(ym,Ticker,w)]))$mdd })
  pt<-paired(eg,base_g)
  worst2<-base_g[order(net)][1:2,ym]; b2<-tailm(base_g[!ym%in%worst2]); e2<-tailm(eg[!ym%in%worst2])
  d_dd<-bt$downside_dev-et$downside_dev; d_mdd<-bt$mdd-et$mdd
  rand_d_dd<-bt$downside_dev-rdd; rand_d_mdd_mean<-mean(bt$mdd-rmdd)
  # 4 criteria
  otr<-byt[tier=="OTHER",rate]; mdr<-byt[tier=="MID",rate]
  C1<-(length(otr)&&!is.na(otr)&&otr>=0.05)||(length(mdr)&&!is.na(mdr)&&mdr>=0.05)
  C2<-(d_mdd>rand_d_mdd_mean)&&(d_dd>max(rand_d_dd))
  C3<-pt$t> -1.64
  C4<-((b2$mdd-e2$mdd)>0)||((b2$downside_dev-e2$downside_dev)>0)
  list(name=name, n_months=bt$n<-nrow(base_g), base_tail=bt[c("mdd","downside_dev","worst_month","sr")],
    binding_overall=mean(B$bound), by_tier=byt, mean_k=mean(unlist(k_by)),
    d_downside_dev=d_dd, d_downside_dev_rel_pct=100*d_dd/bt$downside_dev, d_mdd=d_mdd,
    rand_d_dd_seeds=rand_d_dd, rand_d_mdd_mean=rand_d_mdd_mean, paired_nwt=pt$t, paired_mean=pt$mean,
    c4_d_dd_ex2=b2$downside_dev-e2$downside_dev,
    criteria=list(C1=C1,C2=C2,C3=C3,C4=C4,pass=sum(C1,C2,C3,C4)))
}

VPH<-as.data.table(read_parquet("stage_artifacts/d3_dossier/holdings_monthly_v02ep.parquet"))
V<-eval_substrate(VPH,"V02_EP")
# reload P-pure result from step06 for side-by-side
P6<-readRDS(file.path(OUT,"consumption_diagnostic.rds"))
saveRDS(list(V02_EP=V, Ppure_ref=P6$criteria$FB, Ppure_ab=P6$ab$FB), file.path(OUT,"v02ep_crosscheck.rds"))

cat("\n===== V02_EP 교차확인 (F-B 단독, 동일 프레임) =====\n")
cat(sprintf("months %d | binding overall %.1f%%\n", V$n_months, 100*V$binding_overall)); print(V$by_tier)
cat(sprintf("mean_k %.2f | Δdownside_dev %.4f (%.2f%% rel) | rand_dd_seeds %s | ΔMDD %.4f | paired NW-t %.2f\n",
  V$mean_k, V$d_downside_dev, V$d_downside_dev_rel_pct, paste(round(V$rand_d_dd_seeds,4),collapse=","), V$d_mdd, V$paired_nwt))
cat("V02_EP criteria:", unlist(V$criteria), "\n")
cat("P-pure criteria (step06):", unlist(P6$criteria$FB), "\n")
cat("[08] DONE\n")
