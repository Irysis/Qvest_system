## NP-156b1 — tier-프로파일 보존 귀무로 1.307 재판정
## NP-156b 의 균등 무작위 귀무는 신호-선택 바스켓의 정확한 귀무가 아니다(선택이 사이즈 구성을 바꿈).
## WT-007 실측: momentum 류 top-25 EW 의 가중 share = MEGA 0.0216 · MID 0.0405 · OTHER 0.938.
## EW 이므로 가중 share ≈ 개수 share ⇒ 25종 중 MEGA ~0.5 · MID ~1 · OTHER ~23.5.
## 이 tier 구성을 보존한 채 종목만 무작위 교체한 귀무를 만든다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[156b1] ",fmt,"\n"),...))
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
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))[Date>=as.Date("2012-12-01") & Date<=as.Date("2026-06-30")]
setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
P[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","OTHER"))]
say("R4 창 %d개월", uniqueN(P$Date))

## 귀무 A: 균등 무작위 (NP-156b 재현)  /  귀무 B: tier 보존 (MEGA 0~1 · MID 1 · OTHER 나머지)
pick <- function(D, matched){
  if (!matched) return(D[sample(.N, min(25L,.N))])
  nm <- if (runif(1) < 0.54) 1L else 0L          # MEGA 기대 0.54종 (0.0216*25)
  ni <- 1L                                       # MID 기대 1.01종 (0.0405*25)
  no <- 25L - nm - ni
  rbind(if (nm>0) D[tier=="MEGA"][sample(.N, min(nm,.N))] else D[0],
        D[tier=="MID"][sample(.N, min(ni,.N))],
        D[tier=="OTHER"][sample(.N, min(no,.N))])
}
draw <- function(seed, matched){ set.seed(seed)
  S <- P[, pick(.SD, matched), by=Date]
  S[, .(diff = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m)), by=Date]$diff }
tA <- sapply(1:60, function(s) nw_t(draw(s, FALSE)))
tB <- sapply(1:60, function(s) nw_t(draw(s, TRUE)))
rep <- function(t, lab){
  say("--- %s (60 draw) ---", lab)
  say("  중앙값 %.3f · 평균 %.3f · sd %.3f · 95%% %.3f", median(t), mean(t), sd(t), quantile(t,.95))
  say("  ★1.307 백분위 = %.1f%%  ·  2.0 도달 %d/60", mean(t <= 1.307)*100, sum(t>=2.0)) }
rep(tA, "귀무 A 균등 무작위")
rep(tB, "귀무 B tier-프로파일 보존")
say("--- 판정 ---")
say("  보존 귀무에서 1.307 백분위 %.1f%% (균등 %.1f%%)", mean(tB<=1.307)*100, mean(tA<=1.307)*100)
say("  → 백분위가 크게 낮아지면 1.307 의 상당분이 tier 구성 산물이고 신호 기여는 축소된다")
