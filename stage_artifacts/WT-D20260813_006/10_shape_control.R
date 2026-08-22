## WT-D20260813_006 / FQ-234 — 분포 형상의 vol-독립성 검증 (자기 적대검증 2차)
## 제기: absorb 분위별 형상 단조성은 그냥 "Q1 이 고변동"인 것 아닌가.
## 검사: ①vol·size 직교화 잔차(absorb_neu) 분위로 형상 재산출 ②vol 3분위 **내부** 형상
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
J <- list()
P <- as.data.table(read_parquet(file.path(OUT,"absorb_panel.parquet"))); P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT,"fwd.rds"))
RET <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
LIQ <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]
vs <- sort(unique(RET$Date)); vs <- vs[vs < as.Date("2026-06-01")]
ALPHA <- readRDS(file.path(OUT,"alpha_variants.rds"))
## absorb_neu score = z(잔차 of -absorb) => absorb_neu 방향으로 되돌리려면 부호 반전
NEU <- ALPHA$absorb_neu[Date %in% vs][, .(Date, Ticker, absorb_neu = -score)]
X <- merge(P[Date %in% vs, .(Date,Ticker,absorb,win_vol,log_size)], NEU, by=c("Date","Ticker"))
X <- merge(X, LIQ[Date %in% vs], by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
X <- merge(X, RET[Date %in% vs], by=c("Date","Ticker"))
X <- X[is.finite(absorb)&is.finite(absorb_neu)&is.finite(win_vol)&is.finite(Ret_1m)]
WIN <- list(long=as.Date(c("2000-01-01","2026-06-01")), clean=as.Date(c("2015-07-01","2026-06-01")))
nwt <- function(x){x<-x[is.finite(x)]; .nw_t_mean(x, lag=3L)}

shape_tbl <- function(s, keyvar) {
  s <- copy(s)
  s[, g := cut(frank(get(keyvar)), breaks=5, labels=FALSE), by=Date]
  s[, ex := Ret_1m - mean(Ret_1m), by=Date]
  o <- s[, .(mean=mean(ex), median=median(ex), p90=quantile(ex,.90), p10=quantile(ex,.10),
             up20=mean(ex>0.20), dn20=mean(ex< -0.20),
             skew=mean((ex-mean(ex))^3)/(sd(ex)^3), sd=sd(ex), n=.N), by=g][order(g)]
  as.list(as.data.frame(round(o, 6)))
}

## ① absorb_neu(vol·size 직교) 분위 형상
J$shape_by_absorb_neu <- list()
for (w in names(WIN)) J$shape_by_absorb_neu[[w]] <-
  shape_tbl(X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]], "absorb_neu")

## ② vol 3분위 **내부** absorb 분위 형상 (long 창)
J$shape_within_vol_tercile <- list()
s <- X[Date>=WIN$long[1] & Date<WIN$long[2]]
s[, vt := cut(frank(win_vol), breaks=3, labels=FALSE), by=Date]
for (k in 1:3) J$shape_within_vol_tercile[[paste0("vol_tercile_", k)]] <- shape_tbl(s[vt==k], "absorb")

## ③ 월별 중앙값 스프레드(Q5-Q1) 의 NW-t — absorb_neu 기준
med_sp <- function(w, keyvar) {
  s <- X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]]
  s <- copy(s)[, g := cut(frank(get(keyvar)), breaks=5, labels=FALSE), by=Date]
  s[, ex := Ret_1m - mean(Ret_1m), by=Date]
  q <- s[, .(med=median(ex[g==5])-median(ex[g==1]), mn=mean(ex[g==5])-mean(ex[g==1]),
             up=mean(ex[g==5]>0.20)-mean(ex[g==1]>0.20)), by=Date]
  list(n=nrow(q), median_spread=mean(q$med), median_spread_nw_t=nwt(q$med),
       mean_spread=mean(q$mn), mean_spread_nw_t=nwt(q$mn),
       uptail_prob_diff=mean(q$up), uptail_prob_diff_nw_t=nwt(q$up))
}
J$median_spread_neu <- list()
for (w in names(WIN)) {
  J$median_spread_neu[[paste0(w,"__absorb")]]     <- med_sp(w, "absorb")
  J$median_spread_neu[[paste0(w,"__absorb_neu")]] <- med_sp(w, "absorb_neu")
}

writeLines(jsonlite::toJSON(J, auto_unbox=TRUE, pretty=TRUE, digits=6, null="null"),
           file.path(OUT,"10_shape_control.json"))
cat("[done] 10_shape_control.json\n")
