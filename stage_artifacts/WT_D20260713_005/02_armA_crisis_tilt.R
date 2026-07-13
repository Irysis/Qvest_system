# R21 / WT-D20260713_005 — arm A: 위기-조건부 저베타 within-sleeve 틸트
# 현 book(noLayer4) 슬리브 top-20(LinTilt λ1.5 cap0.20)를, 위기월(regime CRISIS/CAUTION)에 한해
# 칼만-저베타 상위로 sqrt-완만 재가중. 현금 오버레이 exposure=m4×β_R05 는 모든 arm 동일(상쇄).
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260713_005"; R19 <- "stage_artifacts/WT_D20260713_003"
source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")

cat("[A1] load infra...\n")
rawdata <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
             col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","BM_Ret")))
rawdata[, Date := as.Date(Date)]
rawdata[, K200 := (K200==1|K200==TRUE)]; rawdata[, KQ150 := (KQ150==1|KQ150==TRUE)]
beta <- as.data.table(read_parquet(file.path(R19,"beta_monthly.parquet")))
sig_dates <- sort(unique(beta$Date))
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
RET  <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH<- fwd$bench_dt[,  .(Date=as.Date(Date), BM_Ret)]
LIQ  <- fwd$liq_dt[,    .(Date=as.Date(Date), Ticker, adv)]
SIZE <- rawdata[Date %in% sig_dates, .(Size=last(Size)), by=.(Date,Ticker)][is.finite(Size)]

# ── STR_1715 sleeve score + regime (r05 panel, decision-YM join) ──
r05 <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet"))
r05[, YM := format(as.Date(Date),"%Y-%m")]
SC <- r05[is.finite(score_eff), .(YM, Ticker, score_eff, regime_state)]
# regime per YM (single label)
REG <- unique(SC[,.(YM,regime_state)])[, .SD[1], by=YM]
crisis_YM <- REG[regime_state %in% c("CRISIS","CAUTION"), YM]

# ── overlay exposure = m4_scalar × β_R05  (noLayer4), key decision-YM ──
wts <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
EXP <- wts[, .(YM=decision_ym, exposure = m4_scalar * beta_R05_V6)]
EXP <- unique(EXP)[, .SD[1], by=YM]

# helper: LinTilt λ1.5 cap0.20 (noLayer4 규칙 정확 재현)
.norm <- function(w,ub=0.20,ts=1,mi=50){w[is.na(w)]<-0;w[w<0]<-0;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8||s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<0]<-0};w}
.tilt <- function(a,lam=1.5,ub=0.20){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,ub)}

# ── build weights per sig_date: base / armA_K / armA_O / placebo(shift regime 12m) ──
cat("[A2] build sleeve weights (base / K-tilt / O-tilt / placebo)...\n")
GAMMA <- 0.5
crisis_shift <- REG[, .(YM, regime_state)]; setorder(crisis_shift, YM)
crisis_shift[, YM_target := shift(YM, 12, type="lead")]      # regime label(t) applied to t+12 (시점-무관 검출)
placebo_crisis_YM <- crisis_shift[regime_state %in% c("CRISIS","CAUTION") & !is.na(YM_target), YM_target]

wl_base<-list(); wl_K<-list(); wl_O<-list(); wl_plK<-list()
sleeve_diag <- list()
for (i in seq_along(sig_dates)) {
  t <- sig_dates[i]; YM <- format(t,"%Y-%m")
  liq_tk <- LIQ[Date==t & adv>=2e8, Ticker]
  cand <- merge(RET[Date==t,.(Ticker)], SC[YM==(YM), .(Ticker,score_eff)], by="Ticker")
  cand <- cand[Ticker %in% liq_tk & is.finite(score_eff)]
  if (nrow(cand) < 5) next
  setorder(cand,-score_eff); picks <- cand[seq_len(min(20L,nrow(cand)))]
  wb <- .tilt(setNames(picks$score_eff,picks$Ticker)); names(wb)<-picks$Ticker
  bt <- beta[Date==t & Ticker %in% picks$Ticker, .(Ticker,beta_ols,beta_kalman)]
  dt_base <- data.table(Date=t, Ticker=names(wb), w=as.numeric(wb))
  wl_base[[i]] <- dt_base
  # tilt function within held set
  mk_tilt <- function(bcol){
    m <- merge(dt_base, bt[,.(Ticker,b=get(bcol))], by="Ticker", all.x=TRUE)
    if (all(is.na(m$b))) return(copy(dt_base))
    m[, zlb := { bb<- -b; ifelse(is.finite(bb),(bb-mean(bb,na.rm=T))/pmax(sd(bb,na.rm=T),1e-10),0) }]
    m[!is.finite(zlb), zlb:=0]
    m[, g := sqrt(pmax(1+GAMMA*zlb, 0.05))]
    m[, w2 := w*g]; m[, w2 := as.numeric(.norm(w2))]
    m[, .(Date=t, Ticker, w=w2)]
  }
  isC   <- YM %in% crisis_YM
  isCpl <- YM %in% placebo_crisis_YM
  wl_K[[i]]   <- if (isC)   mk_tilt("beta_kalman") else copy(dt_base)
  wl_O[[i]]   <- if (isC)   mk_tilt("beta_ols")    else copy(dt_base)
  wl_plK[[i]] <- if (isCpl) mk_tilt("beta_kalman") else copy(dt_base)
  sleeve_diag[[i]] <- data.table(Date=t, YM=YM, crisis=isC, n_held=nrow(dt_base),
     med_ivrank=NA_real_)
}
W_base<-rbindlist(wl_base); W_K<-rbindlist(wl_K); W_O<-rbindlist(wl_O); W_plK<-rbindlist(wl_plK)
cat(sprintf("  months=%d | crisis months(regime)=%d | placebo-shift crisis months=%d\n",
    length(unique(W_base$Date)), length(intersect(unique(W_base$Date), sig_dates[format(sig_dates,'%Y-%m')%in%crisis_YM])),
    length(intersect(unique(W_base$Date), sig_dates[format(sig_dates,'%Y-%m')%in%placebo_crisis_YM]))))

# ── measure via weighted_screen_bt with common overlay exposure ──
cat("[A3] weighted_screen_bt (base / K / O / placebo) + overlay exposure...\n")
EXPd <- data.table(Date=sig_dates, YM=format(sig_dates,"%Y-%m"))
EXPd <- merge(EXPd, EXP, by="YM", all.x=TRUE)[, .(Date, exposure)]
EXPd[!is.finite(exposure), exposure := 1]
run_w <- function(W,id) weighted_screen_bt(W, RET[,.(Date,Ticker,Ret_1m)], BENCH, cost_bps_oneway=15,
             run_id=id, strategy_id=id, exposure_dt=EXPd)
res_base<-run_w(W_base,"R21A_base"); res_K<-run_w(W_K,"R21A_K")
res_O<-run_w(W_O,"R21A_O"); res_plK<-run_w(W_plK,"R21A_placeboK")

get_metrics <- function(res){
  pr<-as.data.table(res$period_returns); setorder(pr,date)
  act<-pr$ret_net-pr$benchmark_ret; n<-length(act)
  nav<-cumprod(1+pr$ret_net); yrs<-n/12; cagr<-nav[n]^(1/yrs)-1
  peak<-cummax(nav); mdd<-max((peak-nav)/peak)
  sr<-function(x) if(length(x)>6&&sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA
  oos<-median(vapply(c(.55,.65,.75),function(f){k<-floor(n*f);is<-sr(act[1:k]);o<-sr(act[(k+1):n]);if(is.na(is)||is<=0)NA else o/is},numeric(1)),na.rm=TRUE)
  list(port_t=round(res$portfolio_alpha_t_nw_lag3,3), net_sr=round(res$net_sr,3),
       ir=round(res$information_ratio,3), turnover=round(res$turnover_annual,3),
       mean_active=round(mean(act),5), cagr=round(cagr,4), mdd=round(mdd,4),
       calmar=round(ifelse(mdd>0,cagr/mdd,NA),3), oos_retention=round(oos,3), n=n)
}
m_base<-get_metrics(res_base); m_K<-get_metrics(res_K); m_O<-get_metrics(res_O); m_plK<-get_metrics(res_plK)

# ── paired NW-t: (K − base) full & crisis-only ; (K − O) kalman marginal ; placebo (plK − base) ──
act_dt <- function(res,nm){d<-as.data.table(res$period_returns)[,.(date,a=ret_net-benchmark_ret)];setnames(d,"a",nm);d}
J <- Reduce(function(x,y) merge(x,y,by="date"),
      list(act_dt(res_base,"base"),act_dt(res_K,"K"),act_dt(res_O,"O"),act_dt(res_plK,"plK")))
J[, YM := format(date,"%Y-%m")]; J[, is_crisis := YM %in% crisis_YM]
paired <- function(d) list(nw_t=round(.nw_t_mean(d,3L),3), mean_annual=round(mean(d)*12,5), n=length(d))
p_Kb_full   <- paired(J$K - J$base)
p_Kb_crisis <- paired(J[is_crisis==TRUE, K - base])
p_KO_full   <- paired(J$K - J$O)
p_plb_full  <- paired(J$plK - J$base)
# AX-001v2 market-crisis (R19 def) for defense framing
BMm<-BENCH[order(Date)];BMm[,roll6:=frollsum(BM_Ret,6)]
mkt_crisis<-BMm[BM_Ret< -0.05|(is.finite(roll6)&roll6<=quantile(roll6,0.2,na.rm=T)),Date]
J[, is_mktcrisis := date %in% mkt_crisis]
ax001 <- list(
  regime_crisis_months=p_Kb_crisis$n, market_crisis_months=sum(J$is_mktcrisis),
  base_regime_crisis_active=round(mean(J[is_crisis==TRUE]$base),5),
  K_regime_crisis_active=round(mean(J[is_crisis==TRUE]$K),5),
  K_minus_base_regime_crisis=p_Kb_crisis,
  base_mkt_crisis_active=round(mean(J[is_mktcrisis==TRUE]$base),5),
  K_mkt_crisis_active=round(mean(J[is_mktcrisis==TRUE]$K),5),
  mdd_base=m_base$mdd, mdd_K=m_K$mdd, mdd_relief=round(m_base$mdd-m_K$mdd,4),
  note="AX-001v2 조건부: 전기간 SR 채점 금지. 위기구간 active + Core(base) 대비 MDD 완화.")

summary <- list(
  wt_id="WT-D20260713_005", arm="A_crisis_conditional_lowbeta_tilt",
  tilt_spec=list(gamma=GAMMA, form="w_base × sqrt(pmax(1+gamma*z(-beta),0.05)), renorm cap0.20",
     N_sleeve=20, applied_when="regime_state ∈ {CRISIS,CAUTION}", overlay="m4×β_R05 common to all arms"),
  arms=list(base=m_base, armA_K=m_K, armA_O=m_O, placebo_K_shift12m=m_plK),
  paired=list(K_vs_base_full=p_Kb_full, K_vs_base_crisis=p_Kb_crisis,
     K_vs_O_kalman_marginal=p_KO_full, placebo_vs_base_full=p_plb_full),
  ax001v2_conditional=ax001,
  crisis_months_regime=length(intersect(unique(W_base$Date), sig_dates[format(sig_dates,'%Y-%m')%in%crisis_YM])),
  cost_model_version="v2.4_kr_retail_15bps", universe="KR_top342 (K200∪KQ150, LIQ 2e8)",
  selection_objective="canonical_port_t", n_trials=2, selection_type="sweep",
  interpret="arm A는 book-construction 개선 여부(AX-001v2). K_vs_base = 틸트 순효과, K_vs_O = 칼만 한계기여, placebo_vs_base = 시점-무관 스타일 효과(유의하면 R3 재판).")
writeLines(jsonlite::toJSON(summary, auto_unbox=TRUE, pretty=TRUE, digits=6, null="null"),
           file.path(OUT,"armA_crisis_tilt_summary.json"))
write_parquet(rbindlist(list(W_base[,arm:="base"],W_K[,arm:="K"],W_O[,arm:="O"],W_plK[,arm:="placeboK"])),
              file.path(OUT,"armA_weights.parquet"))
cat("[A] DONE.\n")
cat(sprintf("  base PORT_t=%.2f sr=%.2f mdd=%.3f | K=%.2f sr=%.2f mdd=%.3f | O=%.2f | placeboK=%.2f\n",
    m_base$port_t,m_base$net_sr,m_base$mdd, m_K$port_t,m_K$net_sr,m_K$mdd, m_O$port_t, m_plK$port_t))
cat(sprintf("  K-base full NW_t=%.2f | K-base CRISIS NW_t=%.2f (n=%d) | K-O marginal NW_t=%.2f | placebo-base NW_t=%.2f\n",
    p_Kb_full$nw_t, p_Kb_crisis$nw_t, p_Kb_crisis$n, p_KO_full$nw_t, p_plb_full$nw_t))
cat(sprintf("  MDD relief (base-K)=%.4f | regime-crisis active base=%.4f K=%.4f\n",
    ax001$mdd_relief, ax001$base_regime_crisis_active, ax001$K_regime_crisis_active))
