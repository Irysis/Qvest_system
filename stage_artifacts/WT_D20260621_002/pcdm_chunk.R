#==============================================================================
# PCDM chunked runner — processes a date range [CHUNK_LO, CHUNK_HI], writes shard.
# Fresh process per chunk avoids long-run memory accumulation segfault.
# Usage: Rscript pcdm_chunk.R <chunk_lo> <chunk_hi> <shard_idx>
#==============================================================================
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
           VECLIB_MAXIMUM_THREADS="1", ARROW_NUM_THREADS="2")
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); arrow::set_cpu_count(1)

args <- commandArgs(trailingOnly = TRUE)
CHUNK_LO <- as.Date(args[1]); CHUNK_HI <- as.Date(args[2]); SHARD <- args[3]
OUT <- "stage_artifacts/WT_D20260621_002"
LOG <- function(...) { cat(sprintf("[%s][s%s] %s\n", format(Sys.time(),"%H:%M:%S"), SHARD, paste0(...))); flush.console() }

RAW <- ".cache/rawdata.parquet"; BMF <- ".cache/benchmark.parquet"
WMAX <- 504L
cumret <- function(r) prod(1+r)-1
GRID <- CJ(K=c(10L,20L,40L), W=c(252L,504L), H=c("12_1","6_1"))

# load rawdata: need history back WMAX+40 days before CHUNK_LO for peer learning
LOG("loading rawdata for chunk ", as.character(CHUNK_LO), " .. ", as.character(CHUNK_HI))
ds <- open_dataset(RAW)
lo_b <- as.Date(CHUNK_LO - 800L); hi_b <- as.Date(CHUNK_HI + 40L)
RD <- ds |> dplyr::filter(Date >= lo_b, Date <= hi_b) |>
  dplyr::select(Date,Ticker,Close,Vol,Size,Ret,Sector,K200,KQ150,AdminStock,TradingHalt) |>
  dplyr::collect() |> as.data.table()
RD[, Date := as.Date(Date)]; setorder(RD, Ticker, Date); RD[, ym := year(Date)*100L+month(Date)]
BM <- as.data.table(read_parquet(BMF)); BM[,Date:=as.Date(Date)]; BM<-BM[,.(Date,BM_Ret)][!is.na(BM_Ret)]; setkey(BM,Date)

me_all <- sort(RD[,.(Date=max(Date)),by=ym]$Date)
nxt_of <- function(d){i<-which(me_all==d); if(i<length(me_all)) me_all[i+1L] else as.Date(NA)}
months <- me_all[me_all>=CHUNK_LO & me_all<=CHUNK_HI]
LOG("months in chunk: ", length(months))

compute_month <- function(sig_date){
 tryCatch({
  w <- RD[Date<=sig_date & Date> (sig_date-(WMAX+40L))]
  if(nrow(w)==0) return(NULL)
  snap <- RD[Date==sig_date]; if(nrow(snap)==0) return(NULL)
  univ <- unique(snap[(K200==1|KQ150==1)&(is.na(AdminStock)|AdminStock==0)&(is.na(TradingHalt)|TradingHalt==0)&!is.na(Close)&Close>0,Ticker])
  if(length(univ)<30) return(NULL)
  liq <- w[Ticker %in% univ & Date<=sig_date]; setorder(liq,Ticker,Date)
  adtv <- liq[,{n<-.N;k<-min(20L,n);.(adv=mean(tail(Vol,k)*tail(Close,k),na.rm=TRUE))},by=Ticker]
  wr <- w[Ticker %in% univ & !is.na(Ret), .(Date,Ticker,Ret)]
  dc <- dcast(wr, Date~Ticker, value.var="Ret"); M <- as.matrix(dc[,-1,with=FALSE]); colnames(M)<-colnames(dc)[-1]
  bm_w <- BM[Date %in% dc$Date]; setkey(bm_w,Date)
  ref <- w[Ticker %in% univ & !is.na(Ret) & !is.na(Close)]; setorder(ref,Ticker,Date)
  reff <- ref[,{n<-.N;rr<-Ret;pr<-Close
    m01<-NA_real_; if(n>252L){i0<-n-252L+1L;i1<-n-21L;if(i1>i0)m01<-cumret(rr[i0:i1])}
    m08<-NA_real_; if(n>=252L){td<-data.table(Date=Date,Ret=rr);mg<-bm_w[td,on="Date"][!is.na(Ret)&!is.na(BM_Ret)]
      if(nrow(mg)>=252L){fit<-.lm.fit(cbind(1,mg$BM_Ret),mg$Ret);rs<-fit$residuals;nr<-length(rs);i1<-nr-21L;i0<-max(1L,nr-252L+1L);if(i1>i0)m08<-sum(rs[i0:i1])}}
    list(M01=m01,M08=m08)},by=Ticker]
  secmap <- snap[Ticker %in% univ,.(Ticker,Sector)]; reff<-merge(reff,secmap,by="Ticker",all.x=TRUE)
  reff[,sec_avg:=mean(M01,na.rm=TRUE),by=Sector]; reff[,M24:=fifelse(!is.na(M01)&!is.na(sec_avg),M01-sec_avg,NA_real_)]
  nd <- nxt_of(sig_date); fwd<-NULL
  if(!is.na(nd)){fw<-RD[Ticker %in% univ & Date>sig_date & Date<=nd & !is.na(Ret)];fwd<-fw[,.(Ret_1m=cumret(Ret)),by=Ticker]}
  out_list <- vector("list", nrow(GRID))
  for(gi in seq_len(nrow(GRID))){ out_list[[gi]]<-tryCatch({
    K<-GRID$K[gi];W<-GRID$W[gi];H<-GRID$H[gi];hlen<-if(H=="12_1")252L else 126L
    if(nrow(M)<60L)return(NULL); wkeep<-tail(seq_len(nrow(M)),min(W,nrow(M))); Mw<-M[wkeep,,drop=FALSE]
    ok<-colSums(!is.na(Mw))>=60L; if(sum(ok)<30L)return(NULL); Mok<-Mw[,ok,drop=FALSE]; tk<-colnames(Mok)
    C<-suppressWarnings(stats::cor(Mok,use="pairwise.complete.obs")); C[!is.finite(C)]<-0; diag(C)<-NA_real_
    hkeep<-tail(seq_len(nrow(M)),hlen); Mh<-M[hkeep,tk,drop=FALSE]; sk<-nrow(Mh)-21L; if(sk<=1L)return(NULL); hi<-1:sk
    nT<-length(tk); A<-matrix(0,nT,nT)
    for(j in seq_len(nT)){cj<-C[,j];ord<-order(cj,decreasing=TRUE,na.last=NA);kk<-ord[seq_len(min(K,length(ord)))];if(length(kk)>=3L)A[kk,j]<-1}
    cs<-colSums(A);good<-cs>=3L; if(sum(good)<10L)return(NULL); An<-A; An[,good]<-sweep(A[,good,drop=FALSE],2,cs[good],"/")
    Mhh<-Mh[hi,,drop=FALSE]; obs<-colSums(is.finite(Mhh)); Mh0<-Mhh; Mh0[!is.finite(Mh0)]<-0
    PM<-Mh0%*%An; D<-Mh0-PM; pcv<-colSums(D)
    nb<-floor(nrow(D)/21L); pev<-rep(NA_real_,nT)
    if(nb>=3L){bi<-rep(seq_len(nb),each=21L)[seq_len(nb*21L)];Db<-rowsum(D[seq_len(nb*21L),,drop=FALSE],bi);pev<-colMeans(Db>0)}
    Lg<-log1p(Mh0);Lg[!is.finite(Lg)]<-0;cumr<-expm1(colSums(Lg));brv<-rep(NA_real_,nT)
    for(j in which(good)){pr<-which(A[,j]==1);if(length(pr)>0)brv[j]<-mean(cumr[j]>cumr[pr],na.rm=TRUE)}
    v<-data.table(Ticker=tk,pcdm=pcv,persist=pev,breadth=brv,obs=obs,good=good)
    v<-v[good==TRUE & obs>=40L][,`:=`(good=NULL,obs=NULL)]; if(nrow(v)==0L)return(NULL)
    v[,`:=`(K=K,W=W,H=H,sig_date=sig_date)]; v
   }, error=function(e) NULL) }
  pcdm_all<-rbindlist(out_list,use.names=TRUE,fill=TRUE); if(nrow(pcdm_all)==0L)return(NULL)
  list(pcdm=pcdm_all, ref=reff[,.(Ticker,M01,M08,M24)], fwd=fwd, adtv=adtv, sig_date=sig_date)
 }, error=function(e){LOG("ERR ",as.character(sig_date),": ",conditionMessage(e));NULL})
}

res <- vector("list", length(months))
for(mi in seq_along(months)){ res[[mi]]<-compute_month(months[mi])
  if(mi%%6L==0L) LOG("  ",mi,"/",length(months)," (",as.character(months[mi]),")") }
res <- Filter(Negate(is.null), res)
LOG("non-null months=", length(res))
pcdm <- rbindlist(lapply(res,function(x)x$pcdm),use.names=TRUE,fill=TRUE)
refp <- rbindlist(lapply(res,function(x){r<-copy(x$ref);r[,sig_date:=x$sig_date];r}),use.names=TRUE,fill=TRUE)
fwdp <- rbindlist(lapply(res,function(x){if(is.null(x$fwd))return(NULL);f<-copy(x$fwd);f[,sig_date:=x$sig_date];f}),use.names=TRUE,fill=TRUE)
adtp <- rbindlist(lapply(res,function(x){a<-copy(x$adtv);a[,sig_date:=x$sig_date];a}),use.names=TRUE,fill=TRUE)
write_parquet(pcdm, file.path(OUT,paste0("shard_pcdm_",SHARD,".parquet")))
write_parquet(refp, file.path(OUT,paste0("shard_ref_",SHARD,".parquet")))
write_parquet(fwdp, file.path(OUT,paste0("shard_fwd_",SHARD,".parquet")))
write_parquet(adtp, file.path(OUT,paste0("shard_adtv_",SHARD,".parquet")))
LOG("SHARD DONE rows pcdm=",nrow(pcdm)," fwd=",nrow(fwdp))
