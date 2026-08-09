# c2_untested_axes.R — 완전성 렌즈 2차
#  T4 F1/F4 사전 킬 규칙의 검정력 (라운드 자신의 계약으로 재판정)
#  T5 canonical PORT_t 단조개선(2.050->2.381)에 플라시보가 없다 — 직접 만든다
#  T6 C6 생존편의 census
# READ-ONLY.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
say <- function(f, ...) cat(sprintf(paste0("[C2] ", f, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")

nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  fit<-lm(x~1); as.numeric(lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]) }

TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
say("INPUT RAWDATA rows=%d dates=%d (DAILY)", nrow(RAW), uniqueN(RAW$Date))
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)

# ---------- T6: 생존편의 census (universe 이탈 = 상폐 인식되는가) ----------
lastseen <- RAW[, .(last_date=max(Date), first_date=min(Date)), by=Ticker]
inuniv <- RAW[(K200==TRUE|KQ150==TRUE), .(u_last=max(Date)), by=Ticker]
LS <- merge(lastseen, inuniv, by="Ticker")
panel_end <- max(RAW$Date)
gone <- LS[last_date < panel_end - 60]
say("T6 RAWDATA 전체 티커 %d · 유니버스 소속 이력 티커 %d", uniqueN(RAW$Ticker), nrow(LS))
say("T6 패널 종료 60일 이전에 사라진(=상폐/이관) 유니버스 티커 %d건 (%.1f%%)",
    nrow(gone), 100*nrow(gone)/nrow(LS))
say("T6 그중 사라지기 직전까지 유니버스 소속이던 티커 %d건",
    nrow(gone[u_last >= last_date - 40]))
rm(lastseen, inuniv, LS); gc(verbose=FALSE)

RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
SIG <- sort(unique(TUNED$Date)); sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date=as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date=as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/size_panel.parquet"))
size_dt[, Date := as.Date(Date)]

W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
           Date+Ticker ~ Factor_Name, value.var="score")
W <- merge(W, UNIV, by=c("Date","Ticker"))
W <- merge(W, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
W <- W[is.na(adv) | adv >= 2e8]
W <- merge(W, returns_dt, by=c("Date","Ticker"), all.x=TRUE)
W <- merge(W, bench_dt, by="Date", all.x=TRUE)
W[, act := Ret_1m - BM_Ret]
ELIG <- W[is.finite(M01_PATHQ)]
ELIG[, rk_m01 := frank(-M01_PATHQ, ties.method="first"), by=Date]
say("ELIG rows=%d 월=%d", nrow(ELIG), uniqueN(ELIG$Date))

# ---------- T4: F4 킬스위치 / F1 기각 규칙의 검정력 ----------
say("── T4 F4 킬스위치(밴드 rank20~40 기울기<=0 → 측정 전 기각) 재현 + 검정력 ──")
for (f in c("D03_EWMA","Q01_EB")) {
  D <- ELIG[rk_m01>=20 & rk_m01<=40 & is.finite(get(f)) & is.finite(act)]
  D[, xz := { s<-sd(get(f)); if(!is.finite(s)||s<=0) NA_real_ else (get(f)-mean(get(f)))/s }, by=Date]
  sl <- D[is.finite(xz), { if(.N<8L) .(b=NA_real_) else .(b=as.numeric(coef(lm(act~xz))[2])) }, by=Date]
  b <- sl$b[is.finite(sl$b)]
  tt <- nw_t(b)
  v <- verdict_with_power(observed_t=tt, observed_monthly=mean(b), n=length(b),
                          sd_monthly=sd(b), design="full")
  req <- required_effect(n=length(b), sd_monthly=sd(b))
  reqp <- 100*req$required_annual
  say("  %s  기울기 연 %+.3f%%  NW t=%+.3f  n월=%d | 필요효과 연 %.2f%% | 관측/필요 %.2f | 라벨 %s",
      f, 100*12*mean(b), tt, length(b), reqp, abs(100*12*mean(b))/reqp, v$verdict)
  # 사전등록 바(placebo sd 0.0256/0.01727) 기준으로도
  sdpre <- if (f=="D03_EWMA") 0.02560 else 0.01727
  req2 <- required_effect(n=length(b), sd_monthly=sdpre)
  say("     사전등록 sd 기준 필요효과 연 %.2f%% → 관측/필요 %.2f",
      100*req2$required_annual, abs(100*12*mean(b))/(100*req2$required_annual))
}
say("── T4b F1 기각 규칙(D03 Q1-Q3 t > -1 이면 좌측국소화 REJECT) ──")
for (f in c("D03_EWMA","Q01_EB")) {
  D <- ELIG[is.finite(get(f)) & is.finite(act)]
  D[, qq := { v<-get(f); cut(frank(v), breaks=quantile(frank(v), probs=seq(0,1,.2)),
      include.lowest=TRUE, labels=FALSE) }, by=Date]
  qm <- D[, .(m=mean(act)), by=.(Date,qq)]
  w <- dcast(qm, Date ~ qq, value.var="m")
  d13 <- w[["1"]] - w[["3"]]; d53 <- w[["5"]] - w[["3"]]
  v13 <- verdict_with_power(observed_t=nw_t(d13), observed_monthly=mean(d13,na.rm=TRUE),
                            n=sum(is.finite(d13)), sd_monthly=sd(d13,na.rm=TRUE), design="full")
  say("  %s Q1-Q3 연 %+.2f%% t=%+.2f 라벨=%s | Q5-Q3 연 %+.2f%% t=%+.2f",
      f, 100*12*mean(d13,na.rm=TRUE), nw_t(d13), v13$verdict,
      100*12*mean(d53,na.rm=TRUE), nw_t(d53))
}

# ---------- T5: canonical PORT_t 단조개선의 플라시보 ----------
say("── T5 canonical PORT_t: base -> Q01_q20 개선(2.050->2.381)에 무작위 제외 대조 ──")
score_base <- ELIG[, .(Date, Ticker, score=M01_PATHQ)]
run_w1 <- function(ex, tag) {
  sc <- if (is.null(ex)) score_base else
    score_base[!ELIG[ex, on=.(Date,Ticker), .(Date,Ticker)], on=.(Date,Ticker)]
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
    liq_dt=liq_dt, liq_min=2e8, run_id="COMPLETENESS_LENS",
    strategy_id=paste0("CL_", tag), diag_dual_basis=FALSE, size_dt=size_dt)
}
excl_set <- function(f, q) {
  D <- ELIG[is.finite(get(f))]
  D[, thr := quantile(get(f), q, type=7, na.rm=TRUE), by=Date]
  D[get(f) <= thr, .(Date,Ticker)]
}
rb <- run_w1(NULL, "base")
say("  base PORT_t=%+.3f", rb$portfolio_alpha_t_nw_lag3)
eq <- excl_set("Q01_EB", 0.20)
rq <- run_w1(eq, "q01_q20")
say("  Q01_q20 PORT_t=%+.3f (재현 확인)", rq$portfolio_alpha_t_nw_lag3)
# 무작위 제외: 동월 동개수, ELIG 전체에서 (Q01 가용 여부 무관)
cnt <- eq[, .(k=.N), by=Date]
POOL <- merge(ELIG[, .(Date, Ticker)], cnt, by="Date")
say("  월별 제외 개수 k: 평균 %.1f 중앙 %d (ELIG 월평균 %.1f 대비 %.1f%%)",
    mean(cnt$k), as.integer(median(cnt$k)), nrow(ELIG)/uniqueN(ELIG$Date),
    100*mean(cnt$k)/(nrow(ELIG)/uniqueN(ELIG$Date)))
set.seed(20260809L); pt <- numeric(0); NSEED <- 12L
for (s in seq_len(NSEED)) {
  ex <- POOL[, .(Ticker=sample(Ticker, min(k[1], .N-30L))), by=Date]
  r <- run_w1(ex[, .(Date, Ticker)], paste0("plc", s))
  pt <- c(pt, r$portfolio_alpha_t_nw_lag3)
  say("  placebo seed %02d PORT_t=%+.3f", s, r$portfolio_alpha_t_nw_lag3)
}
say("  PLACEBO PORT_t: mean %+.3f sd %.3f range [%+.3f, %+.3f] | real Q01_q20 %+.3f | 우측 p=%.3f",
    mean(pt), sd(pt), min(pt), max(pt), rq$portfolio_alpha_t_nw_lag3,
    mean(pt >= rq$portfolio_alpha_t_nw_lag3))
say("  base 대비 개선분: real %+.3f vs placebo 평균 %+.3f",
    rq$portfolio_alpha_t_nw_lag3 - rb$portfolio_alpha_t_nw_lag3,
    mean(pt) - rb$portfolio_alpha_t_nw_lag3)
saveRDS(list(pt=pt, base=rb$portfolio_alpha_t_nw_lag3, real=rq$portfolio_alpha_t_nw_lag3),
        "stage_artifacts/wt001_verify/comp/c2.rds")
say("완료")
