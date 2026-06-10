suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
PROJ <- 'G:/Quant_Module_Moltbot'; setwd(PROJ)
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
load_monthly <- function(p){ s<-readRDS(file.path(PROJ,p)); d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]; bm<-data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])); d<-merge(d,bm,by='Date',all.x=TRUE); d[,ym:=format(Date,'%Y%m')]; d[!is.finite(r),r:=0]; d[!is.finite(bm),bm:=0]; d[,.(r=prod(1+r)-1,bm=prod(1+bm)-1),by=ym] }
EP <- load_monthly('04_Research/strategies/STR_AS_20260605_202226_37668/sim_result.rds'); EP[,act:=r-bm]
EP[,yr:=substr(ym,1,4)]
yr_sr <- EP[,.(n=.N, act_ann=round(mean(act)*12,4), act_sr=round(sr(act),3)), by=yr]
cat('=== EP 연도별 active(벤치초과) ===\n'); print(yr_sr)
nM<-nrow(EP); cut<-floor(nM*0.6); cat(sprintf('IS=%s~%s  OOS=%s~%s\n', EP$ym[1], EP$ym[cut], EP$ym[cut+1], tail(EP$ym,1)))
roll <- sapply(60:nM, function(i) sr(EP$act[(i-59):i]))
cat(sprintf('5y rolling active SR: min=%.2f med=%.2f max=%.2f last=%.2f\n', min(roll,na.rm=T), median(roll,na.rm=T), max(roll,na.rm=T), tail(roll,1)))
recent <- EP[ym>='202101']; cat(sprintf('최근(2021+): n=%d net SR=%.3f active SR=%.3f net CAGR=%.2f%%\n', nrow(recent), sr(recent$r), sr(recent$act), (prod(1+recent$r)^(12/nrow(recent))-1)*100))
# IS/OOS 절반 raw vs active 비교 (raw net retention과 대조)
cat(sprintf('전체 net SR=%.3f active SR=%.3f\n', sr(EP$r), sr(EP$act)))
