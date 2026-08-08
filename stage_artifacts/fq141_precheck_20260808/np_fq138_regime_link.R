## FQ-138 사전확인 — 국면 변수 mega_spread 가 오늘 특성화한 d 와 같은 축인가
## 같으면 439개월 d 특성화(base rate·시대구조·현재 상태)를 FQ-138 사전등록에 그대로 쓸 수 있다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
say <- function(fmt,...) cat(sprintf(paste0("[fq138] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))
setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
M <- P[, .(d            = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m),
           mega_spread  = mean(Ret_1m[rk<=10]) - median(Ret_1m)), by=Date][order(Date)]
say("%d개월 (%s ~ %s)", nrow(M), min(M$Date), max(M$Date))
say("--- 두 국면 변수의 관계 ---")
say("  cor(d, mega_spread) = %+.3f", cor(M$d, M$mega_spread))
say("  부호 일치율 = %.1f%%", mean(sign(M$d)==sign(M$mega_spread))*100)
M[, `:=`(d_lag=shift(d,1), ms_lag=shift(mega_spread,1))]
Ml <- M[is.finite(d_lag)]
say("  [t-1 기준, FQ-138 이 쓰는 형태] cor = %+.3f · 부호일치 %.1f%%",
    cor(Ml$d_lag, Ml$ms_lag), mean(sign(Ml$d_lag)==sign(Ml$ms_lag))*100)
say("--- FQ-138 국면(t-1 mega_spread <= 0) 의 base rate ---")
say("  전 구간 %.1f%% (%d/%d개월)", mean(Ml$ms_lag<=0)*100, sum(Ml$ms_lag<=0), nrow(Ml))
Ml[, era := paste0(floor(as.integer(format(Date,"%Y"))/5)*5,"s")]
print(Ml[, .(n=.N, ms_neg_pct=round(mean(ms_lag<=0)*100,1), d_neg_pct=round(mean(d_lag<=0)*100,1)), by=era][order(era)])
say("--- 현재 상태 (최근 12개월) ---")
print(tail(M[, .(Date, d=round(d,4), mega_spread=round(mega_spread,4),
                 fq138_regime=ifelse(shift(mega_spread,1)<=0,"ON","OFF"))], 12))
