# SJM+EP A/B seed-stability 재확인 — IS/OOS cut을 3가지(55/60/65)로 변주해
# SJM−EW 부호 안정성 확인 (robust 게이트: min-across-k & cut-stable).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- 'G:/Quant_Module_Moltbot'; setwd(PROJ)
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules); RL<-list(); AL<-list()
for(sid in mod_ids){ s<-tryCatch(readRDS(file.path(PROJ,MP$modules[[sid]]$sim_result_path)),error=function(e)NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]
  bm<-if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d<-merge(d,bm,by="Date",all.x=TRUE) else d[,bm:=0]
  RL[[sid]]<-d[,.(Date,r)]; AL[[sid]]<-d[,.(Date,bm)] }
mod_ids<-names(RL)
RM<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(mod_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z})); setorder(RM,Date)
BMm<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(mod_ids,function(s){z<-AL[[s]][,.(Date,bm)];setnames(z,"bm",s);z}))
BM<-data.table(Date=BMm$Date,bm=apply(as.matrix(BMm[,-1]),1,function(v)median(v,na.rm=TRUE)))
RM[,ym:=format(Date,"%Y%m")]; avail<-RM[,.(n=sum(sapply(.SD,function(c)any(is.finite(c))))),by=ym,.SDcols=mod_ids][n>=3,ym]; RM<-RM[ym%in%avail]
MoM<-RM[,c(lapply(.SD,function(c){c[!is.finite(c)]<-0;prod(1+c)-1}),.(me=max(Date))),by=ym,.SDcols=mod_ids]
BM[,ym:=format(Date,"%Y%m")]; BMo<-BM[ym%in%avail,.(bm=prod(1+ifelse(is.finite(bm),bm,0))-1),by=ym]
MoM<-merge(MoM,BMo,by="ym"); setorder(MoM,me)
UN<-as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[,Date:=as.Date(Date)]
JM<-as.data.table(read_parquet(file.path(PROJ,".cache/regime_jump_daily.parquet")))[,Date:=as.Date(Date)]
AX<-merge(UN[,.(Date,Category)],JM[,.(Date,SJM=ifelse(JM_State==1L,"bear","bull"))],by="Date",all=TRUE); setorder(AX,Date)
AX[,Cat_l:=shift(Category,1L)]; AX[,SJM_l:=shift(SJM,1L)]
me_lab<-merge(MoM[,.(ym,me)],AX,by.x="me",by.y="Date",all.x=TRUE); setorder(me_lab,me)
me_lab[,Cat_prev:=shift(Cat_l)]; me_lab[,SJM_prev:=shift(SJM_l)]
nM<-nrow(MoM)
sjm_states<-c("bull","bear")
res<-data.table()
for(frac in c(0.55,0.60,0.65)){
  is_cut<-floor(nM*frac); is_ym<-MoM$ym[1:is_cut]; oos_ym<-MoM$ym[(is_cut+1):nM]
  IS<-MoM[ym%in%is_ym]; act_is<-as.matrix(IS[,..mod_ids])-IS$bm
  overall_IR<-setNames(apply(act_is,2,function(x)sr(x)),mod_ids)
  irSJM<-list(); for(st in sjm_states){ idx<-which((setNames(me_lab$SJM_prev,me_lab$ym)[is_ym])==st)
    irSJM[[st]]<-if(length(idx)<6) setNames(rep(NA,length(mod_ids)),mod_ids) else setNames(apply(act_is[idx,,drop=FALSE],2,function(x)sr(x)),mod_ids) }
  sjm_lab<-setNames(me_lab$SJM_prev,me_lab$ym)
  port_oos<-function(sel_fun){ prev<-NULL;rn<-numeric()
    for(y in oos_ym){ S<-sel_fun(y);S<-S[!is.na(S)];if(!length(S)){rn<-c(rn,NA);next}
      row<-MoM[ym==y];pr<-mean(unlist(row[,..S]))
      if(!is.null(prev)){to<-length(union(setdiff(prev,S),setdiff(S,prev)))/max(length(S),1);pr<-pr-to*(15/1e4)}
      prev<-S;rn<-c(rn,pr)};rn }
  topS<-names(sort(overall_IR,decreasing=TRUE))
  for(k in c(3,4,5)){
    ew<-port_oos(function(y)mod_ids)
    rotS<-port_oos(function(y){st<-sjm_lab[[y]];if(is.na(st)||all(is.na(irSJM[[st]])))return(topS[1:k]);names(sort(irSJM[[st]],decreasing=TRUE))[1:k]})
    res<-rbind(res,data.table(cut=paste0(frac*100,"%"),k=k,EW=round(sr(ew),3),Rotate_SJM=round(sr(rotS),3),SJM_minus_EW=round(sr(rotS)-sr(ew),3)))
  }
}
cat("=== SJM−EW across 3 IS/OOS cuts × 3 k (seed/cut-stability) ===\n"); print(res)
# robust = 모든 (cut,k)서 SJM−EW>0.05 그리고 부호 일관
all_pos<-all(res$SJM_minus_EW>0.05,na.rm=TRUE); any_neg<-any(res$SJM_minus_EW<0,na.rm=TRUE)
verdict<-if(all_pos)"ROBUST (모든 cut×k 동시 >0.05)" else if(any_neg)"NONROBUST (부호 flip 관측)" else "NONROBUST (일부 k서 미달/단조감소)"
cat(sprintf("\n★ cut-stability 평결: %s\n  SJM−EW: min=%.3f max=%.3f | 음수 관측=%s\n", verdict, min(res$SJM_minus_EW,na.rm=T), max(res$SJM_minus_EW,na.rm=T), any_neg))
write_json(list(test="SJM+EP cut-stability (91-module pool)", grid=res, all_positive=all_pos, any_negative=any_neg, verdict=verdict),
  file.path(PROJ,"04_Research/factor_rotation/output/sjm_ep_seed_check.json"), auto_unbox=TRUE, pretty=TRUE, digits=4)
