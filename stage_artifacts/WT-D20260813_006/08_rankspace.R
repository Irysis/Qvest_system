## WT-D20260813_006 / FQ-234 Lane B — 랭크공간 진단
## 왜: rank-IC 는 유의(harvey-t 4.2~4.7)한데 분위 평균·PORT_t 는 0 이다.
##     이 갈림이 (a) 크기(size) 적재의 부산물인지 (b) 평균-소비로 전이 안 되는 랭크 사실인지 판별.
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
RET <- RET[Date %in% vs]; LIQ <- LIQ[Date %in% vs]; P <- P[Date %in% vs]
ELIG <- merge(P[, .(Date,Ticker)], LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8][,.(Date,Ticker)]
ALPHA <- readRDS(file.path(OUT,"alpha_variants.rds"))
WIN <- list(long=as.Date(c("2000-01-01","2026-06-01")), clean=as.Date(c("2015-07-01","2026-06-01")))
in_win <- function(d,w) d>=WIN[[w]][1] & d<WIN[[w]][2]
zc <- function(x){s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) return(rep(NA_real_,length(x))); (x-mean(x,na.rm=TRUE))/s}
wins <- function(x){q<-quantile(x,c(.01,.99),na.rm=TRUE); pmin(pmax(x,q[1]),q[2])}
nwt <- function(x){x<-x[is.finite(x)]; .nw_t_mean(x, lag=3L)}

## 1) 사전등록 통제판본(absorb_neu = vol·size 직교화)의 rank-IC
ic_of <- function(A,w){
  M <- merge(A[in_win(Date,w)], RET, by=c("Date","Ticker"))
  ic <- M[, if(.N>=20 && sd(score)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date]
  ic <- ic[is.finite(ic)]
  list(rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), n=nrow(ic),
       harvey_t=mean(ic$ic)/(sd(ic$ic)/sqrt(nrow(ic))), nw_t=nwt(ic$ic),
       frac_neg=mean(ic$ic<0), sign_test_p=binom.test(sum(ic$ic<0), nrow(ic), 0.5)$p.value)
}
J$rank_ic_by_spec <- list()
for (sp in c("primary","absorb_neu","absorb_share","absorb_1m")) {
  for (w in c("long","clean")) J$rank_ic_by_spec[[paste0(sp,"__",w)]] <- ic_of(ALPHA[[sp]], w)
}

## 2) 랭크공간 FMB — 좌변을 forward 수익의 **횡단면 백분위**로 (꼬리 지배 제거)
fmb_rank <- function(w){
  M <- merge(P[in_win(Date,w), .(Date,Ticker,absorb,win_vol,log_size)], RET, by=c("Date","Ticker"))
  M <- merge(M, ELIG, by=c("Date","Ticker"))
  M <- M[is.finite(absorb)&is.finite(win_vol)&is.finite(log_size)&is.finite(Ret_1m)]
  co <- M[, {
    yr <- (frank(Ret_1m)-0.5)/.N
    a<-zc(wins(absorb)); v<-zc(wins(win_vol)); s<-zc(wins(log_size))
    .(b_uni=as.numeric(coef(lm(yr~a))[2]), b_ctl=as.numeric(coef(lm(yr~a+v+s))[2]),
      b_size=as.numeric(coef(lm(yr~a+v+s))[4]))
  }, by=Date]
  list(n_months=nrow(co),
       uni_mean=mean(co$b_uni), uni_nw_t=nwt(co$b_uni),
       ctl_mean=mean(co$b_ctl), ctl_nw_t=nwt(co$b_ctl),
       size_coef_mean=mean(co$b_size), size_coef_nw_t=nwt(co$b_size),
       survival_ratio=mean(co$b_ctl)/mean(co$b_uni),
       note="좌변 = forward 수익 횡단면 백분위(0~1). 계수 = absorb 1sd 당 백분위 이동.")
}
J$fmb_rankspace <- list()
for (w in c("long","clean")) J$fmb_rankspace[[w]] <- fmb_rank(w)

## 3) 평균 vs 중앙값 갈림의 정량 — 분위별 평균/중앙값 스프레드의 NW-t
mm <- function(w){
  M <- merge(ALPHA$primary[in_win(Date,w)], RET, by=c("Date","Ticker"))
  Q <- M[, { g<-cut(frank(score),breaks=5,labels=FALSE)
             .(sp_mean=mean(Ret_1m[g==5],na.rm=TRUE)-mean(Ret_1m[g==1],na.rm=TRUE),
               sp_med =median(Ret_1m[g==5],na.rm=TRUE)-median(Ret_1m[g==1],na.rm=TRUE)) }, by=Date]
  list(n=nrow(Q), mean_spread_mean=mean(Q$sp_mean), mean_spread_nw_t=nwt(Q$sp_mean),
       median_spread_mean=mean(Q$sp_med), median_spread_nw_t=nwt(Q$sp_med),
       frac_median_spread_neg=mean(Q$sp_med<0),
       note="sp_med = 분위 내 **중앙값** 차. 평균 축과 부호/유의가 갈리면 = 정보가 분포 위치에 있고 평균에 없음")
}
J$mean_vs_median <- list()
for (w in c("long","clean")) J$mean_vs_median[[w]] <- mm(w)

writeLines(jsonlite::toJSON(J, auto_unbox=TRUE, pretty=TRUE, digits=6, null="null"),
           file.path(OUT,"08_rankspace.json"))
cat("[done] 08_rankspace.json\n")
