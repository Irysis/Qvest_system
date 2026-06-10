# EP 한계기여 격리(ablation): 신규 AS 모듈(EP+8) 제외 vs 포함 시 SJM−EW 차이.
# SJM 이득이 EP 직교 슬리브에서 오는가, 아니면 기존 풀의 regime specialist에서 오는가?
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- 'G:/Quant_Module_Moltbot'; setwd(PROJ)
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
mdd<- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
all_ids <- names(MP$modules)
new_as <- grep("STR_AS_2026", all_ids, value=TRUE)   # EP + 8 신규
RL<-list(); AL<-list()
for(sid in all_ids){ s<-tryCatch(readRDS(file.path(PROJ,MP$modules[[sid]]$sim_result_path)),error=function(e)NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]
  bm<-if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d<-merge(d,bm,by="Date",all.x=TRUE) else d[,bm:=0]
  RL[[sid]]<-d[,.(Date,r)]; AL[[sid]]<-d[,.(Date,bm)] }
JM<-as.data.table(read_parquet(file.path(PROJ,".cache/regime_jump_daily.parquet")))[,Date:=as.Date(Date)]
JM[,SJM:=ifelse(JM_State==1L,"bear","bull")]; setorder(JM,Date); JM[,SJM_l:=shift(SJM,1L)]

run_pool <- function(use_ids){
  RM<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(use_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z})); setorder(RM,Date)
  BMm<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(use_ids,function(s){z<-AL[[s]][,.(Date,bm)];setnames(z,"bm",s);z}))
  BM<-data.table(Date=BMm$Date,bm=apply(as.matrix(BMm[,-1]),1,function(v)median(v,na.rm=TRUE)))
  RM[,ym:=format(Date,"%Y%m")]; avail<-RM[,.(n=sum(sapply(.SD,function(c)any(is.finite(c))))),by=ym,.SDcols=use_ids][n>=3,ym]; RM<-RM[ym%in%avail]
  MoM<-RM[,c(lapply(.SD,function(c){c[!is.finite(c)]<-0;prod(1+c)-1}),.(me=max(Date))),by=ym,.SDcols=use_ids]
  BM[,ym:=format(Date,"%Y%m")]; BMo<-BM[ym%in%avail,.(bm=prod(1+ifelse(is.finite(bm),bm,0))-1),by=ym]
  MoM<-merge(MoM,BMo,by="ym"); setorder(MoM,me)
  me_lab<-merge(MoM[,.(ym,me)],JM[,.(Date,SJM_l)],by.x="me",by.y="Date",all.x=TRUE); setorder(me_lab,me); me_lab[,SJM_prev:=shift(SJM_l)]
  sjm_lab<-setNames(me_lab$SJM_prev,me_lab$ym)
  nM<-nrow(MoM); is_cut<-floor(nM*0.6); is_ym<-MoM$ym[1:is_cut]; oos_ym<-MoM$ym[(is_cut+1):nM]
  IS<-MoM[ym%in%is_ym]; act_is<-as.matrix(IS[,..use_ids])-IS$bm
  overall_IR<-setNames(apply(act_is,2,function(x)sr(x)),use_ids); topS<-names(sort(overall_IR,decreasing=TRUE))
  irSJM<-list(); for(st in c("bull","bear")){ idx<-which(sjm_lab[is_ym]==st)
    irSJM[[st]]<-if(length(idx)<6) setNames(rep(NA,length(use_ids)),use_ids) else setNames(apply(act_is[idx,,drop=FALSE],2,function(x)sr(x)),use_ids) }
  port_oos<-function(sel_fun){ prev<-NULL;rn<-numeric()
    for(y in oos_ym){ S<-sel_fun(y);S<-S[!is.na(S)];if(!length(S)){rn<-c(rn,NA);next}
      row<-MoM[ym==y];pr<-mean(unlist(row[,..S]))
      if(!is.null(prev)){to<-length(union(setdiff(prev,S),setdiff(S,prev)))/max(length(S),1);pr<-pr-to*(15/1e4)}
      prev<-S;rn<-c(rn,pr)};rn }
  out<-data.table()
  for(k in c(3,4,5)){
    ew<-port_oos(function(y)use_ids)
    rotS<-port_oos(function(y){st<-sjm_lab[[y]];if(is.na(st)||all(is.na(irSJM[[st]])))return(topS[1:k]);names(sort(irSJM[[st]],decreasing=TRUE))[1:k]})
    # SJM top-k 셀에 신규AS 모듈이 실제 선택됐는지
    sel_new<-0; for(y in oos_ym){st<-sjm_lab[[y]];if(is.na(st)||all(is.na(irSJM[[st]])))sel<-topS[1:k] else sel<-names(sort(irSJM[[st]],decreasing=TRUE))[1:k]; sel_new<-sel_new+sum(sel %in% new_as)}
    out<-rbind(out,data.table(k=k,EW=round(sr(ew),3),Rotate_SJM=round(sr(rotS),3),SJM_minus_EW=round(sr(rotS)-sr(ew),3),SJM_mdd=round(mdd(rotS),3),new_AS_picks=sel_new))
  }
  out }

cat("=== WITHOUT 신규 AS (기존",length(setdiff(all_ids,new_as)),"모듈) ===\n")
r_wo<-run_pool(setdiff(all_ids,new_as)); print(r_wo)
cat("\n=== WITH 신규 AS (",length(all_ids),"모듈, EP 포함) ===\n")
r_w<-run_pool(all_ids); print(r_w)
cat(sprintf("\n★ EP/신규AS ablation: SJM−EW mean WITHOUT=%.3f → WITH=%.3f (Δ%+.3f)\n",
  mean(r_wo$SJM_minus_EW,na.rm=T), mean(r_w$SJM_minus_EW,na.rm=T), mean(r_w$SJM_minus_EW,na.rm=T)-mean(r_wo$SJM_minus_EW,na.rm=T)))
cat(sprintf("  SJM top-k가 신규AS 모듈 실제선택 횟수(WITH): k3/4/5 = %s (0이면 EP 직교 슬리브 미사용)\n",
  paste(r_w$new_AS_picks,collapse="/")))
write_json(list(without_new=r_wo, with_new=r_w,
  mean_sjm_minus_ew_without=round(mean(r_wo$SJM_minus_EW,na.rm=T),3),
  mean_sjm_minus_ew_with=round(mean(r_w$SJM_minus_EW,na.rm=T),3),
  new_as_selected_in_sjm=sum(r_w$new_AS_picks)),
  file.path(PROJ,"04_Research/factor_rotation/output/sjm_ep_ablation.json"), auto_unbox=TRUE, pretty=TRUE, digits=4)
