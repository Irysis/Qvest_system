# =============================================================================
# r5_te_floor.R
#  (A) span test 순환성 제거 (Q01 tier 를 X_QUAL 없이 / D03 tier 에 명시 저변동항 추가)
#  (B) 구조적 추적오차(TE) 하한 — "벤치에 담을 수 없는 tier 가 있다"의 계량화
#  (C) cap-tier 분해 (MEGA/MID/SMALL · dual-basis)
#  (D) arm 별 실현 TE/β (계약 canonical_screen_bt 경유)
#  ★비중 제안 아님 — (B)의 보유집합은 하한을 유효하게 만들기 위한 argmin 이며 산출하지 않는다.
#   metric_type = risk_estimate / canonical_screen
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r5] ",fmt,"\n"),...))

E   <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT,"factor_returns.parquet"))); FR[,Date:=as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT,"residuals_panel.parquet"))); RES[,Date:=as.Date(Date)]
AS  <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
m2  <- readRDS(file.path(OUT,"r2_meta.rds")); fac_names <- m2$fac_names; STY <- m2$sty
say("입력: E %d행/%d월 | FR %d월 | RES %d행 | AS %d행/%d월",
    nrow(E), uniqueN(E$Date), nrow(FR), nrow(RES), nrow(AS), uniqueN(AS$Date))

nwt <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<10) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag){ s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }
  if(s<=0) return(NA_real_); m/sqrt(s/n) }

# ── (A) 순환성 제거 span ─────────────────────────────────────────────────────
P <- merge(AS[, .(Date,Ticker,D03_EWMA_pct,Q01_EB_pct,excl_q01_q20,rk_m01)],
           E[, .(Date,Ticker,Ret_1m,Size,X_D03)], by=c("Date","Ticker"))
qtag <- function(p) cut(p, breaks=c(-Inf,.2,.4,.6,.8,Inf), labels=paste0("Q",1:5))
P[, d03_q := qtag(D03_EWMA_pct)][, q01_q := qtag(Q01_EB_pct)]
mk <- function(col){ z<-P[!is.na(get(col)) & is.finite(Ret_1m)]
  merge(z[get(col)=="Q5", .(hi=mean(Ret_1m)), by=Date], z[get(col)=="Q1", .(lo=mean(Ret_1m)), by=Date], by="Date")[, .(Date, spread=hi-lo)] }
sp_d03 <- mk("d03_q"); sp_q01 <- mk("q01_q")
span <- function(y_dt, xn, lab){
  m <- merge(y_dt, FR, by="Date"); X <- as.matrix(m[, ..xn]); X[!is.finite(X)] <- 0
  X <- X[, apply(X,2,stats::sd)>1e-10, drop=FALSE]
  f <- stats::lm(m$spread ~ X); s <- summary(f); e <- stats::residuals(f)
  say("  %-40s R2=%.3f 잔차연변동 %.4f (총 %.4f) 미설명 %.1f%%",
      lab, s$r.squared, stats::sd(e)*sqrt(12), stats::sd(m$spread)*sqrt(12), 100*(1-s$r.squared))
  list(r2=s$r.squared, resid=stats::sd(e)*sqrt(12), tot=stats::sd(m$spread)*sqrt(12), e=e, dates=m$Date)
}
say("[A] 순환성 제거 span test")
noqual <- setdiff(fac_names, "X_QUAL"); noivol <- setdiff(fac_names, "X_IVOL")
a1 <- span(sp_q01, fac_names, "Q01 Q5-Q1 ~ 전 팩터 (X_QUAL=Q01 포함 → 순환)")
a2 <- span(sp_q01, noqual,   "Q01 Q5-Q1 ~ X_QUAL 제거 (비순환)")
a3 <- span(sp_d03, fac_names,"D03 Q5-Q1 ~ 전 팩터 (X_IVOL 포함)")
a4 <- span(sp_d03, noivol,   "D03 Q5-Q1 ~ X_IVOL 제거")
say("  ⇒ 순환항 제거 시 설명력: Q01 %.3f→%.3f (Δ%.3f) | D03 %.3f→%.3f (Δ%.3f)",
    a1$r2,a2$r2,a2$r2-a1$r2, a3$r2,a4$r2,a4$r2-a3$r2)

# ── (B) 구조적 TE 하한 ───────────────────────────────────────────────────────
# TE^2 = a'BΩB'a + Σ a_i^2 d_i  (BΩB' PSD) ⇒ TE^2 >= Σ a_i^2 d_i.
# 보유 25종·상한 0.20 이면 미보유 i 는 a_i = -w_b,i, 보유 i 는 |a_i| >= max(0, w_b,i-0.20).
# 하한을 최소화하는 보유집합(=하한이 유효하려면 최소값을 써야 함)을 정렬로 선택.
say("[B] 구조적 TE 하한 — 벤치 cap-w 대비 (top-25, 상한 0.20, long-only, Σw=1)")
d_at <- function(asof){
  lo <- seq(asof, by="-60 months", length.out=2)[2]
  ds <- RES[Date<=asof & Date>lo][, .(n=.N, sv=stats::var(resid)), by=Ticker][n>=24]
  pri <- median(ds$sv, na.rm=TRUE); ds[, w:=n/(n+24)][, spec_var := w*sv+(1-w)*pri]
  list(ds=ds[, .(Ticker, spec_var)], prior=pri)
}
eval_dates <- sort(unique(E$Date)); eval_dates <- eval_dates[eval_dates >= as.Date("2009-01-01") &
                                                            eval_dates <= as.Date("2026-06-30")]
res <- vector("list", length(eval_dates))
for (i in seq_along(eval_dates)) {
  d <- eval_dates[i]
  U <- E[Date==d & is.finite(Size) & Size>0, .(Ticker, Size)]
  if (nrow(U) < 50) next
  dd <- d_at(d); U <- merge(U, dd$ds, by="Ticker", all.x=TRUE)
  U[!is.finite(spec_var), spec_var := dd$prior]
  U[, wb := Size/sum(Size)]
  U[, cost_unheld := wb^2 * spec_var]
  U[, cost_held   := pmax(0, wb-0.20)^2 * spec_var]
  U[, gain := cost_unheld - cost_held]        # 보유 시 절약분
  setorder(U, -gain)
  hold <- 1:min(25L, nrow(U))
  te2 <- sum(U$cost_held[hold]) + sum(U$cost_unheld[-hold])
  cover <- sum(pmin(U[order(-wb)]$wb[1:min(25,nrow(U))], 0.20))
  res[[i]] <- data.table(Date=d, n_uni=nrow(U), te_floor_ann=sqrt(te2*12),
                         bm_cover_max=cover, unheldable=1-cover,
                         w_max=max(U$wb), hhi_bm=sum(U$wb^2),
                         n_eff_bm=1/sum(U$wb^2))
}
TF <- rbindlist(res)
say("  TE 하한(연율) 중앙 %.4f  [%.4f, %.4f] | 최근(2026-06) %.4f",
    median(TF$te_floor_ann), min(TF$te_floor_ann), max(TF$te_floor_ann),
    TF[Date==max(Date)]$te_floor_ann)
say("  25종·상한0.20 으로 담을 수 있는 벤치 비중 최대 중앙 %.3f ⇒ 구조적 미보유 %.3f (최근 %.3f)",
    median(TF$bm_cover_max), median(TF$unheldable), TF[Date==max(Date)]$unheldable)
say("  벤치 최대 단일비중 중앙 %.3f (최근 %.3f) | 벤치 유효종목수 중앙 %.1f",
    median(TF$w_max), TF[Date==max(Date)]$w_max, median(TF$n_eff_bm))
say("  ★상한 0.20 이 구속되는 월 비율 = %.3f (벤치 최대비중 > 0.20 인 월)", mean(TF$w_max > 0.20))

# cap-tier 별 벤치 비중
tier_tab <- rbindlist(lapply(eval_dates, function(d){
  U <- E[Date==d & is.finite(Size) & Size>0, .(Ticker, Size)]; if(nrow(U)<50) return(NULL)
  setorder(U,-Size); U[, rk := .I][, wb := Size/sum(Size)]
  U[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","SMALL"))]
  U[, .(bm_w=sum(wb), n=.N), by=tier][, Date:=d]
}))
say("  벤치 cap-tier 비중(월 중앙): %s",
    paste(tier_tab[, .(m=round(median(bm_w),4)), by=tier][order(-m)][, sprintf("%s %.3f", tier, m)], collapse=" | "))

# ── (D) arm 실현 TE / β (계약 경유) ─────────────────────────────────────────
say("[D] arm 실현 위험지표 — canonical_screen_bt (계약)")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
FW <- readRDS("stage_artifacts/WT_D20260808_001/fwd_cache.rds")
arms <- list(base = AS[, .(Date,Ticker,score)],
             q01f = AS[!is.na(score_q01filtered), .(Date,Ticker,score=score_q01filtered)])
armres <- list()
for (nm in names(arms)) {
  r <- tryCatch(canonical_screen_bt(arms[[nm]], FW$returns_dt, FW$bench_dt, top_n=25L,
                 cost_bps_oneway=15, liq_dt=FW$liq_dt, liq_min=2e8,
                 run_id=paste0("wt001_risk_",nm), strategy_id=paste0("arm_",nm),
                 diag_dual_basis=FALSE), error=function(e){say("  %s 실패: %s", nm, conditionMessage(e)); NULL})
  if (is.null(r)) next
  bc <- as.data.table(r$benchmark_compare)
  g <- function(k) { v <- bc[metric_name==k]; if(!nrow(v)) NA_real_ else as.numeric(v$active_value[1]) }
  gs <- function(k){ v <- bc[metric_name==k]; if(!nrow(v)) NA_real_ else as.numeric(v$strategy_value[1]) }
  armres[[nm]] <- list(TE=g("Tracking_Error"), IR=g("Information_Ratio"),
                       beta=gs("Beta_to_Benchmark"), port_t=g("Portfolio_Alpha_t_NW_lag3"),
                       alpha_ann=g("Alpha_Annualized"), n=nrow(as.data.table(r$period_returns)),
                       up=gs("Up_Capture"), dn=gs("Down_Capture"), cor=gs("Correlation"))
  say("  arm %-5s n=%d | TE %.4f | β %.3f | IR %.3f | PORT_t %.3f | 상승포착 %.3f 하락포착 %.3f",
      nm, armres[[nm]]$n, armres[[nm]]$TE, armres[[nm]]$beta, armres[[nm]]$IR,
      armres[[nm]]$port_t, armres[[nm]]$up, armres[[nm]]$dn)
}
if (length(armres) >= 1) {
  tef <- median(TF$te_floor_ann)
  for (nm in names(armres)) say("  ⇒ arm %s 실현 TE %.4f / 구조하한 %.4f = %.2f배 (하한이 예산의 %.1f%%)",
      nm, armres[[nm]]$TE, tef, armres[[nm]]$TE/tef, 100*tef/armres[[nm]]$TE)
}

saveRDS(list(span_nocirc=list(q01_full=a1,q01_noqual=a2,d03_full=a3,d03_noivol=a4),
             TF=TF, tier_tab=tier_tab, armres=armres),
        file.path(OUT,"r5_te.rds"))
write_parquet(TF, file.path(OUT,"te_floor_series.parquet"))
say("저장 완료")
