# r3_captier_stock.R — R3 lane: cap-tier-conditional STOCK selection (P1 = 벽 이동 유일 각도)
# 질문: cap-tier 선별이 cap-w 벽(baseline momentum port_t=1.277) 돌파하나,
#        아니면 cap-w 트랩(알파 MID국소·벤치 MEGA보상) 재확인?  wall_broken=(port_t>1.6)
#
# 데이터(읽기전용): eval_harness.R 소스 → .FAM(종목단 팩터 z + Size + K200/KQ150 멤버십),
#   .Rg/.BMg/.LQg, .size_dt, .oos_dates(163m 2012-12~2026-06), .a_mom(baseline), .BASELINE_MOM_PORT_T=1.277
# tier 분할: K200==1 → MEGA, KQ150==1 → MID (실측 clean partition: both=0, neither=0)
#
# PIT: 스코어 = t-관측 팩터 z(momentum 우선) + t-관측 tier 멤버십 → 무 look-ahead(baseline momentum과 동일 구조).
#      변형 (c)만 과거(<t) 실현 tier-알파로 slot 배분 → expanding IS-only, 연간 refit, burn-in.
#      lag1(전월 스코어 shift)가 base보다 높으면 동월누출 → 각 변형 자가검증.
# metric_type=canonical (canonical_screen_bt 직접 측정). proxy·자체합성 금지.

setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

OUT <- "04_Research/method_frontier/fq057_p1_risk_accuracy"
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
fams <- .fams
oos  <- .oos_dates

# ---- 종목단 패널: oos 한정 + tier 라벨 + 팩터 z ----
FAM <- .FAM[Date %in% oos, .(Date, Ticker, value, quality, momentum, low_vol, size, dividend,
                             Size, K200, KQ150)]
FAM[, tier := fifelse(!is.na(K200) & K200==1, "MEGA",
              fifelse(!is.na(KQ150) & KQ150==1, "MID", "OTHER"))]
cat(sprintf("[panel] rows=%d, tier counts: MEGA=%d MID=%d OTHER=%d\n",
            nrow(FAM), sum(FAM$tier=="MEGA"), sum(FAM$tier=="MID"), sum(FAM$tier=="OTHER")))

# 종목 composite: momentum z(R2 winner) 우선 + ew 6-factor mean 대안
FAM[, comp_mom := momentum]
FAM[, comp_ew  := rowMeans(.SD, na.rm=TRUE), .SDcols=fams]
# 2-positive-family(momentum+value, one-hot cap-w 양성 유이) blend
FAM[, comp_mv  := rowMeans(.SD, na.rm=TRUE), .SDcols=c("momentum","value")]

# ---- 명시적 tier-slot 선별을 score로 인코딩 ----
#   per-date: MEGA top n_mega + MID top n_mid (comp 내림차순) = core(높은 score), 각 tier 버퍼 3(낮은 score, liq 대체용).
#   canonical top-25는 core 25를 먼저 뽑고, liq로 core 탈락 시에만 버퍼 소환.
#   n_mega/n_mid: 상수(a/b/mega) 또는 date별 벡터(c).
build_score <- function(comp_col, n_mega_by_date, buffer=3L){
  D <- FAM[is.finite(get(comp_col)), .(Date, Ticker, tier, cmp=get(comp_col))]
  # date별 n_mega lookup
  nm_dt <- data.table(Date=names(n_mega_by_date), n_mega=as.integer(n_mega_by_date))
  nm_dt[, Date:=as.Date(Date)]
  D <- merge(D, nm_dt, by="Date")
  D[, n_mid := 25L - n_mega]
  # tier 내 랭킹(내림차순, 1=best)
  D[, rk := frank(-cmp, ties.method="first"), by=.(Date, tier)]
  # slot: core = rk <= n_slot(tier), buffer = n_slot < rk <= n_slot+buffer
  D[, n_slot := fifelse(tier=="MEGA", n_mega, fifelse(tier=="MID", n_mid, 0L))]
  D <- D[n_slot > 0L]                          # OTHER 및 slot=0 tier 제외
  D[, sel := fifelse(rk <= n_slot, "core", fifelse(rk <= n_slot + buffer, "buf", "no"))]
  D <- D[sel != "no"]
  # score: core = 1000 - rk (항상 buffer보다 큼), buffer = 100 - rk
  D[, score := fifelse(sel=="core", 1000 - rk, 100 - rk)]
  D[, .(Date, Ticker, score)]
}

# 상수 n_mega 벡터 헬퍼
const_nmega <- function(k) setNames(rep(as.integer(k), length(oos)), as.character(oos))

# ---- canonical 측정 + 지표 추출 (paired vs baseline momentum, lag1 self-check) ----
measure <- function(score_dt, label){
  res <- canonical_screen_bt(score_dt[Date %in% oos], .Rg, .BMg, top_n=25L, cost_bps_oneway=15,
                             liq_dt=.LQg, liq_min=2e8, run_id="r3cs", strategy_id=label,
                             periods_per_year=12L, diag_dual_basis=TRUE, size_dt=.size_dt)
  a <- .active_series(res)
  # lag1: 종목 score를 1개월 shift(전월 score → 당월 적용)
  sc <- as.data.table(score_dt)[Date %in% oos]; setorder(sc, Ticker, Date)
  dmap <- data.table(Date=oos, nxt=shift(oos, -1L))[!is.na(nxt)]   # Date의 다음 oos월
  sc <- merge(sc, dmap, by="Date")
  lag1_sc <- sc[, .(Date=nxt, Ticker, score)]
  lag1_t <- tryCatch(canonical_screen_bt(lag1_sc[Date %in% oos], .Rg, .BMg, top_n=25L,
                     cost_bps_oneway=15, liq_dt=.LQg, liq_min=2e8, run_id="r3cs_lag1",
                     strategy_id=paste0(label,"_lag1"), periods_per_year=12L,
                     diag_dual_basis=FALSE)$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  list(res=res, a=a,
       label=label,
       port_t=round(res$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
       oos_ret=round(.oos_ret_of(res$period_returns),3),
       net_sr=round(res$net_sr,3),
       calmar=round(.calmar_of(res$period_returns),3),
       turnover=round(res$turnover_annual,2),
       paired_vs_mom_t=round(.paired_t(a, .a_mom),3),
       lag1_port_t=round(lag1_t,3),
       n_months=res$n_months)
}

results <- list()
row <- function(m) data.table(variant=m$label, port_t=m$port_t, ew_uni_t=m$ew_uni_t,
  oos_ret=m$oos_ret, net_sr=m$net_sr, calmar=m$calmar, turnover=m$turnover,
  paired_vs_mom_t=m$paired_vs_mom_t, lag1_port_t=m$lag1_port_t, n=m$n_months,
  wall_broken=(is.finite(m$port_t) && m$port_t > 1.6))

cat("\n========== 진단 기준선 (tier-pure, momentum comp) ==========\n")
m_mega <- measure(build_score("comp_mom", const_nmega(25L)), "mega_pure_mom")   # 25 MEGA
m_mid  <- measure(build_score("comp_mom", const_nmega(0L)),  "mid_pure_mom")    # 25 MID (b)
results <- c(results, list(m_mega, m_mid))
print(rbindlist(lapply(list(m_mega,m_mid), row)))

cat("\n========== (a) tier-balanced ==========\n")
m_bal_mom <- measure(build_score("comp_mom", const_nmega(13L)), "bal_13_12_mom")
m_bal_ew  <- measure(build_score("comp_ew",  const_nmega(13L)), "bal_13_12_ew")
m_bal_mv  <- measure(build_score("comp_mv",  const_nmega(13L)), "bal_13_12_mv")
results <- c(results, list(m_bal_mom, m_bal_ew, m_bal_mv))
print(rbindlist(lapply(list(m_bal_mom,m_bal_ew,m_bal_mv), row)))

cat("\n========== (b) MID concentration (comp 변형) ==========\n")
m_mid_ew <- measure(build_score("comp_ew", const_nmega(0L)), "mid_pure_ew")
m_mid_mv <- measure(build_score("comp_mv", const_nmega(0L)), "mid_pure_mv")
results <- c(results, list(m_mid_ew, m_mid_mv))
print(rbindlist(lapply(list(m_mid_ew,m_mid_mv), row)))

# ---- (c) tier-weight IS-예측: 과거(<t) 실현 tier-알파로 slot 배분, 연간 refit, expanding IS-only ----
cat("\n========== (c) tier-weight IS-prediction (walk-forward) ==========\n")
# 두 tier-pure 월별 active series (full oos 산출 후 prefix만 사용 → PIT: year y 배분은 <Jan1(y)만)
a_mega <- m_mega$a; setnames(a_mega, "active", "act_mega")
a_mid  <- m_mid$a;  setnames(a_mid,  "active", "act_mid")
tier_act <- merge(a_mega[,.(date, act_mega)], a_mid[,.(date, act_mid)], by="date")
setorder(tier_act, date)

k_temp <- 8.0   # softmax 온도 (IS tier t-score 차 → slot 배분)
alloc_nmega <- integer(length(oos)); names(alloc_nmega) <- as.character(oos)
alloc_log <- list()
for(i in seq_along(oos)){
  d <- oos[i]; y <- as.integer(format(d,"%Y"))
  b <- as.Date(sprintf("%d-01-01", y))         # 연 시작 경계 → 연간 refit (연중 동일 배분)
  isw <- tier_act[date < b]
  if(nrow(isw) < 18L){ alloc_nmega[i] <- 13L    # burn-in → balanced
  } else {
    # IS tier 값 = mean/sd (t-유사), softmax
    sm <- function(x){s<-sd(x); if(!is.finite(s)||s<=0) return(0); mean(x)/s}
    vm <- sm(isw$act_mega); vd <- sm(isw$act_mid)
    wm <- exp(k_temp*vm)/(exp(k_temp*vm)+exp(k_temp*vd))
    nmega <- as.integer(round(25*wm)); nmega <- max(3L, min(22L, nmega))
    alloc_nmega[i] <- nmega
  }
}
# 연도별 배분 로그
alloc_dt <- data.table(date=oos, year=as.integer(format(oos,"%Y")), n_mega=alloc_nmega)
cat("연도별 slot 배분(n_mega/25):\n"); print(alloc_dt[, .(n_mega=n_mega[1]), by=year])

m_isw_mom <- measure(build_score("comp_mom", alloc_nmega), "isw_tierweight_mom")
results <- c(results, list(m_isw_mom))
print(row(m_isw_mom))

cat("\n========== (참조) whole-universe momentum top25 (no tier logic) ==========\n")
allmom_sc <- FAM[is.finite(comp_mom), .(Date, Ticker, score=comp_mom)]
m_allmom <- measure(allmom_sc, "allmom_notier")
results <- c(results, list(m_allmom))
print(row(m_allmom))

# ---- 종합 ----
cat("\n\n########## 종합 (baseline momentum port_t=", .BASELINE_MOM_PORT_T, ") ##########\n", sep="")
summ <- rbindlist(lapply(results, row))
setorder(summ, -port_t)
print(summ)

# best (port_t 기준)
best <- summ[which.max(port_t)]
cat(sprintf("\n[best by port_t] %s: port_t=%.3f, paired_vs_mom=%.3f, wall_broken=%s\n",
            best$variant, best$port_t, best$paired_vs_mom_t, best$wall_broken))

# tier 분해(best가 MID인지 트랩 확인) — cap_tier 진단 append
cat("\n===== cap-tier weight/contrib 분해 (진단, mid_pure_mom) =====\n")
ct <- m_mid$res$diag_cap_tier
if(isTRUE(ct$available)){
  cat("weight_share_avg:\n"); print(unlist(ct$weight_share_avg))
  cat("contrib_gross_annualized:\n"); print(unlist(ct$contrib_gross_annualized))
}

# 저장
best_score <- switch(best$variant,
  mega_pure_mom=build_score("comp_mom",const_nmega(25L)),
  mid_pure_mom=build_score("comp_mom",const_nmega(0L)),
  bal_13_12_mom=build_score("comp_mom",const_nmega(13L)),
  bal_13_12_ew=build_score("comp_ew",const_nmega(13L)),
  bal_13_12_mv=build_score("comp_mv",const_nmega(13L)),
  mid_pure_ew=build_score("comp_ew",const_nmega(0L)),
  mid_pure_mv=build_score("comp_mv",const_nmega(0L)),
  isw_tierweight_mom=build_score("comp_mom",alloc_nmega),
  allmom_notier=allmom_sc)
write_parquet(best_score, file.path(OUT, "theta_R3_captier_stock.parquet"))
fwrite(summ, file.path(OUT, "r3_captier_stock_summary.csv"))
saveRDS(list(summary=summ, best=best, alloc=alloc_dt,
             baseline_mom=.BASELINE_MOM_PORT_T), file.path(OUT, "r3_captier_stock.rds"))
cat("\n[r3_captier_stock] done. saved theta_R3_captier_stock.parquet + summary.csv + rds\n")
