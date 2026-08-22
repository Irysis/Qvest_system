## WT-D20260813_006 / FQ-234 — 자기 적대검증 실측 축
## 제기: absorb 는 창 내 하락일 수·과거수익과 기계적으로 얽힌다. 랭크공간 결과가
##       (a) 과거수익(반전/모멘텀)의 재포장인지 (b) 독립 재료인지.
## 통제 추가: 과거 3M 수익(창과 동일 구간) · 창 내 하락일 비율 · 회전율(거래대금/시총)
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

## 과거 3M 수익 = 월말 종가비 (RAWDATA stored Close — Ret 재계산 아님, 레벨 비)
RAW <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
        col_select=c("Date","Ticker","Close")))
RAW[, Date := as.Date(Date)]
ME <- sort(unique(P$Date))
CL <- RAW[Date %in% ME, .(Date, Ticker, Close)]
setorder(CL, Ticker, Date)
CL[, Close_3m := shift(Close, 3L), by = Ticker]
CL[, midx := match(Date, ME)]
CL[, midx_3m := shift(midx, 3L), by = Ticker]
CL <- CL[is.finite(Close) & is.finite(Close_3m) & Close_3m > 0 & (midx - midx_3m) == 3L]
CL[, past3m := Close/Close_3m - 1]
rm(RAW); invisible(gc())

X <- merge(P[Date %in% vs, .(Date,Ticker,absorb,win_vol,log_size,Size)], CL[, .(Date,Ticker,past3m)],
           by=c("Date","Ticker"))
X <- merge(X, LIQ[Date %in% vs], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
X[, turn := adv / Size]
X <- merge(X, RET[Date %in% vs], by=c("Date","Ticker"))
X <- X[is.finite(absorb)&is.finite(win_vol)&is.finite(log_size)&is.finite(past3m)&is.finite(Ret_1m)]
J$n_rows <- nrow(X); J$n_months <- uniqueN(X$Date)

zc <- function(x){s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) rep(NA_real_,length(x)) else (x-mean(x,na.rm=TRUE))/s}
wins <- function(x){q<-quantile(x,c(.01,.99),na.rm=TRUE); pmin(pmax(x,q[1]),q[2])}
nwt <- function(x){x<-x[is.finite(x)]; .nw_t_mean(x, lag=3L)}
WIN <- list(long=as.Date(c("2000-01-01","2026-06-01")), clean=as.Date(c("2015-07-01","2026-06-01")))

## 1) absorb 와 과거수익의 횡단면 상관 (기계적 얽힘의 크기)
J$absorb_vs_past3m <- list()
for (w in names(WIN)) {
  s <- X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]]
  cc <- s[, .(c = cor(absorb, past3m, method="spearman")), by=Date]
  J$absorb_vs_past3m[[w]] <- list(mean_spearman=mean(cc$c), sd=sd(cc$c),
                                  min=min(cc$c), max=max(cc$c), n=nrow(cc))
}

## 2) 랭크공간 FMB — 통제 계단식
step_fmb <- function(w){
  s <- X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]]
  co <- s[, {
    yr <- (frank(Ret_1m)-0.5)/.N
    a<-zc(wins(absorb)); v<-zc(wins(win_vol)); sz<-zc(wins(log_size))
    p<-zc(wins(past3m)); tu<-zc(wins(ifelse(is.finite(turn),turn,NA_real_)))
    tu[!is.finite(tu)] <- 0
    m1<-lm(yr~a); m2<-lm(yr~a+v+sz); m3<-lm(yr~a+v+sz+p); m4<-lm(yr~a+v+sz+p+tu)
    .(b1=coef(m1)[2], b2=coef(m2)[2], b3=coef(m3)[2], b4=coef(m4)[2],
      bp=coef(m3)[5])
  }, by=Date]
  list(n_months=nrow(co),
       m1_absorb_only  = list(mean=mean(co$b1), nw_t=nwt(co$b1)),
       m2_plus_vol_size= list(mean=mean(co$b2), nw_t=nwt(co$b2)),
       m3_plus_past3m  = list(mean=mean(co$b3), nw_t=nwt(co$b3)),
       m4_plus_turnover= list(mean=mean(co$b4), nw_t=nwt(co$b4)),
       past3m_own_coef = list(mean=mean(co$bp), nw_t=nwt(co$bp)),
       survival_m4_over_m1 = mean(co$b4)/mean(co$b1))
}
J$stepwise_rank_fmb <- list()
for (w in names(WIN)) J$stepwise_rank_fmb[[w]] <- step_fmb(w)

## 3) 같은 계단을 **평균공간**(레벨 수익)으로 — 두 공간의 갈림 확인
step_fmb_lvl <- function(w){
  s <- X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]]
  co <- s[, {
    a<-zc(wins(absorb)); v<-zc(wins(win_vol)); sz<-zc(wins(log_size)); p<-zc(wins(past3m))
    .(b1=coef(lm(Ret_1m~a))[2], b3=coef(lm(Ret_1m~a+v+sz+p))[2])
  }, by=Date]
  list(n_months=nrow(co), m1=list(mean=mean(co$b1), nw_t=nwt(co$b1)),
       m3=list(mean=mean(co$b3), nw_t=nwt(co$b3)))
}
J$stepwise_level_fmb <- list()
for (w in names(WIN)) J$stepwise_level_fmb[[w]] <- step_fmb_lvl(w)

## 4) 분포 형상 직접 관측 — absorb 분위별 forward 수익의 중앙값/평균/왜도/우측꼬리
shape <- function(w){
  s <- X[Date>=WIN[[w]][1] & Date<WIN[[w]][2]]
  s[, g := cut(frank(absorb), breaks=5, labels=FALSE), by=Date]
  s[, ex := Ret_1m - mean(Ret_1m), by=Date]     # 월별 횡단면 demean (시장성분 제거)
  out <- s[, .(mean=mean(ex), median=median(ex),
               p90=quantile(ex,.90), p10=quantile(ex,.10),
               frac_gt_20pct=mean(ex>0.20), frac_lt_m20pct=mean(ex< -0.20),
               skew=mean((ex-mean(ex))^3)/(sd(ex)^3), n=.N), by=g][order(g)]
  as.list(as.data.frame(out))
}
J$distribution_shape_by_absorb_quintile <- list()
for (w in names(WIN)) J$distribution_shape_by_absorb_quintile[[w]] <- shape(w)

writeLines(jsonlite::toJSON(J, auto_unbox=TRUE, pretty=TRUE, digits=6, null="null"),
           file.path(OUT,"09_adversarial.json"))
cat("[done] 09_adversarial.json\n")
