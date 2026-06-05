#!/usr/bin/env Rscript
# =============================================================================
# fr_regime_search.R — 자가발전 Cycle: 여러 레짐 정의로 walk-forward 앙상블 →
#   OOS-안정 로테이션(EW 초과 + OOS 엣지 안정)을 탐색. 실측 기반.
# PIT: 축 t-1, 버킷 expanding, 가중 IS-only, 모듈 frozen, forward 적용.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%`<-function(a,b) if(is.null(a)||length(a)==0||all(is.na(a)))b else a
source(file.path(PROJ,"02_Infrastructure/portfolio/module_dispatcher.R"))
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6||sd(r)==0)NA else mean(r)/sd(r)*sqrt(12)}
MIN_IS<-60L; MIN_MOD<-3L

MP<-fromJSON(file.path(PROJ,"06_Registry/module_performance.json"),simplifyVector=FALSE); mod_ids<-names(MP$modules)
rets<-lapply(mod_ids,function(s){x<-readRDS(file.path(PROJ,MP$modules[[s]]$sim_result_path))$DAILY_NAV_DT;data.table(Date=as.Date(x$Date),r=x$Strategy_Ret)});names(rets)<-mod_ids
RM<-Reduce(function(a,b)merge(a,b,by="Date",all=TRUE),lapply(mod_ids,function(s){x<-copy(rets[[s]]);setnames(x,"r",s);x}));setorder(RM,Date)
RM[,ym:=format(Date,"%Y%m")]
av<-RM[,.(n=sum(sapply(.SD,function(c)any(is.finite(c))))),by=ym,.SDcols=mod_ids]; RM<-RM[ym%in%av[n>=MIN_MOD,ym]]
RD<-as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[,Date:=as.Date(Date)]
UN<-as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[,Date:=as.Date(Date)]
AX<-merge(RD[,.(Date,MRS,HY_z=HY_z_smooth)],UN[,.(Date,KTRI=KTRI_Score,Category)],by="Date",all=TRUE);setorder(AX,Date)
me<-RM[,.(me_date=max(Date)),by=ym];setorder(me,me_date)
mreg<-merge(me,AX,by.x="me_date",by.y="Date",all.x=TRUE);setorder(mreg,me_date)
for(a in c("MRS","KTRI","HY_z"))mreg[,(paste0(a,"_lag")):=shift(get(a),1L)]; mreg[,Cat_lag:=shift(Category,1L)]

terc<-function(v){n<-length(v);b<-rep("NA",n);for(i in seq_len(n)){if(i<MIN_IS||is.na(v[i]))next;q<-quantile(v[1:(i-1)],c(.33,.67),na.rm=TRUE);if(any(is.na(q))||q[1]>=q[2])next;b[i]<-if(v[i]<=q[1])"L" else if(v[i]<=q[2])"M" else "H"};b}
regdefs<-list(Category=ifelse(is.na(mreg$Cat_lag),"NA",mreg$Cat_lag), MRS_terc=terc(mreg$MRS_lag),
  KTRI_terc=terc(mreg$KTRI_lag), HY_terc=terc(mreg$HY_z_lag),
  MRSxKTRI=paste0(terc(mreg$MRS_lag),"_",terc(mreg$KTRI_lag)))

# EW baseline
M0<-RM[ym%in%mreg$ym[(MIN_IS+1):nrow(mreg)]]; ewd<-M0[,{v<-rowMeans(.SD,na.rm=TRUE);.(Date,e=v)},.SDcols=mod_ids];ewd[,ym:=format(Date,"%Y%m")];ewm<-ewd[,.(ret=prod(1+e)-1),by=ym];ew_sr<-sr(ewm$ret)

wf<-function(reglab){              # reglab: 월별 벡터 (mreg 순서)
  mlab<-data.table(ym=mreg$ym, reg=reglab)
  dlab<-merge(RM[,.(Date,ym)],mlab,by="ym")[,.(Date,reg)]    # 일간 broadcast
  months<-mreg$ym; ens<-list(); pw<-NULL
  for(i in seq_along(months)){ if(i<=MIN_IS)next; m<-months[i]; rn<-reglab[i]; if(rn=="NA"||grepl("NA",rn))next
    is_end<-mreg$me_date[i-1]
    ISa<-merge(RM[Date<=is_end],dlab,by="Date")             # IS 일간 + regime 라벨
    avail<-mod_ids[sapply(mod_ids,function(s)sum(is.finite(ISa[[s]]))>=250)]; if(length(avail)<MIN_MOD)next
    sel<-ISa[reg==rn]; if(nrow(sel)<20)next
    rir<-setNames(sapply(avail,function(s){x<-sel[[s]];x<-x[is.finite(x)];if(length(x)<20||sd(x)==0)0 else mean(x)/sd(x)*sqrt(252)}),avail)
    nrg<-setNames(sapply(avail,function(s)sum(is.finite(sel[[s]]))/21),avail)
    vol<-setNames(sapply(avail,function(s){x<-ISa[[s]];x<-x[is.finite(x)];sd(tail(x,252))}),avail)
    w<-compute_regime_module_weights(rir,vol,nrg)
    Md<-RM[ym==m]; er<-Md[,{v<-0;for(s in names(w)){rr<-get(s);rr[!is.finite(rr)]<-0;v<-v+w[s]*rr};.(Date,e=v)}]
    if(!is.null(pw)){to<-sum(abs(w-pw[names(w)]),na.rm=TRUE);er[1,e:=e-to*(15/1e4)]}; pw<-w
    ens[[m]]<-er }
  ED<-rbindlist(ens); if(!nrow(ED))return(NULL); ED[,ym:=format(Date,"%Y%m")]; ED[,.(ret=prod(1+e)-1),by=ym] }

cat("EW baseline SR =",round(ew_sr,3),"\n\n")
res<-list()
for(k in names(regdefs)){
  r<-tryCatch(wf(regdefs[[k]]),error=function(e){cat("ERR",k,conditionMessage(e),"\n");NULL}); if(is.null(r))next
  M<-merge(r,ewm,by="ym",suffixes=c("",".ew")); M[,edge:=ret-ret.ew]; n<-nrow(M);kk<-floor(n*.65)
  oos<-sr(M$edge[(kk+1):n])/sr(M$edge[1:kk])
  res[[k]]<-data.table(regime=k,n_months=nrow(r),rot_SR=sr(r$ret),ew_SR=ew_sr,
    edge_SR=sr(M$edge),edge_vs_ew=sr(r$ret)-ew_sr,oos_edge_retention=oos)
  cat(sprintf("  %-10s rot_SR=%.3f vs EW %.3f (Δ%+.3f) | edge_SR=%.2f OOS_edge_ret=%.2f\n",k,sr(r$ret),ew_sr,sr(r$ret)-ew_sr,sr(M$edge),oos))
}
R<-rbindlist(res,fill=TRUE)[order(-edge_vs_ew)]
write_json(R,file.path(PROJ,"04_Research/factor_rotation/output/regime_search.json"),auto_unbox=TRUE,pretty=TRUE,na="null",digits=4)
cat("\n==== 레짐 정의별 OOS 로테이션 ====\n");print(R[,.(regime,n_months,rot_SR=round(rot_SR,3),edge_vs_ew=round(edge_vs_ew,3),edge_SR=round(edge_SR,2),oos_edge_retention=round(oos_edge_retention,2))])
b<-R[edge_vs_ew>0 & oos_edge_retention>0][order(-edge_vs_ew)][1]
cat(sprintf("\n★ best OOS-안정 로테이션: %s (EW대비 +%.3f, OOS_edge_ret %.2f)\n", b$regime%||%"없음", b$edge_vs_ew%||%NA, b$oos_edge_retention%||%NA))
