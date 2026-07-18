# run_R4_mid_construction.R — R4 lane: UNIVERSE CONSTRUCTION lever (선별규칙 불변, 유니버스 구성 변경)
# 핵심질문: cap-w 트랩이 횡단 SELECTION 특유인가, CONSTRUCTION으로도 못 벗어나는 구조적 벽인가?
#   선별규칙 = factor-momentum top-25 고정. 유니버스만 MID-tier 강조로 재구성.
#   벤치 = cap-w KOSPI200(.BMg) 고정.
#   - 유니버스를 알파 있는 곳(MID rank 11-30, mid active 0.430>mega -0.275)로 구성하면 cap-w port_t 회복?
#   - 아니면 벤치가 cap-w K200 고정 → MID 집중 = 벤치 이탈(음의 mega-beta) = active가 알파 아닌 tier-beta 베팅(구조적)?
#   판정 신호: cap-w port_t vs 1.277 (baseline mom, full univ). + EW-uni_t 병기(벤치가 벽인지 진단).
# PIT: 유니버스 필터는 Size/K200/KQ150 @t (contemporaneous cross-section, forward 아님). momentum score는 하네스가 PIT.
#      lag1 스트레스 = per-stock score 1개월 shift. IS-only(oracle 별도 라벨).
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
W6 <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- .fams
oos  <- .oos_dates

# ---------- (0) base momentum per-stock score (선별규칙 = 하네스 baseline과 동일) ----------
# .score_from_theta(.mom_theta) = sum_f theta_mom_f * z_f  (per-stock). 이게 top-25 선별 score.
base_score <- .score_from_theta(.mom_theta)          # data.table(Date,Ticker,score)
base_score <- base_score[Date %in% oos]

# per-month cap_rank (full univ 시총 내림차순) — MID/MEGA tier 정의 (diag_cap_tier와 동일 규약)
CR <- copy(.size_dt)[Date %in% oos & !is.na(size)]
setorder(CR, Date, -size)
CR[, cap_rank := seq_len(.N), by=Date]
# value z (MID-value 복합용)
VZ <- .FAM[Date %in% oos, .(Date, Ticker, value)]

# merge universe characteristics onto base_score
BS <- merge(base_score, CR[, .(Date,Ticker,cap_rank)], by=c("Date","Ticker"), all.x=TRUE)
BS <- merge(BS, .FAM[Date %in% oos, .(Date,Ticker,K200,KQ150,value_z=value)], by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[R4] base_score rows=%d (mom per-stock, %d oos months)\n", nrow(BS), length(oos)))

# ---------- helper: universe-restricted canonical measure + paired vs mom ----------
.a_mom_dt <- copy(.a_mom)[, .(date, mom_active=active)]   # baseline mom active

measure_univ <- function(score_dt, label){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]
  S <- S[Date %in% .Rg$Date & Date %in% oos]
  res <- canonical_screen_bt(S, .Rg, .BMg, top_n=25L, cost_bps_oneway=15,
              liq_dt=.LQg, liq_min=2e8, run_id=paste0("r4_",label), strategy_id=paste0("r4_",label),
              periods_per_year=12L, diag_dual_basis=TRUE, size_dt=.size_dt)
  pr <- res$period_returns
  pr[, active := ret_net - benchmark_ret]
  # paired vs mom
  mg <- merge(pr[,.(date,active)], .a_mom_dt, by="date")
  pvm <- .nw_t_mean(mg$active - mg$mom_active, lag=3)
  # calmar
  x <- xts(pr$ret_net, order.by=as.Date(pr$date)); nn<-nrow(x)
  ann <- prod(1+coredata(x))^(12/nn)-1; mdd <- as.numeric(maxDrawdown(x))
  cal <- if(is.finite(mdd)&&mdd>0) ann/mdd else NA_real_
  # oos_ret (3분할 중앙값, active)
  a<-pr$active; n<-length(a); fr<-c(.55,.65,.75)
  sr<-function(z){s<-sd(z);if(!is.finite(s)||s<=0)return(NA);mean(z)/s*sqrt(12)}
  orr<-median(sapply(fr,function(f){k<-floor(n*f);if(k<6||n-k<6)return(NA);is<-sr(a[1:k]);oo<-sr(a[(k+1):n]);if(is.na(is)||is<=0)return(NA);oo/is}),na.rm=TRUE)
  ewd <- res$diag_ew_universe
  ct  <- res$diag_cap_tier
  list(label=label, res=res, pr=pr,
       port_t=round(res$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(if(!is.null(ewd)) ewd$portfolio_alpha_t_nw_lag3 else NA,3),
       oos_ret=round(orr,3), net_sr=round(res$net_sr,3), calmar=round(cal,3),
       turnover=round(res$turnover_annual,2), paired_vs_mom_t=round(pvm,3),
       n=res$n_months,
       mega_wshare=round(if(isTRUE(ct$available)) ct$weight_share_avg$MEGA else NA,3),
       mid_wshare=round(if(isTRUE(ct$available)) ct$weight_share_avg$MID else NA,3),
       other_wshare=round(if(isTRUE(ct$available)) ct$weight_share_avg$OTHER else NA,3))
}

# lag1 stress: per-stock score를 1개월 shift(전월 score로 당월 선별) 후 동일 유니버스필터 재적용
measure_lag1 <- function(filter_fun, label){
  # shift base score within ticker by 1 month (use prev sig_date score)
  dts <- sort(unique(BS$Date))
  lm <- data.table(Date=dts, prevDate=shift(dts,1))[!is.na(prevDate)]
  bs_prev <- merge(lm, BS[,.(prevDate=Date,Ticker,score)], by="prevDate", allow.cartesian=TRUE)[,.(Date,Ticker,score)]
  # re-attach current-month universe chars (filter uses @t chars, score is lagged)
  bs_prev <- merge(bs_prev, BS[,.(Date,Ticker,cap_rank,K200,KQ150,value_z)], by=c("Date","Ticker"))
  sc <- filter_fun(bs_prev)
  S <- sc[!is.na(score), .(Date,Ticker,score)]; S <- S[Date %in% .Rg$Date & Date %in% oos]
  res <- canonical_screen_bt(S, .Rg, .BMg, top_n=25L, cost_bps_oneway=15, liq_dt=.LQg, liq_min=2e8,
              run_id=paste0("r4lag1_",label), strategy_id=paste0("r4lag1_",label),
              periods_per_year=12L, diag_dual_basis=FALSE)
  round(res$portfolio_alpha_t_nw_lag3,3)
}

# ---------- (1) CONSTRUCTION 변형 정의 (선별규칙=momentum top-25 불변, 유니버스만 변경) ----------
# 각 filter_fun: BS-like dt(Date,Ticker,score,cap_rank,K200,KQ150,value_z) -> 필터된 dt (score 유지)
variants <- list(
  # baseline (full univ, sanity — 1.277 재현 확인)
  full_univ       = function(d) d,
  # (a) MID-tier 강조: mega(rank<=10) drop
  mega_drop10     = function(d) d[cap_rank > 10 | is.na(cap_rank)],
  # (a) MID band 집중 (알파 국소 band rank 11-50)
  mid_band_11_50  = function(d) d[!is.na(cap_rank) & cap_rank>=11 & cap_rank<=50],
  # (a) MID+ broad (rank 11-100)
  mid_11_100      = function(d) d[!is.na(cap_rank) & cap_rank>=11 & cap_rank<=100],
  # (a) KQ150 focus (KOSDAQ mid-cap)
  kq150_focus     = function(d) d[KQ150==1],
  # (a) non-mega broad (rank 11+, 하한 없음)
  nonmega_all     = function(d) d[!is.na(cap_rank) & cap_rank>=11],
  # (c) MID-value 복합: rank 11-100 AND value_z>0, momentum top-25
  midvalue_mom    = function(d) d[!is.na(cap_rank) & cap_rank>=11 & cap_rank<=100 & is.finite(value_z) & value_z>0]
)

cat("[R4] measuring CONSTRUCTION variants (cap-w K200 bench)...\n")
res_list <- lapply(names(variants), function(nm){
  fv <- variants[[nm]]
  m <- measure_univ(fv(BS), nm)
  l1 <- tryCatch(measure_lag1(fv, nm), error=function(e) NA_real_)
  data.table(variant=nm, port_t=m$port_t, ew_uni_t=m$ew_uni_t, oos_ret=m$oos_ret,
             net_sr=m$net_sr, calmar=m$calmar, turnover=m$turnover,
             paired_vs_mom_t=m$paired_vs_mom_t, lag1_port_t=l1, n=m$n,
             mega_w=m$mega_wshare, mid_w=m$mid_wshare, other_w=m$other_wshare)
})
res <- rbindlist(res_list)

# (b) cap-tier-balanced: 각 tier에서 momentum top → 균형 25 (MEGA 5 + MID 10 + OTHER 10)
balanced_score <- function(d){
  # tier 라벨
  d <- copy(d)
  d[, tier := fifelse(!is.na(cap_rank)&cap_rank<=10,"MEGA",
               fifelse(!is.na(cap_rank)&cap_rank<=30,"MID","OTHER"))]
  # 각 tier·date에서 momentum score 상위 quota만 남기고 나머지 -Inf (top-25 자연선택되게 quota 내 순위 boost)
  # 방법: tier별 상위 quota 종목에 score 유지, 그 외 이 유니버스서 제외
  quota <- c(MEGA=5L, MID=10L, OTHER=10L)
  d[, rk := frank(-score, ties.method="first"), by=.(Date,tier)]
  d[rk <= quota[tier]]
}
m_bal <- measure_univ(balanced_score(BS), "captier_balanced")
l1_bal <- tryCatch(measure_lag1(balanced_score, "captier_balanced"), error=function(e) NA_real_)
res <- rbind(res, data.table(variant="captier_balanced", port_t=m_bal$port_t, ew_uni_t=m_bal$ew_uni_t,
        oos_ret=m_bal$oos_ret, net_sr=m_bal$net_sr, calmar=m_bal$calmar, turnover=m_bal$turnover,
        paired_vs_mom_t=m_bal$paired_vs_mom_t, lag1_port_t=l1_bal, n=m_bal$n,
        mega_w=m_bal$mega_wshare, mid_w=m_bal$mid_wshare, other_w=m_bal$other_wshare))

res[, beats_mom := port_t > .BASELINE_MOM_PORT_T]
res[, base_mom_port_t := .BASELINE_MOM_PORT_T]
res[, leak_suspect := is.finite(lag1_port_t) & lag1_port_t > port_t + 0.30]

cat("\n===== R4 mid_construction RESULTS (baseline mom port_t=1.277, cap-w K200 bench) =====\n")
print(res)

# ---------- (2) 판정 ----------
# full_univ 제외한 construction 변형 중 best cap-w port_t
res_constr <- res[variant != "full_univ"]
best <- res_constr[which.max(port_t)]
best_ew <- res_constr[which.max(ew_uni_t)]

wall_broken <- best$port_t >= 2.95
beats <- best$port_t > .BASELINE_MOM_PORT_T
# 구조적 판정: EW-uni는 회복하나 cap-w는 못하면 → 벤치(cap-w K200)가 벽 = 구조적
ew_recovers <- best_ew$ew_uni_t >= 2.0
capw_stuck  <- best$port_t < .BASELINE_MOM_PORT_T

verdict <- if(wall_broken) "WALL_BROKEN: construction lever가 cap-w PORT_t>=2.95 달성" else
  if(beats) sprintf("PARTIAL_LIFT: construction이 cap-w port_t를 momentum(1.277) 위로 올림(best %.3f) but <2.95", best$port_t) else
  if(ew_recovers && capw_stuck) sprintf("STRUCTURAL_BENCH_WALL: MID 집중이 EW-uni는 회복(best ew_uni_t %.3f)하나 cap-w K200 벤치 고정이라 cap-w port_t는 momentum 미만(best %.3f) — 벽=벤치구성 미스매치(SELECTION 특유 아님, CONSTRUCTION으로도 벤치 이탈=음의 tier-beta로 무효)", best_ew$ew_uni_t, best$port_t) else
  sprintf("CONSTRUCTION_NO_ALPHA: MID 집중이 cap-w(best %.3f)·EW-uni(best %.3f) 어느쪽도 momentum 미돌파 — 유니버스 재구성으로 알파 실현 실패", best$port_t, best_ew$ew_uni_t)

summary <- list(
  lane="R4 mid_construction", date=as.character(Sys.Date()),
  baseline_momentum_port_t=.BASELINE_MOM_PORT_T,
  best_capw=as.list(best), best_by_ew_uni=as.list(best_ew),
  wall_broken=wall_broken, beats_momentum=beats,
  ew_recovers=ew_recovers, capw_stuck=capw_stuck,
  verdict=verdict)
write_json(summary, file.path(W6,"R4_mid_construction_summary.json"), pretty=TRUE, auto_unbox=TRUE)
fwrite(res, file.path(W6,"R4_mid_construction_results.csv"))
# 산출물: best construction의 유니버스-필터 라벨 + 결과
saveRDS(list(results=res, verdict=verdict, best=best, best_ew=best_ew), file.path(W6,"R4_mid_construction.rds"))

cat("\n[R4] best construction: variant=", best$variant, " cap-w port_t=", best$port_t,
    " ew_uni_t=", best$ew_uni_t, " lag1=", best$lag1_port_t, "\n")
cat("[R4] VERDICT:", verdict, "\n[R4] done.\n")
