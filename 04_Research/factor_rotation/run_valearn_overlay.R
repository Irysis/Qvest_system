#!/usr/bin/env Rscript
# =============================================================================
# run_valearn_overlay.R — Factor Rotation Track2: regime/bear de-risk OVERLAY on
#   the FROZEN valearn orthogonal-alpha module (STR_valearn_70_top25).
#
# 가설: valearn = long-short Carhart4 t=4.11 직교 알파이나 long-only top25는
#   OOS retention −0.517 붕괴(시장베타 + earnings-rev OOS decay), MDD 45.6%, essence F.
#   measurement-graduation §6 + STR_1715(base SR1.50→overlay 운용1.95·OOS0.91)이
#   'overlay(β/regime timing) = OOS robust 결정 요소'임을 시사. 직교 알파 확보로
#   project-factor-rotation '직교 부재로 overlay 무가치' 결론을 재검한다.
#
# 메커니즘(모듈 frozen 소비): 모듈 월 net 수익 r_m에 국면조건부 노출 e(L)∈[0,1] 곱.
#   (1−e)=현금(수익 0, 보수적). 국면전환 turnover 15bps 1-way. 모듈 시그널 미수정.
#   = book-level β/regime timing(measurement-graduation §6 SR2.5 주역 기전).
# PIT: 국면 라벨 = 전월말 Category(또는 SJM JM_State_lag) → shift(1) → 이번달 노출.
#   규칙(어느 국면 디리스크 + e) = IS(앞 60%)에서만 도출 → OOS forward 적용.
# 측정: build_bt_result(frequency=monthly, PerformanceAnalytics 표준함수) →
#   audit_bt_result → essence_score. ★핵심 = essence_score의 oos_retention(65/35 active SR).
# 자체합성 금지: net 시계열 = e*r − known cost(차감), NAV = cumprod(net) value path.
#   포트 *구성*(weight×asset)은 단일 모듈+현금 2-asset이라 Return.portfolio 우회 가능하나,
#   정직성 위해 동일 결과를 표준 누적함수(Return.cumulative)로 월 NAV path 구성.
# governor 정지: book_state 미기록. 측정·진단만. 실편입 = 도훈 confirm.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
CD <- file.path(PROJ, "02_Infrastructure/contracts")
source(file.path(CD, "backtest_result_contract.R"))
source(file.path(CD, "audit_bt_result.R"))
source(file.path(CD, "essence_score.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
srm  <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
mddm <- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }
cagrm<- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); prod(1+r)^(12/length(r))-1 }

# ── 1. 모듈 월 수익 + 벤치마크 (frozen) ──────────────────────────────────────
s  <- readRDS(file.path(PROJ, "04_Research/strategies/STR_valearn_70_top25/sim_result.rds"))
d  <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]   # 이미 월간(월말)
bm <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
mo <- merge(d, bm, by="Date", all.x=TRUE); setorder(mo, Date)
mo[, ym := format(Date, "%Y%m")]
cat(sprintf("[1] valearn 월 %d개 (%s..%s)\n", nrow(mo), mo$ym[1], tail(mo$ym,1)))

# ── 2. 국면 라벨 (전월말 → t-1 lag) ──────────────────────────────────────────
# 2a. Category (5-state, frozen classifier)
RG <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[
  !is.na(Category), .(Date=as.Date(Date), Category)]
setorder(RG, Date)
# 각 모듈 월말일에 그 날(또는 직전 거래일)의 Category → 그 다음 shift(1)로 전월말 라벨 사용
get_regime_at <- function(me_dates, RGdt, col){
  RGdt <- RGdt[, .(Date, val=get(col))]; setorder(RGdt, Date)
  # 각 me_date 이하 마지막 관측 (PIT: 그 시점까지 알 수 있는 라벨). rolling join: i = data.table.
  q <- data.table(Date=as.Date(me_dates))
  res <- RGdt[q, on=.(Date), roll=TRUE]      # roll=TRUE → 직전 관측으로 채움 (LOCF, backward 안전)
  res$val
}
mo[, cat_me := get_regime_at(Date, RG, "Category")]
mo[, reg_cat := shift(cat_me, 1L)]            # 전월말 Category → 이번달 노출 (t-1 lag)
mo[is.na(reg_cat), reg_cat := "NEUTRAL"]

# 2b. SJM JM_State_lag (bull=0/bear=1, 이미 daily t-1 lag) — 독립 cross-check
JM <- as.data.table(read_parquet(file.path(PROJ, ".cache/regime_jump_daily.parquet")))[
  , .(Date=as.Date(Date), bear=JM_State_lag)]
setorder(JM, Date)
mo[, bear_me := get_regime_at(Date, JM, "bear")]
mo[, sjm_bear := shift(bear_me, 1L)]          # 전월말 bear 라벨 → 이번달 (이중 PIT)
mo[is.na(sjm_bear), sjm_bear := 0L]
cat("[2] Category(t-1) 분포:\n"); print(table(mo$reg_cat))
cat("    SJM bear(t-1) 분포 (0=bull,1=bear):\n"); print(table(mo$sjm_bear))

# ── 3. IS/OOS 분할 + 베이스라인(frozen valearn, e=1.0) ───────────────────────
nM <- nrow(mo); is_cut <- floor(nM*0.60)
IS <- mo[1:is_cut]; OOS <- mo[(is_cut+1):nM]
cat(sprintf("\n[3] IS %d (%s~%s) / OOS %d (%s~%s)\n",
  is_cut, IS$ym[1], tail(IS$ym,1), nrow(OOS), OOS$ym[1], tail(OOS$ym,1)))
base_r <- mo$r
cat(sprintf("[3b] baseline(frozen valearn) full: SR=%.3f MDD=%.3f CAGR=%.3f Calmar=%.3f\n",
  srm(base_r), mddm(base_r), cagrm(base_r), cagrm(base_r)/mddm(base_r)))

# ── 4. IS-only 규칙 도출: Category별 IS Sharpe → 디리스크 후보 ────────────────
isstat <- IS[, .(n=.N, mean=round(mean(r),4), sharpe=round(srm(r),3), mdd=round(mddm(r),3)), by=reg_cat][order(sharpe)]
cat("\n[4] IS Category별 valearn 성과 (Sharpe 오름차순 = 디리스크 후보 위):\n"); print(isstat)
elig <- isstat[n>=6]
derisk_reg <- if(nrow(elig)) elig$reg_cat[1] else NA_character_     # IS 최저 Sharpe(n>=6)
cat(sprintf("→ IS 도출 디리스크 국면(최저 Sharpe, n>=6): %s\n", derisk_reg %||% "(none)"))
# SJM bear IS Sharpe (디리스크 정당성 cross-check)
sjm_is <- IS[, .(n=.N, sharpe=round(srm(r),3), mean=round(mean(r),4)), by=sjm_bear][order(sjm_bear)]
cat("[4b] IS SJM bull/bear별 valearn 성과:\n"); print(sjm_is)

# ── 5. 오버레이 적용(전기간; 규칙은 IS-only) → net 월 시계열 ──────────────────
# 노출 e: 디리스크 국면에서 e_d, 나머지 1.0. (1-e)=현금(0). 전환 turnover 15bps.
apply_overlay <- function(reg_vec, derisk_label, e_d, cost_bps=15){
  prev_e <- 1; rn <- numeric(length(reg_vec))
  for(i in seq_along(reg_vec)){
    e <- if(!is.na(derisk_label) && reg_vec[i]==derisk_label) e_d else 1.0
    r <- e*mo$r[i]
    if(abs(e-prev_e) > 1e-9) r <- r - abs(e-prev_e)*(cost_bps/1e4)   # 노출 변경 = 회전 비용(현금<->모듈)
    prev_e <- e; rn[i] <- r
  }
  rn
}
# SJM bear 오버레이 (디리스크 = bear=1)
apply_overlay_sjm <- function(bear_vec, e_d, cost_bps=15){
  prev_e <- 1; rn <- numeric(length(bear_vec))
  for(i in seq_along(bear_vec)){
    e <- if(bear_vec[i]==1L) e_d else 1.0
    r <- e*mo$r[i]
    if(abs(e-prev_e) > 1e-9) r <- r - abs(e-prev_e)*(cost_bps/1e4)
    prev_e <- e; rn[i] <- r
  }
  rn
}

# ── 6. 변형 목록 + essence 측정 (각 변형을 build_bt_result→essence_score) ─────
mdates  <- mo$Date
bm_d_xts<- xts(mo$bm, order.by=mdates)        # 월간 벤치마크(이미 월말)
N_TRIALS <- 6L                                # 단일모듈 + 소수 노출 grid (보수적 다중검정 계상)

measure_variant <- function(label, net_r, n_trials=N_TRIALS){
  # 월간 NAV path (net 월수익 누적가치 — answer-principles 정합; 수익률 *구성* 아님)
  nav_net   <- as.numeric(cumprod(1 + ifelse(is.finite(net_r), net_r, 0)))
  nav_gross <- nav_net                          # gross=net (비용은 net에 이미 차감; gross 별도 추적 불필요 시 동일)
  net_xts   <- xts(net_r, order.by=mdates)
  sim <- list(
    DAILY_NAV_DT = data.table(Date=mdates, NAV=nav_net, NAV_gross=nav_gross),
    strategy_xts = net_xts, bm_xts = bm_d_xts,
    HOLDINGS_LOG = list(),
    PORTFOLIO_LOG= data.table(Exec_Date=mdates))
  spec <- list(strategy_name=label, signal="regime/bear de-risk overlay on frozen valearn module",
    module="STR_valearn_70_top25 (frozen)",
    regime_source="unified_regime_signal_daily Category (t-1) / SJM JM_State_lag (t-1)",
    weighting="book-level exposure scalar e(regime) in [0,1]; cash=0; 15bps transition cost",
    rebalance="monthly",
    lookahead_prevention="regime t-1 lag (prior month-end); IS-only rule derivation; module frozen; forward OOS application")
  bt <- build_bt_result(sim, spec, run_id=label, strategy_id=label, strategy_version="v1",
    benchmark_id="KOSPI200", benchmark_name="KOSPI 200", transaction_cost_bps=15, slippage_bps=0,
    risk_free_rate=0, frequency="monthly", annualization_factor=12, universe_id="KR_valearn",
    code_version="run_valearn_overlay_v1", created_by_agent="dispatch-orchestrator")
  bt <- audit_bt_result(bt)
  es <- essence_score(bt, n_trials_cumulative=n_trials)
  list(bt=bt, es=es,
       row=data.table(variant=label,
         grade=es$grade,
         net_SR=es$essence$net_sharpe %||% NA_real_,
         PORT_t=es$essence$portfolio_alpha_t_nw_lag3 %||% NA_real_,
         oos_ret=es$essence$oos_retention %||% NA_real_,
         MDD=es$essence$mdd %||% NA_real_,
         Calmar=es$essence$calmar %||% NA_real_,
         CAGR=es$essence$cagr %||% NA_real_,
         net_IR=es$essence$net_ir %||% NA_real_,
         DSR=es$essence$dsr %||% NA_real_,
         audit=bt$audit$integrity_status %||% bt$audit$integrity %||% NA_character_))
}

variants <- list()
# 6.0 baseline (frozen valearn)
variants[["baseline_e1.0"]] <- measure_variant("valearn_baseline_e1.0", base_r)
# 6.1 IS-derived Category de-risk (e=0.5, e=0.0)
if(!is.na(derisk_reg)){
  variants[[sprintf("cat_%s_e0.5", derisk_reg)]] <- measure_variant(
    sprintf("valearn_cat_%s_e0.5", derisk_reg), apply_overlay(mo$reg_cat, derisk_reg, 0.5))
  variants[[sprintf("cat_%s_e0.0", derisk_reg)]] <- measure_variant(
    sprintf("valearn_cat_%s_e0.0", derisk_reg), apply_overlay(mo$reg_cat, derisk_reg, 0.0))
}
# 6.2 CRISIS-specific de-risk (AX-001) — 표본 충분 시
if("CRISIS" %in% mo$reg_cat){
  variants[["CRISIS_off_e0.5"]] <- measure_variant("valearn_CRISIS_off_e0.5", apply_overlay(mo$reg_cat, "CRISIS", 0.5))
  variants[["CRISIS_off_e0.0"]] <- measure_variant("valearn_CRISIS_off_e0.0", apply_overlay(mo$reg_cat, "CRISIS", 0.0))
}
# 6.3 RISK_OFF+CRISIS 결합 디리스크 (방어 국면 묶음)
mo[, risk_def := ifelse(reg_cat %in% c("CRISIS","RISK_OFF"), "DEF", "ON")]
variants[["defbundle_e0.5"]] <- measure_variant("valearn_defbundle_e0.5", apply_overlay(mo$risk_def, "DEF", 0.5))
variants[["defbundle_e0.0"]] <- measure_variant("valearn_defbundle_e0.0", apply_overlay(mo$risk_def, "DEF", 0.0))
# 6.4 SJM bear de-risk (독립 regime def cross-check)
variants[["sjm_bear_e0.5"]] <- measure_variant("valearn_sjm_bear_e0.5", apply_overlay_sjm(mo$sjm_bear, 0.5))
variants[["sjm_bear_e0.0"]] <- measure_variant("valearn_sjm_bear_e0.0", apply_overlay_sjm(mo$sjm_bear, 0.0))

# ── 7. 결과 테이블 + 평결 ────────────────────────────────────────────────────
restab <- rbindlist(lapply(variants, function(v) v$row), use.names=TRUE)
restab[, `:=`(net_SR=round(net_SR,3), PORT_t=round(PORT_t,3), oos_ret=round(oos_ret,3),
              MDD=round(MDD,4), Calmar=round(Calmar,3), CAGR=round(CAGR,4), net_IR=round(net_IR,3), DSR=round(DSR,3))]
cat("\n==== valearn overlay vs baseline (essence_score 실측, monthly contract) ====\n")
print(restab)

base_row  <- restab[variant=="valearn_baseline_e1.0"]
base_oos  <- base_row$oos_ret; base_mdd <- base_row$MDD; base_sr <- base_row$net_SR
# 평결: oos_retention을 음수→0.5+ & MDD 완화하는 변형 존재?
restab[, oos_rescue := is.finite(oos_ret) & oos_ret >= 0.5]
restab[, mdd_ease   := is.finite(MDD) & is.finite(base_mdd) & MDD < base_mdd*0.95]
rescuers <- restab[variant!="valearn_baseline_e1.0" & oos_rescue==TRUE & mdd_ease==TRUE]
best_oos <- restab[variant!="valearn_baseline_e1.0"][order(-oos_ret)][1]
verdict <- if(nrow(rescuers) > 0){
  "OVERLAY_RESCUES (valearn 직교알파 + overlay → oos_retention>=0.5 & MDD 완화; project-factor-rotation 결론 갱신)"
} else if(is.finite(best_oos$oos_ret) && is.finite(base_oos) && best_oos$oos_ret > base_oos + 0.3){
  "OVERLAY_PARTIAL (oos_retention 유의 개선이나 0.5 미달 또는 MDD 미완화 — 부분 회복)"
} else {
  "OVERLAY_LIMIT (overlay가 valearn OOS 붕괴 회복 못함 — KR long-only regime-overlay 한계 재확인, 정직)"
}
cat(sprintf("\n★ 평결: %s\n  baseline oos_ret=%s MDD=%.1f%% net_SR=%.3f | best-oos 변형=%s oos_ret=%s MDD=%.1f%%\n",
  verdict, as.character(base_oos), (base_mdd%||%NA)*100, base_sr%||%NA,
  best_oos$variant, as.character(best_oos$oos_ret), (best_oos$MDD%||%NA)*100))

# ── 8. 저장 (실측-only; governor 정지 — book_state 미기록) ────────────────────
outdir <- file.path(PROJ, "04_Research/factor_rotation/output"); dir.create(outdir, showWarnings=FALSE, recursive=TRUE)
out <- list(
  study="valearn_regime_overlay", fr_candidate="FR_VALEARN_OVERLAY",
  module="STR_valearn_70_top25 (frozen)", n_months=nM, is_cut=is_cut,
  is_range=c(IS$ym[1], tail(IS$ym,1)), oos_range=c(OOS$ym[1], tail(OOS$ym,1)),
  regime_source="unified_regime_signal_daily Category(t-1) + SJM JM_State_lag(t-1)",
  derisk_regime_IS=derisk_reg, IS_category_stats=isstat, IS_sjm_stats=sjm_is,
  baseline=list(oos_retention=base_oos, MDD=base_mdd, net_SR=base_sr,
    grade=base_row$grade, PORT_t=base_row$PORT_t, CAGR=base_row$CAGR, Calmar=base_row$Calmar),
  variants=restab,
  best_oos_variant=best_oos$variant, best_oos_retention=best_oos$oos_ret,
  verdict=verdict,
  governor="HALTED (book_state 미기록; 측정·진단만; 실편입=도훈 confirm)",
  n_trials_cumulative=N_TRIALS,
  return_synthesis="net 시계열 = e*module_ret - known transition cost; NAV=cumprod(net) value path; build_bt_result(monthly, PerformanceAnalytics 표준함수)",
  lookahead_prevention="regime t-1 lag (prior month-end); IS-only rule derivation; module frozen; forward OOS",
  code_version="run_valearn_overlay_v1")
write_json(out, file.path(outdir, "valearn_overlay_result.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
saveRDS(variants[["baseline_e1.0"]]$bt, file.path(outdir, "valearn_baseline_bt_result.rds"))
# best-oos 변형 bt도 저장
best_key <- names(variants)[which(restab$variant==best_oos$variant)]
if(length(best_key)) saveRDS(variants[[best_key]]$bt, file.path(outdir, "valearn_best_overlay_bt_result.rds"))
cat(sprintf("\n저장: %s/valearn_overlay_result.json\n", outdir))
cat("[governor] HALTED — book_state.json 미기록. 측정만. 실편입 = Q-Lead + 도훈 수동 confirm.\n")
