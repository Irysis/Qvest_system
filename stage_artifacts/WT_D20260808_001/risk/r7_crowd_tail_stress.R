# =============================================================================
# r7_crowd_tail_stress.R — crowding / concentration / cap-tier / tail(EVT) /
#   stress / regime correlation (연속 조건화 — 분할 판정 없음)
#   metric_type = risk_estimate / canonical_screen / risk_validation
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r7] ",fmt,"\n"),...))

E   <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
AS  <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
FW  <- readRDS("stage_artifacts/WT_D20260808_001/fwd_cache.rds")
LIQ <- as.data.table(FW$liq_dt); LIQ[,Date:=as.Date(Date)]
BEN <- as.data.table(FW$bench_dt); BEN[,Date:=as.Date(Date)]
TB  <- as.data.table(read_parquet(file.path(OUT,"te_budget_panel.parquet"))); TB[,Date:=as.Date(Date)]
S3  <- readRDS(file.path(OUT,"r3_sigma.rds"))
AS_OF <- as.Date("2026-06-30")
say("입력 E %d행/%d월 | AS %d행 | BEN %d월 | TB %d행 (관측단위 월간)",
    nrow(E), uniqueN(E$Date), nrow(AS), nrow(BEN), nrow(TB))

nwt <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<10) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if(s<=0) return(NA_real_); m/sqrt(s/n) }

# ── 0. 벤치 상위 종목 (구조 확인) ───────────────────────────────────────────
U0 <- E[Date==AS_OF & is.finite(Size) & Size>0][order(-Size)]
U0[, wb := Size/sum(Size)]
raw_nm <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Name")))
raw_nm[, Date := as.Date(Date)]
nm <- unique(raw_nm[Date>=AS_OF-40 & Date<=AS_OF+10, .(Ticker, Name)], by="Ticker")
say("[벤치 구조 %s] 유니버스 %d종 | 상위 8:", as.character(AS_OF), nrow(U0))
print(merge(U0[1:8, .(Ticker, wb=round(wb,4))], nm, by="Ticker", all.x=TRUE)[order(-wb)])
say("  벤치 HHI %.4f | 유효종목수 %.1f | top10 비중 %.3f | 0.20 초과 종목 %d",
    sum(U0$wb^2), 1/sum(U0$wb^2), sum(U0$wb[1:10]), sum(U0$wb>0.20))

# ── 1. crowding_score_per_factor (Acadian 2026, 의무) ────────────────────────
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
fe <- rbindlist(list(
  AS[Date==AS_OF & is.finite(M01_PATHQ), .(Ticker, factor_name="M01_PATHQ", exposure=M01_PATHQ)],
  AS[Date==AS_OF & is.finite(Q01_EB),    .(Ticker, factor_name="Q01_EB",    exposure=Q01_EB)],
  AS[Date==AS_OF & is.finite(D03_EWMA),  .(Ticker, factor_name="D03_EWMA",  exposure=D03_EWMA)],
  AS[Date==AS_OF & is.finite(score),     .(Ticker, factor_name="ARM_base_M01PATHQ", exposure=score)],
  AS[Date==AS_OF & is.finite(score_q01filtered), .(Ticker, factor_name="ARM_q01filtered", exposure=score_q01filtered)]
))
say("crowding 입력 factor_exposures rows=%d, 팩터 %d개", nrow(fe), uniqueN(fe$factor_name))
bmt <- unique(RAW[Date<=AS_OF & Date>AS_OF-40 & (K200==TRUE|KQ150==TRUE)]$Ticker)
CR <- tryCatch(crowding_score_per_factor(fe, AS_OF, RAW, benchmark_tickers=bmt, top_n=25L),
               error=function(e){ say("crowding 실패: %s", conditionMessage(e)); NULL })
if (!is.null(CR)) print(CR[, lapply(.SD, function(z) if(is.numeric(z)) round(z,4) else z)])

# 3m delta (RAPID_INCREASE 판정)
d3 <- seq(AS_OF, by="-3 months", length.out=2)[2]
d3 <- max(AS$Date[AS$Date <= d3])
fe3 <- rbindlist(list(
  AS[Date==d3 & is.finite(score), .(Ticker, factor_name="ARM_base_M01PATHQ", exposure=score)],
  AS[Date==d3 & is.finite(score_q01filtered), .(Ticker, factor_name="ARM_q01filtered", exposure=score_q01filtered)],
  AS[Date==d3 & is.finite(D03_EWMA), .(Ticker, factor_name="D03_EWMA", exposure=D03_EWMA)]))
CR3 <- tryCatch(crowding_score_per_factor(fe3, d3, RAW, benchmark_tickers=bmt, top_n=25L), error=function(e) NULL)
if (!is.null(CR3) && !is.null(CR)) {
  mm <- merge(CR[, .(factor_name, cs_now=crowding_score)], CR3[, .(factor_name, cs_3m=crowding_score)], by="factor_name")
  mm[, delta_3m := cs_now - cs_3m]
  say("[crowding 3개월 변화 — >=0.15 이면 RAPID_INCREASE]"); print(mm[, lapply(.SD, function(z) if(is.numeric(z)) round(z,4) else z)])
}

# ── 2. 집중도: 섹터 HHI / 유효종목수 ────────────────────────────────────────
sc_at <- function(d, col){
  s <- merge(AS[Date==d & is.finite(get(col)), .(Ticker, sc=get(col))], LIQ[Date==d, .(Ticker, adv)], by="Ticker", all.x=TRUE)
  s <- s[is.na(adv)|adv>=2e8][order(-sc)]; head(s$Ticker, 25)
}
conc <- rbindlist(lapply(sort(unique(AS$Date)), function(d){
  h <- sc_at(d,"score"); if(length(h)<25) return(NULL)
  se <- E[Date==d & Ticker %in% h]
  st <- se[, .N, by=Sector][, sh := N/sum(N)]
  data.table(Date=d, sector_hhi=sum(st$sh^2), n_sector=nrow(st), n_eff=25)
}))
say("[집중도 · base arm top-25 EW] 섹터 HHI 중앙 %.4f (최근 %.4f) | 섹터수 중앙 %.1f | 유효종목수 25 (EW)",
    median(conc$sector_hhi), conc[Date==max(Date)]$sector_hhi, median(conc$n_sector))
say("  참고 벤치 섹터 HHI(시총가중, 최근) %.4f",
    { U0b <- merge(U0[, .(Ticker, wb)], E[Date==AS_OF, .(Ticker, Sector)], by="Ticker")
      sum(U0b[, .(w=sum(wb)), by=Sector]$w^2) })

# ── 3. cap-tier 분해 (v8.3.1 의무 필드) ─────────────────────────────────────
tier_rows <- rbindlist(lapply(sort(unique(TB$Date)), function(d){
  U <- E[Date==d & is.finite(Size) & Size>0][order(-Size)]
  U[, rk := .I][, wb := Size/sum(Size)]
  U[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","SMALL"))]
  h <- sc_at(d,"score"); if(length(h)<25) return(NULL)
  U[, w := fifelse(Ticker %in% h, 1/25, 0)][, a := w-wb]
  bmr <- BEN[Date==d]$BM_Ret; if(!length(bmr)) return(NULL)
  U[, act_contrib := w*(Ret_1m-bmr)]
  U[, .(tier=tier[1], hold_w=sum(w), bm_w=sum(wb), active_w=sum(a),
        act_ret=sum(act_contrib, na.rm=TRUE), abs_a=sum(abs(a))), by=tier][, Date:=d]
}))
tsum <- tier_rows[, .(hold_w=median(hold_w), bm_w=median(bm_w), active_w=median(active_w),
                      act_ret_sum=sum(act_ret), abs_a=median(abs_a)), by=tier]
tsum[, alpha_share := act_ret_sum/sum(act_ret_sum)]
tsum[, active_w_share := abs_a/sum(abs_a)]
say("[cap-tier 분해 · base arm]"); print(tsum[, lapply(.SD, function(z) if(is.numeric(z)) round(z,4) else z)])
# tier 별 필터축 within-tier rank-IC (signal_alive 판정 재료)
ic_tier <- rbindlist(lapply(sort(unique(AS$Date)), function(d){
  U <- E[Date==d & is.finite(Size) & Size>0][order(-Size)]; U[, rk:=.I]
  U[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","SMALL"))]
  z <- merge(U[, .(Ticker, tier, Ret_1m)], AS[Date==d, .(Ticker, Q01_EB, D03_EWMA)], by="Ticker")
  z <- z[is.finite(Ret_1m)]
  z[, .(ic_q01 = if(sum(is.finite(Q01_EB))>=8) cor(Q01_EB, Ret_1m, method="spearman", use="complete.obs") else NA_real_,
        ic_d03 = if(sum(is.finite(D03_EWMA))>=8) cor(D03_EWMA, Ret_1m, method="spearman", use="complete.obs") else NA_real_,
        n=.N), by=tier][, Date:=d]
}))
ics <- ic_tier[, .(ic_q01=mean(ic_q01,na.rm=TRUE), t_q01=nwt(ic_q01),
                   ic_d03=mean(ic_d03,na.rm=TRUE), t_d03=nwt(ic_d03), n_med=median(n)), by=tier]
say("[tier 내부 rank-IC (advisory — tier 분할이라 검정력 낮음, 계수만)]")
print(ics[, lapply(.SD, function(z) if(is.numeric(z)) round(z,4) else z)])

# ── 4. arm 수익 시계열 (계약 경유) ──────────────────────────────────────────
source("02_Infrastructure/contracts/canonical_screen_bt.R")
r_base <- canonical_screen_bt(AS[, .(Date,Ticker,score)], FW$returns_dt, FW$bench_dt, top_n=25L,
            cost_bps_oneway=15, liq_dt=FW$liq_dt, liq_min=2e8, run_id="wt001_r7_base",
            strategy_id="arm_base", diag_dual_basis=FALSE)
r_filt <- canonical_screen_bt(AS[!is.na(score_q01filtered), .(Date,Ticker,score=score_q01filtered)],
            FW$returns_dt, FW$bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=FW$liq_dt, liq_min=2e8,
            run_id="wt001_r7_filt", strategy_id="arm_filt", diag_dual_basis=FALSE)
PR <- as.data.table(r_base$period_returns); PR[, date:=as.Date(date)]
PRf<- as.data.table(r_filt$period_returns); PRf[, date:=as.Date(date)]
PB <- merge(PR[, .(date, ret_base=ret_net)], PRf[, .(date, ret_filt=ret_net)], by="date")
PB <- merge(PB, BEN[, .(date=Date, bm=BM_Ret)], by="date")
PB[, `:=`(act_base=ret_base-bm, act_filt=ret_filt-bm)]
say("[arm 수익 시계열] n=%d (%s ~ %s) — 계약 canonical_screen_bt period_returns",
    nrow(PB), as.character(min(PB$date)), as.character(max(PB$date)))

# ── 5. Tail: EVT-GPD + Hill + CF-VaR ────────────────────────────────────────
has_evir <- requireNamespace("evir", quietly=TRUE)
tailfun <- function(r, lab) {
  x <- r[is.finite(r)]; losses <- -x
  q95 <- as.numeric(quantile(x, 0.05)); q99 <- as.numeric(quantile(x, 0.01))
  es95 <- mean(x[x<=q95]); es99 <- mean(x[x<=q99])
  cf95 <- as.numeric(VaR(xts(x, order.by=seq(as.Date("2000-01-31"), by="month", length.out=length(x))),
                          p=0.95, method="modified"))
  out <- list(n=length(x), emp_var_95=q95, emp_es_95=es95, emp_var_99=q99, emp_es_99=es99,
              cf_var_95=cf95, skew=as.numeric(skewness(x)), kurt=as.numeric(kurtosis(x)))
  if (has_evir) {
    u <- as.numeric(quantile(losses, 0.90)); nex <- sum(losses>u)
    fit <- tryCatch(evir::gpd(losses, threshold=u), error=function(e) NULL)
    if (!is.null(fit)) {
      rm_ <- tryCatch(evir::riskmeasures(fit, c(0.95,0.99)), error=function(e) NULL)
      out$gpd_xi <- as.numeric(fit$par.ests["xi"]); out$gpd_beta <- as.numeric(fit$par.ests["beta"])
      out$gpd_n_exceed <- nex; out$gpd_threshold <- u
      if (!is.null(rm_)) { out$evt_var_95 <- -rm_[1,"quantile"]; out$evt_es_95 <- -rm_[1,"sfall"]
                           out$evt_var_99 <- -rm_[2,"quantile"]; out$evt_es_99 <- -rm_[2,"sfall"] }
    }
    hk <- min(40L, max(10L, floor(length(losses)*0.15)))
    hh <- tryCatch(evir::hill(losses, option="alpha", end=hk+5, plot=FALSE), error=function(e) NULL)
    if (!is.null(hh)) out$hill_alpha <- as.numeric(hh$y[length(hh$y)])
  }
  say("  %-14s n=%3d | VaR95 %.4f ES95 %.4f | VaR99 %.4f ES99 %.4f | CF-VaR95 %.4f | 왜도 %.2f 첨도 %.2f%s",
      lab, out$n, out$emp_var_95, out$emp_es_95, out$emp_var_99, out$emp_es_99, out$cf_var_95,
      out$skew, out$kurt,
      if (!is.null(out$gpd_xi)) sprintf(" | GPD ξ %.3f (초과 %d) EVT-ES95 %.4f, Hill α %.2f",
        out$gpd_xi, out$gpd_n_exceed, out$evt_es_95 %||% NA_real_, out$hill_alpha %||% NA_real_) else "")
  out
}
`%||%` <- function(a,b) if (is.null(a)) b else a
say("[꼬리위험 — 월간, 손실 = 음수 수익]")
T_base <- tailfun(PB$ret_base, "arm_base 총")
T_filt <- tailfun(PB$ret_filt, "arm_filt 총")
T_abase<- tailfun(PB$act_base, "arm_base 액티브")
T_afilt<- tailfun(PB$act_filt, "arm_filt 액티브")
T_bm   <- tailfun(PB$bm,       "벤치")
say("  ⚠ 월간 %d관측 · 90%% 문턱 초과 %d개 = GPD 추정 표본 얇음 → EVT 값은 advisory 라벨",
    nrow(PB), T_base$gpd_n_exceed %||% NA_integer_)

# 꼬리 의존 (TDC, 경험적 하방)
tdc <- function(a,b,q=0.10){ ta<-quantile(a,q); tb<-quantile(b,q); sum(a<=ta & b<=tb)/max(1,sum(b<=tb)) }
say("[꼬리 의존 TDC(하방 10%%)] base↔벤치 %.3f | filt↔벤치 %.3f | base↔filt %.3f",
    tdc(PB$ret_base,PB$bm), tdc(PB$ret_filt,PB$bm), tdc(PB$ret_base,PB$ret_filt))

# ── 6. Stress (coverage 표시, <85% = UNRELIABLE) ─────────────────────────────
sp <- list(list("GFC","2007-10-01","2009-03-31"), list("Euro_Debt","2011-07-01","2011-12-31"),
           list("China_Shock","2015-06-01","2016-02-29"), list("COVID","2020-01-01","2020-06-30"),
           list("Rate_Hike_2022","2022-01-01","2022-12-31"), list("Iran_War","2026-02-01","2026-04-30"))
st <- rbindlist(lapply(sp, function(z){
  s<-as.Date(z[[2]]); e<-as.Date(z[[3]])
  sub <- PB[date>=s & date<=e]
  n_exp <- length(seq(s, e, by="month"))
  cov <- nrow(sub)/n_exp
  if (nrow(sub)==0) return(data.table(period=z[[1]], n=0L, coverage=0, base=NA_real_, filt=NA_real_,
                                      bm=NA_real_, act_base=NA_real_, act_filt=NA_real_, status="NO_DATA"))
  data.table(period=z[[1]], n=nrow(sub), coverage=cov,
             base=prod(1+sub$ret_base)-1, filt=prod(1+sub$ret_filt)-1, bm=prod(1+sub$bm)-1,
             act_base=(prod(1+sub$ret_base)-1)-(prod(1+sub$bm)-1),
             act_filt=(prod(1+sub$ret_filt)-1)-(prod(1+sub$bm)-1),
             status=if(cov<0.85) "UNRELIABLE_COVERAGE" else "OK")
}))
say("[스트레스 구간 — 누적 수익, coverage<0.85 = UNRELIABLE]")
print(st[, lapply(.SD, function(z) if(is.numeric(z)) round(z,4) else z)])
# 시나리오 민감도 (Σ 기반, 예측)
say("[시나리오 민감도 · Σ 기반 예측] 시장 -5%%: base arm β %.3f ⇒ %.4f",
    { b <- as.numeric(coef(lm(PB$ret_base ~ PB$bm))[2]); b }, -0.05*as.numeric(coef(lm(PB$ret_base ~ PB$bm))[2]))

# ── 7. Regime correlation — 연속 조건화 (분할 판정 없음) ────────────────────
RW <- dcast(E[, .(Date,Ticker,Ret_1m)], Date~Ticker, value.var="Ret_1m")
dts_all <- RW$Date; RM <- as.matrix(RW[,-1])
regrows <- list()
for (i in seq_along(dts_all)) {
  d <- dts_all[i]; if (i < 24) next
  h <- sc_at(d,"score"); if (length(h) < 25) next
  ix <- match(h, colnames(RM)); ix <- ix[!is.na(ix)]
  sub <- RM[(i-23):(i-1), ix, drop=FALSE]     # PIT: d 이전 실현 23개월
  keep <- which(colSums(!is.na(sub)) >= 12); if (length(keep) < 8) next
  cm <- suppressWarnings(cor(sub[,keep,drop=FALSE], use="pairwise.complete.obs"))
  avg_cor <- mean(cm[upper.tri(cm)], na.rm=TRUE)
  bmw <- BEN[Date < d][order(Date)]; bmw <- tail(bmw$BM_Ret, 12)
  regrows[[length(regrows)+1]] <- data.table(Date=d, avg_pair_cor=avg_cor, n_names=length(keep),
    mkt_vol_12m=stats::sd(bmw)*sqrt(12), mkt_ret_12m=prod(1+bmw)-1)
}
RG <- rbindlist(regrows)
say("[국면 상관 — 연속 조건화] n=%d 월 | 보유 25종 평균 쌍상관 중앙 %.3f [%.3f, %.3f]",
    nrow(RG), median(RG$avg_pair_cor), min(RG$avg_pair_cor), max(RG$avg_pair_cor))
fitc <- lm(avg_pair_cor ~ mkt_vol_12m + mkt_ret_12m, data=RG)
print(round(summary(fitc)$coefficients, 4))
say("  ⇒ 시장변동 +1%%p 당 평균 쌍상관 %+.4f (t %.2f) — 상관 상승은 분산효과 감소 = 위기 시 TE·손실 확대 경로",
    coef(fitc)[["mkt_vol_12m"]]/100, summary(fitc)$coefficients["mkt_vol_12m","t value"])
write_parquet(RG, "stage_artifacts/WT_D20260808_001/regime_correlation.parquet")

saveRDS(list(CR=CR, CR3=if(exists("mm")) mm else NULL, conc=conc, tsum=tsum, ics=ics,
             tail=list(base=T_base,filt=T_filt,act_base=T_abase,act_filt=T_afilt,bm=T_bm),
             tdc=c(base_bm=tdc(PB$ret_base,PB$bm), filt_bm=tdc(PB$ret_filt,PB$bm)),
             stress=st, RG=RG, fitc=summary(fitc)$coefficients, PB=PB,
             bench=list(hhi=sum(U0$wb^2), n_eff=1/sum(U0$wb^2), top10=sum(U0$wb[1:10]),
                        n_over_cap=sum(U0$wb>0.20), w_max=max(U0$wb))),
        file.path(OUT,"r7_risk.rds"))
say("저장 완료")
