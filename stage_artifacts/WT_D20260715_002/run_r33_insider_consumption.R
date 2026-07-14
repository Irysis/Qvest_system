## run_r33_insider_consumption.R — WT-D20260715_002 / FQ-049 / R33
## insider 소비면 전환: R9 next_probe P1 직접 소비.
##   R9(pool-선별풀 멤버로서 insider) = KILL (paired <= +0.73). 본 라운드는
##   cap-w 횡단선택 벽이 안 걸리는 소비면(exclusion 필터 / monitoring 경보)에서 유효한가.
##
## §7b 정합: base = production 파생 clean T-1 패널 (production_parity_verified, PORT_t 3.058).
##   파생 저장 패널(268m same-month vintage) 재사용 금지. insider 패널 = 로컬 재사용(재빌드 X).
##   DART API 금지. book_state/05_Production/outputs/ramp 무변경 (산출 stage_artifacts만).
##
## PIT (C5 오버레이 타이밍): production 홀딩월 YM 는 T-1 신호로 결정(clean 검증).
##   insider 필터/경보 신호 = signal_date(월말 m) 로 홀딩월 (m+1) 을 필터 → 홀딩월 시작 전
##   데이터만 (signal_date = YM-1 월말). ins_hold_ym = ym(signal_date +1월) == hold_ym 병합.
##
## 갈래 A (exclusion형 유니버스 필터): 임원 대량 순매도(INS01 z <= -1.0 사전고정) 종목을
##   홀딩월 top-25 후보에서 사전 배제 → canonical paired(filtered - base). paired = 벤치·vintage
##   canceling (robust). dual-basis(cap-w + EW-uni) 절대치 병기.
## 갈래 B (monitoring 경보): net-buy 클러스터(INS02 z>=+1.0) 및 net-sell 극단(INS01 z<=-1.0)
##   플래그 종목의 forward 위험(수익/하방/변동성/tail) vs 비플래그, dual-basis, NW-t.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/factor_validation.R")        # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")

OUT <- "stage_artifacts/WT_D20260715_002"
logf <- file.path(OUT, "_r33_run_log.txt")
if (file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ym <- function(d) as.integer(format(as.Date(d), "%Y")) * 100L + as.integer(format(as.Date(d), "%m"))
ymshift <- function(ymv, k){ y<-ymv%/%100L; m<-ymv%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L + (t%%12L)+1L }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_); m<-lm(x~1)
  as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); mean(x)/s*sqrt(12) }
mdd <- function(r){ nav<-cumprod(1+r); min(nav/cummax(nav)-1) }

w("=== R33 insider 소비면 전환 — WT-D20260715_002 / FQ-049 ===")

## ── vintage pin (R9 pin 재사용 = 부모 라운드 정합) ────────────────────────────
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
wf("[vintage] rawdata pin=%s (mtime=%s)", RAW_P, PIN_MTIME)

## ── 1. base = production clean T-1 패널 (§7b) ─────────────────────────────────
CLEAN_P <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"
clean <- as.data.table(read_parquet(CLEAN_P))
clean[, Date := as.Date(Date)]
stopifnot(all(c("Date","Ticker","score_eff","Ret_1m") %in% names(clean)))
clean_meta <- fromJSON("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1_meta.json")
wf("[base] clean T-1 panel: rows=%d months=%d range=%s~%s label=%s parity_PORT_t=%.3f",
   nrow(clean), uniqueN(clean$Date), as.character(min(clean$Date)), as.character(max(clean$Date)),
   clean_meta$label, clean_meta$parity$screen_cap_w_top25$port_t_nw_lag3)
hold_dates <- sort(unique(clean$Date))

## ── 2. 벤치/유동성/시총 = pinned rawdata, 홀딩월 정렬 (벡터화 month-end) ────────
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
raw <- as.data.table(read_parquet(RAW_P, col_select=all_of(.need))); raw[,Date:=as.Date(Date)]
raw <- raw[!is.na(Close) & Close>0]
raw[, yq := ym(Date)]
me_of_ym <- raw[, .(me=max(Date)), by=yq]               # 각 year-month 의 월말 거래일
me <- merge(raw, me_of_ym, by="yq")[Date==me]           # 월말 스냅샷만
setorder(me, Ticker, yq)
me[, `:=`(Close_prev = shift(Close), yq_prev = shift(yq)), by=Ticker]
me[, uni_prev := shift(K200==TRUE | KQ150==TRUE), by=Ticker]
me[, `:=`(Size_prev = shift(Size), Vol_prev = shift(Vol), Cl_prev2 = shift(Close)), by=Ticker]
## 홀딩월 H 수익 = Close(me H) / Close(me H-1) - 1, 연속월(yq_prev = H-1)만
me[, ret_hold := Close/Close_prev - 1]
me[, cons := (ymshift(yq_prev, 1L) == yq)]              # 직전 월말이 정확히 H-1
mh <- me[cons==TRUE & !is.na(ret_hold) & uni_prev==TRUE]  # 유니버스(t-1) 필터
mh[, adv_prev := Vol_prev * Close_prev]                 # t-1 ADV proxy
## 홀딩월 first-of-month stamp
fom <- function(ymv) as.Date(sprintf("%04d-%02d-01", ymv%/%100L, ymv%%100L))
mh[, hold_date := fom(yq)]
## cap-w / EW 벤치 (홀딩월별)
capwb <- mh[, .(BM_Ret = weighted.mean(ret_hold, w=ifelse(is.na(Size_prev)|Size_prev<=0,0,Size_prev), na.rm=TRUE),
                ew = mean(ret_hold, na.rm=TRUE)), by=.(hold_date, hold_ym=yq)]
clean[, hold_ym := ym(Date)]
BENCH_DT <- merge(data.table(hold_ym=ym(hold_dates), Date=hold_dates), capwb[,.(hold_ym, BM_Ret)], by="hold_ym")[, .(Date, BM_Ret)]
EWB_DT   <- merge(data.table(hold_ym=ym(hold_dates), Date=hold_dates), capwb[,.(hold_ym, ew)], by="hold_ym")[, .(Date, ew)]
LIQ_DT   <- merge(data.table(hold_ym=ym(hold_dates), Date=hold_dates), mh[,.(hold_ym=yq, Ticker, adv=adv_prev)], by="hold_ym", allow.cartesian=TRUE)[, .(Date, Ticker, adv)]
SIZE_DT  <- merge(data.table(hold_ym=ym(hold_dates), Date=hold_dates), mh[,.(hold_ym=yq, Ticker, Size=Size_prev)], by="hold_ym", allow.cartesian=TRUE)[, .(Date, Ticker, Size)]
RET_DT   <- clean[, .(Date, Ticker, Ret_1m)]            # §7b: production-verified returns
tick_ov <- length(intersect(unique(clean$Ticker), unique(mh$Ticker)))
wf("[align] bench months=%d liq rows=%d size rows=%d | ticker overlap clean∩raw=%d", nrow(BENCH_DT), nrow(LIQ_DT), nrow(SIZE_DT), tick_ov)
rm(raw, me); invisible(gc())

## ── 3. insider 패널 (로컬 재사용) + 홀딩월 정렬 ───────────────────────────────
ins <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet"))
ins[, signal_date := as.Date(signal_date)]
ins[, hold_ym := ymshift(ym(signal_date), 1L)]          # PIT: signal m → 홀딩월 m+1
insw <- dcast(ins, hold_ym + security_id ~ factor_id, value.var="z")
setnames(insw, "security_id", "Ticker")
INS_COV <- range(insw$hold_ym)
wf("[insider] rows=%d hold_ym cov=%d~%d (홀딩월 정렬, signal m→m+1 PIT)", nrow(insw), INS_COV[1], INS_COV[2])

## ── 사전등록 (동결) ───────────────────────────────────────────────────────────
PREREG <- list(mode="RAMP-adjacent alpha consumption", round="R33", fq="FQ-049", wt="WT-D20260715_002",
  base_source="production clean T-1 (alpha_scores_str1715_268m_cleanT1.parquet, production_parity_verified)",
  base_returns="production-verified Ret_1m (§7b)", bench="cap-w KOSPI200∪KQ150 (rawdata pin, hold-aligned)",
  pit="clean T-1 alpha + insider signal_date(m월말)→홀딩월(m+1) 필터, 홀딩월 시작 전 데이터만 (C5)",
  branchA=list(kind="universe exclusion filter", target="INS01_OffNetBuyIntensity3m z <= -1.0 (임원 대량 순매도, 사전고정)",
    action="배제 후 잔여에서 top-25 EW 재선정", authoritative="paired NW-t (filtered - base, 벤치·vintage canceling)",
    dual_basis="cap-w + EW-uni 절대 PORT_t 병기 (canonical_screen_diag, 비바인딩)"),
  branchB=list(kind="monitoring tripwire", flags=list(net_buy_cluster="INS02_OffBuyBreadth6m z >= +1.0",
    net_sell_extreme="INS01_OffNetBuyIntensity3m z <= -1.0"),
    outcome="forward 1m 수익(홀딩월) — 평균/하방/변동성/tail(<-15%) vs 비플래그", dual_basis="raw + market-excess(ret-BM)"),
  top_n=25L, cost_bps_oneway=15, liq_min=2e8, gate_hard=c(port_t_capwt=2.95, oos_retention=0.7, calmar=0.64),
  paired_kill=2.0, selection_type="chain (가설주도 고정 config, sweep 아님)", n_trials=3L,
  honest_prior="FQ-001 standalone insider DEAD_PRELIM + R9 pool-선별 KILL(paired<=+0.73) — 보수적",
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r33.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("[prereg] config_hash=%s selection_type=chain n_trials=3", PREREG$config_hash)

## ── 4. 배관 parity: base canonical (cap-w PORT_t ~ 3.058 재현 확인) ────────────
base_scores <- clean[!is.na(score_eff), .(Date, Ticker, score=score_eff)]
cs_base <- canonical_screen_bt(base_scores, RET_DT, BENCH_DT, top_n=25L, cost_bps_oneway=15,
             liq_dt=LIQ_DT, liq_min=2e8, run_id="r33base", strategy_id="base_clean",
             diag_dual_basis=TRUE, size_dt=SIZE_DT)
wf("[parity] base cap-w PORT_t=%.3f (target 3.058) | EW-uni diag PORT_t=%.3f | n_months=%d | TO=%.2f",
   cs_base$portfolio_alpha_t_nw_lag3, cs_base$diag_ew_universe$portfolio_alpha_t_nw_lag3,
   cs_base$n_months, cs_base$turnover_annual)

## ── 5. 갈래 A: exclusion 필터 ─────────────────────────────────────────────────
EXCL_THR <- -1.0
excl <- insw[!is.na(INS01_OffNetBuyIntensity3m) & INS01_OffNetBuyIntensity3m <= EXCL_THR, .(hold_ym, Ticker, flag=1L)]
wf("[A] 배제 후보(INS01 z<=%.1f) rows=%d months=%d (net-seller 극단)", EXCL_THR, nrow(excl), uniqueN(excl$hold_ym))
## base top-25 보유에서 실제 배제되는 종목 수 (challenge #1)
base_hold <- copy(cs_base$period_returns)  # 참고용; 실제 보유는 재계산 필요
## filtered scores = base score에서 배제종목 제거 (해당 홀딩월)
bs <- merge(base_scores, data.table(hold_ym=ym(base_scores$Date), Date=base_scores$Date, Ticker=base_scores$Ticker),
            by=c("Date","Ticker"))
bs[, hold_ym := ym(Date)]
bs <- merge(bs, excl[, .(hold_ym, Ticker, flag)], by=c("hold_ym","Ticker"), all.x=TRUE)
filt_scores <- bs[is.na(flag), .(Date, Ticker, score)]
## 실제 base top-25 중 배제된 종목 수/월 진단
setorder(base_scores, Date, -score)
top25_base <- base_scores[, .(Ticker=Ticker[seq_len(min(25L,.N))]), by=Date]
top25_base[, hold_ym := ym(Date)]
top25_base <- merge(top25_base, excl[,.(hold_ym,Ticker,flag)], by=c("hold_ym","Ticker"), all.x=TRUE)
excl_in_top25 <- top25_base[!is.na(flag), .N, by=Date]
wf("[A] base top-25 중 배제된 종목: 총 %d건 / 영향월 %d / 월평균(영향월) %.2f종목",
   sum(excl_in_top25$N), nrow(excl_in_top25), if(nrow(excl_in_top25)) mean(excl_in_top25$N) else 0)

cs_filt <- canonical_screen_bt(filt_scores, RET_DT, BENCH_DT, top_n=25L, cost_bps_oneway=15,
             liq_dt=LIQ_DT, liq_min=2e8, run_id="r33filt", strategy_id="filtered",
             diag_dual_basis=TRUE, size_dt=SIZE_DT)
wf("[A] filtered cap-w PORT_t=%.3f | EW-uni diag=%.3f | n=%d | TO=%.2f",
   cs_filt$portfolio_alpha_t_nw_lag3, cs_filt$diag_ew_universe$portfolio_alpha_t_nw_lag3,
   cs_filt$n_months, cs_filt$turnover_annual)

## paired (filtered - base): 벤치·vintage canceling — authoritative
prb <- as.data.table(cs_base$period_returns)[, .(date, base=ret_net)]
prf <- as.data.table(cs_filt$period_returns)[, .(date, filt=ret_net)]
pm <- merge(prb, prf, by="date"); pm[, d := filt - base]; setnames(pm, "date", "Date")
paired_t <- nwt(pm$d); paired_ann <- mean(pm$d, na.rm=TRUE)*12
n_active <- sum(abs(pm$d) > 1e-12)
## 위험: 각 arm active(vs cap-w) 시계열
ab <- merge(as.data.table(cs_base$period_returns)[,.(date,ret_net,benchmark_ret)],
            as.data.table(cs_filt$period_returns)[,.(date,filt=ret_net)], by="date")
ab[, act_base := ret_net - benchmark_ret]; ab[, act_filt := filt - benchmark_ret]
riskA <- list(base_mdd=mdd(ab$ret_net), filt_mdd=mdd(ab$filt),
  base_active_sr=srf(ab$act_base), filt_active_sr=srf(ab$act_filt),
  base_active_vol=sd(ab$act_base)*sqrt(12), filt_active_vol=sd(ab$act_filt)*sqrt(12))
wf("[A] PAIRED (filtered-base) NW-t=%+.2f Δann=%+.4f | 영향월=%d / %d | KILL(>=2.0)=%s",
   paired_t, paired_ann, n_active, nrow(pm), !(is.finite(paired_t) && paired_t>=2.0))
wf("[A] risk: MDD base=%.3f filt=%.3f | active-SR base=%.2f filt=%.2f | active-vol base=%.3f filt=%.3f",
   riskA$base_mdd, riskA$filt_mdd, riskA$base_active_sr, riskA$filt_active_sr, riskA$base_active_vol, riskA$filt_active_vol)

## ── 6. 갈래 B: monitoring 경보 (forward 위험) ─────────────────────────────────
## 유니버스 forward 수익(홀딩월) + BM merge — insider 커버 홀딩월만
uni <- merge(RET_DT, BENCH_DT, by="Date")
uni[, hold_ym := ym(Date)]
uni[, exc := Ret_1m - BM_Ret]                            # market-excess
uni <- uni[hold_ym >= INS_COV[1] & hold_ym <= INS_COV[2]]
## 플래그 부착
flagB <- function(cond_expr, lab){
  fl <- insw[eval(cond_expr), .(hold_ym, Ticker, f=1L)]
  d <- merge(uni, fl, by=c("hold_ym","Ticker"), all.x=TRUE); d[is.na(f), f:=0L]
  ## 월별 그룹평균 → 시계열 gap (flag - nonflag), dual-basis
  g <- d[, .(m_ret_f = mean(Ret_1m[f==1L], na.rm=TRUE), m_ret_n = mean(Ret_1m[f==0L], na.rm=TRUE),
             m_exc_f = mean(exc[f==1L], na.rm=TRUE),     m_exc_n = mean(exc[f==0L], na.rm=TRUE),
             nf = sum(f==1L)), by=hold_ym][nf>0]
  gap_ret <- g$m_ret_f - g$m_ret_n; gap_exc <- g$m_exc_f - g$m_exc_n
  ## pooled 위험 통계 (flag vs nonflag)
  ff <- d[f==1L]; nn <- d[f==0L]
  list(label=lab, n_flag_obs=nrow(ff), n_months=nrow(g), avg_flag_per_month=mean(g$nf),
    mean_fwd_flag=mean(ff$Ret_1m,na.rm=TRUE), mean_fwd_nonflag=mean(nn$Ret_1m,na.rm=TRUE),
    downside_flag=mean(ff$Ret_1m[ff$Ret_1m<0],na.rm=TRUE), downside_nonflag=mean(nn$Ret_1m[nn$Ret_1m<0],na.rm=TRUE),
    vol_flag=sd(ff$Ret_1m,na.rm=TRUE), vol_nonflag=sd(nn$Ret_1m,na.rm=TRUE),
    tail_hit_flag=mean(ff$Ret_1m < -0.15,na.rm=TRUE), tail_hit_nonflag=mean(nn$Ret_1m < -0.15,na.rm=TRUE),
    gap_ret_ann=mean(gap_ret,na.rm=TRUE)*12, gap_ret_t=nwt(gap_ret),
    gap_exc_ann=mean(gap_exc,na.rm=TRUE)*12, gap_exc_t=nwt(gap_exc))
}
B_buy  <- flagB(quote(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= 1.0), "net_buy_cluster(INS02>=+1.0)")
B_sell <- flagB(quote(!is.na(INS01_OffNetBuyIntensity3m) & INS01_OffNetBuyIntensity3m <= -1.0), "net_sell_extreme(INS01<=-1.0)")
for(B in list(B_buy, B_sell)){
  wf("[B:%s] n_obs=%d months=%d avg/mo=%.1f | fwd flag=%+.4f nonflag=%+.4f | gap_ret_t=%+.2f gap_exc_t=%+.2f",
     B$label, B$n_flag_obs, B$n_months, B$avg_flag_per_month, B$mean_fwd_flag, B$mean_fwd_nonflag, B$gap_ret_t, B$gap_exc_t)
  wf("[B:%s] downside flag=%+.4f nonflag=%+.4f | vol flag=%.4f nonflag=%.4f | tail(<-15%%) flag=%.3f nonflag=%.3f",
     B$label, B$downside_flag, B$downside_nonflag, B$vol_flag, B$vol_nonflag, B$tail_hit_flag, B$tail_hit_nonflag)
}

## ── 7. 저장 ───────────────────────────────────────────────────────────────────
res <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  parity=list(base_capw_port_t=cs_base$portfolio_alpha_t_nw_lag3, target=3.058,
    base_ewuni_port_t=cs_base$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    base_n_months=cs_base$n_months, base_turnover=cs_base$turnover_annual),
  branchA=list(excl_threshold=EXCL_THR, n_excl_candidate_rows=nrow(excl), n_excl_months=uniqueN(excl$hold_ym),
    excl_in_top25_total=sum(excl_in_top25$N), excl_in_top25_affected_months=nrow(excl_in_top25),
    excl_in_top25_avg_when_affected=if(nrow(excl_in_top25)) mean(excl_in_top25$N) else 0,
    filt_capw_port_t=cs_filt$portfolio_alpha_t_nw_lag3, filt_ewuni_port_t=cs_filt$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    filt_turnover=cs_filt$turnover_annual,
    paired_nw_t=paired_t, paired_delta_ann=paired_ann, paired_n_months=nrow(pm), paired_active_months=n_active,
    paired_kill=!(is.finite(paired_t) && paired_t>=2.0), risk=riskA,
    capw_tier_base=cs_base$diag_cap_tier$weight_share_avg, capw_tier_filt=cs_filt$diag_cap_tier$weight_share_avg),
  branchB=list(net_buy_cluster=B_buy, net_sell_extreme=B_sell),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(res, file.path(OUT,"r33_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
saveRDS(list(cs_base=cs_base, cs_filt=cs_filt, pm=pm, ab=ab, B_buy=B_buy, B_sell=B_sell, res=res),
        file.path(OUT,"_r33_objects.rds"))
## paired 시계열 parquet (차트용)
write_parquet(pm, file.path(OUT,"r33_branchA_paired_series.parquet"))
wf("\nR33_DONE parity=%.3f A_paired_t=%+.2f B_buy_gap_t=%+.2f B_sell_gap_t=%+.2f",
   cs_base$portfolio_alpha_t_nw_lag3, paired_t, B_buy$gap_ret_t, B_sell$gap_ret_t)
cat("[SAVED]", file.path(OUT,"r33_results.json"), "\n")
