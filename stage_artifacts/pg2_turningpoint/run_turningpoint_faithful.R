## ============================================================
## PG2 Turning-Point 오버레이 — Harvey팀 충실복제 (BBT FAJ 2024 eqs 8-10)
## 도훈 지시 2026-07-02. R3 정적판 falsification(G1_bbt SR 1.751 < NOL4 1.897,
## NW-t -0.61)의 완성: dynamic ex-ante speed-blend(a_Co/a_Re)가 진짜로도 죽는지 시험.
##
## 이식 대상 = 클린 book NOL4 = beta_R05 × m4 × ret_orig - |Δ(beta_R05×m4)|×15bps
## turning-point = 이 위에 × β_tp (long-only 노출배수 [floor,1]).
##
## ★하드 규율 (위반=결과무효):
##  - 클린 타이밍: 신호월 m → realized_ym = m+2 (배포 prev-month-end 컨벤션, R3와 동일)
##  - lag-stress 필수 = 1차 판별: β_tp에 +1M 추가 lag → SR/paired-NW-t 붕괴 측정
##  - 비용: |Δβ_tp|×15bps delta. PerformanceAnalytics 표준함수만(self-synth 금지)
##  - data.table by-group 전역벡터 참조 금지 (본 스크립트는 base-R 벡터 루프)
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
options(warn = 1)
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_turningpoint")
OFF_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
BM_PIN   <- file.path(OFF_DIR, "benchmark_pinned_20260702.parquet")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
COST <- 0.0015
K_SLOW <- 12L; K_FAST <- 2L
UPDATE_EVERY <- 30L      # 논문: 30개월마다 mixing param 갱신
MIN_PHASE_OBS <- 12L     # 논문: 각 phase 최소 12개월 history 요구
FLOOR <- 0.4             # long-only 노출 하한 (task 예시)

## ---- [1] 월간 BM 수익 + 논문 신호(x_SLOW/x_FAST) ------------------------------
cat("[1] 월간 BM 수익 + 논문 SLOW/FAST 신호 (arithmetic mean of monthly rets)\n")
bm <- as.data.table(read_parquet(BM_PIN))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
bm_x <- xts(bm[[bcol]], order.by = bm$Date)
mret_x <- apply.monthly(bm_x, Return.cumulative)   # 표준함수 (self-synth 금지)
mdt <- data.table(ym = format(index(mret_x), "%Y-%m"), r = as.numeric(mret_x))
setorder(mdt, ym)
nM <- nrow(mdt)

## 논문 eq(1)(2): x_SLOW=mean(prev k_SLOW monthly rets), x_FAST=mean(prev k_FAST).
## 모두 m 이전(월-1..월-k) 데이터만 사용 (frollmean은 현재행 포함이므로 shift 1).
r_prev <- shift(mdt$r, 1)  # r_{m-1} 정렬
mdt[, x_slow := frollmean(shift(r, 1), K_SLOW)]  # mean of r_{m-1..m-12}
mdt[, x_fast := frollmean(shift(r, 1), K_FAST)]  # mean of r_{m-1..m-2}
## 논문 eq(4) 4-state (>=0 은 Bull/Correction 쪽)
mk_state <- function(xs, xf) fifelse(!is.finite(xs) | !is.finite(xf), "NA",
  fifelse(xs >= 0 & xf >= 0, "Bull",
  fifelse(xs >= 0 & xf <  0, "Correction",
  fifelse(xs <  0 & xf <  0, "Bear", "Rebound"))))
mdt[, state := mk_state(x_slow, x_fast)]
## 논문 eq(5)(6): r_SLOW/r_FAST 레그 (부호 정렬된 momentum 레그 수익, 진단·정적맵용)
mdt[, r_slow_leg := fifelse(x_slow >= 0, r, -r)]
mdt[, r_fast_leg := fifelse(x_fast >= 0, r, -r)]

cat(sprintf("    월수=%d, state 분포: %s\n", nM,
  paste(sprintf("%s=%d", names(table(mdt$state)), as.integer(table(mdt$state))), collapse=" ")))

## ---- [2] a_Co / a_Re ex-ante 추정 (논문 Appendix C eqs 8-10) -----------------
## a_Co = 0.5*(1 - (1/C)*AVG[r|Co]/AVG[r2|Co])
## a_Re = 0.5*(1 - (1/C)*AVG[r|Re]/AVG[r2|Re])
## C = FREQ[Bu]/FREQ[Bu|Be]*AVG[r|Bu]/AVG[r2|Bu|Be]
##   - FREQ[Be]/FREQ[Bu|Be]*AVG[r|Be]/AVG[r2|Bu|Be]
## AVG[r|s], AVG[r2|s], FREQ[s]: month m 이전(strictly prior) state=s 월들에 대해.
## r = 그 state 월에 realize된 raw market 수익 mdt$r (state는 월초 관측 → r_m harvest).
## 30개월마다 갱신, inception-to-prior-month, [0,1] clip, phase당 최소 12관측.
cat("[2] a_Co/a_Re ex-ante 추정 (Appendix C, 30M 갱신, [0,1] clip, min 12 obs/phase)\n")
st <- mdt$state; rr <- mdt$r
a_co <- rep(NA_real_, nM); a_re <- rep(NA_real_, nM); Cvec <- rep(NA_real_, nM)
estimate_at <- function(upto) {  # upto = 마지막 포함 index (strictly prior to current apply month)
  idx <- seq_len(upto)
  s <- st[idx]; x <- rr[idx]
  fin <- is.finite(x) & s != "NA"
  s <- s[fin]; x <- x[fin]
  g <- function(lbl) x[s == lbl]
  co <- g("Correction"); re <- g("Rebound"); bu <- g("Bull"); be <- g("Bear")
  # min 12 obs per phase required (Co/Re for the param; Bu/Be for normalizer C)
  if (length(co) < MIN_PHASE_OBS || length(re) < MIN_PHASE_OBS ||
      length(bu) < MIN_PHASE_OBS || length(be) < MIN_PHASE_OBS) return(NULL)
  avg  <- function(v) mean(v)
  avg2 <- function(v) mean(v^2)
  n_bu <- length(bu); n_be <- length(be); n_buBe <- n_bu + n_be
  avg2_buBe <- mean(c(bu, be)^2)
  C <- (n_bu/n_buBe) * avg(bu)/avg2_buBe - (n_be/n_buBe) * avg(be)/avg2_buBe
  if (!is.finite(C) || abs(C) < 1e-8) return(NULL)
  aco <- 0.5 * (1 - (1/C) * avg(co)/avg2(co))
  are <- 0.5 * (1 - (1/C) * avg(re)/avg2(re))
  aco <- min(max(aco, 0), 1); are <- min(max(are, 0), 1)  # [0,1] clip
  list(a_co = aco, a_re = are, C = C)
}
## 30개월 갱신: 각 apply-month m 은 m-1 까지 데이터로 추정된 최신 param 사용.
## 갱신 스케줄: 추정 가능 최초월부터 30개월 간격으로 param 재계산, 사이엔 hold.
cur <- NULL; last_update_at <- -Inf
for (m in seq_len(nM)) {
  prior <- m - 1L  # strictly prior
  if (prior >= MIN_PHASE_OBS) {
    if (!is.finite(last_update_at) || (prior - last_update_at) >= UPDATE_EVERY || is.null(cur)) {
      est <- estimate_at(prior)
      if (!is.null(est)) { cur <- est; last_update_at <- prior }
    }
  }
  if (!is.null(cur)) { a_co[m] <- cur$a_co; a_re[m] <- cur$a_re; Cvec[m] <- cur$C }
}
mdt[, `:=`(a_co = a_co, a_re = a_re, Cparam = Cvec)]
cat(sprintf("    최초 param 확정월: %s | 최종 a_co=%.3f a_re=%.3f C=%.3f\n",
  mdt$ym[which(is.finite(a_co))[1]], tail(a_co[is.finite(a_co)],1),
  tail(a_re[is.finite(a_re)],1), tail(Cvec[is.finite(Cvec)],1)))

## ---- [3] dynamic blended trend position (논문 eq7 → long-only 사상) ----------
## 논문 eq7 r_DYN 는 L/S 포지션. 우리는 blended *signal*(포지션 방향/강도)을 만들어
## long-only 노출배수 β_tp∈[FLOOR,1]로 monotone squash.
## blended position b_m (signal-space, [-1,1] 지향):
##   Bull:       +1   (fast·slow 둘 다 long)
##   Bear:       -1   (둘 다 short)
##   Correction: (1-a_co)*sign(slow) + a_co*sign(fast) = (1-a_co)*(+1) + a_co*(-1) = 1-2*a_co
##   Rebound:    (1-a_re)*sign(slow) + a_re*sign(fast) = (1-a_re)*(-1) + a_re*(+1) = 2*a_re-1
## (부호정렬 momentum 레그의 방향만 살린 blended position — 논문 mixing weight를 그대로 사용)
cat("[3] dynamic blended position → long-only β_tp squash\n")
pos_dyn <- with(mdt, fifelse(state=="Bull", 1,
  fifelse(state=="Bear", -1,
  fifelse(state=="Correction", 1 - 2*a_co,
  fifelse(state=="Rebound", 2*a_re - 1, NA_real_)))))
mdt[, pos_dyn := pos_dyn]
## static 4-state 손맵 (R3 G1 재현: Bull1.0/Corr0.7/Bear0.4/Rebound1.0)
map_static <- function(s) fifelse(s=="Bull",1.0, fifelse(s=="Correction",0.7,
  fifelse(s=="Bear",0.4, fifelse(s=="Rebound",1.0, NA_real_))))
## long-only squash: signal-space pos∈[-1,1] → β∈[FLOOR,1] 선형 (연속 speed-blend 보존)
squash <- function(pos, floor=FLOOR) fifelse(!is.finite(pos), 1.0, floor + (1-floor)*(pos+1)/2)
mdt[, beta_tp_dyn := squash(pos_dyn)]
mdt[, beta_tp_static := map_static(state)]
## 병행 변형: β_AR 분포 freq-match 이산화 (연속 dyn을 배포 노출분포에 매칭)
## (R3 map_freq 재사용 — beta_AR 분포로 이산 그리드에 사상)

## ---- [4] 패널 merge (★클린 타이밍: 신호월 m → realized_ym = m+2) --------------
cat("[4] 패널 merge (신호월 m → realized_ym m+2, 클린) + lag1 스트레스\n")
p <- fread(file.path(BASE_DIR,
  "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)

mdt[, ym_p2 := format(as.Date(paste0(ym,"-01")) %m+% months(2), "%Y-%m")]  # 클린
mdt[, ym_p3 := format(as.Date(paste0(ym,"-01")) %m+% months(3), "%Y-%m")]  # +1M lag 스트레스
sig_clean <- mdt[, .(realized_ym = ym_p2, state_cl = state,
                     beta_tp_dyn_cl = beta_tp_dyn, beta_tp_static_cl = beta_tp_static,
                     pos_dyn_cl = pos_dyn, a_co_cl = a_co, a_re_cl = a_re)]
sig_lag1  <- mdt[, .(realized_ym = ym_p3, state_l1 = state,
                     beta_tp_dyn_l1 = beta_tp_dyn, beta_tp_static_l1 = beta_tp_static)]
p <- merge(p, sig_clean, by="realized_ym", all.x=TRUE)
p <- merge(p, sig_lag1,  by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
## 신호 미가용월(warm-up)은 β_tp=1.0 (중립 노출 = NOL4와 동일 = 오버레이 미개입)
for (cc in c("beta_tp_dyn_cl","beta_tp_static_cl","beta_tp_dyn_l1","beta_tp_static_l1")) {
  set(p, which(!is.finite(p[[cc]])), cc, 1.0)
}
p[is.na(state_cl), state_cl := "NA"]
cat(sprintf("    β_tp_dyn 신호가용 시작월: %s (이전은 1.0 중립)\n",
  p$realized_ym[which(p$beta_tp_dyn_cl != 1.0)[1]]))

## freq-match 이산 변형 (β_AR 분포에 dyn pos 사상)
exp_pct <- function(x) { out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[seq_len(i-1)]; past <- past[is.finite(past)]
    if (length(past) >= 24 && is.finite(x[i])) out[i] <- mean(past < x[i]) }; out }
freq <- prop.table(table(round(p$beta_AR,2)))
lo <- sort(as.numeric(names(freq))[as.numeric(names(freq)) < 0.999])
cumf <- 0; thr <- list()
for (l in lo) { f <- as.numeric(freq[as.character(l)]); if (is.na(f)) f <- 0
  thr[[length(thr)+1]] <- c(l, 1-cumf-f, 1-cumf); cumf <- cumf+f }
map_freq <- function(pp){ if(!is.finite(pp)) return(1.0)
  for (tt in thr) if (pp >= tt[2] && pp < tt[3]) return(tt[1])
  if (length(lo) && pp >= 1-cumf) return(lo[1]); 1.0 }
beta_tp_dyn_freq_cl <- sapply(exp_pct(p$pos_dyn_cl), map_freq)
beta_tp_dyn_freq_cl[!is.finite(beta_tp_dyn_freq_cl)] <- 1.0

## ---- [5] 변형군 (E = beta_R05 × m4 × β_tp; NOL4 base = β_tp≡1) ----------------
cat("[5] 변형군 정의 + 실측\n")
base_bm4 <- p$beta_R05 * p$m4   # NOL4 노출 (β_tp 이전)
E_list <- list(
  NOL4_base            = base_bm4 * 1.0,
  NOL4_x_tp_static     = base_bm4 * p$beta_tp_static_cl,   # 손맵 4-state (R3 G1 계보)
  NOL4_x_tp_dynamic    = base_bm4 * p$beta_tp_dyn_cl,      # ★논문 충실 speed-blend
  NOL4_x_tp_dyn_freq   = base_bm4 * beta_tp_dyn_freq_cl,   # 병행: freq-match 이산화
  faith_clean_ref      = base_bm4 * p$beta_faith,          # 참조: 구 Layer4 faith (클린 아님, 기록)
  AR_ref               = base_bm4 * p$beta_AR              # 참조: AR Layer4
)
## lag1 스트레스 변형 (판별검정)
E_lag1 <- list(
  NOL4_x_tp_static_lag1  = base_bm4 * p$beta_tp_static_l1,
  NOL4_x_tp_dynamic_lag1 = base_bm4 * p$beta_tp_dyn_l1
)

ret_of <- function(E) { dE <- abs(E - shift(E, 1, fill = 1.0)); list(ret = E*p$ret_orig - dE*COST, dE = dE) }
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn) }
ann_sr  <- function(ret, idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(ret, order.by=idx), scale=12)[3,1])
R  <- lapply(E_list, ret_of)
RL <- lapply(E_lag1, ret_of)
ret_base <- R$NOL4_base$ret

## crisis windows (paired 관찰)
crisis_win <- list(
  GFC   = c("2008-06","2009-03"),
  COVID = c("2020-02","2020-05"),
  Y2022 = c("2022-01","2022-12"),
  Y2026 = c("2026-01","2026-06")
)
cum_win <- function(ret, ym_vec, w) {
  sel <- ym_vec >= w[1] & ym_vec <= w[2]
  if (sum(sel) == 0) return(NA_real_)
  as.numeric(Return.cumulative(xts(ret[sel], order.by = p$anchor_date[sel])))
}

res <- rbindlist(lapply(names(E_list), function(nm) {
  ret <- R[[nm]]$ret; x <- xts(ret, order.by=p$anchor_date)
  data.table(variant=nm,
    SR=round(ann_sr(ret),3), CAGR=round(as.numeric(Return.annualized(x, scale=12)),4),
    MDD=round(as.numeric(maxDrawdown(x)),4), Calmar=round(as.numeric(CalmarRatio(x, scale=12)),3),
    Sortino_m=round(as.numeric(SortinoRatio(x, MAR=0)),4),
    ret_2025=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2025"])),4),
    ret_2026=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"])),4),
    avg_expo=round(mean(E_list[[nm]], na.rm=TRUE),3), turnover_dE=round(sum(R[[nm]]$dE, na.rm=TRUE),2),
    nw_t_vs_NOL4=round(nw_t(ret - ret_base),2),
    GFC=round(cum_win(ret,p$realized_ym,crisis_win$GFC),4),
    COVID=round(cum_win(ret,p$realized_ym,crisis_win$COVID),4),
    Y2022=round(cum_win(ret,p$realized_ym,crisis_win$Y2022),4),
    Y2026=round(cum_win(ret,p$realized_ym,crisis_win$Y2026),4))
}))
cat("\n===== TURNING-POINT FAITHFUL — CLEAN RESULTS =====\n"); print(res, nrow=99)

## ---- [6] lag1 스트레스 (1차 판별) --------------------------------------------
cat("\n[6] lag1 스트레스 (동월누출 판별 — clean vs +1M lag)\n")
lag_tbl <- rbindlist(lapply(c("static","dynamic"), function(k) {
  cl_nm <- paste0("NOL4_x_tp_", k); l1_nm <- paste0("NOL4_x_tp_", k, "_lag1")
  ret_cl <- R[[cl_nm]]$ret; ret_l1 <- RL[[l1_nm]]$ret
  data.table(variant=k,
    SR_clean=round(ann_sr(ret_cl),3), SR_lag1=round(ann_sr(ret_l1),3),
    dSR=round(ann_sr(ret_cl)-ann_sr(ret_l1),3),
    NWt_clean_vs_NOL4=round(nw_t(ret_cl-ret_base),2),
    NWt_lag1_vs_NOL4=round(nw_t(ret_l1-ret_base),2))
}))
print(lag_tbl)

## ---- [7] OOS v2 + subperiod (dynamic 생존 시 판정) ---------------------------
cat("\n[7] OOS v2 (3분할 중앙값) + subperiod\n")
oos_v2 <- function(ret) { ns <- length(ret)
  rs <- sapply(c(0.55,0.65,0.75), function(f) { k <- floor(ns*f)
    is_sr <- ann_sr(ret[1:k], p$anchor_date[1:k]); oos_sr <- ann_sr(ret[(k+1):ns], p$anchor_date[(k+1):ns])
    if (!is.finite(is_sr) || abs(is_sr) < 1e-9) return(NA_real_); oos_sr/is_sr })
  round(median(rs, na.rm=TRUE),3) }
pre <- p$anchor_date < as.Date("2017-01-01")
sub <- rbindlist(lapply(c("NOL4_base","NOL4_x_tp_static","NOL4_x_tp_dynamic","NOL4_x_tp_dyn_freq"), function(nm)
  data.table(variant=nm, oos_v2=oos_v2(R[[nm]]$ret),
    SR_pre2017=round(ann_sr(R[[nm]]$ret[pre], p$anchor_date[pre]),3),
    SR_post2017=round(ann_sr(R[[nm]]$ret[!pre], p$anchor_date[!pre]),3))))
print(sub)

## ---- [8] DSR 진단 (sweep) ----------------------------------------------------
n_trials <- 31L + 6L  # R1-3 누적 31 + 본 라운드 6 변형
sr_all <- res$SR
best_sr <- max(sr_all, na.rm=TRUE)
sr_sd <- sd(sr_all, na.rm=TRUE)
## DSR 근사 (Bailey-Lopez de Prado 스타일 진단, 게이트 아님 — chain/sweep 라벨 sweep)
skew_r <- skewness(R[[which.max(sr_all)]]$ret); kurt_r <- kurtosis(R[[which.max(sr_all)]]$ret)
cat(sprintf("\n[8] DSR 진단(sweep, n_trials=%d): best_SR=%.3f, sr_sd_across_variants=%.3f\n",
  n_trials, best_sr, sr_sd))

## ---- [9] 시리즈 + meta 저장 --------------------------------------------------
series_out <- data.table(realized_ym=p$realized_ym, anchor_date=p$anchor_date,
  ret_orig=p$ret_orig, beta_R05=p$beta_R05, m4=p$m4, state_cl=p$state_cl,
  beta_tp_static=p$beta_tp_static_cl, beta_tp_dynamic=p$beta_tp_dyn_cl,
  a_co=p$a_co_cl, a_re=p$a_re_cl,
  ret_NOL4_base=R$NOL4_base$ret,
  ret_tp_static=R$NOL4_x_tp_static$ret,
  ret_tp_dynamic=R$NOL4_x_tp_dynamic$ret,
  ret_tp_dyn_freq=R$NOL4_x_tp_dyn_freq$ret,
  ret_tp_dynamic_lag1=RL$NOL4_x_tp_dynamic_lag1$ret)
fwrite(series_out, file.path(OUT_DIR, "turningpoint_series.csv"))
fwrite(res, file.path(OUT_DIR, "turningpoint_results.csv"))
fwrite(lag_tbl, file.path(OUT_DIR, "turningpoint_lag_stress.csv"))
fwrite(sub, file.path(OUT_DIR, "turningpoint_oos_sub.csv"))

## 성공 기준 판정 (dynamic 대상)
dyn_nwt <- res[variant=="NOL4_x_tp_dynamic", nw_t_vs_NOL4]
dyn_nwt_lag1 <- lag_tbl[variant=="dynamic", NWt_lag1_vs_NOL4]
crit1 <- is.finite(dyn_nwt) && dyn_nwt > 2      # 클린 유의초과
crit2 <- is.finite(dyn_nwt_lag1) && dyn_nwt_lag1 > 2 && (dyn_nwt_lag1 >= dyn_nwt - 0.5)  # lag1 생존
verdict_pass <- crit1 && crit2

meta <- list(
  date="2026-07-02", round="turningpoint-faithful",
  paper="Breaking Bad Trends (Goulding-Harvey-Mazzoleni FAJ 2024, P167) eqs 4,7,8,9,10; Momentum Turning Points (Garg-Goulding-Harvey-Mazzoleni JFE 2023, P158)",
  estimator=list(
    states="eq4: sign(x_slow>=0)&(x_fast>=0)=Bull; slow>=0&fast<0=Correction; both<0=Bear; slow<0&fast>=0=Rebound",
    signals="eq1/2: x_slow=mean(prev 12 monthly rets), x_fast=mean(prev 2). arithmetic mean, no vol-scaling of signal (paper p246-249).",
    mixing="Appendix C eq8/9/10: a_Co=0.5*(1-(1/C)*AVG[r|Co]/AVG[r2|Co]); a_Re=0.5*(1-(1/C)*AVG[r|Re]/AVG[r2|Re]); C=FREQ[Bu]/FREQ[BuBe]*AVG[r|Bu]/AVG[r2|BuBe]-FREQ[Be]/FREQ[BuBe]*AVG[r|Be]/AVG[r2|BuBe]",
    r_definition="r = raw monthly market return realized in the state-s month (state observable at month-start, harvested during month). AVG/FREQ over strictly-prior months.",
    update_freq_months=UPDATE_EVERY, min_phase_obs=MIN_PHASE_OBS, clip="[0,1]",
    shrinkage="structural: estimator centered at 0.5, deviation ∝ signal/noise (AVG[r]/AVG[r2]); no separate multiplier (paper Appendix C)"
  ),
  longonly_adaptation=list(
    principle="paper blended trend = L/S position; long-only 사상: signal-space pos∈[-1,1] → β_tp∈[FLOOR,1] linear squash (연속 speed-blend 보존). β_tp>0 상향 노출, ≤0 floor.",
    pos_dyn="Bull=+1; Bear=-1; Correction=1-2*a_co; Rebound=2*a_re-1 (mixing weight 그대로)",
    squash=sprintf("β=FLOOR+(1-FLOOR)*(pos+1)/2, FLOOR=%.2f", FLOOR),
    freq_match_variant="병행: pos_dyn을 beta_AR 분포에 freq-match 이산화 (배포 노출분포 매칭)"
  ),
  clean_timing="신호월 m → realized_ym = m+2 (배포 prev-month-end 컨벤션, R3 정합)",
  lag_stress="β_tp에 +1M 추가 lag(m→m+3) → SR·paired-NW-t 붕괴 측정 (동월누출 판별)",
  cost="|Δβ_tp|×15bps delta (contract, self-synth 금지)",
  selection_type="sweep", n_trials_cumulative=n_trials,
  metric_type="backtested (panel-overlay, R3와 동일 계보; 절대수치 후속감사 caveat 상속)",
  success_criteria=list(
    crit1_clean_significant=list(rule="dynamic paired NW-t vs NOL4 > 2", value=dyn_nwt, pass=crit1),
    crit2_lag1_survive=list(rule="lag1 NW-t > 2 AND >= clean-0.5", value=dyn_nwt_lag1, pass=crit2),
    crit3_book_marginal="ΔIR≥0.05 — governor/book context, 별도(성과 유의 실패 시 무의미)"
  ),
  verdict=if (verdict_pass) "PASS_PROVISIONAL (crit1&2, crit3 pending)" else "FAIL — W1 오버레이 KR 최종사망 (dynamic 충실판 포함)"
)
write_json(meta, file.path(OUT_DIR, "turningpoint_meta.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat(sprintf("\n[VERDICT] crit1(clean NW-t>2)=%s (%.2f) | crit2(lag1 생존)=%s (%.2f)\n",
  crit1, dyn_nwt, crit2, dyn_nwt_lag1))
cat(sprintf("[VERDICT] %s\n", meta$verdict))
cat("\n[DONE] 산출:", OUT_DIR, "\n")
