## FQ-068a — 하위군별 횡단면 IC (사전등록 fq068a_prereg.json 분류 고정)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[068a] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }; m/sqrt(s/n) }

GRP <- list(
  장비   = c("A036930","A240810","A095610","A084370","A319660","A403870","A042700",
             "A039030","A348210","A420770","A089030","A079370","A253590","A036810"),
  소재   = c("A005290","A357780","A166090","A074600","A064760","A101490","A183300"),
  후공정 = c("A036540","A067310","A131970","A095340","A058470","A131290","A232140"),
  설계IDM= c("A005930","A000660","A000990","A080220","A399720","A402340"))
map <- rbindlist(lapply(names(GRP), function(g) data.table(Ticker=GRP[[g]], grp=g)))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker")); P[, ym := format(Date,"%Y-%m")]

ppi <- as.data.table(read_parquet(file.path(OUT,"fq068_ppi_raw.parquet")))
ppi <- ppi[Series_ID=="PCU334413334413"][order(Date)]
ppi[, `:=`(dppi=Value/shift(Value,1)-1, mom6=Value/shift(Value,6)-1)]
ppi[, ref_ym := format(Date,"%Y-%m")]; ppi[, hold_ym := format(Date %m+% months(2), "%Y-%m")]

R <- merge(P[, .(ym,Ticker,Ret_1m)], ppi[, .(ref_ym,dppi)], by.x="ym", by.y="ref_ym")
setorder(R, Ticker, ym); W <- 36L
R[, beta_ppi := { n<-.N; o<-rep(NA_real_,n)
  if (n>=W) for (i in W:n) { idx<-(i-W+1):i; y<-Ret_1m[idx]; x<-dppi[idx]
    if (sum(is.finite(y)&is.finite(x))>=24 && sd(x,na.rm=TRUE)>0)
      o[i] <- cov(y,x,use="complete.obs")/var(x,use="complete.obs") }
  o }, by=Ticker]

sig <- merge(R[, .(ym,Ticker,beta_ppi,Ret_1m)], ppi[, .(hold_ym,mom6_pit=mom6)], by.x="ym", by.y="hold_ym")
sig <- merge(sig, map, by="Ticker")
sig <- sig[is.finite(beta_ppi) & is.finite(mom6_pit) & is.finite(Ret_1m)]
sig[, score := beta_ppi * sign(mom6_pit)]
say("하위군 패널: %d 종목-월 · %d개월", nrow(sig), uniqueN(sig$ym))
print(sig[, .(종목수=uniqueN(Ticker), 종목월=.N, 월수=uniqueN(ym)), by=grp][order(-종목월)])

say("--- 군 내부 횡단면 rank IC (사전등록 예측: 장비 > 후공정 ~ 소재 > 설계IDM) ---")
res <- rbindlist(lapply(names(GRP), function(g) {
  d <- sig[grp==g]
  ic <- d[, .(ic=suppressWarnings(cor(score, Ret_1m, method="spearman", use="complete.obs")), n=.N),
          by=ym][n>=5 & is.finite(ic)]
  if (nrow(ic) < 20) return(data.table(grp=g, 월수=nrow(ic), IC=NA_real_, t_NW=NA_real_, 필요IC=NA_real_, 판정="표본부족"))
  s <- sd(ic$ic); m <- mean(ic$ic)
  need <- 2.0*s/sqrt(nrow(ic))
  data.table(grp=g, 월수=nrow(ic), IC=round(m,4), t_NW=round(nw_t(ic$ic),2),
             필요IC=round(need,4),
             판정=if (!is.na(nw_t(ic$ic)) && abs(nw_t(ic$ic))>=2.0) "유의"
                  else if (abs(m) < need) "INCONCLUSIVE" else "NEGATIVE_POWERED")
}), fill=TRUE)
print(res)
fwrite(res, file.path(OUT,"fq068a_subsector_ic.csv"))
say("★사전등록 예측 검정: 장비 IC 가 최상위인가 → %s",
    if (!all(is.na(res$IC)) && res[which.max(IC)]$grp == "장비") "예측 적중" else
      sprintf("예측 빗나감 (최상위 = %s)", res[which.max(IC)]$grp))
