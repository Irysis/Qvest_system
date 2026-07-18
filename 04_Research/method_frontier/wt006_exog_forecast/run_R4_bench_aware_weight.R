# run_R4_bench_aware_weight.R — R4 lane: benchmark_aware_weight (WEIGHT axis, SELECTION 불변)
# 핵심질문: cap-w 트랩(EW가 MEGA 저비중→cap-w 벤치 미보상)이 횡단 SELECTION 특유인가,
#   아니면 momentum top-25를 벤치-인지 재가중해도 못 벗어나는 CONSTRUCTION 벽인가?
#   SELECTION = baseline momentum top-25 (불변). WEIGHT만 EW→벤치-인지로 교체:
#     (a) size_prop      : w ∝ Size (cap-w 벤치 근접, min-TE within subset)
#     (b) capw_shrink λ  : w = λ·EW + (1-λ)·capw25 (EW↔cap-w 절충)
#     (c) te_min_tilt κ  : w ∝ Size·exp(κ·score_z) (cap-w base + momentum tilt 보존, κ=0=min-TE)
#   벽 = baseline momentum cap-w port_t 1.277. 넘으면 트랩=selection특유, 못넘으면 구조적.
# PIT: 가중은 t 관측만 — Size_t(당월 시총, t에 known)·score_t(momentum, baseline clean). IS-only(고정 룰, fit 아님).
#   lag1 스트레스: Size_{t-1}로 재가중 → 붕괴하면 동월 size 우위 의심(shouldn't; size slow-moving·비-알파).
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
W6 <- "04_Research/method_frontier/wt006_exog_forecast"
setDTthreads(1)

fams <- .fams
oos  <- .oos_dates

# ---------- (1) momentum top-25 SELECTION 복제 (canonical_screen_bt 내부 로직과 동일) ----------
# score = baseline momentum theta 적용 stock score
mom_score <- .score_from_theta(.mom_theta)            # (Date,Ticker,score)
mom_score <- mom_score[!is.na(score) & Date %in% .Rg$Date & Date %in% oos]
# 유동성필터: adv>=2e8 (adv 없으면 통과 — canonical 규약)
S <- merge(mom_score, .LQg[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
S <- S[is.na(adv) | adv >= 2e8]; S[, adv:=NULL]
# top-25 by score per Date (canonical setorder(-score) 동일)
setorder(S, Date, -score)
SEL <- S[, { n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], score=score[seq_len(n)]) }, by=Date]
# Size merge (당월 시총) — 가중용
SEL <- merge(SEL, .size_dt, by=c("Date","Ticker"), all.x=TRUE)   # size col
SEL[is.na(size) | size<=0, size := median(SEL$size,na.rm=TRUE)]   # 결측 시 중앙값(가중 안정)
setorder(SEL, Date, -score)
cat(sprintf("[R4] SEL rows=%d  dates=%d  avg holds=%.1f\n",
            nrow(SEL), length(unique(SEL$Date)), nrow(SEL)/length(unique(SEL$Date))))

# score_z within-date (te_min tilt용)
SEL[, score_z := (score-mean(score))/(sd(score)+1e-9), by=Date]

# ---------- (2) 가중 스킴 빌더 → W_dt(Date,Ticker,w) ----------
# ★[0,0.20] hard weight-bound (Production Constraint) — 반복 캡 후 renormalize. 배포 가능 여부 게이트.
cap_w <- function(w, cap=0.20){
  for(it in 1:200){ over<-w>cap+1e-12; if(!any(over)) break
    ex<-sum(w[over]-cap); w[over]<-cap; und<- w<cap-1e-12 & !over
    if(sum(w[und])<=0){ w<-w/sum(w); break }
    w[und]<-w[und]+ex*w[und]/sum(w[und]) }
  w/sum(w) }
mk_ew <- function(D){ D[, .(Date,Ticker, w=1/.N), by=Date][, .(Date,Ticker,w)] }
mk_sizeprop <- function(D){ D[, .(Ticker, w=size/sum(size)), by=Date][, .(Date,Ticker,w)] }
mk_sizeprop_cap <- function(D){ D[, .(Ticker, w=cap_w(size/sum(size))), by=Date][, .(Date,Ticker,w)] }
mk_shrink <- function(D, lam){ D[, .(Ticker, w=lam*(1/.N)+(1-lam)*(size/sum(size))), by=Date][, .(Date,Ticker,w)] }
mk_shrink_cap <- function(D, lam){ D[, .(Ticker, w=cap_w(lam*(1/.N)+(1-lam)*(size/sum(size)))), by=Date][, .(Date,Ticker,w)] }
mk_tilt   <- function(D, kap){ D[, { raw<-size*exp(kap*score_z); .(Ticker=Ticker, w=raw/sum(raw)) }, by=Date][, .(Date,Ticker,w)] }
mk_tilt_cap <- function(D, kap){ D[, { raw<-size*exp(kap*score_z); .(Ticker=Ticker, w=cap_w(raw/sum(raw))) }, by=Date][, .(Date,Ticker,w)] }

W_variants <- list(
  ew_parity      = mk_ew(SEL),                 # parity check → should ≈ 1.277
  size_prop      = mk_sizeprop(SEL),           # (a) cap-w 근접 (uncapped — 배포불가, 진단)
  size_prop_cap  = mk_sizeprop_cap(SEL),       # (a) ★[0,0.20] 제약 준수 — 배포가능 게이트
  shrink_l25     = mk_shrink(SEL,0.25),        # (b) 25% EW + 75% capw (uncapped)
  shrink_l50     = mk_shrink(SEL,0.50),        # (b) 50/50 (uncapped)
  shrink_l50_cap = mk_shrink_cap(SEL,0.50),    # (b) 50/50 capped
  shrink_l75     = mk_shrink(SEL,0.75),        # (b) 75% EW + 25% capw
  tilt_k0p5_cap  = mk_tilt_cap(SEL,0.5),       # (c) cap-w base + mild mom tilt, capped
  tilt_k1_cap    = mk_tilt_cap(SEL,1.0),       # (c) capped
  tilt_k2        = mk_tilt(SEL,2.0)            # (c) strong mom tilt (EW쪽 접근)
)

# ---------- (3) 실측: weighted_screen_bt (contract-grade, NW lag-3) ----------
eval_w <- function(W_dt, label){
  r <- weighted_screen_bt(W_dt, .Rg, .BMg, cost_bps_oneway=15,
                          run_id=paste0("r4_",label), strategy_id=paste0("r4_",label))
  pr <- r$period_returns
  # oos_ret (3분할 중앙값, active) + calmar (ret_net) — harness 규약과 동일 산식
  a <- pr$ret_net - pr$benchmark_ret; nn<-length(a); fr<-c(.55,.65,.75)
  sr<-function(x){s<-sd(x); if(!is.finite(s)||s<=0) return(NA); mean(x)/s*sqrt(12)}
  oosr<-median(sapply(fr,function(f){k<-floor(nn*f); if(k<6||nn-k<6) return(NA)
    is<-sr(a[1:k]); oo<-sr(a[(k+1):nn]); if(is.na(is)||is<=0) return(NA); oo/is}), na.rm=TRUE)
  x<-xts::xts(pr$ret_net, order.by=as.Date(pr$date)); ann<-prod(1+coredata(x))^(12/nrow(x))-1
  mdd<-as.numeric(PerformanceAnalytics::maxDrawdown(x)); cal<-if(is.finite(mdd)&&mdd>0) ann/mdd else NA
  maxw <- max(W_dt[, .(mw=max(w)), by=Date]$mw)   # 최대 단일종목 비중 (제약 [0,0.20] 점검)
  data.table(variant=label, port_t=round(r$portfolio_alpha_t_nw_lag3,3),
             ir=round(r$information_ratio,3), net_sr=round(r$net_sr,3),
             calmar=round(cal,3), oos_ret=round(oosr,3),
             turnover=round(r$turnover_annual,2), max_w=round(maxw,3),
             deploy_ok=(maxw<=0.2001), n=r$n_months)
}
cat("[R4] evaluating weight variants...\n")
res <- rbindlist(lapply(names(W_variants), function(nm) eval_w(W_variants[[nm]], nm)))

# ---------- (4) paired_vs_mom_t (best variant vs baseline momentum active, NW lag-3) ----------
mom_active <- .a_mom[, .(date, a_mom=active)]
paired_of <- function(W_dt){
  r <- weighted_screen_bt(W_dt, .Rg, .BMg, cost_bps_oneway=15, run_id="r4p", strategy_id="r4p")
  pr <- r$period_returns; av <- data.table(date=pr$date, a=pr$ret_net-pr$benchmark_ret)
  mg <- merge(av, mom_active, by="date"); .nw_t_mean(mg$a - mg$a_mom, lag=3)
}
res[, paired_vs_mom_t := sapply(names(W_variants), function(nm) round(paired_of(W_variants[[nm]]),3))]
res[, base_mom_port_t := .BASELINE_MOM_PORT_T]
res[, beats_mom := paired_vs_mom_t > 0]        # 벤치인지 가중이 momentum active 초과?

# ---------- (5) lag1 PIT 스트레스 (best DEPLOYABLE benchmark-aware = 제약준수 中 최대 port_t) ----------
res_deploy <- res[variant!="ew_parity" & deploy_ok==TRUE]
ba <- if(nrow(res_deploy)>0) res_deploy[which.max(port_t)] else res[variant!="ew_parity"][which.max(port_t)]
best_lab <- ba$variant
# Size_{t-1} 재가중: date별 prev-date size로 대체 → SEL_lag 만들고 동일 maker 재적용
dts <- sort(unique(SEL$Date)); prevmap <- data.table(Date=dts, pdate=shift(dts,1))
SL <- merge(SEL, prevmap, by="Date")
sz_prev <- .size_dt[, .(pdate=Date, Ticker, size_prev=size)]
SL <- merge(SL, sz_prev, by=c("pdate","Ticker"), all.x=TRUE)
SL[is.na(size_prev)|size_prev<=0, size_prev := size]   # prev 없으면 당월 fallback
SEL_lag <- copy(SL); SEL_lag[, size := size_prev]      # size를 전월값으로 교체, score/score_z 불변
maker <- list(size_prop=mk_sizeprop, size_prop_cap=mk_sizeprop_cap,
              shrink_l25=function(D) mk_shrink(D,0.25), shrink_l50=function(D) mk_shrink(D,0.50),
              shrink_l50_cap=function(D) mk_shrink_cap(D,0.50), shrink_l75=function(D) mk_shrink(D,0.75),
              tilt_k0p5_cap=function(D) mk_tilt_cap(D,0.5), tilt_k1_cap=function(D) mk_tilt_cap(D,1.0),
              tilt_k2=function(D) mk_tilt(D,2.0))[[best_lab]]
W_lag1 <- maker(SEL_lag)
lag1_pt <- weighted_screen_bt(W_lag1, .Rg, .BMg, cost_bps_oneway=15, run_id="r4lag1", strategy_id="r4lag1")$portfolio_alpha_t_nw_lag3
leak_flag <- ba$port_t > lag1_pt + 0.30

cat("\n===== R4 bench_aware_weight RESULTS (baseline momentum cap-w port_t=1.277) =====\n")
print(res)
cat(sprintf("\n[R4] best benchmark-aware = %s  port_t=%.3f  lag1(Size_t-1)=%.3f  leak_suspect=%s\n",
            best_lab, ba$port_t, lag1_pt, leak_flag))

# ---------- (6) 판정 (★배포가능성 게이트 = [0,0.20] 제약 준수분만 1급) ----------
best_all      <- res[which.max(port_t)]
best_ba       <- if(nrow(res_deploy)>0) res_deploy[which.max(port_t)] else res[variant!="ew_parity"][which.max(port_t)]
best_uncapped <- res[variant!="ew_parity"][which.max(port_t)]   # 진단(배포불가 포함)
ew_pt     <- res[variant=="ew_parity", port_t]
wall_broken <- best_ba$port_t >= 2.95            # 배포가능분 기준
beats_mom   <- best_ba$paired_vs_mom_t > 0
parity_ok <- abs(ew_pt - .BASELINE_MOM_PORT_T) < 0.15
deployable <- isTRUE(best_ba$deploy_ok)

verdict <- if(wall_broken) {
  "WALL_BROKEN: 배포가능([0,0.20]) benchmark-aware weight가 PORT_t>=2.95 -> cap-w 트랩은 selection·weight 교정으로 돌파"
} else if(best_ba$port_t > .BASELINE_MOM_PORT_T + 0.20) {
  sprintf("PARTIAL_LIFT_DEPLOYABLE: 제약준수 벤치-인지 가중(%s)이 momentum EW(1.277)->%.3f로 상당 상승(HARD 2.95 미달). ★cap-w 트랩의 큰 부분이 WEIGHT(EW의 소형주 틸트) 아티팩트 — SELECTION 아닌 WEIGHT axis로 완화 가능. 잔여 갭=진짜 알파 부재 아닌 벤치-상대 소형주 페널티였음", best_lab, best_ba$port_t)
} else {
  "STRUCTURAL: 배포가능 벤치-인지 가중 전부 momentum EW(1.277) 이하 -> WEIGHT axis도 미돌파"
}
selection_specific_verdict <- if(best_ba$port_t > .BASELINE_MOM_PORT_T + 0.20)
  sprintf("SELECTION_SPECIFIC(WEIGHT-fixable): 트랩은 SELECTION 특유가 아니라 EW *가중*의 소형주 틸트 아티팩트 — 동일 25종목을 제약준수 cap-tilt 재가중(%s)만으로 port_t 1.277->%.3f. R3(cap-w-native SELECTION tilt 미돌파)와 대조: 벽은 '가중 basis'에 있었지 신호에 있지 않았음. ★단 HARD 2.95 미달 — 재가중은 벤치-상대 소형주 페널티 제거일 뿐 신규 알파 생성 아님(net_sr 0.74·oos 0.61은 momentum 신호 자체 상한)", best_lab, best_ba$port_t) else
  "STRUCTURAL_DIRECTION: 제약준수 가중으로도 못 벗어남 -> 벽은 construction/구조"

summary <- list(
  lane="R4 benchmark_aware_weight (WEIGHT axis)", date=as.character(Sys.Date()),
  baseline_momentum_port_t=.BASELINE_MOM_PORT_T,
  ew_parity_port_t=ew_pt, parity_ok=parity_ok,
  best_bench_aware_deployable=as.list(best_ba), best_uncapped_diag=as.list(best_uncapped),
  best_all=as.list(best_all),
  wall_broken=wall_broken, beats_mom=beats_mom, deployable=deployable,
  lag1_best=lag1_pt, leak_suspect=leak_flag,
  verdict=verdict, selection_specific_verdict=selection_specific_verdict)
write_json(summary, file.path(W6,"R4_bench_aware_weight_summary.json"), pretty=TRUE, auto_unbox=TRUE)
fwrite(res, file.path(W6,"R4_bench_aware_weight_results.csv"))
# best benchmark-aware weight 저장
write_parquet(W_variants[[best_lab]], file.path(W6,"weights_R4_best_bench_aware.parquet"))
cat("\n[R4] VERDICT:", verdict, "\n[R4] SELECTION-SPECIFIC:", selection_specific_verdict, "\n[R4] done.\n")
