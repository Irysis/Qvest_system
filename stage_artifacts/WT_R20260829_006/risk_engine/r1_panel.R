## WT-R20260829_006 RISK Stage 1 (v2) — 고정 매크로섹터 설계
suppressPackageStartupMessages({library(data.table);library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
S  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"

mk <- readRDS(file.path(S,"p1s_market.rds"))
RET <- mk$RET_DT; BEN <- mk$BENCH_DT; LIQ <- mk$LIQ_DT; SIZ <- mk$SIZE_DT; UNI <- mk$UNIV_DT; ME <- mk$ME
FZ  <- as.data.table(read_parquet(file.path(S,"p1s_family_z_panel.parquet")))
FAMS <- sort(unique(FZ$family))

SECMAP <- c(
 "IT하드웨어"="IT","소프트웨어"="IT","반도체"="IT","디스플레이"="IT","IT가전"="IT","통신서비스"="IT",
 "건강관리"="HEALTH",
 "자동차"="CONSDISC","화장품,의류,완구"="CONSDISC","미디어,교육"="CONSDISC","소매(유통)"="CONSDISC","호텔,레저서비스"="CONSDISC",
 "필수소비재"="STAPLE",
 "건설,건축관련"="INDUST","기계"="INDUST","상사,자본재"="INDUST","운송"="INDUST","조선"="INDUST",
 "화학"="MATER","비철,목재등"="MATER","철강"="MATER",
 "은행"="FIN","증권"="FIN","보험"="FIN",
 "에너지"="ENUTIL","유틸리티"="ENUTIL")
SEC_REF <- "IT"
SEC_LV  <- c("HEALTH","CONSDISC","STAPLE","INDUST","MATER","FIN","ENUTIL")  ## OTHER(미분류)는 IT 기준군에 흡수 — 월 4회만 추정가능해 zero-fill 아티팩트 유발

sec <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Sector")))
sec[, Date := as.Date(Date)]; sec <- sec[Date %in% ME]
sec[, sec9 := SECMAP[Sector]]; sec[is.na(sec9), sec9 := "OTHER"]
cat("[sector9]\n"); print(sec[, .N, by=sec9][order(-N)])

## rolling beta (과거 60앵커, 당월 forward 미포함)
RB <- merge(RET, BEN, by="Date"); RB[, `:=`(mr=Ret_1m, br=BM_Ret)]
adates <- sort(unique(RB$Date)); bl <- vector("list", length(adates))
for (i in seq_along(adates)) {
  d <- adates[i]; lo <- adates[max(1L,i-60L)]
  w <- RB[Date>=lo & Date<d]; if (nrow(w)==0L) next
  bb <- w[, .(nobs=.N, cvb=if(.N>=24L) stats::cov(mr,br) else NA_real_,
                        vb =if(.N>=24L) stats::var(br)     else NA_real_), by=Ticker]
  bb[, beta := 0.67*(cvb/vb) + 0.33]
  bl[[i]] <- bb[is.finite(beta), .(Date=d, Ticker, beta, nobs)]
}
BETA <- rbindlist(bl); saveRDS(BETA, file.path(O,"beta_panel.rds"))
cat("[beta] rows",nrow(BETA),"dates",uniqueN(BETA$Date),"\n")

zsc <- function(x){ x<-as.numeric(x); mu<-mean(x,na.rm=TRUE); s<-stats::sd(x,na.rm=TRUE)
  if(!is.finite(s)||s<=0) return(rep(0,length(x))); y<-(x-mu)/s; y[!is.finite(y)]<-0; pmax(pmin(y,3),-3) }

FZW <- dcast(FZ, Date+Ticker ~ family, value.var="z_fam")
setnames(FZW, FAMS, paste0("f_",FAMS)); fcols <- paste0("f_",FAMS)

XCOLS <- c("x_beta","x_size","x_liq", paste0("x_",fcols), paste0("s_",SEC_LV))
FULL  <- c("Intercept", XCOLS)

dts <- sort(unique(RET$Date)); dts <- dts[dts >= as.Date("2005-11-01")]
Fl<-vector("list",length(dts)); El<-vector("list",length(dts)); Cl<-vector("list",length(dts)); Bl<-vector("list",length(dts))
for (i in seq_along(dts)) {
  d <- dts[i]
  keep <- merge(UNI[Date==d,.(Ticker)], LIQ[Date==d,.(Ticker,adv)], by="Ticker", all.x=TRUE)[is.na(adv)|adv>=2e8]
  X <- merge(keep, RET[Date==d,.(Ticker,Ret_1m)], by="Ticker")
  X <- merge(X, SIZ[Date==d,.(Ticker,Size)], by="Ticker")
  X <- merge(X, BETA[Date==d,.(Ticker,beta)], by="Ticker")
  X <- merge(X, sec[Date==d,.(Ticker,sec9)], by="Ticker", all.x=TRUE)
  fz <- FZW[Date==d]; fz[, Date:=NULL]
  X <- merge(X, fz, by="Ticker", all.x=TRUE)
  X <- X[is.finite(Ret_1m)&is.finite(Size)&Size>0&is.finite(beta)]
  for (cc in fcols) { v<-X[[cc]]; v[!is.finite(v)]<-0; set(X,j=cc,value=v) }
  if (nrow(X) < 80L) next
  X[is.na(sec9), sec9:="OTHER"]
  X[, `:=`(x_beta=zsc(beta), x_size=zsc(log(Size)), x_liq=zsc(log(pmax(adv,1))))]
  for (cc in fcols) set(X, j=paste0("x_",cc), value=zsc(X[[cc]]))
  for (s in SEC_LV) set(X, j=paste0("s_",s), value=as.numeric(X$sec9==s))
  M <- cbind(Intercept=1, as.matrix(X[, ..XCOLS]))
  keepc <- apply(M,2,function(v) stats::sd(v)>0 | all(v==1))
  keepc["Intercept"] <- TRUE
  Mu <- M[, keepc, drop=FALSE]
  fit <- stats::lm.fit(Mu, X$Ret_1m)
  cf <- setNames(rep(NA_real_, length(FULL)), FULL)
  cfu <- fit$coefficients; cfu[!is.finite(cfu)] <- NA_real_
  cf[names(cfu)] <- cfu
  Fl[[i]] <- data.table(Date=d, factor=FULL, fret=as.numeric(cf))
  El[[i]] <- data.table(Date=d, Ticker=X$Ticker, resid=as.numeric(fit$residuals))
  Bl[[i]] <- cbind(data.table(Date=d, Ticker=X$Ticker), X[, ..XCOLS])
  ss_t <- sum((X$Ret_1m-mean(X$Ret_1m))^2); ss_r <- sum(fit$residuals^2)
  Cl[[i]] <- data.table(Date=d, n=nrow(X), k=ncol(Mu), r2=1-ss_r/ss_t,
                        sd_tot=sqrt(ss_t/(nrow(X)-1)), sd_res=sqrt(ss_r/(nrow(X)-1)),
                        n_na_coef=sum(is.na(cf)))
  if (i %% 60 == 0) cat("  [",i,"/",length(dts),"]",as.character(d),"n",nrow(X),"r2",round(1-ss_r/ss_t,3),"\n")
}
FR<-rbindlist(Fl,fill=TRUE); ER<-rbindlist(El,fill=TRUE); CV<-rbindlist(Cl,fill=TRUE); BB<-rbindlist(Bl,fill=TRUE)
cat("[out] months",nrow(CV)," mean R2",round(mean(CV$r2),4)," median n",median(CV$n),
    " total NA coefs",sum(CV$n_na_coef),"\n")
cat("[out] range",as.character(min(CV$Date)),"~",as.character(max(CV$Date)),"\n")
saveRDS(list(FR=FR,ER=ER,CV=CV,BB=BB,FAMS=FAMS,SEC_LV=SEC_LV,SEC_REF=SEC_REF,XCOLS=XCOLS,SECMAP=SECMAP),
        file.path(O,"r1_reg.rds"))
cat("[done]\n")
