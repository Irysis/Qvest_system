## ============================================================================
## R28 (FQ-041, WT-D20260714_004) — C06_TP_Gap frozen pruning verification
## Builds full-history score panels: {fdb_off 0(T-1,PIT)/+1(same-month,stored-matching)}
##   x {theta stored/ic} x {sleeve 7F/6F(-C06)}, screens cap-w top-25, paired NW-t IS+holdout.
## READ-ONLY vs 05_Production (methodology copy in stage_artifacts). book_state 무변경.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite); library(lubridate); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_004")
source(file.path(QM,"02_Infrastructure/config.R"))
source(file.path(QM,"02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(QM,"02_Infrastructure/ramp/factor_validation.R"))     # build_monthly_forward_returns
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))

save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}

SLEEVE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
SLEEVE6 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR")   # -C06
SLEEVE_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
W_CORE<-0.65; W_DEF<-0.35
winsor_z<-function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
IS_END <- as.Date("2024-06-30"); HO_START <- as.Date("2024-07-01")  # return-month split (d0 basis)

## ---- shared inputs ----
ic <- as.data.table(read_parquet(file.path(QM,".cache/factor_db/factor_ic_monthly.parquet")))
ic[,Date:=as.Date(Date)]; ic[,Usable_Date:=as.Date(Usable_Date)]
reg <- .load_registry()
RAW <- as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet"),
        col_select=c("Ticker","Date","Close","Vol","Size","K200","KQ150")))
RAW[,Date:=as.Date(Date)]
RAWliq <- copy(RAW[,.(Ticker,Date,Close,Vol)]); RAWliq[,TV:=Close*Vol]; setorder(RAWliq,Ticker,Date)
RAWliq[,A:=frollmean(TV,20L,align="right"),by=Ticker]; RAWliq[,AvgTV20:=shift(A,1L),by=Ticker]
RAWliq <- RAWliq[,.(Ticker,Date,AvgTV20)]
k2<-as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_k200.parquet")));k2[,Date:=as.Date(Date)]
kq<-as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_kq150.parquet")));kq[,Date:=as.Date(Date)]
bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]
theta_map <- unique(bk[,.(Date, theta_core)])
get_stored_theta <- function(d){ s<-theta_map[Date==d,theta_core][1]; if(is.na(s))return(NULL); unlist(fromJSON(s)) }

## ---- forward returns / bench / size (deltair pattern) ----
need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
rd <- RAW[Date>=as.Date("2003-06-01"), ..need]
rd[,ym:=format(Date,"%Y-%m")]
mend <- rd[,.(md=max(Date)),by=ym]; setorder(mend,md)
sig_dates <- mend$md[format(mend$md,"%Y-%m")>="2003-12"]
fwd <- build_monthly_forward_returns(rd, sig_dates)
fwd_ret <- fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench <- fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
liqf  <- fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
d0s <- sort(unique(fwd_ret$Date))
## size panel (universe month-end) for cap-w + cap-tier diag
umend <- merge(rd, mend, by.x=c("ym","Date"), by.y=c("ym","md"))
umend[, inu:=(!is.na(K200)&K200==TRUE)|(!is.na(KQ150)&KQ150==TRUE)]
SIZE <- umend[inu==TRUE,.(Date,Ticker,Size)]
cat(sprintf("fwd d0s=%d (%s..%s)\n",length(d0s),as.character(min(d0s)),as.character(max(d0s))))

## ---- score builder for one AS_OF, one recipe ----
build_core <- function(fdp, AS_OF, CUT, sleeve, theta_vec){
  rdf<-function(p,fac){f<-as.data.table(read_parquet(p,col_select=c("Ticker","Factor_Name","Z_Score","Coverage")));
    f[Factor_Name%in%fac&Coverage==TRUE&!is.na(Z_Score),.(Ticker,Factor_Name,Z_Score)]}
  fdb<-rbind(rdf(fdp,c(SLEEVE7,"Q07_Earnings_Stability","Q25_Ohlson_O")), rdf(fdp,"M08_Residual_Mom")); fdb[,sig_date:=AS_OF]
  if(length(setdiff(c(SLEEVE7,SLEEVE_DEF),unique(fdb$Factor_Name)))) return(NULL)  # need all 7 present
  fa<-align_factor_direction(fdb,reg,sig_date=AS_OF,min_ic_months=12L); if("Z_Score_Aligned"%in%names(fa))fa[,Z_Score:=Z_Score_Aligned]
  fw<-dcast(fa,sig_date+Ticker~Factor_Name,value.var="Z_Score",fill=NA_real_)
  pc<-RAWliq[Date<=CUT,max(Date)]; liq<-RAWliq[Date==pc&!is.na(AvgTV20)&AvgTV20>=2e8,.(Ticker)]; fw<-merge(fw,liq,by="Ticker")
  uni<-unique(c(k2[Date==k2[Date<=CUT,max(Date)]&K200==1,Ticker],kq[Date==kq[Date<=CUT,max(Date)]&KQ150==1,Ticker])); fw<-fw[Ticker%in%uni]
  if(nrow(fw)<25) return(NULL)
  Kc<-length(sleeve); tc<-theta_vec[sleeve]; tc[!is.finite(tc)]<-0
  tc<-if(sum(abs(tc))<=0) setNames(rep(1/Kc,Kc),sleeve) else tc/sum(abs(tc))
  td<-setNames(rep(1/3,3),SLEEVE_DEF)
  agg<-function(df,fc,w){fc<-intersect(intersect(names(w),fc),names(df));W<-as.numeric(w[fc]);W<-W/sum(W);X<-as.matrix(df[,..fc]);X<-apply(X,2,winsor_z);X[is.na(X)]<-0;as.numeric(X%*%W)}
  fw[,Sc:=agg(.SD,sleeve,tc)]; fw[,Sd:=agg(.SD,SLEEVE_DEF,td)]
  fw[,Scz:=zc(Sc)]; fw[,Sdz:=zc(Sd)]; fw[,score_eff:=W_CORE*Scz+W_DEF*Sdz]
  fw[,.(Ticker,score_eff)]
}

## ---- main loop: build all panels keyed by d0 (fwd sig_date) ----
## variants: off {0=T-1(PIT), 1=same-month(stored)} x theta {stored, ic} x sleeve {7,6}
variants <- CJ(off=c(0L,1L), theta=c("stored","ic"), sleeve=c("S7","S6"), sorted=FALSE)
panels <- setNames(vector("list", nrow(variants)), apply(variants,1,paste,collapse="_"))
ic_theta <- function(AS_OF, sleeve){
  Kc<-length(sleeve)
  icm<-ic[Usable_Date<AS_OF&!is.na(IC)&Factor_Name%in%sleeve,.(m=mean(IC,na.rm=T)),by=Factor_Name]
  tc<-setNames(rep(0,Kc),sleeve); for(f in icm$Factor_Name)tc[f]<-max(icm[Factor_Name==f,m],0)
  if(sum(abs(tc))<=0) setNames(rep(1/Kc,Kc),sleeve) else {tc<-tc/sum(abs(tc)); v<-setNames(rep(0,length(SLEEVE7)),SLEEVE7); v[sleeve]<-tc; v}
}
rows <- vector("list", length(d0s))
t0 <- Sys.time()
for(i in seq_along(d0s)){
  d0 <- d0s[i]
  AS_OF <- as.Date(paste0(format(d0 %m+% months(1),"%Y-%m"),"-01"))  # score label month = ny(d0)
  CUT <- AS_OF-1L
  th_st <- get_stored_theta(AS_OF)  # named vec over 4 core (may be NULL for pre-2004)
  # factor_db files
  fdp0 <- file.path(QM,sprintf(".cache/factor_db/factor_db_%s.parquet",format(AS_OF-1,"%Y%m")))       # T-1
  fdp1 <- file.path(QM,sprintf(".cache/factor_db/factor_db_%s.parquet",format(as.Date(paste0(format(AS_OF,"%Y-%m"),"-01")),"%Y%m")))  # same-month
  out <- data.table(Date=d0, Ticker=character(0))
  acc <- list()
  for(vr in seq_len(nrow(variants))){
    off<-variants$off[vr]; thm<-variants$theta[vr]; slv<-variants$sleeve[vr]
    sleeve <- if(slv=="S7") SLEEVE7 else SLEEVE6
    fdp <- if(off==0L) fdp0 else fdp1
    if(!file.exists(fdp)) next
    if(thm=="stored"){ if(is.null(th_st)) next; theta_vec<-th_st } else theta_vec<-ic_theta(AS_OF, sleeve)
    r <- tryCatch(build_core(fdp, AS_OF, CUT, sleeve, theta_vec), error=function(e) NULL)
    if(is.null(r)) next
    setnames(r,"score_eff",names(panels)[vr])
    acc[[names(panels)[vr]]] <- r
  }
  if(length(acc)==0) next
  m <- Reduce(function(a,b) merge(a,b,by="Ticker",all=TRUE), acc)
  m[,Date:=d0]
  rows[[i]] <- m
  if(i %% 40 == 0) cat(sprintf("  ...%d/%d (%s) %.1fs\n", i, length(d0s), as.character(d0), as.numeric(Sys.time()-t0,units="secs")))
}
PAN <- rbindlist(rows, fill=TRUE)
cat(sprintf("panel built: %d rows, %d months, cols=%s\n", nrow(PAN), uniqueN(PAN$Date), paste(setdiff(names(PAN),c("Date","Ticker")),collapse=",")))
save_safe(PAN, file.path(WT,"recon_panels.parquet"), function(o,p) write_parquet(o,p))
save_safe(list(fwd_ret=fwd_ret,bench=bench,liqf=liqf,SIZE=SIZE,bk=bk), file.path(WT,"screen_inputs.rds"), saveRDS)
cat("BUILD_DONE\n")
