## FQ-068 R1 — 반도체 PPI 모멘텀이 KR 반도체 공급망(장비·소재) 수익을 예측하는가
## PIT: 참조월 M-2 까지만 사용 (발표지연 중앙 43일·최대 105일 실측 → 보수 고정)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[R1] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector_Lv2")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size,Sector_Lv2)]
P <- merge(U, ret, by=c("Date","Ticker"))
setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
P[, semi := !is.na(Sector_Lv2) & grepl("반도체|디스플레이패널", Sector_Lv2)]
P[, hold_ym := format(as.Date(paste0(format(Date,"%Y-%m"),"-01")) %m+% months(1), "%Y-%m")]
say("패널 %d개월 · 반도체 월평균 %.1f종 (non-MEGA %.1f)", uniqueN(P$Date),
    nrow(P[semi==TRUE])/uniqueN(P$Date), nrow(P[semi==TRUE & rk>10])/uniqueN(P$Date))

ppi <- as.data.table(read_parquet(file.path(OUT,"fq068_ppi_raw.parquet")))
ppi <- ppi[Series_ID=="PCU334413334413"][order(Date)]
ppi[, `:=`(mom3=Value/shift(Value,3)-1, mom6=Value/shift(Value,6)-1, mom12=Value/shift(Value,12)-1)]
ppi[, hold_ym := format(Date %m+% months(2), "%Y-%m")]   # 참조월 M -> 홀딩월 M+2 (PIT)

M <- merge(P, ppi[, .(hold_ym, mom3, mom6, mom12)], by="hold_ym")
say("병합 %d개월 (%s ~ %s)", uniqueN(M$hold_ym), min(M$hold_ym), max(M$hold_ym))

S <- M[, .(semi_ew=mean(Ret_1m[semi==TRUE]), semi_nm=mean(Ret_1m[semi==TRUE & rk>10]),
           uni_ew=mean(Ret_1m), mom3=mom3[1], mom6=mom6[1], mom12=mom12[1]), by=hold_ym][order(hold_ym)]
S <- S[is.finite(semi_ew) & is.finite(mom6)]
S[, `:=`(exc=semi_ew-uni_ew, exc_nm=semi_nm-uni_ew)]
say("유효 %d개월 · 반도체 초과 평균 %+.4f/월 (연 %+.2f%%)", nrow(S), mean(S$exc), mean(S$exc)*12*100)

say("--- 섹터 타이밍: PPI 모멘텀 부호별 반도체 초과수익 ---")
for (sig in c("mom3","mom6","mom12")) {
  on <- S[get(sig)>0]; off <- S[get(sig)<=0]
  d  <- mean(on$exc) - mean(off$exc)
  tt <- tryCatch(t.test(on$exc, off$exc)$statistic, error=function(e) NA_real_)
  say("  %-5s ON %3d월 %+.4f | OFF %3d월 %+.4f | 차 %+.4f (연 %+.2f%%) t=%.2f",
      sig, nrow(on), mean(on$exc), nrow(off), mean(off$exc), d, d*12*100, tt)
}
say("--- non-MEGA 한정 (top-25 EW 로 표현 가능한 횡단면) ---")
for (sig in c("mom3","mom6","mom12")) {
  on <- S[get(sig)>0]; off <- S[get(sig)<=0]
  d  <- mean(on$exc_nm) - mean(off$exc_nm)
  tt <- tryCatch(t.test(on$exc_nm, off$exc_nm)$statistic, error=function(e) NA_real_)
  say("  %-5s 차 %+.4f (연 %+.2f%%) t=%.2f", sig, d, d*12*100, tt)
}
fwrite(S, file.path(OUT,"fq068_r1_sector_timing.csv")); say("저장 완료")
