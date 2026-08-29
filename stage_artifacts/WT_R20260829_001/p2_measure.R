## p2_measure.R — WT-R20260829_001 Phase 2: 독립 2-way 정렬 실측 + 사전등록 검정 2종
## 논문 사양(CJL1996 Section III.A, p.12): 매월 초 과거 6개월 수익률 3등분 × 독립적으로
##   최근 이익 서프라이즈(SUE) 3등분 → 9셀, 셀 내 EW.
## 판정 권위 = canonical_screen_bt (metric_type="canonical_screen"). 자체합성 금지.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(sandwich); library(lmtest)})
setDTthreads(2)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/no_signal_control.R"))
`%||%` <- function(a,b) if (is.null(a)) b else a

OUT <- "stage_artifacts/WT_R20260829_001"
TOP_N <- 25L; COST <- 15; LIQ_MIN <- 2e8
NQ <- 3L   # CJL1996 원문값 — 3분위 독립 정렬

FW    <- as.data.table(read_parquet(file.path(OUT,"panel_factors.parquet")))
RET   <- as.data.table(read_parquet(file.path(OUT,"panel_returns.parquet")))
BENCH <- as.data.table(read_parquet(file.path(OUT,"panel_bench.parquet")))
LIQ   <- as.data.table(read_parquet(file.path(OUT,"panel_liq.parquet")))
FW[, Date := as.Date(Date)]; RET[, Date := as.Date(Date)]
BENCH[, Date := as.Date(Date)]; LIQ[, Date := as.Date(Date)]
SIZE_DT <- FW[is.finite(Size), .(Date,Ticker,Size)]

.nwt <- function(x, lag=3L){ x <- x[is.finite(x)]; if(length(x) < 12L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,3]) }
.nwse <- function(x, lag=3L){ x <- x[is.finite(x)]; if(length(x) < 12L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,2]) }

## ── 1. 자격 유니버스 + 독립 2-way 정렬 ──────────────────────────────────────
## 유동성 규약은 canonical_screen_bt 와 동일(is.na(adv) 통과) — 검정과 포트가 같은 모집단
E <- FW[is.finite(M02_Mom_6_1) & is.finite(C01_SUE) & (is.na(adv) | adv >= LIQ_MIN)]
E[, n_m := .N, by=Date]
E <- E[n_m >= 30L]
E[, pm := (frank(M02_Mom_6_1, ties.method="average") - 0.5)/.N, by=Date]
E[, ps := (frank(C01_SUE,      ties.method="average") - 0.5)/.N, by=Date]
E[, tm := pmin(NQ, floor(pm*NQ)+1L)]
E[, ts := pmin(NQ, floor(ps*NQ)+1L)]

## K200-only breakpoint 변형 (CJL1996 NYSE-only breakpoint 의 KR 대응 — 강건성)
bpk <- E[, {
  vm <- M02_Mom_6_1[K200==1]; vs <- C01_SUE[K200==1]
  if (length(vm) < 30L) vm <- M02_Mom_6_1
  if (length(vs) < 30L) vs <- C01_SUE
  qm <- as.numeric(quantile(vm, c(1/3,2/3), na.rm=TRUE))
  qs <- as.numeric(quantile(vs, c(1/3,2/3), na.rm=TRUE))
  .(m1=qm[1], m2=qm[2], s1=qs[1], s2=qs[2])
}, by=Date]
E <- merge(E, bpk, by="Date")
E[, tm_k := 1L + as.integer(M02_Mom_6_1 > m1) + as.integer(M02_Mom_6_1 > m2)]
E[, ts_k := 1L + as.integer(C01_SUE      > s1) + as.integer(C01_SUE      > s2)]
E[, c("m1","m2","s1","s2") := NULL]

EM <- merge(E, RET, by=c("Date","Ticker"))    # forward 1M (t → t+1)
cat(sprintf("[p2] eligible %d행 / %d월 (%s~%s) | 월 중앙 %d종목 | 수익매칭 %d행\n",
    nrow(E), uniqueN(E$Date), as.character(min(E$Date)), as.character(max(E$Date)),
    as.integer(median(E[,.N,by=Date]$N)), nrow(EM)))

cellpop <- E[, .N, by=.(Date,tm,ts)]
jt <- cellpop[tm==NQ & ts==NQ]
cat(sprintf("[p2] joint-top(3,3) 셀 인구: min=%d p10=%d 중앙=%d max=%d (월 %d개)\n",
    min(jt$N), as.integer(quantile(jt$N,.1)), as.integer(median(jt$N)), max(jt$N), nrow(jt)))
fwrite(cellpop, file.path(OUT,"cell_population.csv"))

## ── 2. 사전등록 검정 1급 — 이익 축(SUE 3분위) 통제 후 가격모멘텀 스프레드 ──────
cellret <- EM[, .(r = mean(Ret_1m, na.rm=TRUE), n=.N), by=.(Date,tm,ts)]
MIN_CELL <- 5L
spread_layer <- function(cr, ctrl, targ){
  hi <- cr[cr[[targ]]==NQ]; lo <- cr[cr[[targ]]==1L]
  h2 <- hi[, .(Date, L=get(ctrl), r_hi=r, n_hi=n)]
  l2 <- lo[, .(Date, L=get(ctrl), r_lo=r, n_lo=n)]
  m <- merge(h2, l2, by=c("Date","L"))
  m <- m[n_hi >= MIN_CELL & n_lo >= MIN_CELL]
  m[, sp := r_hi - r_lo][]
}
T1 <- spread_layer(cellret, "ts", "tm")      # SUE 층 고정 → 가격 스프레드 (1급)
T2 <- spread_layer(cellret, "tm", "ts")      # 가격 층 고정 → SUE 스프레드 (역방향)

summ_test <- function(D, label){
  per <- D[, .(n_months=.N, mean_m=mean(sp), sd_m=sd(sp),
               nw_t=.nwt(sp), nw_se=.nwse(sp), ann=12*mean(sp)), by=L]
  setnames(per, "L", "control_layer")
  setorder(per, control_layer)
  avg <- D[, .(sp=mean(sp)), by=Date]
  list(label=label, per_layer=per,
       avg=list(n_months=nrow(avg), mean_m=mean(avg$sp), sd_m=sd(avg$sp),
                ann=12*mean(avg$sp), nw_t=.nwt(avg$sp), nw_se=.nwse(avg$sp)),
       avg_series=avg)
}
R_T1 <- summ_test(T1, "PRIMARY_price_spread_given_SUE_layer")
R_T2 <- summ_test(T2, "REVERSE_SUE_spread_given_price_layer")
cat("\n===== 검정1(1급): SUE 층 통제 후 가격모멘텀 3분위 스프레드 =====\n"); print(R_T1$per_layer)
cat(sprintf("  [층평균] n=%d · %.4f%%/월 · 연 %.2f%% · NW-t %.3f\n",
    R_T1$avg$n_months, 100*R_T1$avg$mean_m, 100*R_T1$avg$ann, R_T1$avg$nw_t))
cat("\n===== 검정2(역방향): 가격 층 통제 후 SUE 3분위 스프레드 =====\n"); print(R_T2$per_layer)
cat(sprintf("  [층평균] n=%d · %.4f%%/월 · 연 %.2f%% · NW-t %.3f\n",
    R_T2$avg$n_months, 100*R_T2$avg$mean_m, 100*R_T2$avg$ann, R_T2$avg$nw_t))

## 크기산술 관문 — CJL1996 Table 6 panel B(미국): 6개월 3.1% → 월 0.5167%
IMPLIED_M <- 0.031/6
pw <- function(res, implied){
  se <- res$avg$nw_se; mde80 <- 2.8016*se; ratio <- implied/mde80
  list(implied_monthly=implied, nw_se=se, mde80=mde80, ratio=ratio,
       expected_t=ratio*2.8016, power=pnorm(ratio*2.8016 - 1.96)) }
PW1 <- pw(R_T1, IMPLIED_M); PW2 <- pw(R_T2, 0.043/6)
cat(sprintf("\n[크기산술] T1: MDE80=%.4f%%/월 · ratio=%.4f · 기대t=%.3f · 검정력=%.1f%%\n",
    100*PW1$mde80, PW1$ratio, PW1$expected_t, 100*PW1$power))
cat(sprintf("[크기산술] T2: MDE80=%.4f%%/월 · ratio=%.4f · 기대t=%.3f · 검정력=%.1f%%\n",
    100*PW2$mde80, PW2$ratio, PW2$expected_t, 100*PW2$power))

## Fama-MacBeth (CJL1996 Section III.B, p.14): 백분위-랭크 설명변수 + size 통제
FM <- EM[is.finite(Size) & Size > 0]
FM[, lsz := log(Size)]
fmb <- FM[, { f <- try(lm(Ret_1m ~ pm + ps + lsz), silent=TRUE)
              if (inherits(f,"try-error")) NULL else as.list(coef(f)) }, by=Date]
FMB <- list(n_months=nrow(fmb),
  b_pm=mean(fmb$pm), t_pm=.nwt(fmb$pm), b_ps=mean(fmb$ps), t_ps=.nwt(fmb$ps),
  b_lsz=mean(fmb$lsz), t_lsz=.nwt(fmb$lsz))
cat(sprintf("\n[Fama-MacBeth] n=%d · b(price-rank)=%.4f t=%.3f · b(SUE-rank)=%.4f t=%.3f · b(logSize)=%.5f t=%.3f\n",
    FMB$n_months, FMB$b_pm, FMB$t_pm, FMB$b_ps, FMB$t_ps, FMB$b_lsz, FMB$t_lsz))

## ── 3. 포트폴리오 arm 실측 (canonical_screen_bt = 권위) ──────────────────────
E[, score_joint   := fifelse(tm==NQ & ts==NQ, pmin(pm,ps), NA_real_)]
E[, score_joint_k := fifelse(tm_k==NQ & ts_k==NQ, pmin(pm,ps), NA_real_)]
E[, score_min_all := pmin(pm, ps)]
E[, score_mom := pm]
E[, score_sue := ps]
E[, score_zsum := M02_Mom_6_1 + C01_SUE]

ARMS <- list(
  joint2way        = E[is.finite(score_joint),   .(Date,Ticker,score=score_joint)],
  joint2way_k200bp = E[is.finite(score_joint_k), .(Date,Ticker,score=score_joint_k)],
  mom_only         = E[, .(Date,Ticker,score=score_mom)],
  sue_only         = E[, .(Date,Ticker,score=score_sue)],
  zsum_control     = E[, .(Date,Ticker,score=score_zsum)]
)
CS <- list()
for (nm in names(ARMS)) {
  CS[[nm]] <- tryCatch(canonical_screen_bt(ARMS[[nm]], RET, BENCH, top_n=TOP_N,
      cost_bps_oneway=COST, liq_dt=LIQ, liq_min=LIQ_MIN, size_dt=SIZE_DT,
      run_id="WT-R20260829_001", strategy_id=nm, diag_dual_basis=TRUE),
      error=function(e){cat("[ERR]",nm,conditionMessage(e),"\n"); NULL})
  x <- CS[[nm]]
  if (!is.null(x))
    cat(sprintf("[arm] %-18s n=%3d PORT_t=%7.3f IR=%7.3f alpha_ann=%7.3f%% TO=%.2f\n", nm,
      x$n_months %||% NA, x$portfolio_alpha_t_nw_lag3 %||% NA_real_,
      x$information_ratio %||% NA_real_, 100*(x$alpha_annual %||% NA_real_),
      x$turnover_annual %||% NA_real_))
}
saveRDS(CS, file.path(OUT,"canonical_arms.rds"))
saveRDS(list(T1=R_T1,T2=R_T2,PW1=PW1,PW2=PW2,FMB=FMB), file.path(OUT,"tests_stage1.rds"))
write_parquet(E[, .(Date,Ticker,pm,ps,tm,ts,tm_k,ts_k,score_joint,score_min_all,score_mom,score_sue)],
              file.path(OUT,"alpha_scores.parquet"))
cat("[p2] DONE stage1\n")
