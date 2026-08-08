## NP-b2b3a — 111-145 에 3중 검정 적용 (고립성 · 시대재현 · 이웃구별) + 단조축 국소 통제
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[b3a] ",fmt,"\n"),...))
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

bd <- function(D, lo, hi){ W <- D[rk>=lo & rk<=hi]
  if (nrow(W)<50) return(NULL)
  list(e=mean(W$excess)*12, t=mean(W$excess)/sd(W$excess)*sqrt(nrow(W)), n=nrow(W)) }

say("=== 검정 1: 슬라이딩 고립성 (35-폭, 90~200) ===")
S <- rbindlist(lapply(seq(90,200,by=5), function(s){
  b <- bd(P,s,s+34); if (is.null(b)) NULL else
  data.table(band=paste0(s,"-",s+34), e=round(b$e,4), t=round(b$t,2))}))
print(S)

say("=== 검정 2: 시대 재현 (111-145) ===")
eras <- list(c("1990-01-01","1999-12-31","1990s"), c("2000-01-01","2009-12-31","2000s"),
             c("2010-01-01","2016-12-31","2010-16"), c("2017-01-01","2026-07-31","2017+"))
for (e in eras){ D <- P[Date>=as.Date(e[1]) & Date<=as.Date(e[2])]
  b <- bd(D,111,145)
  if (is.null(b)) { say("  %-8s 표본 부족", e[3]); next }
  say("  %-8s  %+.4f (t %+.2f · n %d)", e[3], b$e, b$t, b$n) }

say("=== 검정 3 + 단조축 국소 통제: 국소 이웃(±50) 대비 ===")
loc <- function(D, lo, hi, pad=50){
  W <- D[rk>=lo & rk<=hi]
  N <- D[(rk>=lo-pad & rk<lo) | (rk>hi & rk<=hi+pad)]
  if (nrow(W)<50 || nrow(N)<50) return(NULL)
  diff <- mean(W$excess) - mean(N$excess)
  se <- sqrt(var(W$excess)/nrow(W) + var(N$excess)/nrow(N))
  list(d=diff*12, t=diff/se) }
for (lab in list(c("111","145"), c("31","60"))) {
  lo <- as.integer(lab[1]); hi <- as.integer(lab[2])
  g <- loc(P, lo, hi)
  say("  전 구간 %s-%s : 국소 이웃 대비 %+.4f (t %+.2f)  [유니버스 대비 %+.4f]",
      lo, hi, g$d, g$t, bd(P,lo,hi)$e)
  for (e in eras){ D <- P[Date>=as.Date(e[1]) & Date<=as.Date(e[2])]; g2 <- loc(D,lo,hi)
    if (!is.null(g2)) say("      %-8s %+.4f (t %+.2f)", e[3], g2$d, g2$t) }
}
