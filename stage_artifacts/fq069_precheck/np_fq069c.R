## FQ-069c — 업종-레벨 신호의 구조적 IC 상한: 업종 간 vs 업종 내 수익 분산 분해
## 목적: null 이 '재료 판정'인지 '설계 천장'인지 가른다. 매핑 재작성 없음(사후적합 방지).
## 방법: ①분산 분해(between/within) ②완전예지 업종 신호(oracle)의 IC = 달성 가능 상한
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq069_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[069c] ",fmt,"\n"),...))
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
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector","Sector_Lv2")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Sector,Sector_Lv2)]
P <- merge(U, ret, by=c("Date","Ticker")); P[, ym := format(Date,"%Y-%m")]
P <- P[ym >= "2009-10"]
P[, bsi_ind := MAP[Sector]]

decomp <- function(grpcol, lab) {
  D <- P[!is.na(get(grpcol)) & is.finite(Ret_1m)]
  r <- D[, {
    tot <- var(Ret_1m)
    gm  <- .SD[, .(m=mean(Ret_1m), n=.N), by=g]
    bet <- sum(gm$n*(gm$m-mean(Ret_1m))^2)/(.N)
    .(share = bet/tot, k = uniqueN(g), n = .N)
  }, by=ym, .SDcols=c("Ret_1m","g")]
  say("%-22s 업종 %5.1f개 · 업종간 분산 비중 **%.1f%%** (월 중앙)", lab, median(r$k), median(r$share)*100)
  invisible(r)
}
P[, g := bsi_ind]; d1 <- decomp("g", "BSI 매핑 (16업종)")
P[, g := Sector];  d2 <- decomp("g", "RAWDATA Sector (26)")
P[, g := Sector_Lv2]; d3 <- decomp("g", "Sector_Lv2 (세분)")

say("--- ★oracle 상한: 업종 실현수익을 완전예지한 신호의 rank IC ---")
oracle <- function(grpcol, lab) {
  D <- P[!is.na(get(grpcol)) & is.finite(Ret_1m)]
  ic <- D[, { gm <- .SD[, .(gr=mean(Ret_1m)), by=g]
              x <- merge(.SD, gm, by="g")
              .(ic = suppressWarnings(cor(x$gr, x$Ret_1m, method="spearman"))) },
          by=ym, .SDcols=c("Ret_1m","g")]
  ic <- ic[is.finite(ic)]
  say("  %-22s oracle IC %+.4f (t_NW %.1f) · 월수 %d", lab, mean(ic$ic), nw_t(ic$ic), nrow(ic))
  invisible(NULL)
}
P[, g := bsi_ind];   oracle("g","BSI 매핑 (16업종)")
P[, g := Sector];    oracle("g","RAWDATA Sector (26)")
P[, g := Sector_Lv2];oracle("g","Sector_Lv2 (세분)")
say("★읽는 법: oracle IC = 업종을 완벽히 맞혀도 나올 수 있는 최대 IC.")
say("   실측 신호 IC(업황 -0.001 / 설비투자 +0.017)를 이 상한과 대조하면 설계 천장 여부가 판정된다.")
