## FQ-068c — 제외필터 소비면: 고 PPI-베타 상위 10% 를 유니버스에서 제외하면 개선되는가
## ★무조건 제외(전 기간) — 국면 조건부는 분할이라 검정력 없음(오늘 3회 실증). 전표본 유지.
## 검정: 월별 (제외 후 EW − 제외 전 EW) 시계열의 NW t
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[068c] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
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
s <- E[item=="반도체" & ccy=="D"][order(ym)]
s[, dx := Value/shift(Value,1)-1]
s[, ref_ym := paste0(substr(ym,1,4),"-",substr(ym,5,6))]
R <- merge(P[, .(ym,Ticker,Ret_1m)], s[, .(ref_ym,dx)], by.x="ym", by.y="ref_ym")
stopifnot(nrow(R) > 0)
setorder(R, Ticker, ym); W <- 36L
R[, beta := { n<-.N; o<-rep(NA_real_,n)
  if (n>=W) for (i in W:n) { idx<-(i-W+1):i; y<-Ret_1m[idx]; x<-dx[idx]
    if (sum(is.finite(y)&is.finite(x))>=24 && sd(x,na.rm=TRUE)>0)
      o[i] <- cov(y,x,use="complete.obs")/var(x,use="complete.obs") }
  o }, by=Ticker]
S <- R[is.finite(beta) & is.finite(Ret_1m)]
say("패널 %d 종목-월 · %d개월", nrow(S), uniqueN(S$ym))

test_excl <- function(q, lab) {
  D <- S[, {
    thr <- quantile(beta, 1-q, na.rm=TRUE)
    keep <- beta < thr
    .(base = mean(Ret_1m), filt = mean(Ret_1m[keep]),
      n_all = .N, n_drop = sum(!keep))
  }, by=ym][is.finite(base) & is.finite(filt)]
  D[, d := filt - base]
  say("--- %s (상위 %.0f%% 제외) ---", lab, q*100)
  say("  월수 %d · 월평균 제외 %.1f종 / %.1f종", nrow(D), mean(D$n_drop), mean(D$n_all))
  say("  개선 %+.5f/월 (연 %+.2f%%) · NW t %+.2f", mean(D$d), mean(D$d)*12*100, nw_t(D$d))
  need <- 2.0*sd(D$d)/sqrt(nrow(D))
  say("  검정력: 필요 %+.5f/월(연 %+.2f%%) | 관측 %+.5f -> %s", need, need*12*100, mean(D$d),
      if (abs(mean(D$d)) < need) "INCONCLUSIVE_UNDERPOWERED" else "NEGATIVE_POWERED")
  invisible(NULL)
}
for (q in c(0.10, 0.20)) test_excl(q, sprintf("고 PPI-베타 제외"))
say("--- 반대 방향 대조: 저 베타 제외(하위 10%%) ---")
D2 <- S[, { thr <- quantile(beta, 0.10, na.rm=TRUE)
  .(base=mean(Ret_1m), filt=mean(Ret_1m[beta > thr])) }, by=ym][is.finite(base)&is.finite(filt)]
D2[, d := filt - base]
say("  개선 %+.5f/월 (연 %+.2f%%) · NW t %+.2f", mean(D2$d), mean(D2$d)*12*100, nw_t(D2$d))
