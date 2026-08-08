## FQ-068a1a — pooled OLS t(-2.35) 가 클러스터/FMB 보정에서 살아남는가
## 방법: Fama-MacBeth (월별 횡단면 회귀 → 계수 시계열의 NW t). 횡단면 상관을 구조적으로 처리.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[a1a] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }; m/sqrt(s/n) }

GRP <- c("A036930","A240810","A095610","A084370","A319660","A403870","A042700","A039030",
         "A348210","A420770","A089030","A079370","A253590","A036810",
         "A005290","A357780","A166090","A074600","A064760","A101490","A183300",
         "A036540","A067310","A131970","A095340","A058470","A131290","A232140",
         "A005930","A000660","A000990","A080220","A399720","A402340")

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

R <- merge(P[, .(ym,Ticker,Ret_1m,Size)], ppi[, .(ref_ym,dppi)], by.x="ym", by.y="ref_ym")
setorder(R, Ticker, ym); W <- 36L
R[, beta_ppi := { n<-.N; o<-rep(NA_real_,n)
  if (n>=W) for (i in W:n) { idx<-(i-W+1):i; y<-Ret_1m[idx]; x<-dppi[idx]
    if (sum(is.finite(y)&is.finite(x))>=24 && sd(x,na.rm=TRUE)>0)
      o[i] <- cov(y,x,use="complete.obs")/var(x,use="complete.obs") }
  o }, by=Ticker]

S <- merge(R[, .(ym,Ticker,beta_ppi,Ret_1m,Size)], ppi[, .(hold_ym,mom6_pit=mom6)], by.x="ym", by.y="hold_ym")
S <- S[Ticker %in% GRP & is.finite(beta_ppi) & is.finite(mom6_pit) & is.finite(Ret_1m)]
S[, score := beta_ppi * sign(mom6_pit)]
S[, `:=`(z=(score-mean(score))/pmax(sd(score),1e-9), y=Ret_1m-mean(Ret_1m),
         lsz=log(Size)), by=ym]
S <- S[is.finite(z) & is.finite(y)]

say("--- 대조: pooled OLS (직전 라운드 재현) ---")
c0 <- summary(lm(y ~ z, data=S))$coefficients
say("  z %+.5f · t %.2f · n=%d", c0["z","Estimate"], c0["z","t value"], nrow(S))

say("--- ★Fama-MacBeth (월별 횡단면 → 계수 시계열 NW t) ---")
for (minN in c(5L, 8L)) {
  fm <- S[, if (.N >= minN) .(b = coef(lm(y ~ z))[["z"]], n=.N) else NULL, by=ym]
  say("  최소 %d종목: 월수 %d · 평균 계수 %+.5f · 단순 t %.2f · **NW(lag3) t %.2f**",
      minN, nrow(fm), mean(fm$b), mean(fm$b)/sd(fm$b)*sqrt(nrow(fm)), nw_t(fm$b))
}
say("--- 사이즈 통제 후 FMB (z + log Size) ---")
fm2 <- S[, if (.N >= 8L) .(b = coef(lm(y ~ z + lsz))[["z"]], n=.N) else NULL, by=ym]
say("  월수 %d · 평균 %+.5f · NW t %.2f", nrow(fm2), mean(fm2$b), nw_t(fm2$b))
say("★판정: pooled t 는 %s", if (abs(nw_t(fm2$b)) >= 2.0) "FMB 에서도 유지" else "FMB 에서 소멸 — pooled 는 상관 미보정으로 부풀려진 값")
