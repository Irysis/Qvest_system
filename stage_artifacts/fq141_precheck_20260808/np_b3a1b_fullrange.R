## NP-b3a1b — 축 통합(d ≡ -size_eff)이 전 구간에서 유지되는가
## 직전 라운드는 rk>300 절대 순위를 써서 2010+ 199개월만 봤다. 상대 분위로 재정의해 439개월 검증.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[b3a1b] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))
setorder(P, Date, -Size); P[, `:=`(rk=seq_len(.N), N=.N), by=Date]
P[, q := rk/N]                                   # 상대 분위 (0=최대형)
P[, uni_ew := mean(Ret_1m), by=Date]; P[, excess := Ret_1m - uni_ew]

M <- P[, .(
  d          = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m),
  size_rel   = mean(excess[q>0.90]) - mean(excess[q<=0.10]),   # 하위10% − 상위10% (상대)
  size_abs   = if (sum(rk>300)>0) mean(excess[rk>300]) - mean(excess[rk<=10]) else NA_real_,
  n_names    = .N
), by=Date][order(Date)]
say("전체 %d개월 · size_rel 유효 %d · size_abs 유효 %d",
    nrow(M), sum(is.finite(M$size_rel)), sum(is.finite(M$size_abs)))

Mr <- M[is.finite(d) & is.finite(size_rel)]
say("--- 전 구간 (%s ~ %s, %d개월) ---", min(Mr$Date), max(Mr$Date), nrow(Mr))
say("  cor(d, size_rel) = %+.3f", cor(Mr$d, Mr$size_rel))
both <- M[is.finite(size_rel) & is.finite(size_abs)]
say("  [정합] cor(size_rel, size_abs) = %+.3f  (n=%d, 2010+ 겹침)", cor(both$size_rel, both$size_abs), nrow(both))
say("  [대조] cor(d, size_abs) = %+.3f", cor(both$d, both$size_abs))

say("--- 시대별 cor(d, size_rel) ---")
for (e in list(c(1990,1999),c(2000,2009),c(2010,2016),c(2017,2026))) {
  W <- Mr[as.integer(format(Date,"%Y"))>=e[1] & as.integer(format(Date,"%Y"))<=e[2]]
  if (nrow(W)>12) say("  %d-%d  n=%3d  cor=%+.3f", e[1], e[2], nrow(W), cor(W$d, W$size_rel))
}
say("--- 사전 규칙: |cor|>=0.7 통합 유지 · <0.4 통합 철회 ---")
