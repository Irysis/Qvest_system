## FQ-068b — ECOS KR 수출물가(반도체/장비) 전표본 횡단면, FMB 추정 (사전등록 fq068b_prereg.json)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[068b] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }; m/sqrt(s/n) }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker")); P[, ym := format(Date,"%Y-%m")]

E <- as.data.table(read_parquet(file.path(OUT,"fq068b_ecos_semi.parquet")))
run_one <- function(item_lab, ccy_sel, lab) {
  s <- E[item==item_lab & ccy==ccy_sel][order(ym)]
  if (!nrow(s)) { say("%s 계열 없음", lab); return(NULL) }
  s[, `:=`(dx = Value/shift(Value,1)-1, mom6 = Value/shift(Value,6)-1)]
  s[, ref_ym := paste0(substr(ym,1,4),"-",substr(ym,5,6))]   # ★P$ym 과 형식 일치(YYYY-MM) — 빈 병합 방지
  s[, hold_ym := format(as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")) %m+% months(2), "%Y-%m")]
  R <- merge(P[, .(ym,Ticker,Ret_1m,Size)], s[, .(ref_ym, dx)], by.x="ym", by.y="ref_ym")
  if (!nrow(R)) { say("%s ★병합 0행 — 키 형식 불일치", lab); return(NULL) }
  setorder(R, Ticker, ym); W <- 36L
  R[, beta := { n<-.N; o<-rep(NA_real_,n)
    if (n>=W) for (i in W:n) { idx<-(i-W+1):i; y<-Ret_1m[idx]; x<-dx[idx]
      if (sum(is.finite(y)&is.finite(x))>=24 && sd(x,na.rm=TRUE)>0)
        o[i] <- cov(y,x,use="complete.obs")/var(x,use="complete.obs") }
    o }, by=Ticker]
  S <- merge(R[, .(ym,Ticker,beta,Ret_1m,Size)], s[, .(hold_ym, m6=mom6)], by.x="ym", by.y="hold_ym")
  S <- S[is.finite(beta) & is.finite(m6) & is.finite(Ret_1m)]
  S[, score := beta * sign(m6)]
  S[, `:=`(z=(score-mean(score))/pmax(sd(score),1e-9), y=Ret_1m-mean(Ret_1m)), by=ym]
  S <- S[is.finite(z)&is.finite(y)]
  fm <- S[, if (.N>=30) .(b=coef(lm(y~z))[["z"]]) else NULL, by=ym]
  ic <- S[, if (.N>=30) .(ic=suppressWarnings(cor(score,Ret_1m,method="spearman",use="complete.obs"))) else NULL, by=ym]
  ic <- ic[is.finite(ic)]
  say("--- %s ---", lab)
  say("  패널 %d 종목-월 · %d개월", nrow(S), uniqueN(S$ym))
  say("  FMB 계수 %+.5f · NW t %+.2f  (월수 %d)", mean(fm$b, na.rm=TRUE), nw_t(fm$b), nrow(fm))
  say("  rank IC %+.4f · NW t %+.2f · IC sd %.4f", mean(ic$ic), nw_t(ic$ic), sd(ic$ic))
  need <- 2.0*sd(ic$ic)/sqrt(nrow(ic))
  say("  검정력: t=2.0 필요 IC %.4f | 관측 |IC| %.4f -> %s", need, abs(mean(ic$ic)),
      if (abs(mean(ic$ic)) < need) "INCONCLUSIVE_UNDERPOWERED" else "NEGATIVE_POWERED")
  say("  참고: IC 0.04 이면 기대 t %.2f", 0.04/sd(ic$ic)*sqrt(nrow(ic)))
  invisible(NULL)
}
say("=== PRIMARY (사전등록: 달러기준) ===")
run_one("반도체","D","반도체 수출물가 (달러) — PRIMARY")
run_one("반도체장비","D","반도체장비 수출물가 (달러) — 기전 중간마디")
say("=== SECONDARY (결과 무관 병기: 원화기준) ===")
run_one("반도체","W","반도체 수출물가 (원화)")
run_one("반도체장비","W","반도체장비 수출물가 (원화)")
