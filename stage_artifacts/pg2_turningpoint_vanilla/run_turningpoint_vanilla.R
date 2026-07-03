## ============================================================
## PG2 Turning-Point 오버레이 — VANILLA BASE TEST (도훈 지시 2026-07-02)
##
## track 1(stage_artifacts/pg2_turningpoint/)은 turning-point를 NOL4(=R05×m4,
## 이미 regime 방어 중) *위에 stacking* 해 드래그로 사망했다.
## 이번은 **모든 기존 오버레이를 벗기고(NAKED = ret_orig) turning-point를
## 유일 오버레이로** 주어, R05×m4와 *경쟁이 아니라 대체*로서 값을 하는지 공정히 본다.
##
## ★재사용: β_tp_static / β_tp_dynamic 산출 로직(BBT FAJ 2024 eqs 4,7,8,9,10)은
##   run_turningpoint_faithful.R [1][2][3]을 그대로 재사용(동일 estimator·동일 신호).
##   베이스만 NOL4 → NAKED(ret_orig)로 교체.
##
## ★변형(전부 NAKED=ret_orig 위 단독 오버레이, 클린 타이밍 신호월 m→realized m+2):
##   1. NAKED                 = ret_orig (오버레이 전무)
##   2. NAKED × β_tp_static   (4-state 손맵 단독)
##   3. NAKED × β_tp_dynamic  (speed-blend 단독 — 주인공)
##   4. NAKED × β_faith_clean (faith 단독, 참조)
##   5. NAKED × (β_R05 × m4)  = NOL4 단독 (제거 확정 챔피언, 기준선)
##   6. NAKED × β_AR          (AR 단독, 참조)
##
## ★하드 규율(위반=결과무효):
##  - 클린 타이밍: turning-point 신호월 m → realized_ym = m+2 (배포 prev-month-end 컨벤션)
##  - |Δ노출|×15bps delta 비용, PerformanceAnalytics 표준함수만(self-synth 금지)
##  - lag1 스트레스(β_tp에 +1M 추가 lag) = 동월누출 판별
##  - 판정: 각 변형 vs NAKED AND vs NOL4 paired NW-t
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
options(warn = 1)
try(setDTthreads(1), silent = TRUE)
try(arrow::set_cpu_count(1), silent = TRUE)
try(arrow::set_io_thread_count(1), silent = TRUE)
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_turningpoint_vanilla")
OFF_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
BM_PIN   <- file.path(OFF_DIR, "benchmark_pinned_20260702.parquet")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
COST <- 0.0015
K_SLOW <- 12L; K_FAST <- 2L
UPDATE_EVERY <- 30L      # 논문: 30개월마다 mixing param 갱신
MIN_PHASE_OBS <- 12L     # 논문: 각 phase 최소 12개월 history
FLOOR <- 0.4             # long-only 노출 하한 (track1과 동일)

## ==== [1] 월간 BM 수익 + 논문 SLOW/FAST 신호 (track1 재사용, 불변) ============
cat("[1] 월간 BM 수익 + 논문 SLOW/FAST 신호\n")
bm <- as.data.table(read_parquet(BM_PIN))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
bm_x <- xts(bm[[bcol]], order.by = bm$Date)
mret_x <- apply.monthly(bm_x, Return.cumulative)
mdt <- data.table(ym = format(index(mret_x), "%Y-%m"), r = as.numeric(mret_x))
setorder(mdt, ym); nM <- nrow(mdt)
mdt[, x_slow := frollmean(shift(r, 1), K_SLOW)]  # mean of r_{m-1..m-12}
mdt[, x_fast := frollmean(shift(r, 1), K_FAST)]  # mean of r_{m-1..m-2}
mk_state <- function(xs, xf) fifelse(!is.finite(xs) | !is.finite(xf), "NA",
  fifelse(xs >= 0 & xf >= 0, "Bull",
  fifelse(xs >= 0 & xf <  0, "Correction",
  fifelse(xs <  0 & xf <  0, "Bear", "Rebound"))))
mdt[, state := mk_state(x_slow, x_fast)]
cat(sprintf("    월수=%d, state 분포: %s\n", nM,
  paste(sprintf("%s=%d", names(table(mdt$state)), as.integer(table(mdt$state))), collapse=" ")))

## ==== [2] a_Co / a_Re ex-ante (Appendix C eqs 8-10) — track1 재사용, 불변 ======
cat("[2] a_Co/a_Re ex-ante (30M 갱신, [0,1] clip, min 12 obs/phase)\n")
st <- mdt$state; rr <- mdt$r
a_co <- rep(NA_real_, nM); a_re <- rep(NA_real_, nM); Cvec <- rep(NA_real_, nM)
estimate_at <- function(upto) {
  idx <- seq_len(upto); s <- st[idx]; x <- rr[idx]
  fin <- is.finite(x) & s != "NA"; s <- s[fin]; x <- x[fin]
  g <- function(lbl) x[s == lbl]
  co <- g("Correction"); re <- g("Rebound"); bu <- g("Bull"); be <- g("Bear")
  if (length(co) < MIN_PHASE_OBS || length(re) < MIN_PHASE_OBS ||
      length(bu) < MIN_PHASE_OBS || length(be) < MIN_PHASE_OBS) return(NULL)
  avg <- function(v) mean(v); avg2 <- function(v) mean(v^2)
  n_bu <- length(bu); n_be <- length(be); n_buBe <- n_bu + n_be
  avg2_buBe <- mean(c(bu, be)^2)
  C <- (n_bu/n_buBe) * avg(bu)/avg2_buBe - (n_be/n_buBe) * avg(be)/avg2_buBe
  if (!is.finite(C) || abs(C) < 1e-8) return(NULL)
  aco <- 0.5 * (1 - (1/C) * avg(co)/avg2(co))
  are <- 0.5 * (1 - (1/C) * avg(re)/avg2(re))
  aco <- min(max(aco, 0), 1); are <- min(max(are, 0), 1)
  list(a_co = aco, a_re = are, C = C)
}
cur <- NULL; last_update_at <- -Inf
for (m in seq_len(nM)) {
  prior <- m - 1L
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

## ==== [3] dynamic blended position → long-only β_tp squash — track1 재사용 =====
cat("[3] dynamic blended position → long-only β_tp squash\n")
pos_dyn <- with(mdt, fifelse(state=="Bull", 1,
  fifelse(state=="Bear", -1,
  fifelse(state=="Correction", 1 - 2*a_co,
  fifelse(state=="Rebound", 2*a_re - 1, NA_real_)))))
mdt[, pos_dyn := pos_dyn]
map_static <- function(s) fifelse(s=="Bull",1.0, fifelse(s=="Correction",0.7,
  fifelse(s=="Bear",0.4, fifelse(s=="Rebound",1.0, NA_real_))))
squash <- function(pos, floor=FLOOR) fifelse(!is.finite(pos), 1.0, floor + (1-floor)*(pos+1)/2)
mdt[, beta_tp_dyn := squash(pos_dyn)]
mdt[, beta_tp_static := map_static(state)]

## ==== [4] 패널 merge (★클린 타이밍 신호월 m → realized_ym m+2) =================
cat("[4] 패널 merge (신호월 m → realized_ym m+2, 클린) + lag1 스트레스\n")
p <- fread(file.path(BASE_DIR,
  "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)

mdt[, ym_p2 := format(as.Date(paste0(ym,"-01")) %m+% months(2), "%Y-%m")]  # 클린
mdt[, ym_p3 := format(as.Date(paste0(ym,"-01")) %m+% months(3), "%Y-%m")]  # +1M lag 스트레스
sig_clean <- mdt[, .(realized_ym = ym_p2, state_cl = state,
                     beta_tp_dyn_cl = beta_tp_dyn, beta_tp_static_cl = beta_tp_static,
                     pos_dyn_cl = pos_dyn, a_co_cl = a_co, a_re_cl = a_re)]
sig_lag1  <- mdt[, .(realized_ym = ym_p3, beta_tp_dyn_l1 = beta_tp_dyn,
                     beta_tp_static_l1 = beta_tp_static)]
p <- merge(p, sig_clean, by="realized_ym", all.x=TRUE)
p <- merge(p, sig_lag1,  by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
## 신호 미가용월(warm-up)은 β=1.0 중립 노출(오버레이 미개입)
for (cc in c("beta_tp_dyn_cl","beta_tp_static_cl","beta_tp_dyn_l1","beta_tp_static_l1")) {
  set(p, which(!is.finite(p[[cc]])), cc, 1.0)
}
p[is.na(state_cl), state_cl := "NA"]
cat(sprintf("    β_tp_dyn 신호가용 시작월: %s (이전은 1.0 중립)\n",
  p$realized_ym[which(p$beta_tp_dyn_cl != 1.0)[1]]))

## ==== [5] 변형군 (E = 노출배수; BASE = NAKED = ret_orig 위 단독 오버레이) ======
## ★핵심: base 노출 = 1.0(NAKED). 각 오버레이는 단독으로 곱해짐. NOL4는 변형 5.
cat("[5] 변형군 정의 (NAKED base 위 단독 오버레이) + 실측\n")
E_list <- list(
  NAKED           = rep(1.0, nrow(p)),                 # 오버레이 전무
  NAKED_x_tp_static  = p$beta_tp_static_cl,            # turning-point 4-state 단독
  NAKED_x_tp_dynamic = p$beta_tp_dyn_cl,               # ★turning-point speed-blend 단독 (주인공)
  NAKED_x_faith      = p$beta_faith,                   # faith 단독 (참조)
  NOL4               = p$beta_R05 * p$m4,              # ★R05×m4 단독 (제거확정 챔피언 = 기준선)
  NAKED_x_AR         = p$beta_AR                       # AR 단독 (참조)
)
## lag1 스트레스 (turning-point 판별검정)
E_lag1 <- list(
  NAKED_x_tp_static_lag1  = p$beta_tp_static_l1,
  NAKED_x_tp_dynamic_lag1 = p$beta_tp_dyn_l1
)

## delta-cost: |Δ노출|×15bps. NAKED는 노출 상수 1.0 → Δ=0 → 비용=0 (bare 알파).
ret_of <- function(E) { dE <- abs(E - shift(E, 1, fill = E[1])); list(ret = E*p$ret_orig - dE*COST, dE = dE) }
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn) }
ann_sr  <- function(ret, idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(ret, order.by=idx), scale=12)[3,1])
R  <- lapply(E_list, ret_of)
RL <- lapply(E_lag1, ret_of)
ret_naked <- R$NAKED$ret       # 기준 1: 완전 바닐라
ret_nol4  <- R$NOL4$ret        # 기준 2: 제거확정 챔피언

## crisis windows
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
    nw_t_vs_NAKED=round(nw_t(ret - ret_naked),2),
    nw_t_vs_NOL4=round(nw_t(ret - ret_nol4),2),
    GFC=round(cum_win(ret,p$realized_ym,crisis_win$GFC),4),
    COVID=round(cum_win(ret,p$realized_ym,crisis_win$COVID),4),
    Y2022=round(cum_win(ret,p$realized_ym,crisis_win$Y2022),4),
    Y2026=round(cum_win(ret,p$realized_ym,crisis_win$Y2026),4))
}))
cat("\n===== TURNING-POINT VANILLA (NAKED base) — CLEAN RESULTS =====\n"); print(res, nrow=99)

## ==== [6] lag1 스트레스 (동월누출 판별) =======================================
cat("\n[6] lag1 스트레스 (clean vs +1M lag)\n")
lag_tbl <- rbindlist(lapply(c("static","dynamic"), function(k) {
  cl_nm <- paste0("NAKED_x_tp_", k); l1_nm <- paste0("NAKED_x_tp_", k, "_lag1")
  ret_cl <- R[[cl_nm]]$ret; ret_l1 <- RL[[l1_nm]]$ret
  data.table(variant=k,
    SR_clean=round(ann_sr(ret_cl),3), SR_lag1=round(ann_sr(ret_l1),3),
    dSR=round(ann_sr(ret_cl)-ann_sr(ret_l1),3),
    NWt_clean_vs_NAKED=round(nw_t(ret_cl-ret_naked),2),
    NWt_lag1_vs_NAKED=round(nw_t(ret_l1-ret_naked),2),
    NWt_clean_vs_NOL4=round(nw_t(ret_cl-ret_nol4),2))
}))
print(lag_tbl)

## ==== [7] OOS v2 (3분할 중앙값) + subperiod ===================================
cat("\n[7] OOS v2 (3분할 중앙값) + subperiod\n")
oos_v2 <- function(ret) { ns <- length(ret)
  rs <- sapply(c(0.55,0.65,0.75), function(f) { k <- floor(ns*f)
    is_sr <- ann_sr(ret[1:k], p$anchor_date[1:k]); oos_sr <- ann_sr(ret[(k+1):ns], p$anchor_date[(k+1):ns])
    if (!is.finite(is_sr) || abs(is_sr) < 1e-9) return(NA_real_); oos_sr/is_sr })
  round(median(rs, na.rm=TRUE),3) }
pre <- p$anchor_date < as.Date("2017-01-01")
sub <- rbindlist(lapply(names(E_list), function(nm)
  data.table(variant=nm, oos_v2=oos_v2(R[[nm]]$ret),
    SR_pre2017=round(ann_sr(R[[nm]]$ret[pre], p$anchor_date[pre]),3),
    SR_post2017=round(ann_sr(R[[nm]]$ret[!pre], p$anchor_date[!pre]),3))))
print(sub)

## ==== [8] 최우수안 build_bt_result (PORT_t + ΔIR 시도) ========================
cat("\n[8] 최우수안 계약 build_bt_result 시도\n")
## 두 핵심질문 판정을 위해 turning-point dynamic vs NAKED / vs NOL4 SR 비교로 winner 선정.
sr_map <- setNames(res$SR, res$variant)
best_nm <- names(sort(sr_map, decreasing=TRUE))[1]
cat(sprintf("    최우수 SR 변형 = %s (SR=%.3f)\n", best_nm, sr_map[best_nm]))
best_ret <- R[[best_nm]]$ret
bt_ok <- FALSE
contract_path <- file.path(BASE_DIR, "02_Infrastructure/contracts/backtest_result_contract.R")
if (file.exists(contract_path)) {
  try({
    source(contract_path)
    bm_m <- data.table(ym = format(index(mret_x), "%Y-%m"), bmret = as.numeric(mret_x))
    p2 <- merge(p[, .(realized_ym, anchor_date)], bm_m, by.x="realized_ym", by.y="ym", all.x=TRUE)
    setorder(p2, realized_ym)
    dnav <- data.table(Date = p$anchor_date, NAV = cumprod(1 + best_ret))
    sim_result <- list(
      DAILY_NAV_DT = dnav,
      strategy_xts = xts(best_ret, order.by = p$anchor_date),
      bm_xts       = xts(p2$bmret, order.by = p$anchor_date),
      HOLDINGS_LOG = NULL, PORTFOLIO_LOG = NULL
    )
    strategy_spec <- list(strategy_id="TP_VANILLA_best", name=best_nm,
      universe="KOSPI200UKOSDAQ150", rebalance="monthly", cost_bps=15)
    btr <- build_bt_result(sim_result, strategy_spec,
      run_id=paste0("TPVAN_", best_nm), strategy_id="TP_VANILLA_best",
      benchmark_id="KOSPI200UKOSDAQ150", benchmark_name="K200+KQ150 pinned",
      frequency="monthly", annualization_factor=12,
      universe_id="KR_TOP342", code_version="run_turningpoint_vanilla",
      created_by_agent="forge")
    saveRDS(btr, file.path(OUT_DIR, "bt_result_best.rds"))
    bt_ok <- TRUE
    cat("    build_bt_result 성공 → bt_result_best.rds\n")
    if (!is.null(btr$benchmark_compare)) { cat("    benchmark_compare:\n"); print(btr$benchmark_compare) }
  }, silent = FALSE)
}
if (!bt_ok) cat("    build_bt_result 미가용 — 계약 rds 생략(수치 무영향, 진단표는 완결)\n")

## ==== [9] 시리즈 + meta 저장 ==================================================
series_out <- data.table(realized_ym=p$realized_ym, anchor_date=p$anchor_date,
  ret_orig=p$ret_orig, state_cl=p$state_cl,
  beta_tp_static=p$beta_tp_static_cl, beta_tp_dynamic=p$beta_tp_dyn_cl,
  beta_R05=p$beta_R05, m4=p$m4, beta_faith=p$beta_faith, beta_AR=p$beta_AR,
  a_co=p$a_co_cl, a_re=p$a_re_cl,
  ret_NAKED=R$NAKED$ret,
  ret_tp_static=R$NAKED_x_tp_static$ret,
  ret_tp_dynamic=R$NAKED_x_tp_dynamic$ret,
  ret_faith=R$NAKED_x_faith$ret,
  ret_NOL4=R$NOL4$ret,
  ret_AR=R$NAKED_x_AR$ret,
  ret_tp_dynamic_lag1=RL$NAKED_x_tp_dynamic_lag1$ret)
fwrite(series_out, file.path(OUT_DIR, "turningpoint_vanilla_series.csv"))
fwrite(res, file.path(OUT_DIR, "turningpoint_vanilla_results.csv"))
fwrite(lag_tbl, file.path(OUT_DIR, "turningpoint_vanilla_lag_stress.csv"))
fwrite(sub, file.path(OUT_DIR, "turningpoint_vanilla_oos_sub.csv"))

## 두 핵심질문 판정
q_dyn_vs_naked <- res[variant=="NAKED_x_tp_dynamic", nw_t_vs_NAKED]
q_dyn_vs_nol4  <- res[variant=="NAKED_x_tp_dynamic", nw_t_vs_NOL4]
sr_dyn  <- res[variant=="NAKED_x_tp_dynamic", SR]
sr_naked<- res[variant=="NAKED", SR]
sr_nol4 <- res[variant=="NOL4", SR]
mdd_dyn  <- res[variant=="NAKED_x_tp_dynamic", MDD]
mdd_naked<- res[variant=="NAKED", MDD]
mdd_nol4 <- res[variant=="NOL4", MDD]

## Q1: turning-point 단독이 NAKED를 유의 초과(SR↑ AND MDD↓ AND NW-t>2)?
q1_pass <- is.finite(q_dyn_vs_naked) && q_dyn_vs_naked > 2 && sr_dyn > sr_naked && mdd_dyn < mdd_naked
## Q2(결정적): turning-point 단독이 NOL4를 이기나(SR↑ AND NW-t>0, 유의는 >2)?
q2_beat <- sr_dyn > sr_nol4
q2_sig  <- is.finite(q_dyn_vs_nol4) && q_dyn_vs_nol4 > 2

meta <- list(
  date="2026-07-02", round="turningpoint-VANILLA (naked base, single overlay)",
  논점="track1은 turning-point를 NOL4 위 stacking해 드래그로 사망. 본 테스트는 모든 오버레이 제거(NAKED=ret_orig) 위 turning-point 단독 오버레이 → R05×m4와 대체 경쟁 공정측정",
  paper="Breaking Bad Trends (Goulding-Harvey-Mazzoleni FAJ 2024, P167) eqs 4,7,8,9,10 (estimator track1 재사용, 불변)",
  base_change="track1 base=beta_R05*m4 (NOL4) → vanilla base=1.0 (NAKED=ret_orig). β_tp 산출 로직 동일.",
  variants=names(E_list),
  clean_timing="turning-point 신호월 m → realized_ym = m+2 (배포 prev-month-end 컨벤션)",
  cost="|Δ노출|×15bps delta (NAKED는 노출 상수 → 비용 0)",
  metric_type="backtested (panel-overlay; track1과 동일 계보)",
  selection_type="chain (가설주도 대체검정 — track1 sweep과 별개 단일 대체 질문)",
  crisis_windows=crisis_win,
  Q1_tp_beats_NAKED=list(
    rule="dynamic vs NAKED: SR↑ AND MDD↓ AND paired NW-t>2",
    SR_dyn=sr_dyn, SR_naked=sr_naked, MDD_dyn=mdd_dyn, MDD_naked=mdd_naked,
    nw_t_vs_NAKED=q_dyn_vs_naked, pass=q1_pass),
  Q2_tp_beats_NOL4=list(
    rule="dynamic vs NOL4(챔피언): SR↑ (유의=NW-t>2)",
    SR_dyn=sr_dyn, SR_nol4=sr_nol4, MDD_dyn=mdd_dyn, MDD_nol4=mdd_nol4,
    nw_t_vs_NOL4=q_dyn_vs_nol4, beats=q2_beat, significant=q2_sig),
  best_variant=best_nm, best_SR=unname(sr_map[best_nm]),
  verdict=if (q2_beat) {
    if (q2_sig) "turning-point 단독이 NOL4를 유의 초과 — R05×m4 대체 여지 OPEN(후속 정밀검증)"
    else "turning-point 단독이 NOL4를 SR 초과하나 비유의 — 대체 borderline"
  } else "turning-point 단독이 NOL4에 미달 — R05×m4가 최선 단독 오버레이 재확인, turning-point 최종사망"
)
write_json(meta, file.path(OUT_DIR, "turningpoint_vanilla_meta.json"),
  auto_unbox=TRUE, pretty=TRUE, digits=6)

cat(sprintf("\n[핵심질문 1] turning-point 단독 > NAKED? SR %.3f vs %.3f | MDD %.4f vs %.4f | NW-t %.2f → %s\n",
  sr_dyn, sr_naked, mdd_dyn, mdd_naked, q_dyn_vs_naked, if(q1_pass) "PASS" else "FAIL"))
cat(sprintf("[핵심질문 2] turning-point 단독 > NOL4(챔피언)? SR %.3f vs %.3f | MDD %.4f vs %.4f | NW-t %.2f → beats=%s sig=%s\n",
  sr_dyn, sr_nol4, mdd_dyn, mdd_nol4, q_dyn_vs_nol4, q2_beat, q2_sig))
cat(sprintf("[VERDICT] %s\n", meta$verdict))
cat("\n[DONE] 산출:", OUT_DIR, "\n")
