## FQ-068 R2 — 설계 전환: 섹터 타이밍(저검정력) → **횡단면 PPI-베타 팩터**
## 가설: 반도체 PPI 에 민감한 종목은 PPI 상승 국면에서 초과수익을 낸다.
##   신호 = PPI-베타(과거 36개월 회귀) × 현재 PPI 모멘텀 부호  → 횡단면 랭킹
## PIT: PPI 는 참조월 M-2 까지만(발표지연 실측), 베타 추정도 그 시점 정보로만.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[R2] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }; m/sqrt(s/n) }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector_Lv2")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))
P[, ym := format(Date,"%Y-%m")]

## PPI 월간 변화율 (참조월 기준) → PIT 이동은 아래 신호 결합에서
ppi <- as.data.table(read_parquet(file.path(OUT,"fq068_ppi_raw.parquet")))
ppi <- ppi[Series_ID=="PCU334413334413"][order(Date)]
ppi[, `:=`(dppi = Value/shift(Value,1)-1, mom6 = Value/shift(Value,6)-1)]
ppi[, ref_ym := format(Date,"%Y-%m")]

## --- 종목별 PPI-베타: 과거 36개월 수익 ~ 동기 PPI 변화 회귀 (rolling, PIT: 신호월까지)
## 신호월 t 에서 쓰는 PPI 는 참조월 t-2 까지 ⇒ 회귀 표본도 그 범위
R <- merge(P[, .(ym, Ticker, Ret_1m, Date, Size)],
           ppi[, .(ref_ym, dppi)], by.x="ym", by.y="ref_ym")
setorder(R, Ticker, ym)
W <- 36L
R[, beta_ppi := {
  n <- .N; out <- rep(NA_real_, n)
  if (n >= W) for (i in W:n) {
    idx <- (i-W+1):i
    y <- Ret_1m[idx]; x <- dppi[idx]
    if (sum(is.finite(y) & is.finite(x)) >= 24 && sd(x, na.rm=TRUE) > 0)
      out[i] <- cov(y, x, use="complete.obs")/var(x, use="complete.obs")
  }
  out
}, by=Ticker]
say("베타 추정 완료 — 유효 %d / %d 종목-월", sum(is.finite(R$beta_ppi)), nrow(R))

## --- 신호: beta_ppi(신호월까지 추정) × PPI mom6(참조월 M-2, PIT)
ppi[, hold_ym := format(Date %m+% months(2), "%Y-%m")]
sig <- merge(R[, .(ym, Ticker, beta_ppi, Ret_1m, Size)],
             ppi[, .(hold_ym, mom6_pit=mom6)], by.x="ym", by.y="hold_ym")
sig <- sig[is.finite(beta_ppi) & is.finite(mom6_pit) & is.finite(Ret_1m)]
sig[, score := beta_ppi * sign(mom6_pit)]
say("신호 패널 %d개월 · %d 종목-월", uniqueN(sig$ym), nrow(sig))

## --- 횡단면 rank IC
ic <- sig[, .(ic = suppressWarnings(cor(score, Ret_1m, method="spearman", use="complete.obs")),
              n = .N), by=ym][n >= 30 & is.finite(ic)][order(ym)]
say("--- 횡단면 rank IC (신호 = PPI베타 × PPI모멘텀 부호) ---")
say("  월수 %d · 평균 IC %+.4f · sd %.4f · IC>0 비율 %.1f%%",
    nrow(ic), mean(ic$ic), sd(ic$ic), mean(ic$ic>0)*100)
say("  t(단순) %.2f · t_NW(lag3) %.2f · ICIR %.3f",
    mean(ic$ic)/sd(ic$ic)*sqrt(nrow(ic)), nw_t(ic$ic), mean(ic$ic)/sd(ic$ic))

## 대조: 베타 단독(모멘텀 부호 없이)
sig[, score_raw := beta_ppi]
ic2 <- sig[, .(ic = suppressWarnings(cor(score_raw, Ret_1m, method="spearman", use="complete.obs")), n=.N),
           by=ym][n>=30 & is.finite(ic)]
say("--- 대조: 베타 단독 ---")
say("  평균 IC %+.4f · t_NW %.2f", mean(ic2$ic), nw_t(ic2$ic))
fwrite(ic, file.path(OUT,"fq068_r2_ic.csv")); say("저장 완료")
