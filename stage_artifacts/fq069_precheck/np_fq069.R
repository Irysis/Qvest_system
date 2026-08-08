## FQ-069 — 업종별 BSI 전망의 KR 주식 횡단면 정보 (사전등록 fq069_prereg.json 준수)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq069_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[069] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }; m/sqrt(s/n) }

MAP <- c("반도체"="C2600","IT하드웨어"="C2600","IT가전"="C2600","디스플레이"="C2600",
  "화학"="C2000","건강관리"="C2100","철강"="C2400","비철,목재등"="C2400",
  "기계"="C2900","상사,자본재"="C2900","자동차"="C3000","조선"="C3100",
  "화장품,의류,완구"="C1400","필수소비재"="C1000","에너지"="C1900",
  "건설,건축관련"="F4100","소매(유통)"="G4500","운송"="H4900",
  "소프트웨어"="J5800","미디어,교육"="J5800","통신서비스"="J5800",
  "유틸리티"="D3500","호텔,레저서비스"="I5500")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size,Sector)]
P <- merge(U, ret, by=c("Date","Ticker"))
P[, ym := format(Date,"%Y-%m")]
P[, bsi_ind := MAP[Sector]]
say("유니버스 %d 종목-월 · 매핑됨 %d (%.1f%%) · 미매핑 섹터 %s", nrow(P), sum(!is.na(P$bsi_ind)),
    mean(!is.na(P$bsi_ind))*100, paste(unique(P[is.na(bsi_ind)]$Sector), collapse=","))
P <- P[!is.na(bsi_ind)]

B <- as.data.table(read_parquet(file.path(OUT,"fq069_bsi.parquet")))
B[, ref_ym := paste0(substr(ym,1,4),"-",substr(ym,5,6))]
setorder(B, bsi, ITEM_CODE2, ref_ym)
B[, chg3 := val - shift(val,3), by=.(bsi, ITEM_CODE2)]
## PIT: 홀딩월 M 신호 = M-1 전망 → hold_ym = ref_ym + 1
B[, hold_ym := format(as.Date(paste0(ref_ym,"-01")) %m+% months(1), "%Y-%m")]

run <- function(bsi_lab, use_level, lab) {
  s <- B[bsi==bsi_lab, .(hold_ym, bsi_ind=ITEM_CODE2, sig = if (use_level) val else chg3)]
  s <- s[is.finite(sig)]
  S <- merge(P[, .(ym,Ticker,Ret_1m,bsi_ind)], s, by.x=c("ym","bsi_ind"), by.y=c("hold_ym","bsi_ind"))
  if (!nrow(S)) { say("%s ★병합 0행", lab); return(NULL) }
  S[, `:=`(z=(sig-mean(sig))/pmax(sd(sig),1e-9), y=Ret_1m-mean(Ret_1m)), by=ym]
  S <- S[is.finite(z)&is.finite(y)]
  fm <- S[, if (.N>=30 && uniqueN(bsi_ind)>=5) .(b=coef(lm(y~z))[["z"]]) else NULL, by=ym]
  ic <- S[, if (.N>=30 && uniqueN(bsi_ind)>=5)
            .(ic=suppressWarnings(cor(sig,Ret_1m,method="spearman",use="complete.obs"))) else NULL, by=ym]
  ic <- ic[is.finite(ic)]
  need <- 2.0*sd(ic$ic)/sqrt(nrow(ic))
  say("--- %s ---", lab)
  say("  %d 종목-월 · %d개월 · 업종 %d", nrow(S), uniqueN(S$ym), uniqueN(S$bsi_ind))
  say("  FMB %+.5f · NW t %+.2f | rank IC %+.4f · NW t %+.2f",
      mean(fm$b,na.rm=TRUE), nw_t(fm$b), mean(ic$ic), nw_t(ic$ic))
  say("  검정력: 필요 IC %.4f | 관측 |IC| %.4f -> %s | IC 0.04 시 기대 t %.2f",
      need, abs(mean(ic$ic)),
      if (abs(mean(ic$ic))<need) "INCONCLUSIVE" else "NEGATIVE_POWERED",
      0.04/sd(ic$ic)*sqrt(nrow(ic)))
  invisible(NULL)
}
say("=== PRIMARY (사전등록) ===")
run("업황전망", FALSE, "업황전망 3개월 변화 ★PRIMARY")
say("=== SECONDARY (결과 무관 전량 보고) ===")
run("업황전망", TRUE,  "업황전망 수준")
run("신규수주전망", FALSE, "신규수주전망 3개월 변화")
run("채산성전망", FALSE, "채산성전망 3개월 변화")
run("설비투자전망", FALSE, "설비투자전망 3개월 변화")
