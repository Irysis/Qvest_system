suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1<-readRDS(file.path(OUT,"op1_objects.rds")); o6<-readRDS(file.path(OUT,"op6_objects.rds"))
A<-o1$A; SELW<-o6$SELW; BASEW<-o6$BASEW; SELP<-o6$SELP; m1<-o6$m1
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); X<-o3$X; STY<-o3$STY
cat("=== 스타일 노출 (활성 = book − cap-weighted 적격 유니버스) ===\n")
expo <- function(W,lab){
  z <- merge(W[,.(Date=as_of_date,Ticker,weight)], X[,c("Date","Ticker","wcap",..STY)], by=c("Date","Ticker"))
  u <- X[Date %in% unique(z$Date), c("Date","Ticker","wcap",..STY), with=FALSE]
  bm <- u[, lapply(.SD, function(v) sum(v*wcap,na.rm=TRUE)/sum(wcap,na.rm=TRUE)), by=Date, .SDcols=STY]
  bk <- z[, lapply(.SD, function(v) sum(v*weight,na.rm=TRUE)), by=Date, .SDcols=STY]
  ac <- merge(bk,bm,by="Date",suffixes=c("",".bm"))
  out <- ac[, lapply(STY, function(s) mean(get(s)-get(paste0(s,".bm")),na.rm=TRUE))]
  setnames(out, STY); out[, method:=lab][]
}
E <- rbind(expo(BASEW,"M1_EW25_base"), expo(SELW,"M2_EW25_buffer50"))
print(E[, c("method",STY), with=FALSE])
cat("\n=== as-of 2026-08-28 활성 노출 ===\n")
aso <- as.Date("2026-08-28")
for(nm in c("M1","SEL")){ W <- if(nm=="M1") BASEW else SELW
  z<-merge(W[as_of_date==aso,.(Date=as_of_date,Ticker,weight)],X[Date==aso,c("Date","Ticker","wcap",..STY)],by=c("Date","Ticker"))
  u<-X[Date==aso]; bmv<-sapply(STY,function(s) sum(u[[s]]*u$wcap,na.rm=TRUE)/sum(u$wcap,na.rm=TRUE))
  bkv<-sapply(STY,function(s) sum(z[[s]]*z$weight,na.rm=TRUE))
  cat(nm,":",paste(sprintf("%s %+.3f",STY,bkv-bmv),collapse=" | "),"\n") }
cat("\n=== D-floor 편향 진단 (rolling-60 잔차분산 p10 바닥) ===\n")
source(file.path(OUT,"op3_sigma_mod.R"))
fl <- rbindlist(lapply(seq(13,259), function(j){
  tk <- A[Date==ME[j]][order(-fh_lag1d,Ticker)]$Ticker[1:25]
  z <- sigma_at(j,tk); if(is.null(z)) return(NULL)
  xd <- X[Date==ME[j] & Ticker %in% z$names]
  data.table(j=j, n_floored=sum(z$floored), lift=mean(z$d_floored/z$d_raw),
    volexp_floored=mean(xd$VOL[match(z$names[z$floored],xd$Ticker)],na.rm=TRUE),
    volexp_all=mean(xd$VOL,na.rm=TRUE),
    sizeexp_floored=mean(xd$SIZE[match(z$names[z$floored],xd$Ticker)],na.rm=TRUE),
    sizeexp_all=mean(xd$SIZE,na.rm=TRUE),
    cor_d_vol=suppressWarnings(cor(z$d_raw, xd$VOL[match(z$names,xd$Ticker)],use="pairwise")))}))
cat("floor 발동 종목수/25: 평균",round(mean(fl$n_floored),2),"· 분산 상향 배수 평균",round(mean(fl$lift),4),"\n")
cat("floor 대상 종목 VOL 노출 평균",round(mean(fl$volexp_floored,na.rm=TRUE),3),
    "vs 보유 25종 평균",round(mean(fl$volexp_all),3),"\n")
cat("floor 대상 종목 SIZE 노출 평균",round(mean(fl$sizeexp_floored,na.rm=TRUE),3),
    "vs 보유 25종 평균",round(mean(fl$sizeexp_all),3),"\n")
cat("corr(D_raw, VOL 노출) 시계열 평균",round(mean(fl$cor_d_vol,na.rm=TRUE),4),"\n")
cat("\n=== 손익분기 편도 비용 ===\n")
be <- function(p){ f<-function(cb) mean((p$ret_gross-cb*p$traded)-p$bm); uniroot(f,c(0,0.02))$root*10000 }
cat("M1:",round(be(m1),2),"bps · SELECTED:",round(be(SELP),2),"bps\n")
cat("\n=== 회전/용량 교환 (전구간 259M) ===\n")
cat(sprintf("회전 %.3f -> %.3f (-%.1f%%) · 비용 %.2f%%/yr -> %.2f%%/yr (-%dbps)\n",
  mean(m1$traded)*12, mean(SELP$traded)*12, 100*(1-mean(SELP$traded)/mean(m1$traded)),
  100*mean(m1$cost)*12, 100*mean(SELP$cost)*12, round(1e4*(mean(m1$cost)-mean(SELP$cost))*12)))
cat(sprintf("총활성 %.2f%%/yr -> %.2f%%/yr (알파 손실 %dbps) · 순활성 %.2f%% -> %.2f%% (순 %+dbps)\n",
  100*mean(m1$ret_gross-m1$bm)*12, 100*mean(SELP$ret_gross-SELP$bm)*12,
  round(1e4*(mean(m1$ret_gross-m1$bm)-mean(SELP$ret_gross-SELP$bm))*12),
  100*mean(m1$ret_net-m1$bm)*12, 100*mean(SELP$ret_net-SELP$bm)*12,
  round(1e4*(mean(SELP$ret_net-SELP$bm)-mean(m1$ret_net-m1$bm))*12)))
saveRDS(list(E=E,fl=fl), file.path(OUT,"op7_objects.rds"))
