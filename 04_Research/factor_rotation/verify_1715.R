suppressPackageStartupMessages({ library(data.table); library(xts) })
PROJ <- 'G:/Quant_Module_Moltbot'; setwd(PROJ)
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
load_monthly <- function(p){ s<-readRDS(file.path(PROJ,p)); d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]
  bm<-data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])); d<-merge(d,bm,by='Date',all.x=TRUE)
  d[,ym:=format(Date,'%Y%m')]; d[!is.finite(r),r:=0]; d[!is.finite(bm),bm:=0]; d[,.(r=prod(1+r)-1,bm=prod(1+bm)-1),by=ym] }
# 1715 monthly
pr <- fread(file.path(PROJ,"04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
s1715 <- data.table(ym=format(as.Date(pr$date),"%Y%m"), r1715=pr$ret_net)
cat(sprintf("1715: n=%d %s~%s mean_ret=%.4f sd=%.4f net SR=%.3f\n",
            nrow(s1715), s1715$ym[1], tail(s1715$ym,1), mean(s1715$r1715), sd(s1715$r1715), sr(s1715$r1715)))
# 비교 대상: EP, residual mom, STR_1715
EP  <- load_monthly("04_Research/strategies/STR_AS_20260605_202226_37668/sim_result.rds")
MOM <- load_monthly("04_Research/strategies/STR_AS_20260605_185153_35464/sim_result.rds")
m <- merge(s1715, EP[,.(ym, ep=r)], by="ym"); m <- merge(m, MOM[,.(ym, mom=r)], by="ym")
cat(sprintf("3-way overlap n=%d\n", nrow(m)))
cat(sprintf("cor(1715, EP)=%.3f  cor(1715, MOM)=%.3f  cor(EP, MOM)=%.3f\n",
            cor(m$r1715,m$ep), cor(m$r1715,m$mom), cor(m$ep,m$mom)))
# 1715 첫/끝 일부 값 출력 (정렬 sanity)
cat("1715 head:\n"); print(head(m[,.(ym, r1715=round(r1715,4), ep=round(ep,4), mom=round(mom,4))],4))
cat("1715 tail:\n"); print(tail(m[,.(ym, r1715=round(r1715,4), ep=round(ep,4), mom=round(mom,4))],4))
# 1715가 정말 momentum인지: 자기 net SR과 연 수익
cat(sprintf("1715 over overlap: SR=%.3f ann_ret=%.2f%%\n", sr(m$r1715), mean(m$r1715)*1200))
