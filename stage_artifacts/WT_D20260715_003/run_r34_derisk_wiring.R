## run_r34_derisk_wiring.R — WT-D20260715_003 / FQ-050 / R34
## R33 P1 소비: insider net-buy 클러스터 = monitoring tripwire 배선 검증 + PG2 북 de-risk 예외 진단.
##
## 작업 ①(측정) de-risk 예외 진단 (진단만 · 북 운용 무변경):
##   북 보유(= production score_eff top-25 equity 슬리브) 종목이 net-buy flag(INS02 z>=+1.0)일 때
##   실현 forward 수익/하방/변동성/tail 이 비-flag 보유 대비 개선되는가 (R33 universe→북-레벨 확장).
##   dual-basis(raw + market-excess) · pooled + monthly-paired NW-t · cohort forward MDD(진단).
## 작업 ②(배선 검증) 현 북 14 보유의 net-buy(안전)/net-sell(경보) tripwire 판정 (live PIT snapshot).
##
## §7b: base = production clean T-1 (alpha_scores_str1715_268m_cleanT1, production_parity_verified).
##   파생 저장 268m same-month vintage 재사용 금지. insider 패널 = 로컬 재사용(재빌드 X). DART API X.
## PIT (C5): 보유월 = clean T-1 score_eff 결정(검증). insider flag = signal_date(월말 m) → 홀딩월(m+1),
##   즉 홀딩월 시작 전 데이터만. lag-1 스트레스로 동월누출 배제 실증.
## 규율: 단일스레드 · arrow io(2) · OneDrive temp-rename. book_state/05_Production/outputs 무변경.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2L),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

OUT <- "stage_artifacts/WT_D20260715_003"
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "_r34_run_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ym <- function(d) as.integer(format(as.Date(d), "%Y"))*100L + as.integer(format(as.Date(d), "%m"))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_); m<-lm(x~1)
  as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); mean(x)/s*sqrt(12) }
mdd <- function(r){ r<-r[is.finite(r)]; if(length(r)<3) return(NA_real_); nav<-cumprod(1+r); min(nav/cummax(nav)-1) }  # 진단용(R33 동일 helper)

w("=== R34 insider net-buy tripwire 배선 + 북 de-risk 진단 — WT-D20260715_003 / FQ-050 ===")

## ── vintage pin (R9/R33 pin 재사용 = 부모 라운드 정합) ─────────────────────────
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
wf("[vintage] rawdata pin=%s (mtime=%s)", RAW_P, PIN_MTIME)

## ── 1. base = production clean T-1 패널 (§7b) ──────────────────────────────────
CLEAN_P <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"
clean <- as.data.table(read_parquet(CLEAN_P)); clean[, Date := as.Date(Date)]
stopifnot(all(c("Date","Ticker","score_eff","Ret_1m") %in% names(clean)))
clean[, hold_ym := ym(Date)]
clean_meta <- fromJSON("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1_meta.json")
wf("[base] clean T-1: rows=%d months=%d range=%s~%s parity_PORT_t=%.3f label=%s",
   nrow(clean), uniqueN(clean$Date), as.character(min(clean$Date)), as.character(max(clean$Date)),
   clean_meta$parity$screen_cap_w_top25$port_t_nw_lag3, clean_meta$label)
hold_dates <- sort(unique(clean$Date))

## ── 2. 벤치(cap-w)/유동성/시총 = pinned rawdata, 홀딩월 정렬 (R33 배관 재사용) ────
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
raw <- as.data.table(read_parquet(RAW_P, col_select=all_of(.need))); raw[,Date:=as.Date(Date)]
raw <- raw[!is.na(Close) & Close>0]; raw[, yq := ym(Date)]
me_of_ym <- raw[, .(me=max(Date)), by=yq]
me <- merge(raw, me_of_ym, by="yq")[Date==me]; setorder(me, Ticker, yq)
me[, `:=`(Close_prev=shift(Close), yq_prev=shift(yq)), by=Ticker]
me[, uni_prev := shift(K200==TRUE | KQ150==TRUE), by=Ticker]
me[, `:=`(Size_prev=shift(Size), Vol_prev=shift(Vol)), by=Ticker]
me[, ret_hold := Close/Close_prev - 1]
me[, cons := (ymshift(yq_prev, 1L) == yq)]
mh <- me[cons==TRUE & !is.na(ret_hold) & uni_prev==TRUE]
mh[, adv_prev := Vol_prev * Close_prev]
capwb <- mh[, .(BM_Ret = weighted.mean(ret_hold, w=ifelse(is.na(Size_prev)|Size_prev<=0,0,Size_prev), na.rm=TRUE)), by=.(hold_ym=yq)]
LIQ  <- mh[, .(hold_ym=yq, Ticker, adv=adv_prev)]
SIZE <- mh[, .(hold_ym=yq, Ticker, Size=Size_prev)]
rm(raw, me); invisible(gc())
wf("[align] cap-w bench months=%d | liq rows=%d | size rows=%d", nrow(capwb), nrow(LIQ), nrow(SIZE))

## ── 3. insider 패널 (로컬 재사용) + 홀딩월 정렬 (signal m → hold m+1, C5) ────────
ins <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet"))
ins[, signal_date := as.Date(signal_date)]
ins[, hold_ym := ymshift(ym(signal_date), 1L)]
insw <- dcast(ins, hold_ym + security_id ~ factor_id, value.var="z"); setnames(insw, "security_id", "Ticker")
INS_COV <- range(insw$hold_ym)
NB_THR <- 1.0; NS_THR <- -1.0   # R33 사전고정 문턱 (net-buy 클러스터 / net-sell 극단), sweep 금지
wf("[insider] rows=%d hold_ym cov=%d~%d | net-buy=INS02>=+%.1f · net-sell=INS01<=%.1f (R33 frozen)",
   nrow(insw), INS_COV[1], INS_COV[2], NB_THR, NS_THR)

## ── 4. 북 보유 재구성: production score_eff top-25 equity 슬리브 (liq filter) ─────
## 오버레이(M4×R05)는 북-레벨 현금조절이지 종목선택 아님 → equity 슬리브 = top-25 by score_eff.
S <- clean[!is.na(score_eff), .(hold_ym, Date, Ticker, score=score_eff)]
S <- merge(S, LIQ, by=c("hold_ym","Ticker"), all.x=TRUE)
S <- S[is.na(adv) | adv >= 2e8]        # 유동성필터(2e8, C10 t-1 ADV)
setorder(S, Date, -score)
HELD <- S[, .(Ticker=Ticker[seq_len(min(25L,.N))]), by=.(hold_ym, Date)]
wf("[held] 북 equity 슬리브 재구성: %d held-name-months over %d holding months (top-25 score_eff, liq>=2e8)",
   nrow(HELD), uniqueN(HELD$Date))

## forward 실현수익(§7b clean Ret_1m) + cap-w 벤치 excess 부착
HELD <- merge(HELD, clean[, .(hold_ym, Ticker, Ret_1m)], by=c("hold_ym","Ticker"), all.x=TRUE)
HELD <- merge(HELD, capwb, by="hold_ym", all.x=TRUE)
HELD[, exc := Ret_1m - BM_Ret]
## insider flag 부착 (INS02 net-buy / INS01 net-sell) + size
HELD <- merge(HELD, insw[, .(hold_ym, Ticker, INS02_OffBuyBreadth6m, INS01_OffNetBuyIntensity3m)],
              by=c("hold_ym","Ticker"), all.x=TRUE)
HELD <- merge(HELD, SIZE, by=c("hold_ym","Ticker"), all.x=TRUE)
HELD[, has_ins := as.integer(!is.na(INS02_OffBuyBreadth6m))]
HELD[, nb_flag := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= NB_THR)]
HELD[, ns_flag := as.integer(!is.na(INS01_OffNetBuyIntensity3m) & INS01_OffNetBuyIntensity3m <= NS_THR)]
HELD <- HELD[!is.na(Ret_1m)]   # 실현수익 있는 held-name-month만 진단

## ── 5. DE-RISK 진단: net-buy flag 보유 vs 비-flag 보유 (dual-basis) ──────────────
## 정의: flag = 보유 ∧ INS02 net-buy 클러스터. two 대조군:
##   (P) primary(R33-정합): nonflag = 그 외 모든 보유(무-insider 포함).
##   (R) restricted: insider 커버 보유만(has_ins==1) 내에서 z>=1 vs z<1 (신호-present 대조).
derisk <- function(DT, lab){
  ff <- DT[nb_flag==1L]; nn <- DT[nb_flag==0L]
  ## monthly paired gap (flag mean - nonflag mean), dual-basis
  g <- DT[, .(m_ret_f=mean(Ret_1m[nb_flag==1L],na.rm=TRUE), m_ret_n=mean(Ret_1m[nb_flag==0L],na.rm=TRUE),
              m_exc_f=mean(exc[nb_flag==1L],na.rm=TRUE),     m_exc_n=mean(exc[nb_flag==0L],na.rm=TRUE),
              nf=sum(nb_flag==1L), nn=sum(nb_flag==0L)), by=hold_ym][nf>0 & nn>0]
  gap_ret <- g$m_ret_f - g$m_ret_n; gap_exc <- g$m_exc_f - g$m_exc_n
  ## cohort forward path (진단 MDD/SR) — EW cohort 월수익
  gc <- DT[, .(coh_f=mean(Ret_1m[nb_flag==1L],na.rm=TRUE), coh_n=mean(Ret_1m[nb_flag==0L],na.rm=TRUE),
               bm=mean(BM_Ret,na.rm=TRUE), nf=sum(nb_flag==1L)), by=.(hold_ym)][nf>0]
  setorder(gc, hold_ym)
  list(label=lab, n_flag_obs=nrow(ff), n_nonflag_obs=nrow(nn), n_months=nrow(g),
    avg_flag_per_month=mean(g$nf), avg_nonflag_per_month=mean(g$nn),
    mean_fwd_flag=mean(ff$Ret_1m,na.rm=TRUE), mean_fwd_nonflag=mean(nn$Ret_1m,na.rm=TRUE),
    downside_flag=mean(ff$Ret_1m[ff$Ret_1m<0],na.rm=TRUE), downside_nonflag=mean(nn$Ret_1m[nn$Ret_1m<0],na.rm=TRUE),
    vol_flag=sd(ff$Ret_1m,na.rm=TRUE), vol_nonflag=sd(nn$Ret_1m,na.rm=TRUE),
    tail_hit_flag=mean(ff$Ret_1m < -0.15,na.rm=TRUE), tail_hit_nonflag=mean(nn$Ret_1m < -0.15,na.rm=TRUE),
    gap_ret_ann=mean(gap_ret,na.rm=TRUE)*12, gap_ret_t=nwt(gap_ret),
    gap_exc_ann=mean(gap_exc,na.rm=TRUE)*12, gap_exc_t=nwt(gap_exc),
    ## cohort 진단 (forward drawdown/변동성 — 북-레벨 de-risk 질문 직답)
    cohort_mdd_flag=mdd(gc$coh_f), cohort_mdd_nonflag=mdd(gc$coh_n),
    cohort_vol_flag=sd(gc$coh_f,na.rm=TRUE)*sqrt(12), cohort_vol_nonflag=sd(gc$coh_n,na.rm=TRUE)*sqrt(12),
    cohort_sr_flag=srf(gc$coh_f), cohort_sr_nonflag=srf(gc$coh_n),
    cohort_months=nrow(gc))
}
DR_P <- derisk(HELD, "primary(nonflag=all-other-held)")
DR_R <- derisk(HELD[has_ins==1L], "restricted(insider-covered held only)")
for(D in list(DR_P, DR_R)){
  wf("[derisk:%s] flag_obs=%d nonflag_obs=%d months=%d avg_flag/mo=%.1f", D$label, D$n_flag_obs, D$n_nonflag_obs, D$n_months, D$avg_flag_per_month)
  wf("[derisk:%s] fwd flag=%+.4f nonflag=%+.4f | gap_ret_t=%+.2f gap_exc_t=%+.2f", D$label, D$mean_fwd_flag, D$mean_fwd_nonflag, D$gap_ret_t, D$gap_exc_t)
  wf("[derisk:%s] downside flag=%+.4f nonflag=%+.4f | vol flag=%.4f nonflag=%.4f | tail(<-15%%) flag=%.3f nonflag=%.3f", D$label, D$downside_flag, D$downside_nonflag, D$vol_flag, D$vol_nonflag, D$tail_hit_flag, D$tail_hit_nonflag)
  wf("[derisk:%s] COHORT forward MDD flag=%.3f nonflag=%.3f | vol flag=%.3f nonflag=%.3f | SR flag=%.2f nonflag=%.2f (cohort months=%d)", D$label, D$cohort_mdd_flag, D$cohort_mdd_nonflag, D$cohort_vol_flag, D$cohort_vol_nonflag, D$cohort_sr_flag, D$cohort_sr_nonflag, D$cohort_months)
}

## ── 5b. lag-1 스트레스 (동월누출 배제, C5 규율) ─────────────────────────────────
## flag을 홀딩월 +1 로 한번 더 밀어(신호가 2개월 전) — de-risk 효과가 붕괴하면 동월누출 의심.
HL <- copy(insw[, .(hold_ym=ymshift(hold_ym,1L), Ticker, INS02_OffBuyBreadth6m)])
HELD_L <- merge(HELD[, .(hold_ym, Ticker, Ret_1m, exc, BM_Ret)], HL, by=c("hold_ym","Ticker"), all.x=TRUE)
HELD_L[, nb_flag := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= NB_THR)]
DR_L <- derisk(HELD_L[!is.na(Ret_1m)], "lag1-stress(flag shifted +1m)")
wf("[derisk:LAG1] fwd flag=%+.4f nonflag=%+.4f gap_t=%+.2f | downside flag=%+.4f nonflag=%+.4f | cohort MDD flag=%.3f nonflag=%.3f",
   DR_L$mean_fwd_flag, DR_L$mean_fwd_nonflag, DR_L$gap_ret_t, DR_L$downside_flag, DR_L$downside_nonflag, DR_L$cohort_mdd_flag, DR_L$cohort_mdd_nonflag)

## ── 5c. size-tier 컨텍스트 (flagged-held 이 소형 국소인가) ───────────────────────
HELD[, cap_rank := frank(-Size, ties.method="first"), by=hold_ym]
HELD[, tier := fifelse(cap_rank<=10L,"MEGA", fifelse(cap_rank<=30L,"MID","OTHER"))]
tier_dist <- HELD[nb_flag==1L, .N, by=tier][order(-N)]
wf("[derisk:tier] flagged-held size 분포: %s", paste(sprintf("%s=%d", tier_dist$tier, tier_dist$N), collapse=" "))

## ── 6. 배선 검증: 현 북 14 보유 tripwire snapshot (live PIT) ─────────────────────
H <- fread("05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/20260701_noLayer4_weights_cap_0p20.csv")
hold_cur <- H[Ticker!="CASH" & Weight>0, .(Ticker, Name, Weight)]
CUR_HOLD_YM <- 202607L   # 20260701 weights → 홀딩월 202607; insider signal = 2026-06-30(월말) PIT-clean
ins_cur <- insw[hold_ym==CUR_HOLD_YM, .(Ticker, INS02_OffBuyBreadth6m, INS01_OffNetBuyIntensity3m, INS03_OffNetBuyRecency)]
tw <- merge(hold_cur, ins_cur, by="Ticker", all.x=TRUE)
## ★ tripwire = net-buy SAFE flag만 (R33: net-sell 무정보 t=-0.01 → 경보 아님, advisory 기록만).
##   경보(concern) 방향은 부실 신호(지각제출·감사 distress, filing_delay_watch Part A/B)가 담당.
tw[, nb_safe := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= NB_THR)]
tw[, ns_advisory := as.integer(!is.na(INS01_OffNetBuyIntensity3m) & INS01_OffNetBuyIntensity3m <= NS_THR)]  # advisory only
tw[, tripwire := fifelse(is.na(INS02_OffBuyBreadth6m) & is.na(INS01_OffNetBuyIntensity3m), "NO_INSIDER_DATA",
                 fifelse(nb_safe==1L, "NET_BUY_SAFE", "NEUTRAL"))]
setorder(tw, -Weight)
wf("\n[wiring] 현 북 %d 보유 insider net-buy tripwire (홀딩월 %d · signal 2026-06-30, PIT-clean):", nrow(tw), CUR_HOLD_YM)
for(i in seq_len(nrow(tw))){ r<-tw[i]
  wf("   %-8s %-12s w=%.4f  INS02(net-buy breadth)=%s [%s] (INS01 net-sell=%s advisory·R33 무정보)",
     r$Ticker, ifelse(is.na(r$Name)||r$Name=="","-",r$Name), r$Weight,
     ifelse(is.na(r$INS02_OffBuyBreadth6m),"NA",sprintf("%+.2f",r$INS02_OffBuyBreadth6m)), r$tripwire,
     ifelse(is.na(r$INS01_OffNetBuyIntensity3m),"NA",sprintf("%+.2f",r$INS01_OffNetBuyIntensity3m))) }
n_safe <- tw[tripwire=="NET_BUY_SAFE",.N]; n_neutral <- tw[tripwire=="NEUTRAL",.N]
n_nodata <- tw[tripwire=="NO_INSIDER_DATA",.N]; n_ns_adv <- tw[ns_advisory==1L,.N]
wf("[wiring] NET_BUY_SAFE=%d · NEUTRAL=%d · NO_INSIDER_DATA=%d | (advisory: net-sell z<=-1.0 %d건 — R33 무정보, 경보 아님)", n_safe, n_neutral, n_nodata, n_ns_adv)

## ── 7. 사전등록 해시 + 저장 ─────────────────────────────────────────────────────
PREREG <- list(mode="RAMP-adjacent alpha consumption", round="R34", fq="FQ-050", wt="WT-D20260715_003",
  parent="R33 next_probe P1 (net-buy 클러스터 book de-risk tripwire 배선 측정)",
  base_source="production clean T-1 (alpha_scores_str1715_268m_cleanT1, production_parity_verified)",
  held_reconstruction="score_eff top-25 equity 슬리브 + liq>=2e8 (오버레이=현금조절이지 선택 아님)",
  pit="clean T-1 held + insider signal(월말 m)→홀딩월(m+1) flag, 홀딩월 시작 전 (C5) + lag1 스트레스",
  flags=list(net_buy="INS02_OffBuyBreadth6m z>=+1.0 (R33 frozen)", net_sell="INS01_OffNetBuyIntensity3m z<=-1.0"),
  dual_basis="raw Ret_1m + market-excess(ret-BM cap-w) + cohort forward MDD/vol/SR",
  selection_type="chain (배선/진단 · sweep 아님)", n_trials=1L,
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r34.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("[prereg] config_hash=%s", PREREG$config_hash)

res <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  base_parity=list(clean_parity_port_t=clean_meta$parity$screen_cap_w_top25$port_t_nw_lag3, note="§7b production_parity_verified"),
  held_coverage=list(held_name_months=nrow(HELD), holding_months=uniqueN(HELD$Date),
    insider_covered_held=HELD[has_ins==1L,.N], flagged_held=HELD[nb_flag==1L,.N],
    net_sell_flagged_held=HELD[ns_flag==1L,.N], flagged_held_pct=round(100*HELD[nb_flag==1L,.N]/nrow(HELD),2)),
  derisk_primary=DR_P, derisk_restricted=DR_R, derisk_lag1_stress=DR_L,
  flagged_held_tier_dist=setNames(as.list(tier_dist$N), tier_dist$tier),
  wiring_current_book=list(holding_ym=CUR_HOLD_YM, n_holdings=nrow(tw),
    tripwire_rule="NET_BUY_SAFE = INS02_OffBuyBreadth6m z>=+1.0 (R33 capability). net-sell(INS01)=advisory only(R33 무정보). 경보방향=부실신호(지각/감사)",
    n_net_buy_safe=n_safe, n_neutral=n_neutral, n_no_insider_data=n_nodata, n_net_sell_advisory=n_ns_adv,
    per_holding=lapply(seq_len(nrow(tw)), function(i){ r<-tw[i]
      list(ticker=r$Ticker, name=ifelse(is.na(r$Name),NA,r$Name), weight=r$Weight,
           ins02_net_buy_breadth=if(is.na(r$INS02_OffBuyBreadth6m))NA else round(r$INS02_OffBuyBreadth6m,3),
           ins01_net_sell_advisory=if(is.na(r$INS01_OffNetBuyIntensity3m))NA else round(r$INS01_OffNetBuyIntensity3m,3),
           ins03_recency=if(is.na(r$INS03_OffNetBuyRecency))NA else round(r$INS03_OffNetBuyRecency,3),
           tripwire=r$tripwire) })),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(res, file.path(OUT,"r34_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
saveRDS(list(HELD=HELD, DR_P=DR_P, DR_R=DR_R, DR_L=DR_L, tw=tw, res=res), file.path(OUT,"_r34_objects.rds"))
## 차트용 held monthly cohort series
gc_out <- HELD[, .(coh_flag=mean(Ret_1m[nb_flag==1L],na.rm=TRUE), coh_nonflag=mean(Ret_1m[nb_flag==0L],na.rm=TRUE),
                   nf=sum(nb_flag==1L)), by=hold_ym][nf>0][order(hold_ym)]
write_parquet(gc_out, file.path(OUT,"r34_cohort_series.parquet"))
wf("\nR34_DONE | derisk primary gap_t=%+.2f (fwd flag %+.4f vs %+.4f) downside flag=%+.4f vs %+.4f tail flag=%.3f vs %.3f | lag1 gap_t=%+.2f | wiring safe=%d neutral=%d",
   DR_P$gap_ret_t, DR_P$mean_fwd_flag, DR_P$mean_fwd_nonflag, DR_P$downside_flag, DR_P$downside_nonflag, DR_P$tail_hit_flag, DR_P$tail_hit_nonflag, DR_L$gap_ret_t, n_safe, n_neutral)
cat("[SAVED]", file.path(OUT,"r34_results.json"), "\n")
