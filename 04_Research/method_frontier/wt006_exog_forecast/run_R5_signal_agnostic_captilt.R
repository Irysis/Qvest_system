# run_R5_signal_agnostic_captilt.R — R5 lane: signal_agnostic_captilt
# ★핵심질문: R4가 발견한 cap-tilt lift(momentum EW 1.277 -> size_prop_cap 2.100, +0.82)가
#   momentum-특유(신호 상호작용)인가, 모든 선택신호 공통(construction default = 순수 mega-beta/벤치-상대 재가중)인가?
#   → 여러 선택신호 각각으로 top-25 선정 후 (a)EW (b)size_prop_cap 둘 다 측정 → Δ=capw-EW 비교.
#   Δ가 신호 불문(random-null 포함) 균일 = SIGNAL_AGNOSTIC(EW->cap-tilt 기본가중 이식 = 최대 소비면).
#   momentum에만 크면 MOMENTUM_SPECIFIC. random-null에도 크면 순수 mega-beta 확증.
# 신호: {momentum, value, quality, low_vol, dividend, size, composite(6-fam EW z평균), random-null(seed고정)}.
#   각 신호 = stock-level family z (Z_Score_Aligned, 높을수록 pick). composite=.FAM score_ew. null=고정seed runif.
# WEIGHT 규칙 = run_R4_bench_aware_weight.R의 size_prop_cap 정확 재사용(cap_w [0,0.20] 반복캡+renorm).
# PIT: Size_t=t관측 slow-moving 비-알파. 신호 z=하네스 PIT. lag1(Size_{t-1}) 스트레스로 누출 점검.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
W6 <- "04_Research/method_frontier/wt006_exog_forecast"
setDTthreads(1)
oos <- .oos_dates

# ---------- run_R4의 size_prop_cap 규칙 정확 복제 ----------
cap_w <- function(w, cap=0.20){
  for(it in 1:200){ over<-w>cap+1e-12; if(!any(over)) break
    ex<-sum(w[over]-cap); w[over]<-cap; und<- w<cap-1e-12 & !over
    if(sum(w[und])<=0){ w<-w/sum(w); break }
    w[und]<-w[und]+ex*w[und]/sum(w[und]) }
  w/sum(w) }
mk_ew           <- function(D){ D[, .(Date,Ticker, w=1/.N), by=Date][, .(Date,Ticker,w)] }
mk_sizeprop_cap <- function(D){ D[, .(Ticker, w=cap_w(size/sum(size))), by=Date][, .(Date,Ticker,w)] }

# ---------- 선택신호별 stock-level score 빌더 ----------
FAM <- copy(.FAM)
set.seed(20260719L)
FAM[, rand_null := runif(.N)]   # 고정 seed random-null score (per-row)
sig_cols <- list(
  momentum  = "momentum",
  value     = "value",
  quality   = "quality",
  low_vol   = "low_vol",
  dividend  = "dividend",
  size      = "size",
  composite = "score_ew",   # 6-family EW z평균 (harness 사전계산)
  random_null = "rand_null"
)

# ---------- top-25 SELECTION (canonical 로직: liq>=2e8, top_n=25 by score) — R4와 동일 절차 ----------
build_SEL <- function(sig_col){
  S <- FAM[!is.na(get(sig_col)) & Date %in% .Rg$Date & Date %in% oos, .(Date,Ticker,score=get(sig_col))]
  S <- merge(S, .LQg[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= 2e8]; S[, adv:=NULL]
  setorder(S, Date, -score)
  SEL <- S[, { n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], score=score[seq_len(n)]) }, by=Date]
  SEL <- merge(SEL, .size_dt, by=c("Date","Ticker"), all.x=TRUE)
  SEL[is.na(size) | size<=0, size := median(SEL$size,na.rm=TRUE)]
  SEL
}

# ---------- 측정 (weighted_screen_bt, contract-grade NW lag-3) ----------
metrics_of <- function(W_dt, label){
  r <- weighted_screen_bt(W_dt, .Rg, .BMg, cost_bps_oneway=15, run_id=paste0("r5_",label), strategy_id=paste0("r5_",label))
  pr <- r$period_returns
  a <- pr$ret_net - pr$benchmark_ret; nn<-length(a); fr<-c(.55,.65,.75)
  sr<-function(x){s<-sd(x); if(!is.finite(s)||s<=0) return(NA); mean(x)/s*sqrt(12)}
  oosr<-median(sapply(fr,function(f){k<-floor(nn*f); if(k<6||nn-k<6) return(NA)
    is<-sr(a[1:k]); oo<-sr(a[(k+1):nn]); if(is.na(is)||is<=0) return(NA); oo/is}), na.rm=TRUE)
  x<-xts(pr$ret_net, order.by=as.Date(pr$date)); ann<-prod(1+coredata(x))^(12/nrow(x))-1
  mdd<-as.numeric(maxDrawdown(x)); cal<-if(is.finite(mdd)&&mdd>0) ann/mdd else NA
  maxw <- max(W_dt[, .(mw=max(w)), by=Date]$mw)
  list(port_t=round(r$portfolio_alpha_t_nw_lag3,3), net_sr=round(r$net_sr,3),
       calmar=round(cal,3), oos_ret=round(oosr,3), turnover=round(r$turnover_annual,2),
       max_w=round(maxw,3), n=r$n_months)
}

cat("[R5] evaluating EW vs size_prop_cap across signals...\n")
rows <- list()
SELcache <- list()
for(sg in names(sig_cols)){
  SEL <- build_SEL(sig_cols[[sg]]); SELcache[[sg]] <- SEL
  W_ew <- mk_ew(SEL); W_cap <- mk_sizeprop_cap(SEL)
  m_ew <- metrics_of(W_ew, paste0(sg,"_ew"))
  m_cap<- metrics_of(W_cap, paste0(sg,"_capw"))
  rows[[sg]] <- data.table(
    signal=sg,
    ew_port_t=m_ew$port_t, capw_port_t=m_cap$port_t,
    delta_lift=round(m_cap$port_t - m_ew$port_t,3),
    ew_net_sr=m_ew$net_sr, capw_net_sr=m_cap$net_sr,
    ew_oos=m_ew$oos_ret, capw_oos=m_cap$oos_ret,
    ew_calmar=m_ew$calmar, capw_calmar=m_cap$calmar,
    capw_maxw=m_cap$max_w, capw_turnover=m_cap$turnover, n=m_cap$n)
  cat(sprintf("  %-12s EW=%.3f  capw=%.3f  Δ=%+.3f\n", sg, m_ew$port_t, m_cap$port_t, m_cap$port_t-m_ew$port_t))
}
res <- rbindlist(rows)
setorder(res, -delta_lift)

# ---------- lag1 PIT 스트레스 (momentum·size·random-null cap-tilt) ----------
lag1_capw_pt <- function(sg){
  SEL <- SELcache[[sg]]
  dts <- sort(unique(SEL$Date)); prevmap <- data.table(Date=dts, pdate=shift(dts,1))
  SL <- merge(SEL, prevmap, by="Date")
  sz_prev <- .size_dt[, .(pdate=Date, Ticker, size_prev=size)]
  SL <- merge(SL, sz_prev, by=c("pdate","Ticker"), all.x=TRUE)
  SL[is.na(size_prev)|size_prev<=0, size_prev := size]
  SEL_lag <- copy(SL); SEL_lag[, size := size_prev]
  W <- mk_sizeprop_cap(SEL_lag)
  weighted_screen_bt(W, .Rg, .BMg, cost_bps_oneway=15, run_id=paste0("r5lag_",sg), strategy_id=paste0("r5lag_",sg))$portfolio_alpha_t_nw_lag3
}
lag1_checks <- list()
for(sg in c("momentum","size","random_null","composite")){
  base_pt <- res[signal==sg, capw_port_t]; l1 <- round(lag1_capw_pt(sg),3)
  lag1_checks[[sg]] <- list(base_capw=base_pt, lag1_capw=l1, leak_suspect=(base_pt > l1 + 0.30))
  cat(sprintf("  [lag1] %-12s capw=%.3f  lag1(Size_t-1)=%.3f  leak=%s\n", sg, base_pt, l1, base_pt>l1+0.30))
}

# ---------- 판정 ----------
# Δ 분산 진단: 신호 불문 균일 여부. random-null Δ가 실신호 Δ에 근접하면 signal-agnostic 강한 증거.
delta_vec <- res$delta_lift; names(delta_vec) <- res$signal
d_null <- res[signal=="random_null", delta_lift]
d_mom  <- res[signal=="momentum", delta_lift]
d_mean <- mean(delta_vec); d_sd <- sd(delta_vec); d_min <- min(delta_vec); d_max <- max(delta_vec)
d_real <- delta_vec[names(delta_vec)!="random_null"]
# 신호 특유성: momentum Δ가 나머지 대비 outlier인가?
mom_is_outlier <- d_mom > mean(delta_vec[names(delta_vec)!="momentum"]) + 1.5*sd(delta_vec[names(delta_vec)!="momentum"])
# random-null도 lift 크면(>0.4) mega-beta 확증
null_lifts <- d_null > 0.40

verdict <- if(mom_is_outlier && !null_lifts){
  "MOMENTUM_SPECIFIC: cap-tilt lift가 momentum에 유의 집중(random-null·타 신호는 소폭) — 신호 상호작용"
} else if(null_lifts && (max(delta_vec)-min(delta_vec) < 0.8)){
  "SIGNAL_AGNOSTIC: cap-tilt lift가 random-null 포함 신호 불문 발생(Δ 균일) — EW->size_prop_cap은 construction default(순수 mega-beta/벤치-상대 재가중). 최대 소비면=optimizer/RAMP/book 기본가중 이식"
} else if(null_lifts){
  "SIGNAL_AGNOSTIC_PARTIAL: random-null에도 상당 lift(mega-beta 성분 지배) but Δ 편차 존재 — construction default가 주효과, 신호별 잔차 상호작용 부차"
} else {
  "MIXED: null lift 작고 실신호 lift 산재 — 순수 mega-beta도 순수 signal-specific도 아님(신호별 cap-분포 상호작용)"
}

summary <- list(
  lane="R5 signal_agnostic_captilt", date=as.character(Sys.Date()),
  question="cap-tilt lift가 momentum-특유인가 모든 신호 공통(mega-beta construction default)인가",
  weight_rule="run_R4 size_prop_cap (Size 비례 후 cap_w [0,0.20] 반복캡+renorm) 정확 재사용",
  n_signals=nrow(res), n_months=res$n[1],
  delta_stats=list(mean=round(d_mean,3), sd=round(d_sd,3), min=round(d_min,3), max=round(d_max,3),
                   momentum=d_mom, random_null=d_null, real_signal_mean=round(mean(d_real),3)),
  mom_is_outlier=mom_is_outlier, null_lifts=null_lifts,
  results=res, lag1_checks=lag1_checks, verdict=verdict)
write_json(summary, file.path(W6,"R5_signal_agnostic_captilt_summary.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
fwrite(res, file.path(W6,"R5_signal_agnostic_captilt_results.csv"))

cat("\n===== R5 signal_agnostic_captilt RESULTS (Δ=capw-EW port_t) =====\n")
print(res[, .(signal, ew_port_t, capw_port_t, delta_lift, capw_net_sr, capw_oos, capw_maxw)])
cat(sprintf("\n[R5] Δ stats: mean=%.3f sd=%.3f  [null=%.3f, momentum=%.3f]  real_mean=%.3f\n",
            d_mean, d_sd, d_null, d_mom, mean(d_real)))
cat("[R5] VERDICT:", verdict, "\n[R5] done.\n")
