## NP-b3a1 — 감시 4게이트가 같은 축인가: 벤치핸디캡 d · 사이즈효과 · 111-145 밴드 시계열 상관
## 같으면 bench_handicap_watch 하나로 통합, 다르면 별도 감시가 필요하다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
say <- function(fmt,...) cat(sprintf(paste0("[b3a1] ",fmt,"\n"),...))
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
P[, uni_ew := mean(Ret_1m), by=Date]; P[, excess := Ret_1m - uni_ew]

## 3개 월별 계열
M <- P[, .(
  d        = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m),          # 벤치 핸디캡
  size_eff = mean(excess[rk>300]) - mean(excess[rk<=10]),        # 소형−대형 (사이즈 효과)
  band     = mean(excess[rk>=111 & rk<=145])                     # 111-145 밴드
), by=Date][order(Date)]
M <- M[is.finite(d) & is.finite(size_eff) & is.finite(band)]
say("월 관측 %d (%s ~ %s)", nrow(M), min(M$Date), max(M$Date))

say("--- 월별 상관 ---")
say("  cor(d, size_eff) = %+.3f", cor(M$d, M$size_eff))
say("  cor(d, band)     = %+.3f", cor(M$d, M$band))
say("  cor(size_eff, band) = %+.3f", cor(M$size_eff, M$band))

## 6개월 롤링으로도 (감시가 롤링 기준이므로)
roll <- function(x,k=6) sapply(k:length(x), function(i) mean(x[(i-k+1):i]))
R <- data.table(Date=M$Date[6:nrow(M)], d=roll(M$d), size_eff=roll(M$size_eff), band=roll(M$band))
say("--- 6개월 롤링 상관 (감시 기준 단위) ---")
say("  cor(d, size_eff) = %+.3f", cor(R$d, R$size_eff))
say("  cor(d, band)     = %+.3f", cor(R$d, R$band))
say("  cor(size_eff, band) = %+.3f", cor(R$size_eff, R$band))

say("--- 시대별 cor(d, size_eff) ---")
for (e in list(c(1990,1999),c(2000,2009),c(2010,2016),c(2017,2026))) {
  W <- R[as.integer(format(Date,"%Y"))>=e[1] & as.integer(format(Date,"%Y"))<=e[2]]
  say("  %d-%d  n=%3d  cor=%+.3f", e[1], e[2], nrow(W), cor(W$d, W$size_eff))
}
say("--- 판정 보조: |cor|>=0.7 이면 통합, <0.4 면 별도 감시 필요 ---")
