## _r6_prepost_split.R — 기질교체 paired 개선의 pre/post-2017 분해 (정직성 핵심)
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
x <- readRDS(".cache/_ramp_r6_ppure_20260711.rds"); PR <- x$PR
post <- as.Date("2017-01-01")
nwt <- function(v){ v<-v[is.finite(v)]; if(length(v)<12) return(NA)
  m<-lm(v~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
srf <- function(v){ v<-v[is.finite(v)]; if(length(v)<6) return(NA); mean(v)/sd(v)*sqrt(12) }
split_pair <- function(la, lb){
  m <- merge(PR[[la]][,.(date,a=act_bm)], PR[[lb]][,.(date,b=act_bm)], by="date")
  d <- m$a - m$b; pre <- m$date<post; pst <- m$date>=post
  data.table(model=la, base=lb,
    full_pt=round(nwt(d),2), pre_pt=round(nwt(d[pre]),2), post_pt=round(nwt(d[pst]),2),
    npre=sum(pre), npost=sum(pst),
    a_post_sr=round(srf(m$a[pst]),2), b_post_sr=round(srf(m$b[pst]),2)) }
cat("=== 기질교체 paired 개선의 pre/post-2017 분해 (P-pure − base_all11) ===\n")
R <- rbindlist(list(
  split_pair("Ppure_W36_K20","base_all11_W36"),
  split_pair("Ppure_W36_K10","base_all11_W36"),
  split_pair("Ppure_W60_K20","base_all11_W60")), fill=TRUE)
print(R)
cat("\n=== 선별 격리 (P-pure − ctrl_all102) pre/post ===\n")
R2 <- rbindlist(list(
  split_pair("Ppure_W36_K20","ctrl_all102_W36"),
  split_pair("Ppure_W60_K20","ctrl_all102_W60")), fill=TRUE)
print(R2)
cat("\nPREPOST_DONE\n")
