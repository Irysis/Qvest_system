## run_r36_insider_coverage.R — WT-D20260715_005 / FQ-050 / R36
## insider net-buy tripwire coverage 확장 (R33/R34 next_probe P1 소비).
##   확립된 양성: net-buy breadth 클러스터(INS02 z>=+1.0) = monitoring SAFE tripwire 유효
##   (R33 universe gap t+3.36 / size-neutral t+5.22 / large-cap tier t+2.57; R34 per-holding t+2.50).
##   ★문제: flag 희소(현 북 2.45종/월) → 대형 tier 표본 얇음. 3형태로 표본·강건성 강화 시도.
##
## 3형태 (사전등록 · 고정 config · sweep 아님 · chain):
##   Form1 정밀: INS02>=+1.0 AND INS03>=+0.5 (breadth 상위 ∧ recency 최근) — 정밀도 vs 표본 trade-off
##   Form2 완화: INS02>=+0.5 (R33 +1.0 대비 완화) — 표본↑, SAFE 유지되는가 (정직 prior: 희석 가능)
##   Form3 연속: INS01_OffNetBuyIntensity3m 연속 z-노출 (binary 아님) — 월별 Spearman IC + top-cut
##   + R33 baseline(INS02>=+1.0) 동일 universe 프레임 재계산 = 직접 비교축.
##
## 각 형태: 배포 universe forward gap NW-t + 하방/변동성/급락(<-15%) + size tercile 분해(대형 tier
##   표본·t) + lag1 스트레스(동월누출 배제, C5) + placebo(월내 flag 셔플 순열, 집중-아티팩트 배제).
## 판정축 = SAFE(고수익·저하방·저급락) 유지/강화 + 대형 tier 표본 실제 강화 여부.
##
## §7b: base = production clean T-1 (alpha_scores_str1715_268m_cleanT1, production_parity_verified).
##   파생 저장 268m same-month vintage 재사용 금지. insider 패널 로컬 재사용(재빌드 X). DART API X.
## PIT (C5): 홀딩월 = clean T-1 결정(검증). insider flag = signal_date(월말 m)→홀딩월(m+1),
##   홀딩월 시작 전 데이터만. lag1 스트레스로 동월누출 실증 배제.
## 규율: 단일스레드 · arrow io(2). book_state/05_Production/outputs/ramp 무변경(stage_artifacts만).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2L),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
set.seed(20260715L)

OUT <- "stage_artifacts/WT_D20260715_005"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "_r36_run_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ym <- function(d) as.integer(format(as.Date(d),"%Y"))*100L+as.integer(format(as.Date(d),"%m"))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_); m<-lm(x~1)
  as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }

w("=== R36 insider net-buy tripwire coverage 확장 — WT-D20260715_005 / FQ-050 ===")

## ── vintage pin (R9/R33/R34 pin 재사용 = 부모 라운드 정합) ──────────────────────
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
wf("[vintage] rawdata pin=%s (mtime=%s)", RAW_P, PIN_MTIME)

## ── 1. base = production clean T-1 (§7b) ──────────────────────────────────────
CLEAN_P <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"
clean <- as.data.table(read_parquet(CLEAN_P)); clean[, Date := as.Date(Date)]; clean[, hold_ym := ym(Date)]
stopifnot(all(c("Date","Ticker","score_eff","Ret_1m") %in% names(clean)))
clean_meta <- fromJSON("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1_meta.json")
wf("[base] clean T-1: rows=%d months=%d range=%s~%s parity_PORT_t=%.3f", nrow(clean), uniqueN(clean$Date),
   as.character(min(clean$Date)), as.character(max(clean$Date)), clean_meta$parity$screen_cap_w_top25$port_t_nw_lag3)

## ── 2. size(t-1)/cap-w 벤치 = pinned rawdata, 홀딩월 정렬 (R33 sizeneutral 배관) ──
raw <- as.data.table(read_parquet(RAW_P, col_select=c("Date","Ticker","Close","K200","KQ150","Size","Vol")))
raw[,Date:=as.Date(Date)]; raw <- raw[!is.na(Close)&Close>0]; raw[,yq:=ym(Date)]
me <- merge(raw, raw[,.(me=max(Date)),by=yq], by="yq")[Date==me]; setorder(me,Ticker,yq)
me[,`:=`(Close_prev=shift(Close), yq_prev=shift(yq), Size_prev=shift(Size), Vol_prev=shift(Vol),
         uni_prev=shift(K200==TRUE|KQ150==TRUE)),by=Ticker]
me[,cons:=(ymshift(yq_prev,1L)==yq)]; me[,ret_hold:=Close/Close_prev-1]
mh <- me[cons==TRUE & uni_prev==TRUE & !is.na(Size_prev) & Size_prev>0]
mh[, adv_prev := Vol_prev*Close_prev]
sz  <- mh[, .(hold_ym=yq, Ticker, Size=Size_prev, adv=adv_prev)]
capwb <- mh[!is.na(ret_hold), .(BM_Ret=weighted.mean(ret_hold, w=Size_prev, na.rm=TRUE)), by=.(hold_ym=yq)]
rm(raw,me); invisible(gc())
wf("[align] size(t-1) rows=%d | cap-w bench months=%d", nrow(sz), nrow(capwb))

## ── 3. insider 패널 (로컬 재사용) + 홀딩월 정렬 (signal m→hold m+1, C5) ─────────
ins <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet"))
ins[, signal_date := as.Date(signal_date)]; ins[, hold_ym := ymshift(ym(signal_date),1L)]
insw <- dcast(ins, hold_ym+security_id~factor_id, value.var="z"); setnames(insw,"security_id","Ticker")
INS_COV <- range(insw$hold_ym)
wf("[insider] rows=%d hold_ym cov=%d~%d", nrow(insw), INS_COV[1], INS_COV[2])

## ── 4. universe = clean ∩ size(t-1) ∩ insider-covered (R33 sizeneutral 프레임) ──
uni <- clean[, .(hold_ym, Ticker, Ret_1m)]
uni <- merge(uni, sz, by=c("hold_ym","Ticker"))          # size(t-1) 부착
uni <- merge(uni, capwb, by="hold_ym", all.x=TRUE); uni[, exc := Ret_1m - BM_Ret]
uni <- uni[hold_ym>=INS_COV[1] & hold_ym<=INS_COV[2] & !is.na(Ret_1m)]
uni <- merge(uni, insw[, .(hold_ym, Ticker, INS01_OffNetBuyIntensity3m, INS02_OffBuyBreadth6m, INS03_OffNetBuyRecency)],
             by=c("hold_ym","Ticker"), all.x=TRUE)
uni[, has_ins := as.integer(!is.na(INS02_OffBuyBreadth6m) | !is.na(INS01_OffNetBuyIntensity3m))]
## size tercile (배포 universe 내) + large-cap 명시 tier
uni[, sz_tercile := as.character(cut(frank(Size, ties.method="first")/.N, breaks=c(0,1/3,2/3,1),
     labels=c("small","mid","large"))), by=hold_ym]
uni[, cap_rank := frank(-Size, ties.method="first"), by=hold_ym]
uni[, megatier := fifelse(cap_rank<=30L, "TOP30", "REST")]   # 배포 대형 tier ~ 상위 30
wf("[uni] rows=%d months=%d | insider-covered=%d | tercile dist small/mid/large=%d/%d/%d",
   nrow(uni), uniqueN(uni$hold_ym), uni[has_ins==1L,.N],
   uni[sz_tercile=="small",.N], uni[sz_tercile=="mid",.N], uni[sz_tercile=="large",.N])

## ── helper: binary flag SAFE 통계 ──────────────────────────────────────────────
safe_stats <- function(DT, flagcol){
  DT <- copy(DT); DT[, f := as.integer(get(flagcol))]; DT[is.na(f), f := 0L]
  ff <- DT[f==1L]; nn <- DT[f==0L]
  g <- DT[, .(m_f=mean(Ret_1m[f==1L],na.rm=TRUE), m_n=mean(Ret_1m[f==0L],na.rm=TRUE),
              e_f=mean(exc[f==1L],na.rm=TRUE), e_n=mean(exc[f==0L],na.rm=TRUE),
              nf=sum(f==1L), nn=sum(f==0L)), by=hold_ym][nf>0 & nn>0]
  gap_ret <- g$m_f - g$m_n; gap_exc <- g$e_f - g$e_n
  list(n_flag_obs=nrow(ff), coverage_months=nrow(g), avg_flag_per_month=mean(g$nf),
    fwd_flag=mean(ff$Ret_1m,na.rm=TRUE), fwd_nonflag=mean(nn$Ret_1m,na.rm=TRUE),
    gap_ret_ann=mean(gap_ret,na.rm=TRUE)*12, gap_ret_t=nwt(gap_ret),
    gap_exc_ann=mean(gap_exc,na.rm=TRUE)*12, gap_exc_t=nwt(gap_exc),
    downside_flag=mean(ff$Ret_1m[ff$Ret_1m<0],na.rm=TRUE), downside_nonflag=mean(nn$Ret_1m[nn$Ret_1m<0],na.rm=TRUE),
    vol_flag=sd(ff$Ret_1m,na.rm=TRUE), vol_nonflag=sd(nn$Ret_1m,na.rm=TRUE),
    tail_flag=mean(ff$Ret_1m< -0.15,na.rm=TRUE), tail_nonflag=mean(nn$Ret_1m< -0.15,na.rm=TRUE),
    gap_series=gap_ret)
}
## tier 분해: size tercile 별 gap
tier_gap <- function(DT, flagcol){
  DT <- copy(DT); DT[, f := as.integer(get(flagcol))]; DT[is.na(f), f:=0L]
  out <- DT[, .(gap=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L)), by=.(hold_ym,sz_tercile)][nf>0]
  s <- out[, .(gap_ann=mean(gap,na.rm=TRUE)*12, gap_t=nwt(gap), months=.N, avg_flag=mean(nf)), by=sz_tercile]
  ## large-cap (TOP30) 명시 tier
  outT <- DT[, .(gap=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L)), by=.(hold_ym,megatier)][nf>0]
  sT <- outT[, .(gap_ann=mean(gap,na.rm=TRUE)*12, gap_t=nwt(gap), months=.N, avg_flag=mean(nf), tot_flag=sum(nf)), by=megatier]
  list(tercile=s, top30=sT, n_flag_large_terc=DT[f==1L & sz_tercile=="large",.N], n_flag_top30=DT[f==1L & megatier=="TOP30",.N])
}
## lag1 스트레스: flag 을 홀딩월 +1 로 밀어(신호 2개월 전) SAFE 붕괴 여부
lag1_stress <- function(flagbuild_shift){
  d <- merge(uni[, .(hold_ym, Ticker, Ret_1m, exc)], flagbuild_shift, by=c("hold_ym","Ticker"), all.x=TRUE)
  d[, f := as.integer(!is.na(fl) & fl==1L)]
  g <- d[, .(m_f=mean(Ret_1m[f==1L],na.rm=TRUE), m_n=mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L), nn=sum(f==0L)), by=hold_ym][nf>0 & nn>0]
  list(gap_ret_t=nwt(g$m_f-g$m_n), gap_ret_ann=mean(g$m_f-g$m_n,na.rm=TRUE)*12,
       fwd_flag=mean(d[f==1L]$Ret_1m,na.rm=TRUE), fwd_nonflag=mean(d[f==0L]$Ret_1m,na.rm=TRUE), n_flag=d[f==1L,.N])
}
## placebo: 월내 flag 라벨 순열(동일 개수) → pooled monthly-gap ann 귀무분포. 집중-아티팩트 배제.
placebo_p <- function(DT, flagcol, obs_gap_ann, nperm=300L){
  DT <- copy(DT); DT[, f := as.integer(get(flagcol))]; DT[is.na(f), f:=0L]
  mo <- DT[, .(nf=sum(f), n=.N), by=hold_ym][nf>0 & nf<n]
  DTm <- DT[hold_ym %in% mo$hold_ym]
  ret_by <- split(DTm$Ret_1m, DTm$hold_ym); nf_by <- setNames(mo$nf, as.character(mo$hold_ym))
  perm_ann <- numeric(nperm)
  for(p in seq_len(nperm)){
    gaps <- vapply(names(ret_by), function(k){ r<-ret_by[[k]]; n<-length(r); kf<-nf_by[[k]]
      idx<-sample.int(n,kf); mean(r[idx])-mean(r[-idx]) }, numeric(1))
    perm_ann[p] <- mean(gaps,na.rm=TRUE)*12
  }
  list(p_value=mean(perm_ann>=obs_gap_ann), perm_mean=mean(perm_ann), perm_sd=sd(perm_ann), nperm=nperm)
}

## ── 5. 형태별 flag 정의 + 실측 ─────────────────────────────────────────────────
uni[, F0_base := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m>=1.0)]                    # R33 baseline
uni[, F1_prec := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m>=1.0 &
                            !is.na(INS03_OffNetBuyRecency) & INS03_OffNetBuyRecency>=0.5)]                   # 정밀
uni[, F2_relax := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m>=0.5)]                   # 완화

forms <- list(
  F0_base  = list(col="F0_base",  desc="R33 baseline: INS02 breadth z>=+1.0"),
  F1_prec  = list(col="F1_prec",  desc="Form1 정밀: INS02 z>=+1.0 AND INS03 recency z>=+0.5"),
  F2_relax = list(col="F2_relax", desc="Form2 완화: INS02 z>=+0.5")
)
RES <- list()
for(nm in names(forms)){
  fc <- forms[[nm]]$col
  S  <- safe_stats(uni, fc)
  TG <- tier_gap(uni, fc)
  PB <- placebo_p(uni, fc, S$gap_ret_ann, nperm=300L)
  ## lag1: flag 을 +1월 shift
  fbuild <- switch(nm,
    F0_base  = insw[!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=1.0, .(hold_ym=ymshift(hold_ym,1L),Ticker,fl=1L)],
    F1_prec  = insw[!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=1.0 & !is.na(INS03_OffNetBuyRecency)&INS03_OffNetBuyRecency>=0.5, .(hold_ym=ymshift(hold_ym,1L),Ticker,fl=1L)],
    F2_relax = insw[!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=0.5, .(hold_ym=ymshift(hold_ym,1L),Ticker,fl=1L)])
  L1 <- lag1_stress(fbuild)
  RES[[nm]] <- list(desc=fc, S=S, TG=TG, PB=PB, L1=L1)
  wf("\n[%s] %s", nm, forms[[nm]]$desc)
  wf("   coverage: flag_obs=%d months=%d avg/mo=%.1f | large-terc flags=%d TOP30 flags=%d",
     S$n_flag_obs, S$coverage_months, S$avg_flag_per_month, TG$n_flag_large_terc, TG$n_flag_top30)
  wf("   SAFE: fwd flag=%+.4f nonflag=%+.4f | gap_ann=%+.4f gap_t=%+.2f | placebo p=%.3f (perm ann=%+.4f)",
     S$fwd_flag, S$fwd_nonflag, S$gap_ret_ann, S$gap_ret_t, PB$p_value, PB$perm_mean)
  wf("   risk: downside flag=%+.4f nonflag=%+.4f | vol flag=%.4f nonflag=%.4f | tail(<-15%%) flag=%.3f nonflag=%.3f",
     S$downside_flag, S$downside_nonflag, S$vol_flag, S$vol_nonflag, S$tail_flag, S$tail_nonflag)
  wf("   tier gap (small/mid/large):")
  for(i in seq_len(nrow(TG$tercile))){ r<-TG$tercile[i]; wf("      %-6s gap_ann=%+.4f t=%+.2f avg_flag/mo=%.1f months=%d", r$sz_tercile, r$gap_ann, r$gap_t, r$avg_flag, r$months) }
  for(i in seq_len(nrow(TG$top30))){ r<-TG$top30[i]; wf("      %-6s gap_ann=%+.4f t=%+.2f tot_flag=%d months=%d", r$megatier, r$gap_ann, r$gap_t, r$tot_flag, r$months) }
  wf("   lag1 stress: gap_t=%+.2f gap_ann=%+.4f (fwd flag=%+.4f nonflag=%+.4f n_flag=%d)", L1$gap_ret_t, L1$gap_ret_ann, L1$fwd_flag, L1$fwd_nonflag, L1$n_flag)
}

## ── 6. Form3 연속 (INS01 z-노출) ────────────────────────────────────────────────
u3 <- uni[!is.na(INS01_OffNetBuyIntensity3m)]
## (a) 월별 Spearman IC (INS01 z → forward Ret_1m)
icb <- u3[, .(ic=suppressWarnings(cor(INS01_OffNetBuyIntensity3m, Ret_1m, method="spearman")), n=.N), by=hold_ym][n>=10 & is.finite(ic)]
ic_mean <- mean(icb$ic); ic_t <- nwt(icb$ic); icir <- ic_mean/sd(icb$ic)
## (b) INS01 top-cut(z>=+0.5, buy-intensity 高) SAFE (comparability + downside)
uni[, F3_cut := as.integer(!is.na(INS01_OffNetBuyIntensity3m) & INS01_OffNetBuyIntensity3m>=0.5)]
S3  <- safe_stats(uni, "F3_cut"); TG3 <- tier_gap(uni, "F3_cut"); PB3 <- placebo_p(uni, "F3_cut", S3$gap_ret_ann, 300L)
fb3 <- insw[!is.na(INS01_OffNetBuyIntensity3m)&INS01_OffNetBuyIntensity3m>=0.5, .(hold_ym=ymshift(hold_ym,1L),Ticker,fl=1L)]
L13 <- lag1_stress(fb3)
## (c) 연속 IC 의 lag1 (INS01 shift +1)
u3l <- merge(uni[, .(hold_ym, Ticker, Ret_1m)],
             insw[, .(hold_ym=ymshift(hold_ym,1L), Ticker, INS01L=INS01_OffNetBuyIntensity3m)], by=c("hold_ym","Ticker"))
u3l <- u3l[!is.na(INS01L)]
icbl <- u3l[, .(ic=suppressWarnings(cor(INS01L, Ret_1m, method="spearman")), n=.N), by=hold_ym][n>=10 & is.finite(ic)]
ic_t_lag1 <- nwt(icbl$ic)
RES[["F3_cont"]] <- list(desc="Form3 연속 INS01 z-노출",
  ic_mean=ic_mean, ic_t=ic_t, icir=icir, ic_months=nrow(icb), ic_t_lag1=ic_t_lag1,
  cut_S=S3, cut_TG=TG3, cut_PB=PB3, cut_L1=L13)
wf("\n[F3_cont] Form3 연속 INS01 z-노출")
wf("   Spearman IC: mean=%+.4f t=%+.2f ICIR=%+.2f months=%d | lag1 IC_t=%+.2f", ic_mean, ic_t, icir, nrow(icb), ic_t_lag1)
wf("   INS01>=+0.5 cut SAFE: flag_obs=%d gap_ann=%+.4f gap_t=%+.2f placebo p=%.3f | downside flag=%+.4f nonflag=%+.4f tail flag=%.3f nonflag=%.3f",
   S3$n_flag_obs, S3$gap_ret_ann, S3$gap_ret_t, PB3$p_value, S3$downside_flag, S3$downside_nonflag, S3$tail_flag, S3$tail_nonflag)
wf("   cut tier gap: large-terc flags=%d TOP30 flags=%d", TG3$n_flag_large_terc, TG3$n_flag_top30)
for(i in seq_len(nrow(TG3$tercile))){ r<-TG3$tercile[i]; wf("      %-6s gap_ann=%+.4f t=%+.2f avg_flag/mo=%.1f", r$sz_tercile, r$gap_ann, r$gap_t, r$avg_flag) }
for(i in seq_len(nrow(TG3$top30))){ r<-TG3$top30[i]; wf("      %-6s gap_ann=%+.4f t=%+.2f tot_flag=%d", r$megatier, r$gap_ann, r$gap_t, r$tot_flag) }
wf("   cut lag1: gap_t=%+.2f", L13$gap_ret_t)

## ── 7. 사전등록 해시 + 저장 ─────────────────────────────────────────────────────
PREREG <- list(mode="RAMP-adjacent alpha consumption (monitoring coverage 확장)", round="R36", fq="FQ-050", wt="WT-D20260715_005",
  parent="R33/R34 next_probe P1 (net-buy 클러스터 coverage 확장 — 표본·대형 tier 강건성)",
  base_source="production clean T-1 (alpha_scores_str1715_268m_cleanT1, production_parity_verified)",
  universe="clean ∩ size(t-1) ∩ insider-covered (R33 sizeneutral 프레임)",
  pit="clean T-1 홀딩월(검증) + insider signal(월말 m)→홀딩월(m+1), 홀딩월 시작 전 (C5) + lag1 스트레스",
  forms=list(
    F0_base="INS02_OffBuyBreadth6m z>=+1.0 (R33 baseline 비교축)",
    F1_prec="INS02 z>=+1.0 AND INS03_OffNetBuyRecency z>=+0.5 (정밀)",
    F2_relax="INS02 z>=+0.5 (완화 — 표본↑)",
    F3_cont="INS01_OffNetBuyIntensity3m 연속 Spearman IC + top-cut(z>=+0.5)"),
  measures=c("forward gap NW-lag3 t","downside/vol/tail(<-15%)","size tercile + TOP30 tier 분해","lag1 스트레스","placebo(월내 순열 300)"),
  decision_axis="SAFE(고수익·저하방·저급락) 유지/강화 + 대형 tier 표본 실제 강화. 자본 아님(monitoring 소비면).",
  honest_prior="임계 완화는 표본↑이나 신호 희석 가능 — 순 효과 실측. Form1 AND는 정밀↑ 표본↓ trade-off.",
  selection_type="chain (가설주도 고정 config · sweep 아님)", n_trials=4L,
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r36.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("\n[prereg] config_hash=%s selection_type=chain n_trials=4", PREREG$config_hash)

## 결과 직렬화 (gap_series 는 chart용 parquet 별도)
serialize_form <- function(r){
  base <- list(desc=r$desc)
  if(!is.null(r$S)){
    S<-r$S; base <- c(base, list(coverage=list(n_flag_obs=S$n_flag_obs, coverage_months=S$coverage_months, avg_flag_per_month=round(S$avg_flag_per_month,2),
        n_flag_large_terc=r$TG$n_flag_large_terc, n_flag_top30=r$TG$n_flag_top30),
      safe=list(fwd_flag=round(S$fwd_flag,5), fwd_nonflag=round(S$fwd_nonflag,5), gap_ret_ann=round(S$gap_ret_ann,5), gap_ret_t=round(S$gap_ret_t,3),
        gap_exc_t=round(S$gap_exc_t,3), downside_flag=round(S$downside_flag,5), downside_nonflag=round(S$downside_nonflag,5),
        vol_flag=round(S$vol_flag,5), vol_nonflag=round(S$vol_nonflag,5), tail_flag=round(S$tail_flag,4), tail_nonflag=round(S$tail_nonflag,4)),
      placebo=list(p_value=round(r$PB$p_value,4), perm_mean_ann=round(r$PB$perm_mean,5), perm_sd=round(r$PB$perm_sd,5), nperm=r$PB$nperm),
      tier=list(tercile=r$TG$tercile, top30=r$TG$top30),
      lag1=list(gap_ret_t=round(r$L1$gap_ret_t,3), gap_ret_ann=round(r$L1$gap_ret_ann,5), n_flag=r$L1$n_flag)))
  }
  base
}
out <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  base_parity=list(clean_parity_port_t=clean_meta$parity$screen_cap_w_top25$port_t_nw_lag3, note="§7b production_parity_verified"),
  universe_coverage=list(rows=nrow(uni), months=uniqueN(uni$hold_ym), insider_covered=uni[has_ins==1L,.N]),
  F0_base=serialize_form(RES$F0_base), F1_prec=serialize_form(RES$F1_prec), F2_relax=serialize_form(RES$F2_relax),
  F3_cont=list(desc="Form3 연속 INS01 z-노출",
    continuous_ic=list(ic_mean=round(ic_mean,5), ic_t=round(ic_t,3), icir=round(icir,3), ic_months=nrow(icb), ic_t_lag1=round(ic_t_lag1,3)),
    cut_safe=list(n_flag_obs=S3$n_flag_obs, gap_ret_ann=round(S3$gap_ret_ann,5), gap_ret_t=round(S3$gap_ret_t,3),
      placebo_p=round(PB3$p_value,4), downside_flag=round(S3$downside_flag,5), downside_nonflag=round(S3$downside_nonflag,5),
      vol_flag=round(S3$vol_flag,5), vol_nonflag=round(S3$vol_nonflag,5), tail_flag=round(S3$tail_flag,4), tail_nonflag=round(S3$tail_nonflag,4),
      n_flag_large_terc=TG3$n_flag_large_terc, n_flag_top30=TG3$n_flag_top30, tercile=TG3$tercile, top30=TG3$top30, lag1_t=round(L13$gap_ret_t,3))),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(out, file.path(OUT,"r36_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
saveRDS(list(uni=uni, RES=RES, icb=icb, out=out), file.path(OUT,"_r36_objects.rds"))

## chart용: 형태별 gap_series 시계열 + coverage 요약
gap_wide <- rbindlist(lapply(names(forms), function(nm){
  data.table(form=nm, hold_ym=seq_along(RES[[nm]]$S$gap_series), gap=RES[[nm]]$S$gap_series)
}), fill=TRUE)
write_parquet(gap_wide, file.path(OUT,"r36_gap_series.parquet"))
cov_summary <- rbindlist(list(
  data.table(form="F0_base",  n_flag=RES$F0_base$S$n_flag_obs, avg_mo=RES$F0_base$S$avg_flag_per_month, large_terc=RES$F0_base$TG$n_flag_large_terc, top30=RES$F0_base$TG$n_flag_top30, gap_t=RES$F0_base$S$gap_ret_t),
  data.table(form="F1_prec",  n_flag=RES$F1_prec$S$n_flag_obs, avg_mo=RES$F1_prec$S$avg_flag_per_month, large_terc=RES$F1_prec$TG$n_flag_large_terc, top30=RES$F1_prec$TG$n_flag_top30, gap_t=RES$F1_prec$S$gap_ret_t),
  data.table(form="F2_relax", n_flag=RES$F2_relax$S$n_flag_obs, avg_mo=RES$F2_relax$S$avg_flag_per_month, large_terc=RES$F2_relax$TG$n_flag_large_terc, top30=RES$F2_relax$TG$n_flag_top30, gap_t=RES$F2_relax$S$gap_ret_t),
  data.table(form="F3_cut",   n_flag=S3$n_flag_obs, avg_mo=S3$avg_flag_per_month, large_terc=TG3$n_flag_large_terc, top30=TG3$n_flag_top30, gap_t=S3$gap_ret_t)))
write_parquet(cov_summary, file.path(OUT,"r36_coverage_summary.parquet"))

wf("\nR36_DONE | F0 gap_t=%+.2f(top30 flags=%d) F1 gap_t=%+.2f(top30=%d) F2 gap_t=%+.2f(top30=%d) F3cut gap_t=%+.2f(top30=%d) | F3 IC_t=%+.2f",
   RES$F0_base$S$gap_ret_t, RES$F0_base$TG$n_flag_top30, RES$F1_prec$S$gap_ret_t, RES$F1_prec$TG$n_flag_top30,
   RES$F2_relax$S$gap_ret_t, RES$F2_relax$TG$n_flag_top30, S3$gap_ret_t, TG3$n_flag_top30, ic_t)
cat("[SAVED]", file.path(OUT,"r36_results.json"), "\n")
