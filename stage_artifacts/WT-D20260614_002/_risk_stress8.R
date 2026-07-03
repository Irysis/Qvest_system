# Expand stress to 8 historical periods + coverage-vs-breach distinction (Codex C2 round2)
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/config.R")
OUT<-"stage_artifacts/WT-D20260614_002"
btr<-readRDS("stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds")
pr<-as.data.table(btr$period_returns)[,.(date,ret_net)]; br<-as.data.table(btr$benchmark_returns)[,.(date,bm=benchmark_ret)]
dd<-merge(pr,br,by="date"); setorder(dd,date); dd[,ym:=format(date,"%Y%m")]
mo<-dd[,.(core=prod(1+ret_net)-1, bm=prod(1+bm)-1),by=ym]; mo[,active:=core-bm]

# 8 canonical crisis windows (KR-relevant, FRM/strategy_analyzer style)
W<-list(
  gfc_2008      =c("200806","200902"),
  eudebt_2011   =c("201105","201109"),
  china_2015    =c("201506","201601"),
  vol_2018      =c("201810","201812"),
  covid_2020    =c("202001","202003"),
  ratehike_2022 =c("202201","202210"),
  kr_bear_2024h2=c("202407","202412"),
  kr_corr_2025  =c("202503","202504"))   # recent local correction (low-coverage check)
mlen<-function(a,b) (as.integer(substr(b,1,4))*12+as.integer(substr(b,5,6))) - (as.integer(substr(a,1,4))*12+as.integer(substr(a,5,6))) + 1
st<-rbindlist(lapply(names(W),function(nm){w<-W[[nm]]; sub<-mo[ym>=w[1]&ym<=w[2]]
  cov<-nrow(sub)/mlen(w[1],w[2])
  if(!nrow(sub)) return(data.table(scenario=nm,core=NA,bm=NA,active=NA,n=0,coverage=0,reliable=FALSE,status="NO_DATA"))
  data.table(scenario=nm, core=prod(1+sub$core)-1, bm=prod(1+sub$bm)-1, active=prod(1+sub$core)/prod(1+sub$bm)-1,
    n=nrow(sub), coverage=round(cov,2), reliable=cov>=0.85,
    status=if(cov<0.85)"UNRELIABLE_LOW_COVERAGE" else if(prod(1+sub$core)-1<=-0.25)"RF_R4_BREACH" else "OK")}))
saveRDS(st, file.path(OUT,"_risk_stress8.rds")); print(st)
cat("\n[stress8] periods:",nrow(st)," breaches(reliable):",nrow(st[status=="RF_R4_BREACH"]),
    " low-coverage:",nrow(st[status=="UNRELIABLE_LOW_COVERAGE"]),"\n")
