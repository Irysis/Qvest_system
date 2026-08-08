## NP-156b1b — 2.0 도달에 필요한 신호강도 외삽: (신호강도, cap-tilt 증분) 관계
## WT-007 main arm 들은 port_t 스펙트럼을 갖는다. 각 arm 의 top-25 선택 위에서
## (시총가중 − 동일가중) 증분 t 를 재고 신호강도와의 관계를 본다.
## 신호가 강할수록 증분이 커지면 2.0 도달 필요 강도를 외삽할 수 있고, 무관하면 레인 처분.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
W007 <- file.path(ROOT,"stage_artifacts/WT_D20260803_007")
say <- function(fmt,...) cat(sprintf(paste0("[b1b] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x <- x[is.finite(x)]; n <- length(x); if (n<20) return(NA_real_)
  m <- mean(x); e <- x-m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag){ gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(lag+1))*gl }
  m/sqrt(s/n) }
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
SZ  <- RAWME[!is.na(Size) & Size>0, .(Date,Ticker,Size)]

MAINP <- as.data.table(read_parquet(file.path(W007,"composite_main.parquet")))
MAINP[, Date := as.Date(Date)]
V <- fromJSON(file.path(W007,"alpha_validation.json"))
arms_tbl <- as.data.table(V$arms)

inc_of <- function(a){
  S <- MAINP[arm==a & !is.na(score)]
  setorder(S, Date, -score)
  T25 <- S[, head(.SD, 25L), by=Date, .SDcols=c("Ticker","score")]
  M <- merge(merge(T25, ret, by=c("Date","Ticker")), SZ, by=c("Date","Ticker"))
  if (!nrow(M)) return(NA_real_)
  D <- M[, .(diff = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m), n=.N), by=Date][n>=20]
  nw_t(D$diff)
}
arms <- sort(unique(MAINP$arm))
R <- rbindlist(lapply(arms, function(a){
  pt <- arms_tbl[arm==a, port_t]; ew <- arms_tbl[arm==a, ew_port_t]
  data.table(arm=a, port_t=if(length(pt)) pt[1] else NA_real_,
             ew_port_t=if(length(ew)) ew[1] else NA_real_, captilt_inc=inc_of(a))}))
R <- R[is.finite(captilt_inc)]
setorder(R, -port_t)
say("--- arm 별 (신호강도, cap-tilt 증분 t) ---")
print(R[, .(arm, port_t=round(port_t,3), ew_port_t=round(ew_port_t,3), captilt_inc=round(captilt_inc,3))])
say("--- 관계 ---")
say("  cor(port_t, captilt_inc)    = %+.3f", cor(R$port_t, R$captilt_inc, use="complete.obs"))
say("  cor(ew_port_t, captilt_inc) = %+.3f", cor(R$ew_port_t, R$captilt_inc, use="complete.obs"))
fit <- lm(captilt_inc ~ port_t, data=R)
b <- coef(fit); say("  적합 captilt_inc = %+.3f %+.3f * port_t  (R2 %.3f)", b[1], b[2], summary(fit)$r.squared)
if (is.finite(b[2]) && abs(b[2])>1e-6) {
  need <- (2.0 - b[1])/b[2]
  say("  ★증분 2.0 도달에 필요한 port_t = %.2f  (관측 최대 %.2f)", need, max(R$port_t, na.rm=TRUE))
  say("  → 필요 강도가 관측 범위 밖이면 비중-측 레인 처분")
}
