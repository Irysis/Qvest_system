suppressPackageStartupMessages({ library(data.table); library(arrow) })
QM <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- file.path(QM,"stage_artifacts/method_frontier/fq066_ppi_margin")
R <- readRDS(file.path(OUT,"fq066_results.rds")); mlong <- R$mlong

# 1) sanity: margin values for a few sectors/dates
cat("== margin sample (에너지=refining crack, 화학, 철강) ==\n")
print(mlong[Sector %in% c("에너지","화학","철강") & refmonth %in% as.Date(c("2020-04-01","2021-10-01","2022-06-01"))][order(Sector,refmonth)])
cat("\nmargin summary by sector:\n")
print(mlong[, .(mean=round(mean(margin),3), sd=round(sd(margin),3), min=round(min(margin),3), max=round(max(margin),3)), by=Sector])

# rebuild returns for horizon tests
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
rd <- as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet")))
rd <- rd[Date >= as.Date("2004-06-01") & !is.na(Close) & Close>0]; rd[, ym:=format(Date,"%Y-%m")]
me <- rd[, .(Date=max(Date)), by=ym]$Date; rd_me <- rd[Date %in% me]
sig <- sort(unique(rd_me$Date)); sig <- sig[sig>=as.Date("2005-06-01")]
fwd <- build_monthly_forward_returns(rd_me, sig)
ret <- fwd$returns_dt; sec_me <- rd_me[,.(Date,Ticker,Sector,Size)][!is.na(Sector)]
smap_sec <- unique(mlong$Sector)
sret <- merge(ret, sec_me, by=c("Date","Ticker"))[Sector %in% smap_sec][
  , .(sret=weighted.mean(Ret_1m, w=ifelse(is.na(Size),0,Size), na.rm=TRUE), n=.N), by=.(Date,Sector)][n>=3]

add_months <- function(d,n){ d<-as.Date(paste0(format(d,"%Y-%m"),"-01")); yr<-as.integer(format(d,"%Y")); mo<-as.integer(format(d,"%m"))+n; yr<-yr+(mo-1)%/%12; mo<-((mo-1)%%12)+1; as.Date(sprintf("%04d-%02d-01",yr,mo)) }
assign_margin <- function(LAG,val="margin"){ sd<-data.table(Date=sig); sd[,ref_use:=add_months(Date,-LAG)]; merge(sd, mlong[,.(ref_use=refmonth,Sector,v=get(val))], by="ref_use", allow.cartesian=TRUE)[,.(Date,Sector,margin=v)] }

ic_test <- function(mg, sret_shift=0){
  s2 <- copy(sret); setorder(s2, Sector, Date)
  if (sret_shift!=0) s2[, sret := shift(sret, -sret_shift), by=Sector]  # forward N months
  d <- merge(mg, s2, by=c("Date","Sector"))[!is.na(sret)]
  ic <- d[, if(.N>=5 && sd(margin)>0 && sd(sret)>0) .(ic=cor(margin,sret,method="spearman")) else .(ic=NA_real_), by=Date][!is.na(ic)]
  c(mean=mean(ic$ic), t=mean(ic$ic)/(sd(ic$ic)/sqrt(nrow(ic))), nM=nrow(ic))
}
# contemporaneous (LAG=2 signal vs same-month sret already forward1); use shift to align
cat("\n== IC across horizons (margin LAG=2 YoY spread) ==\n")
mg2 <- assign_margin(2)
for (h in 0:3) { r<-ic_test(mg2, h); cat(sprintf(" fwd+%dm: IC=%.4f t=%.2f nM=%d\n", h+1, r["mean"], r["t"], r["nM"])) }

# level-ratio version: build margin_ratio = out_level/in_level, 3m change — recompute from raw
raw <- as.data.table(read_parquet(file.path(OUT,"ecos_ppi_raw.parquet")))
smapdt <- fread(file.path(OUT,"sector_ppi_map.csv"))
setorder(raw, table, code, refmonth)
lw <- dcast(raw, refmonth ~ table+code, value.var="val")
mr <- rbindlist(lapply(1:nrow(smapdt), function(i){
  oc<-paste0("404Y014_out_",smapdt$out[i]); ic<-paste0("401Y015_in_W_",smapdt$inp[i])
  if(!oc%in%names(lw)||!ic%in%names(lw)) return(NULL)
  data.table(refmonth=lw$refmonth, Sector=smapdt$Sector[i], ratio=lw[[oc]]/lw[[ic]])
}))
setorder(mr, Sector, refmonth)
mr[, marg_chg3 := ratio/shift(ratio,3)-1, by=Sector]  # 3m change in margin ratio (accel)
mlong_bak <- mlong
mlong <<- mr[!is.na(marg_chg3), .(refmonth, Sector, margin=marg_chg3)]
cat("\n== IC: margin-ratio 3m-change (accel), LAG=2, horizons ==\n")
mg3 <- assign_margin(2)
for (h in 0:2){ r<-ic_test(mg3,h); cat(sprintf(" fwd+%dm: IC=%.4f t=%.2f nM=%d\n", h+1, r["mean"], r["t"], r["nM"])) }
